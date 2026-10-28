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
  cat >"$HERDR_BIN_PATH" <<'STUB'
#!/usr/bin/env bash
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
      {"agent":"claude","agent_status":"idle","cwd":"/src/my-app","pane_id":"w1:p1","workspace_id":"w1",
       "terminal_title_stripped":"受信トレイ","agent_session":{"value":"0b6f1c2e-aaaa"}},
      {"agent":"codex","agent_status":"working","cwd":"/src/my-app","foreground_cwd":"/src/my-app/api",
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

@test "table shows workspace labels and the session column" {
  run "$SCRIPT_UNDER_TEST" --session work
  [ "$status" -eq 0 ]
  [[ "$output" == *reviewer*apm*019a2b3c-dddd* ]]
  [[ "$output" != *my-app* ]]
}
