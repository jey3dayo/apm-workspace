#!/usr/bin/env bats
#
# Behavioral tests for scripts/agmsg-state.sh's absorb_plain_dir step, invoked
# as a subprocess via the public `save` command (matching the
# subprocess-invocation style used in apm-workspace.sh.bats). The script has
# no dispatch guard, so it cannot be `source`d directly in a bats setup
# without running its case statement — tests exercise it through `bash
# $SCRIPT_UNDER_TEST <cmd>` with HOME/XDG_STATE_HOME redirected into a
# per-test fixture instead.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/agmsg-state.sh"

  FIXTURE_HOME="$(mktemp -d)"
  SKILL_DIR="$FIXTURE_HOME/.agents/skills/agmsg"
  STATE_ROOT="$FIXTURE_HOME/.local/state/agmsg"
  mkdir -p "$SKILL_DIR/db"
  echo "message-history" >"$SKILL_DIR/db/messages.db"
}

teardown() {
  chmod -R u+w "$STATE_ROOT" 2>/dev/null || true
  rm -rf "$FIXTURE_HOME"
}

@test "save absorbs a plain runtime dir into the store and removes the original" {
  run env HOME="$FIXTURE_HOME" XDG_STATE_HOME="$FIXTURE_HOME/.local/state" bash "$SCRIPT_UNDER_TEST" save
  [ "$status" -eq 0 ]
  [ ! -e "$SKILL_DIR/db" ]
  [ "$(cat "$STATE_ROOT/db/messages.db")" = "message-history" ]
}

@test "save absorbs cleanly when -n skips an already-authoritative store file" {
  mkdir -p "$STATE_ROOT/db"
  echo "already-authoritative" >"$STATE_ROOT/db/messages.db"

  run env HOME="$FIXTURE_HOME" XDG_STATE_HOME="$FIXTURE_HOME/.local/state" bash "$SCRIPT_UNDER_TEST" save
  [ "$status" -eq 0 ]
  [ ! -e "$SKILL_DIR/db" ]
  # -n must not overwrite the store's existing (authoritative) copy.
  [ "$(cat "$STATE_ROOT/db/messages.db")" = "already-authoritative" ]
}

@test "save preserves the runtime dir and fails loudly when the copy into the store fails" {
  mkdir -p "$STATE_ROOT/db"
  chmod 555 "$STATE_ROOT/db"

  run env HOME="$FIXTURE_HOME" XDG_STATE_HOME="$FIXTURE_HOME/.local/state" bash "$SCRIPT_UNDER_TEST" save
  [ "$status" -ne 0 ]
  # The history that was about to be discarded must still be on disk.
  [ -e "$SKILL_DIR/db" ]
  [ "$(cat "$SKILL_DIR/db/messages.db")" = "message-history" ]
  [[ "$output" == *"$SKILL_DIR/db"* ]]
}
