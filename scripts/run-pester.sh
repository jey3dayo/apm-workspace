#!/usr/bin/env bash
set -euo pipefail

# Fanning the suites out is safe because each file pins HOME into its own
# fixtures.
if [ "${APM_TEST_PARALLEL:-1}" = "0" ]; then
  exec pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI -Output Detailed"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$REPO_ROOT/tests"

shopt -s nullglob
files=("$TEST_DIR"/*.Tests.ps1)
if [ "${#files[@]}" -eq 0 ]; then
  echo "No Pester suites found under $TEST_DIR" >&2
  exit 1
fi

log_dir="$(mktemp -d)"
trap 'rm -rf "$log_dir"' EXIT

pids=()
names=()
for file in "${files[@]}"; do
  name="$(basename "$file")"
  names+=("$name")
  # PowerShell single-quoted strings escape an embedded ' by doubling it.
  escaped_file="${file//\'/\'\'}"
  # -CI would also enable Pester's TestResult report, whose default OutputPath
  # is a relative testResults.xml, so every parallel suite would write the same
  # file. Set Run.Exit directly instead.
  pwsh -NoProfile -Command "\$c = New-PesterConfiguration; \$c.Run.Path = '$escaped_file'; \$c.Run.Exit = \$true; \$c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration \$c" \
    >"$log_dir/$name.log" 2>&1 &
  pids+=("$!")
done

status=0
failed=()
for i in "${!pids[@]}"; do
  if ! wait "${pids[$i]}"; then
    status=1
    failed+=("${names[$i]}")
  fi
done

for name in "${names[@]}"; do
  echo "===== $name ====="
  cat "$log_dir/$name.log"
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "FAILED: ${failed[*]}" >&2
fi

exit "$status"
