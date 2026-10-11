#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSPECT_SCRIPT="$REPO_ROOT/manual-skills/.apm/skills/gh-fix-ci/scripts/inspect_pr_checks.py"
  FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  FAKE_GH_CALLS="$BATS_TEST_TMPDIR/gh-calls"
  mkdir -p "$FAKE_BIN"
  : >"$FAKE_GH_CALLS"
  export FAKE_GH_CALLS

  cat >"$FAKE_BIN/gh" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_GH_CALLS"

if [ "${1-}" = "auth" ] && [ "${2-}" = "status" ]; then
  exit 0
fi

if [ "${1-}" = "pr" ] && [ "${2-}" = "checks" ]; then
  if [ "${FAKE_CHECK_WITH_JOB:-yes}" = "yes" ]; then
    cat <<'JSON'
[{"name":"Lint (ubuntu-latest)","state":"FAILURE","conclusion":"failure","detailsUrl":"https://github.com/example/repo/actions/runs/38119938360/job/114412395935"}]
JSON
  else
    cat <<'JSON'
[{"name":"Lint (ubuntu-latest)","state":"FAILURE","conclusion":"failure","detailsUrl":"https://github.com/example/repo/actions/runs/38119938360"}]
JSON
  fi
  exit 0
fi

if [ "${1-}" = "run" ] && [ "${2-}" = "view" ]; then
  if [ "${4-}" = "--json" ]; then
    printf '%s\n' '{"conclusion":"failure","status":"completed","workflowName":"CI","name":"CI","event":"pull_request","headBranch":"test","headSha":"abc123","url":"https://github.com/example/repo/actions/runs/38119938360"}'
    exit 0
  fi
  if [ "${4-}" = "--job" ] && [ "${5-}" = "114412395935" ] && [ "${6-}" = "--log" ]; then
    case "${FAKE_JOB_LOG_STATE:-success}" in
      success)
        cat <<'LOG'
Linux Lint
apt-get update && apt-get install -y example
E: Failed to fetch package index: connection timed out after 300 seconds
Process completed with exit code 124.
LOG
        exit 0
        ;;
      pending)
        printf '%s\n' 'Job is still in progress; log will be available when it is complete' >&2
        exit 1
        ;;
      error)
        printf '%s\n' 'job-specific log endpoint failed' >&2
        exit 1
        ;;
    esac
  fi
  if [ "${4-}" = "--log" ]; then
    cat <<'LOG'
Quality Gate
Determine overall result
Lint FAILED
LOG
    exit 0
  fi
fi

printf 'unexpected fake gh invocation: %s\n' "$*" >&2
exit 90
SH
  chmod +x "$FAKE_BIN/gh"
}

run_inspector() {
  env PATH="$FAKE_BIN:$PATH" \
    FAKE_GH_CALLS="$FAKE_GH_CALLS" \
    FAKE_CHECK_WITH_JOB="${FAKE_CHECK_WITH_JOB:-yes}" \
    FAKE_JOB_LOG_STATE="${FAKE_JOB_LOG_STATE:-success}" \
    python3 "$INSPECT_SCRIPT" --repo "$REPO_ROOT" --pr 422 --json
}

@test "job ID selects only its job log as the failure source" {
  run run_inspector
  [ "$status" -eq 1 ]
  [[ "$output" == *"Linux Lint"* ]]
  [[ "$output" == *"exit code 124"* ]]
  [[ "$output" != *"Quality Gate"* ]]
  grep -Fq 'run view 38119938360 --job 114412395935 --log' "$FAKE_GH_CALLS"
  ! grep -Fq 'run view 38119938360 --log' "$FAKE_GH_CALLS"
}

@test "job log pending does not fall back to aggregate run logs" {
  export FAKE_JOB_LOG_STATE=pending
  run run_inspector
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status": "log_pending"'* ]]
  [[ "$output" != *"Quality Gate"* ]]
  ! grep -Fq 'run view 38119938360 --log' "$FAKE_GH_CALLS"
}

@test "job log errors do not fall back to another job's run log" {
  export FAKE_JOB_LOG_STATE=error
  run run_inspector
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status": "log_unavailable"'* ]]
  [[ "$output" != *"Quality Gate"* ]]
  ! grep -Fq 'run view 38119938360 --log' "$FAKE_GH_CALLS"
}

@test "run-level log behavior remains for checks without a job ID" {
  export FAKE_CHECK_WITH_JOB=no
  run run_inspector
  [ "$status" -eq 1 ]
  [[ "$output" == *"Quality Gate"* ]]
  grep -Fq 'run view 38119938360 --log' "$FAKE_GH_CALLS"
  ! grep -Fq 'run view 38119938360 --job ' "$FAKE_GH_CALLS"
}
