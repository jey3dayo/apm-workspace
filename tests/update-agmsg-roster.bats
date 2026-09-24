#!/usr/bin/env bats
#
# Verifies cmd_update (apm-workspace.sh `refresh`) protects the agmsg roster
# symlinks with the same save/restore contract cmd_apply and
# cmd_sync_local_skills already carry (apm-workspace.sh:960-1019, 1157-1179).
# Observed 2026-09-23: after `mise run refresh`, the agmsg db/teams symlinks
# under ~/.agents/skills/agmsg were absent, because cmd_update calls
# `apm deps update -g` without an agmsg-state.sh save/restore around it.
# Reuses the shared tests/conformance fixture; its apm stub wipes the
# deployed agmsg skill dir on `deps update -g` (see build-fixture.sh) so this
# reproduces the bug against the unmodified script too.
#
# XDG_STATE_HOME must be pinned into the fixture explicitly, same as
# apply-agmsg-roster.bats: this session's real $XDG_STATE_HOME/agmsg is the
# live roster this suite must never touch.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
  FIXTURE_LIB="$REPO_ROOT/tests/conformance/build-fixture.sh"
  export FIXTURE_LIB
}

teardown() {
  if [ -n "${FIXTURE_BASE:-}" ]; then
    rm -rf "$FIXTURE_BASE"
  fi
}

seed_agmsg_fixture() {
  workspace_dir="$1"
  home_dir="$2"

  FIXTURE_XDG_STATE_HOME="$home_dir/.local/state"
  AGMSG_SKILL_DIR="$home_dir/.agents/skills/agmsg"
  AGMSG_STATE_ROOT="$FIXTURE_XDG_STATE_HOME/agmsg"
  mkdir -p "$AGMSG_SKILL_DIR/db" "$AGMSG_SKILL_DIR/teams/sample-team"
  echo "message-history" >"$AGMSG_SKILL_DIR/db/messages.db"
  echo '{"members":[]}' >"$AGMSG_SKILL_DIR/teams/sample-team/config.json"
}

build_own_fixture() {
  source "$FIXTURE_LIB"
  FIXTURE_BASE="$(mktemp -d)"
  build_apply_fixture "$FIXTURE_BASE"
  seed_agmsg_fixture "$FIXTURE_WORKSPACE_DIR" "$FIXTURE_HOME"
}

run_refresh() {
  HOME="$FIXTURE_HOME" \
    XDG_STATE_HOME="$FIXTURE_XDG_STATE_HOME" \
    PATH="${OVERRIDE_BIN_DIR:+$OVERRIDE_BIN_DIR:}$FIXTURE_BIN_DIR:$PATH" \
    APM_WORKSPACE_DIR="$FIXTURE_WORKSPACE_DIR" \
    FIXTURE_CALL_LOG="$FIXTURE_CALL_LOG" \
    bash "$REPO_ROOT/scripts/apm-workspace.sh" refresh
}

# Overrides apm in its own dir placed ahead of the fixture bin dir on $PATH
# (never overwriting the shared stub), reproducing the shared stub's roster
# wipe on `deps update -g` and then failing the command, to prove restore
# still runs on a mid-command abort. Written this way rather than sharing the
# base stub, matching apply-agmsg-roster.bats' fail_apm_compile pattern.
fail_apm_deps_update() {
  override_dir="$1"
  call_log="$2"
  mkdir -p "$override_dir"
  cat >"$override_dir/apm" <<STUB
#!/usr/bin/env bash
printf 'apm %s\n' "\$*" >>"$call_log"
if [ "\$*" = "deps update -g" ]; then
  if [ -n "\${HOME:-}" ] && [ -d "\$HOME/.agents/skills/agmsg" ]; then
    rm -rf "\$HOME/.agents/skills/agmsg"
    mkdir -p "\$HOME/.agents/skills/agmsg"
  fi
  exit 1
fi
exit 0
STUB
  chmod +x "$override_dir/apm"
}

@test "refresh keeps the agmsg roster linked on success" {
  build_own_fixture

  run run_refresh
  [ "$status" -eq 0 ]

  [ -L "$AGMSG_SKILL_DIR/db" ]
  [ -L "$AGMSG_SKILL_DIR/teams" ]
  [ "$(readlink "$AGMSG_SKILL_DIR/db")" = "$AGMSG_STATE_ROOT/db" ]
  [ "$(readlink "$AGMSG_SKILL_DIR/teams")" = "$AGMSG_STATE_ROOT/teams" ]
  [ "$(cat "$AGMSG_STATE_ROOT/db/messages.db")" = "message-history" ]
  [ "$(cat "$AGMSG_STATE_ROOT/teams/sample-team/config.json")" = '{"members":[]}' ]
}

@test "refresh relinks the agmsg roster even when apm deps update -g fails" {
  build_own_fixture
  OVERRIDE_BIN_DIR="$FIXTURE_BASE/override-bin"
  fail_apm_deps_update "$OVERRIDE_BIN_DIR" "$FIXTURE_CALL_LOG"

  run run_refresh
  [ "$status" -ne 0 ]

  [ -L "$AGMSG_SKILL_DIR/db" ]
  [ -L "$AGMSG_SKILL_DIR/teams" ]
  [ "$(readlink "$AGMSG_SKILL_DIR/db")" = "$AGMSG_STATE_ROOT/db" ]
  [ "$(readlink "$AGMSG_SKILL_DIR/teams")" = "$AGMSG_STATE_ROOT/teams" ]
  [ "$(cat "$AGMSG_STATE_ROOT/db/messages.db")" = "message-history" ]
  [ "$(cat "$AGMSG_STATE_ROOT/teams/sample-team/config.json")" = '{"members":[]}' ]
}
