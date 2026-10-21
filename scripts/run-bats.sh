#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log="$(mktemp)"
gitconfig="$(mktemp)"
trap 'rm -f "$log" "$gitconfig"' EXIT

# Hooks export GIT_DIR for the repo being pushed; without this, suites write
# into that repo instead of their fixtures. The throwaway global config keeps
# commits working without touching the user's ~/.gitconfig.
printf '[user]\n\tname = apm-test\n\temail = apm-test@example.invalid\n[init]\n\tdefaultBranch = main\n' >"$gitconfig"
# shellcheck source=lib/git-test-env.sh
. "$SCRIPT_DIR/lib/git-test-env.sh"
apm_isolate_git_env "$gitconfig"

args=()
# bats --jobs needs GNU parallel plus flock or shlock, and exits 1 without them
# rather than falling back, so the guard checks both.
if [ "${APM_TEST_PARALLEL:-1}" != "0" ] &&
	command -v parallel >/dev/null 2>&1 &&
	{ command -v flock >/dev/null 2>&1 || command -v shlock >/dev/null 2>&1; }; then
	# Half the cores keeps the test run from starving the rest of the machine;
	# floor of 4 preserves today's default when core detection is unavailable.
	ncpu=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 8)
	default_jobs=$((ncpu / 2))
	if [ "$default_jobs" -lt 4 ]; then
		default_jobs=4
	fi
	args+=(--jobs "${BATS_JOBS:-$default_jobs}")
fi

status=0
bats ${args[@]+"${args[@]}"} "$REPO_ROOT"/tests/*.bats >"$log" 2>&1 || status=$?

# Passing `ok` lines are dropped; failures, diagnostics, skips and stderr are kept.
awk '/^ok / && !/# skip/ { passed++; next } { print } END { print passed + 0 " passed" }' "$log"
exit "$status"
