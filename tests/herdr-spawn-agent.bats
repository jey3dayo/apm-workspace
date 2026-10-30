#!/usr/bin/env bats

# spawn-agent.sh runs against a stub herdr that records every call and fakes
# one pane split plus an agent start, so no live Herdr server is needed.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/catalog/skills/herdr/scripts/spawn-agent.sh"
  export HERDR_BIN_PATH="$BATS_TEST_TMPDIR/herdr"
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"
  export HERDR_PANE_ID="w1:p1"
  mkdir -p "$STUB_DIR" "$BATS_TEST_TMPDIR/my-app"
  WORK="$(cd "$BATS_TEST_TMPDIR/my-app" && pwd)"
  cat >"$HERDR_BIN_PATH" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_DIR/calls"
[ "${1:-}" = --session ] && shift 2
case "$*" in
  agent)
    echo "  kinds: pi|claude|codex|gemini" >&2; exit 2 ;;
  "agent list")
    if [ -f "$STUB_DIR/started" ] && [ -n "${STUB_READBACK_AGENT_LIST_FAIL:-}" ]; then
      echo '{"error":{"code":"readback_agent_list_failed"}}' >&2; exit 1
    fi
    if [ -f "$STUB_DIR/started" ]; then
      read -r name kind <"$STUB_DIR/started"
      if [ -n "${STUB_NO_READBACK_AGENT:-}" ]; then
        echo '{"result":{"agents":[]}}'
        exit
      fi
      printf '{"result":{"agents":[{"pane_id":"w1:p9","name":"%s","agent":"%s","agent_status":"%s","cwd":"%s","workspace_id":"w1","tab_id":"w1:t1"}]}}\n' \
        "$name" "${STUB_KIND:-$kind}" "${STUB_AGENT_STATUS:-idle}" "${STUB_CWD:-$(cat "$STUB_DIR/cwd")}"
    else
      echo '{"result":{"agents":[{"pane_id":"w1:p2","name":"codex-1","agent":"codex"}]}}'
    fi ;;
  "pane layout "*)
    echo '{"result":{"layout":{"focused_pane_id":"w1:p1","panes":[
      {"pane_id":"w1:p1","rect":{"width":200,"height":50}}]}}}' ;;
  "pane split "*)
    set -- "$@"
    while [ $# -gt 0 ]; do [ "$1" = --cwd ] && echo "$2" >"$STUB_DIR/cwd"; shift; done
    echo '{"result":{"pane":{"pane_id":"w1:p9"}}}' ;;
  "pane process-info --pane w1:p9")
    if [ -f "$STUB_DIR/started" ] && [ -n "${STUB_READBACK_PROCESS_INFO_FAIL:-}" ]; then
      echo '{"error":{"code":"readback_process_info_failed"}}' >&2; exit 1
    fi
    pid=100; [ -n "${STUB_BUSY:-}" ] && pid=200
    [ -f "$STUB_DIR/started" ] && pid=300
    printf '{"result":{"process_info":{"shell_pid":100,"foreground_process_group_id":%s,"foreground_processes":[{"pid":%s,"cmdline":"x","cwd":"/"}]}}}\n' "$pid" "$pid" ;;
  "agent start "*)
    if [ -n "${STUB_START_NOT_READY:-}" ]; then
      echo "$3 $5" >"$STUB_DIR/started"
      echo '{"error":{"code":"agent_not_ready","message":"startup approval needs attention"}}' >&2
      exit 1
    fi
    [ -n "${STUB_START_FAIL:-}" ] && { echo '{"error":{"code":"timeout"}}' >&2; exit 1; }
    echo "$3 $5" >"$STUB_DIR/started"
    echo '{"result":{"type":"agent_started"}}' ;;
  *) echo "unexpected herdr call: $*" >&2; exit 9 ;;
esac
STUB
  chmod +x "$HERDR_BIN_PATH"
}

calls() { cat "$STUB_DIR/calls"; }

@test "rejects bad arguments before touching the layout" {
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 2 ]
  run "$SCRIPT_UNDER_TEST" --kind nope
  [ "$status" -eq 2 ]
  run "$SCRIPT_UNDER_TEST" --kind codex --name Bad
  [ "$status" -eq 2 ]
  run "$SCRIPT_UNDER_TEST" --kind codex --name codex-1
  [ "$status" -eq 2 ]
  run "$SCRIPT_UNDER_TEST" --kind codex --timeout 3000
  [ "$status" -eq 2 ]
  run "$SCRIPT_UNDER_TEST" --kind codex --cwd "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 2 ]
  run "$SCRIPT_UNDER_TEST" --kind codex --session work
  [ "$status" -eq 2 ]
  [[ "$output" == *"--pane"* ]]
  run ! grep -q "pane split" "$STUB_DIR/calls"
}

@test "outside a Herdr pane it needs --pane" {
  unset HERDR_PANE_ID
  run "$SCRIPT_UNDER_TEST" --kind codex
  [ "$status" -eq 2 ]
}

@test "splits the calling pane without focus and starts a named agent" {
  run --separate-stderr "$SCRIPT_UNDER_TEST" --kind codex --cwd "$WORK" -- --model x
  [ "$status" -eq 0 ]
  [ "$output" = "w1:p9" ]
  grep -qx -- "pane split --current --direction right --cwd $WORK --no-focus" "$STUB_DIR/calls"
  grep -qx -- "agent start codex-2 --kind codex --pane w1:p9 -- --model x" "$STUB_DIR/calls"
}

@test "--session is passed explicitly to every call and --focus is honoured" {
  run "$SCRIPT_UNDER_TEST" --kind claude --session work --pane w1:p1 --cwd "$WORK" \
    --direction down --name reviewer --focus --timeout 60000
  [ "$status" -eq 0 ]
  # Only the client-side kind list (`herdr agent` help) runs without it.
  run ! grep -v -e '^--session work ' -e '^agent$' "$STUB_DIR/calls"
  grep -qx -- "--session work pane split --pane w1:p1 --direction down --cwd $WORK --focus" "$STUB_DIR/calls"
  grep -qx -- "--session work agent start reviewer --kind claude --pane w1:p9 --timeout 60000" "$STUB_DIR/calls"
}

@test "--json reports the read-back agent" {
  run --separate-stderr "$SCRIPT_UNDER_TEST" --kind claude --cwd "$WORK" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.pane_id + " " + .kind + " " + .name' <<<"$output")" = "w1:p9 claude claude-1" ]
  [ "$(jq -r .cwd <<<"$output")" = "$WORK" ]
}

@test "times out with exit 3 when the new shell never becomes idle" {
  STUB_BUSY=1 run "$SCRIPT_UNDER_TEST" --kind codex --cwd "$WORK" --shell-timeout 400
  [ "$status" -eq 3 ]
  [[ "$output" == *"w1:p9"* ]]
  run ! grep -q "agent start" "$STUB_DIR/calls"
}

@test "exit 1 when agent start fails" {
  STUB_START_FAIL=1 run "$SCRIPT_UNDER_TEST" --kind codex --cwd "$WORK"
  [ "$status" -eq 1 ]
}

@test "exit 5 with a JSON reason when Herdr reports agent_not_ready" {
  STUB_START_NOT_READY=1 STUB_AGENT_STATUS=idle run --separate-stderr \
    "$SCRIPT_UNDER_TEST" --kind codex --cwd "$WORK" --name reviewer --json
  [ "$status" -eq 5 ]
  [ "$(jq -r '.pane_id + " " + .name + " " + .kind' <<<"$output")" = "w1:p9 reviewer codex" ]
  [ "$(jq -r '.ready' <<<"$output")" = "false" ]
  [ "$(jq -r '.status' <<<"$output")" = "idle" ]
  [ "$(jq -r '.reason.code' <<<"$output")" = "agent_not_ready" ]
  [ "$(jq -r '.reason.message' <<<"$output")" = "startup approval needs attention" ]
  [[ "$stderr" == *"not ready for input"* ]]
  grep -qx -- "agent start reviewer --kind codex --pane w1:p9" "$STUB_DIR/calls"
}

@test "exit 5 exposes the verified pane id in the default output" {
  STUB_START_NOT_READY=1 run --separate-stderr \
    "$SCRIPT_UNDER_TEST" --kind codex --cwd "$WORK" --name reviewer
  [ "$status" -eq 5 ]
  [ "$output" = "w1:p9" ]
  [[ "$stderr" == *"startup approval needs attention"* ]]
}

@test "read-back agent-list failure retains pane id and original not-ready reason" {
  STUB_START_NOT_READY=1 STUB_READBACK_AGENT_LIST_FAIL=1 run --separate-stderr \
    "$SCRIPT_UNDER_TEST" --kind codex --cwd "$WORK" --name reviewer
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"herdr agent list failed"* ]]
  [[ "$stderr" == *"w1:p9"* ]]
  [[ "$stderr" == *"agent_not_ready"* ]]
  [[ "$stderr" == *"startup approval needs attention"* ]]
}

@test "read-back process-info failure retains pane id and original not-ready reason" {
  STUB_START_NOT_READY=1 STUB_READBACK_PROCESS_INFO_FAIL=1 run --separate-stderr \
    "$SCRIPT_UNDER_TEST" --kind codex --cwd "$WORK" --name reviewer
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"herdr pane process-info failed"* ]]
  [[ "$stderr" == *"w1:p9"* ]]
  [[ "$stderr" == *"agent_not_ready"* ]]
  [[ "$stderr" == *"startup approval needs attention"* ]]
}

@test "missing read-back agent retains pane id and original not-ready reason" {
  STUB_START_NOT_READY=1 STUB_NO_READBACK_AGENT=1 run --separate-stderr \
    "$SCRIPT_UNDER_TEST" --kind codex --cwd "$WORK" --name reviewer
  [ "$status" -eq 4 ]
  [[ "$stderr" == *"no agent found"* ]]
  [[ "$stderr" == *"w1:p9"* ]]
  [[ "$stderr" == *"agent_not_ready"* ]]
  [[ "$stderr" == *"startup approval needs attention"* ]]
}

@test "mismatched read-back retains pane id and original not-ready reason" {
  STUB_START_NOT_READY=1 STUB_KIND=claude run --separate-stderr \
    "$SCRIPT_UNDER_TEST" --kind codex --cwd "$WORK" --name reviewer
  [ "$status" -eq 4 ]
  [[ "$stderr" == *"does not match --kind codex"* ]]
  [[ "$stderr" == *"w1:p9"* ]]
  [[ "$stderr" == *"agent_not_ready"* ]]
  [[ "$stderr" == *"startup approval needs attention"* ]]
}

@test "exit 4 when the read-back kind or cwd does not match" {
  STUB_KIND=claude run "$SCRIPT_UNDER_TEST" --kind codex --cwd "$WORK"
  [ "$status" -eq 4 ]
  rm -f "$STUB_DIR/started"
  STUB_CWD=/elsewhere run "$SCRIPT_UNDER_TEST" --kind codex --cwd "$WORK"
  [ "$status" -eq 4 ]
}
