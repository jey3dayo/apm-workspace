#!/usr/bin/env bats
#
# Verifies the agmsg roster save/restore contract that `cmd_apply` and
# `cmd_sync_local_skills` now carry directly (apm-workspace.sh:960-986,
# 1129-1151), rather than relying on mise's `depends`/`depends_post` (which
# never fired `agmsg:state:restore` on a failed `apply` — see
# plans/apply-core-phase2-roster-in-apply.md and
# tmp/apply-audit-20260821/report.md §3). Reuses the shared
# tests/conformance fixture and seeds a plain (pre-relink) agmsg roster into
# its fake $HOME, then forces mid-command failures to prove restore still
# runs.
#
# XDG_STATE_HOME must be pinned into the fixture explicitly everywhere below:
# this session's real $XDG_STATE_HOME/agmsg is the actual live roster this
# suite must never touch, and agmsg-state.sh only honors $HOME for the
# deploy-target half of its paths, not the store half.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURE_LIB="$REPO_ROOT/tests/conformance/build-fixture.sh"
  FIXTURE_BASE="$(mktemp -d)"
  source "$FIXTURE_LIB"
  build_apply_fixture "$FIXTURE_BASE"

  FIXTURE_XDG_STATE_HOME="$FIXTURE_HOME/.local/state"

  # `apply`'s skill-tree swap (replace_skill_targets_from_stage,
  # apm-workspace.sh:980) wipes the *entire* deployed skills root and
  # replaces it with only what's staged from the catalog, so agmsg needs to
  # be a managed catalog skill here too — otherwise the swap would delete
  # $AGMSG_SKILL_DIR outright regardless of the save/restore wiring under
  # test, which would prove nothing about that wiring.
  mkdir -p "$FIXTURE_WORKSPACE_DIR/catalog/skills/agmsg"
  printf '# agmsg\n' >"$FIXTURE_WORKSPACE_DIR/catalog/skills/agmsg/SKILL.md"

  # Seed a plain (non-symlink) agmsg roster, as if it had never been
  # save/restore-relinked yet.
  AGMSG_SKILL_DIR="$FIXTURE_HOME/.agents/skills/agmsg"
  AGMSG_STATE_ROOT="$FIXTURE_XDG_STATE_HOME/agmsg"
  mkdir -p "$AGMSG_SKILL_DIR/db" "$AGMSG_SKILL_DIR/teams/sample-team"
  echo "message-history" >"$AGMSG_SKILL_DIR/db/messages.db"
  echo '{"members":[]}' >"$AGMSG_SKILL_DIR/teams/sample-team/config.json"
}

teardown() {
  rm -rf "$FIXTURE_BASE"
}

run_apply() {
  HOME="$FIXTURE_HOME" \
    XDG_STATE_HOME="$FIXTURE_XDG_STATE_HOME" \
    PATH="$FIXTURE_BIN_DIR:$PATH" \
    APM_WORKSPACE_DIR="$FIXTURE_WORKSPACE_DIR" \
    bash "$REPO_ROOT/scripts/apm-workspace.sh" apply
}

run_sync_local_skills() {
  HOME="$FIXTURE_HOME" \
    XDG_STATE_HOME="$FIXTURE_XDG_STATE_HOME" \
    PATH="$FIXTURE_BIN_DIR:$PATH" \
    APM_WORKSPACE_DIR="$FIXTURE_WORKSPACE_DIR" \
    bash "$REPO_ROOT/scripts/apm-workspace.sh" apply:skills:local "$@"
}

# Overrides the fixture's `apm` stub so `apm compile ...` (compile_codex,
# apm-workspace.sh:701-708, called partway through cmd_apply) fails, forcing
# a mid-apply abort while still exercising the steps before it (including
# the agmsg-state.sh save this test is checking survives).
fail_apm_compile() {
  cat >"$FIXTURE_BIN_DIR/apm" <<STUB
#!/usr/bin/env bash
printf 'apm %s\n' "\$*" >>"$FIXTURE_CALL_LOG"
case "\$1" in
  compile) exit 1 ;;
esac
exit 0
STUB
  chmod +x "$FIXTURE_BIN_DIR/apm"
}

@test "apply relinks the agmsg roster even when it fails partway through" {
  fail_apm_compile

  run run_apply
  [ "$status" -ne 0 ]

  [ -L "$AGMSG_SKILL_DIR/db" ]
  [ -L "$AGMSG_SKILL_DIR/teams" ]
  [ "$(readlink "$AGMSG_SKILL_DIR/db")" = "$AGMSG_STATE_ROOT/db" ]
  [ "$(readlink "$AGMSG_SKILL_DIR/teams")" = "$AGMSG_STATE_ROOT/teams" ]
  [ "$(cat "$AGMSG_STATE_ROOT/db/messages.db")" = "message-history" ]
  [ "$(cat "$AGMSG_STATE_ROOT/teams/sample-team/config.json")" = '{"members":[]}' ]
}

@test "apply relinks the agmsg roster on success too" {
  run run_apply
  [ "$status" -eq 0 ]

  [ -L "$AGMSG_SKILL_DIR/db" ]
  [ -L "$AGMSG_SKILL_DIR/teams" ]
}

@test "the agmsg:state:restore recovery task is idempotent after apply already relinked the roster" {
  run run_apply
  [ "$status" -eq 0 ]
  [ -L "$AGMSG_SKILL_DIR/db" ]

  # Mirrors running the manual `agmsg:state:restore` mise task after apply
  # already restored the roster inline — must be a harmless no-op re-link,
  # not lose or duplicate anything.
  run env HOME="$FIXTURE_HOME" XDG_STATE_HOME="$FIXTURE_XDG_STATE_HOME" \
    bash "$REPO_ROOT/scripts/agmsg-state.sh" restore
  [ "$status" -eq 0 ]

  [ -L "$AGMSG_SKILL_DIR/db" ]
  [ -L "$AGMSG_SKILL_DIR/teams" ]
  [ "$(readlink "$AGMSG_SKILL_DIR/db")" = "$AGMSG_STATE_ROOT/db" ]
  [ "$(cat "$AGMSG_STATE_ROOT/db/messages.db")" = "message-history" ]
  [ "$(cat "$AGMSG_STATE_ROOT/teams/sample-team/config.json")" = '{"members":[]}' ]
}

@test "apply:skills:local relinks the agmsg roster even when it fails partway through" {
  # cmd_sync_local_skills (apply:skills:local) shares the same save/restore
  # wiring as cmd_apply; force replace_codex_skill_target_from_stage's
  # `mkdir -p "$target_skill_path"` to fail by revoking write access on the
  # deploy target's Codex skills root, after the roster save/trap setup has
  # already run. (An earlier failure point — an unresolvable requested skill
  # id — can't be used here: `fail`'s `exit` inside the doubly-nested command
  # substitution in requested_personal_skill_records/requested_local_skill_ids
  # only unwinds that inner subshell, not the script, because `set -e` isn't
  # inherited into nested command substitutions without `shopt -s
  # inherit_errexit`. That's a pre-existing quirk of this call chain, not
  # something introduced by the roster wiring under test here.)
  chmod 555 "$FIXTURE_HOME/.agents/skills"

  run run_sync_local_skills sample-skill
  chmod 755 "$FIXTURE_HOME/.agents/skills"

  [ "$status" -ne 0 ]
  [ -L "$AGMSG_SKILL_DIR/db" ]
  [ -L "$AGMSG_SKILL_DIR/teams" ]
}

@test "apply:skills:local relinks the agmsg roster on success too" {
  run run_sync_local_skills sample-skill
  [ "$status" -eq 0 ]

  [ -L "$AGMSG_SKILL_DIR/db" ]
  [ -L "$AGMSG_SKILL_DIR/teams" ]
}
