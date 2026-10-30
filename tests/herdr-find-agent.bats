#!/usr/bin/env bats

# find-agent.sh runs against a stub herdr that serves two sessions, so no
# live Herdr server is needed.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/catalog/skills/herdr/scripts/find-agent.sh"
  export HERDR_BIN_PATH="$BATS_TEST_TMPDIR/herdr"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset HERDR_SOCKET_PATH
  unset HERDR_SESSION
  cat >"$HERDR_BIN_PATH" <<'STUB'
#!/usr/bin/env bash
if [ "${FAIL_HERDR_SESSION:-}" = work ] && [ "$*" = "--session work agent list" ]; then
  echo "stub: agent list failed for work" >&2
  exit 42
fi
case "$*" in
  "session list --json")
    echo '{"sessions":[
      {"default":true,"name":"default","running":true,"socket_path":"/s/default.sock"},
      {"default":false,"name":"work","running":true,"socket_path":"/s/work.sock"},
      {"default":false,"name":"old","running":false,"socket_path":"/s/old.sock"}]}' ;;
  "--session default workspace list")
    echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"my-app"}]}}' ;;
  "--session work workspace list")
    echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"apm"}]}}' ;;
  "--session default agent list")
    echo '{"result":{"agents":[
      {"agent":"claude","agent_status":"idle","cwd":"/src/my-app/root","pane_id":"w1:p1","workspace_id":"w1",
       "terminal_title_stripped":"受信トレイ","agent_session":{"value":"0b6f1c2e-aaaa"}},
      {"agent":"codex","agent_status":"working","cwd":"/src/my-app/root","foreground_cwd":"/src/my-app/api",
       "pane_id":"w1:p2","workspace_id":"w1"}]}}' ;;
  "--session work agent list")
    echo '{"result":{"agents":[
      {"agent":"codex","agent_status":"idle","cwd":"/src/apm","pane_id":"w1:p1","workspace_id":"w1",
       "name":"reviewer","agent_session":{"value":"019a2b3c-dddd"}}]}}' ;;
  *) echo "unexpected herdr call: $*" >&2; exit 9 ;;
esac
STUB
  chmod +x "$HERDR_BIN_PATH"
}

count() { "$SCRIPT_UNDER_TEST" --json "$@" | jq length; }

@test "lists agents from every running session" {
  [ "$(count)" -eq 3 ]
}

@test "filters by kind, repo, status and title" {
  [ "$(count --kind codex)" -eq 2 ]
  [ "$(count --repo my-app/API)" -eq 1 ]
  [ "$(count --kind codex --status idle)" -eq 1 ]
  [ "$(count --title 受信)" -eq 1 ]
}

@test "--repo searches cwd and foreground_cwd so -q can report ambiguity" {
  run --separate-stderr "$SCRIPT_UNDER_TEST" -q --repo root
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"2 agents match"* ]]
  [ "$(count --repo root)" -eq 2 ]
  [ "$("$SCRIPT_UNDER_TEST" --json --repo root | jq -r '.[] | select(.kind == "codex").cwd')" = "/src/my-app/api" ]
  [ "$("$SCRIPT_UNDER_TEST" --json --repo root | jq '[.[] | has("_repo_cwd")] | any')" = "false" ]
}

@test "query matches an agent session id prefix, a herdr session name, or an agent name" {
  [ "$("$SCRIPT_UNDER_TEST" --json 0b6f | jq -r '.[0].pane_id')" = "w1:p1" ]
  [ "$("$SCRIPT_UNDER_TEST" --json work | jq -r '.[0].session')" = "work" ]
  [ "$(count reviewer)" -eq 1 ]
  [ "$(count default)" -eq 2 ]
}

@test "-q prints one pane id and points at the other session" {
  run --separate-stderr "$SCRIPT_UNDER_TEST" -q 019a
  [ "$status" -eq 0 ]
  [ "$output" = "w1:p1" ]
  [[ "$stderr" == *"herdr --session work"* ]]
}

@test "-q fails on no match and on ambiguous matches" {
  run "$SCRIPT_UNDER_TEST" -q --kind gemini
  [ "$status" -eq 1 ]
  run "$SCRIPT_UNDER_TEST" -q --kind codex
  [ "$status" -eq 3 ]
}

@test "-q does not report a unique match when a running session cannot be read" {
  export FAIL_HERDR_SESSION=work
  run --separate-stderr "$SCRIPT_UNDER_TEST" -q 0b6f
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"stub: agent list failed for work"* ]]
  [[ "$stderr" == *"results are incomplete"* ]]
}

@test "-q uses HERDR_SESSION as the current session without a socket override" {
  export HERDR_SESSION=work
  run --separate-stderr "$SCRIPT_UNDER_TEST" -q 0b6f
  [ "$status" -eq 0 ]
  [ "$output" = "w1:p1" ]
  [[ "$stderr" == *"herdr --session default agent"* ]]
}

@test "-q gives HERDR_SOCKET_PATH precedence over HERDR_SESSION" {
  export HERDR_SESSION=work
  export HERDR_SOCKET_PATH=/s/default.sock
  run --separate-stderr "$SCRIPT_UNDER_TEST" -q 019a
  [ "$status" -eq 0 ]
  [ "$output" = "w1:p1" ]
  [[ "$stderr" == *"herdr --session work agent"* ]]
}

@test "table shows workspace labels and the session column" {
  run "$SCRIPT_UNDER_TEST" --session work
  [ "$status" -eq 0 ]
  [[ "$output" == *reviewer*apm*019a2b3c-dddd* ]]
  [[ "$output" != *my-app* ]]
}
