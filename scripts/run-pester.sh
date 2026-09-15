#!/usr/bin/env bash
set -euo pipefail

# Run each Pester file in its own pwsh process so the four *.Tests.ps1 suites
# overlap on a multi-core runner instead of running back to back. The files are
# independent: every one builds its own mktemp/TestDrive fixtures and pins HOME
# into them, so no state is shared between processes.
#
# Each process logs to its own file, printed in a stable order once all of them
# finish, so concurrent Pester output cannot interleave into unreadable logs.

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
  # PowerShell single-quoted strings escape an embedded ' by doubling it;
  # $file is an absolute path built from the repo checkout location, which is
  # not guaranteed to be free of that character.
  escaped_file="${file//\'/\'\'}"
  pwsh -NoProfile -Command "Invoke-Pester -Path '$escaped_file' -CI -Output Detailed" \
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
