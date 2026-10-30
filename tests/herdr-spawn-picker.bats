#!/usr/bin/env bats

# spawn-picker.sh runs with fake fzf / ghq / herdr and a fake spawn-agent.sh,
# so it needs no tty, no repos and no live Herdr server.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/catalog/skills/herdr/scripts/spawn-picker.sh"
  BIN="$BATS_TEST_TMPDIR/bin"
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$BIN" "$STUB_DIR"
  export PATH="$BIN:$PATH"
  export HERDR_BIN_PATH="$BIN/herdr"
  export SPAWN_AGENT_BIN="$BIN/spawn-agent"
  export HERDR_SOCKET_PATH=/s/work.sock
  export HERDR_ACTIVE_PANE_ID=w2:p3
  export HERDR_ACTIVE_PANE_CWD=/src/github.com/me/my-app/api
  unset HERDR_PANE_ID

  cat >"$BIN/herdr" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "session list --json")
    echo '{"sessions":[{"default":true,"name":"default","socket_path":"/s/default.sock"},
      {"default":false,"name":"work","socket_path":"/s/work.sock"}]}' ;;
  agent) echo "  kinds: pi|claude|codex|gemini" >&2; exit 2 ;;
  *) echo "unexpected herdr call: $*" >&2; exit 9 ;;
esac
STUB
  cat >"$BIN/ghq" <<'STUB'
#!/usr/bin/env bash
[ "$*" = "list -p" ] || exit 9
printf '%s\n' /src/github.com/me/apm /src/github.com/me/my-app /src/github.com/me/my-app-old
STUB
  # Each call answers with the next line of $STUB_DIR/answers; ESC exits 130.
  cat >"$BIN/fzf" <<'STUB'
#!/usr/bin/env bash
n=$(($(cat "$STUB_DIR/fzf-n" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB_DIR/fzf-n"
cat >"$STUB_DIR/fzf-in-$n"
answer=$(sed -n "${n}p" "$STUB_DIR/answers")
[ "$answer" = ESC ] && exit 130
grep -m1 -x -- "$answer" "$STUB_DIR/fzf-in-$n" || exit 1
STUB
  cat >"$BIN/spawn-agent" <<'STUB'
#!/usr/bin/env bash
echo "$*" >"$STUB_DIR/spawn"
exit "${STUB_SPAWN_RC:-0}"
STUB
  chmod +x "$BIN"/*
}

answers() { printf '%s\n' "$@" >"$STUB_DIR/answers"; }

@test "spawns the picked kind in the picked repo next to the active pane" {
  answers /src/github.com/me/apm codex
  run "$SCRIPT_UNDER_TEST" -- --name reviewer
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_DIR/spawn")" = \
    "--kind codex --session work --pane w2:p3 --cwd /src/github.com/me/apm --name reviewer" ]
}

@test "the active pane's repo is listed first and kinds start with claude, codex" {
  answers /src/github.com/me/my-app claude
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$STUB_DIR/fzf-in-1")" = /src/github.com/me/my-app ]
  [ "$(wc -l <"$STUB_DIR/fzf-in-1")" -eq 3 ]
  [ "$(tr '\n' ' ' <"$STUB_DIR/fzf-in-2")" = "claude codex pi gemini " ]
}

@test "Esc at either picker cancels without spawning" {
  answers ESC
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 0 ]
  [ ! -e "$STUB_DIR/spawn" ]
  rm -f "$STUB_DIR/fzf-n"
  answers /src/github.com/me/apm ESC
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 0 ]
  [ ! -e "$STUB_DIR/spawn" ]
}

@test "falls back to the default session when the socket is unknown" {
  export HERDR_SOCKET_PATH=/s/other.sock
  answers /src/github.com/me/apm claude
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 0 ]
  [[ "$(cat "$STUB_DIR/spawn")" == *"--session default --pane w2:p3"* ]]
}

@test "needs an active pane id" {
  unset HERDR_ACTIVE_PANE_ID
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 2 ]
  [ ! -e "$STUB_DIR/spawn" ]
}

@test "passes spawn-agent.sh's failure code through with the error" {
  answers /src/github.com/me/apm codex
  STUB_SPAWN_RC=3 run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 3 ]
  [[ "$output" == *"spawn-agent.sh exited 3"* ]]
}

@test "passes spawn-agent.sh's not-ready code through with the error" {
  answers /src/github.com/me/apm codex
  STUB_SPAWN_RC=5 run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 5 ]
  [[ "$output" == *"spawn-agent.sh exited 5"* ]]
}
