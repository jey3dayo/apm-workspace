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
#
# Only the two success-path tests below ("relinks ... on success too" and
# "relinks the roster immediately after the skill-tree reconcile") observe
# the exact same successful apply run, so setup_file() runs it once and both
# tests read its result — same reason as apply-conformance.bats. Every other
# test forces a failure or a permission change mid-run and needs its own
# fixture so it cannot corrupt the shared one.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
  FIXTURE_LIB="$REPO_ROOT/tests/conformance/build-fixture.sh"
  export FIXTURE_LIB

  FIXTURE_SHARED_BIN_DIR="$(mktemp -d)"
  export FIXTURE_SHARED_BIN_DIR
  source "$FIXTURE_LIB"
  build_apply_stubs "$FIXTURE_SHARED_BIN_DIR" "$FIXTURE_SHARED_BIN_DIR/default-calls.log"

  FIXTURE_SHARED_BASE="$(mktemp -d)"
  export FIXTURE_SHARED_BASE
  build_apply_fixture "$FIXTURE_SHARED_BASE" "$FIXTURE_SHARED_BIN_DIR"
  export FIXTURE_SHARED_HOME="$FIXTURE_HOME"
  export FIXTURE_SHARED_WORKSPACE_DIR="$FIXTURE_WORKSPACE_DIR"
  export FIXTURE_SHARED_CALL_LOG="$FIXTURE_CALL_LOG"
  export FIXTURE_SHARED_PRIVATE_SKILL_DIR="$FIXTURE_PRIVATE_SKILL_DIR"

  seed_agmsg_fixture "$FIXTURE_SHARED_WORKSPACE_DIR" "$FIXTURE_SHARED_HOME"
  export FIXTURE_SHARED_XDG_STATE_HOME="$FIXTURE_XDG_STATE_HOME"
  export FIXTURE_SHARED_AGMSG_SKILL_DIR="$AGMSG_SKILL_DIR"
  export FIXTURE_SHARED_AGMSG_STATE_ROOT="$AGMSG_STATE_ROOT"

  FIXTURE_SHARED_OUTPUT_FILE="$FIXTURE_SHARED_BASE/apply-output.txt"
  export FIXTURE_SHARED_OUTPUT_FILE

  set +e
  HOME="$FIXTURE_SHARED_HOME" \
    XDG_STATE_HOME="$FIXTURE_SHARED_XDG_STATE_HOME" \
    PATH="$FIXTURE_SHARED_BIN_DIR:$PATH" \
    APM_WORKSPACE_DIR="$FIXTURE_SHARED_WORKSPACE_DIR" \
    FIXTURE_CALL_LOG="$FIXTURE_SHARED_CALL_LOG" \
    bash "$REPO_ROOT/scripts/apm-workspace.sh" apply >"$FIXTURE_SHARED_OUTPUT_FILE" 2>&1
  FIXTURE_SHARED_STATUS=$?
  set -e
  export FIXTURE_SHARED_STATUS
}

teardown_file() {
  rm -rf "$FIXTURE_SHARED_BASE" "$FIXTURE_SHARED_BIN_DIR"
}

teardown() {
  if [ -n "${FIXTURE_BASE:-}" ]; then
    rm -rf "$FIXTURE_BASE"
  fi
}

# `apply`'s skill-tree reconcile (reconcile_skills_root_from_stage, called
# from replace_skill_targets_from_stage) replaces each top-level skill
# entry under the deployed skills root with what's staged, and removes any
# deployed entry that isn't staged. agmsg needs to be a managed catalog
# skill here too — otherwise the reconcile's stale-removal pass would
# delete $AGMSG_SKILL_DIR outright regardless of the save/restore wiring
# under test, which would prove nothing about that wiring.
seed_agmsg_fixture() {
  workspace_dir="$1"
  home_dir="$2"

  mkdir -p "$workspace_dir/catalog/skills/agmsg"
  printf '# agmsg\n' >"$workspace_dir/catalog/skills/agmsg/SKILL.md"

  FIXTURE_XDG_STATE_HOME="$home_dir/.local/state"
  AGMSG_SKILL_DIR="$home_dir/.agents/skills/agmsg"
  AGMSG_STATE_ROOT="$FIXTURE_XDG_STATE_HOME/agmsg"
  mkdir -p "$AGMSG_SKILL_DIR/db" "$AGMSG_SKILL_DIR/teams/sample-team"
  echo "message-history" >"$AGMSG_SKILL_DIR/db/messages.db"
  echo '{"members":[]}' >"$AGMSG_SKILL_DIR/teams/sample-team/config.json"
}

# Fresh private fixture reusing the shared stub bin dir, with its own seeded agmsg roster.
build_own_fixture() {
  source "$FIXTURE_LIB"
  FIXTURE_BASE="$(mktemp -d)"
  build_apply_fixture "$FIXTURE_BASE" "$FIXTURE_SHARED_BIN_DIR"
  seed_agmsg_fixture "$FIXTURE_WORKSPACE_DIR" "$FIXTURE_HOME"
}

run_apply() {
  HOME="$FIXTURE_HOME" \
    XDG_STATE_HOME="$FIXTURE_XDG_STATE_HOME" \
    PATH="${OVERRIDE_BIN_DIR:+$OVERRIDE_BIN_DIR:}$FIXTURE_BIN_DIR:$PATH" \
    APM_WORKSPACE_DIR="$FIXTURE_WORKSPACE_DIR" \
    FIXTURE_CALL_LOG="$FIXTURE_CALL_LOG" \
    bash "$REPO_ROOT/scripts/apm-workspace.sh" apply
}

run_sync_local_skills() {
  HOME="$FIXTURE_HOME" \
    XDG_STATE_HOME="$FIXTURE_XDG_STATE_HOME" \
    PATH="${OVERRIDE_BIN_DIR:+$OVERRIDE_BIN_DIR:}$FIXTURE_BIN_DIR:$PATH" \
    APM_WORKSPACE_DIR="$FIXTURE_WORKSPACE_DIR" \
    FIXTURE_CALL_LOG="$FIXTURE_CALL_LOG" \
    bash "$REPO_ROOT/scripts/apm-workspace.sh" apply:skills:local "$@"
}

# Overrides apm (compile_codex, apm-workspace.sh:701-708, called partway
# through cmd_apply) to fail, forcing a mid-apply abort while still
# exercising the steps before it (including the agmsg-state.sh save this
# test is checking survives). Written to its own override dir placed ahead
# of the shared stub bin dir on $PATH, rather than overwriting the shared
# apm stub, so it cannot affect any other test sharing that bin dir.
fail_apm_compile() {
  override_dir="$1"
  call_log="$2"
  mkdir -p "$override_dir"
  cat >"$override_dir/apm" <<STUB
#!/usr/bin/env bash
printf 'apm %s\n' "\$*" >>"$call_log"
case "\$1" in
  compile) exit 1 ;;
esac
exit 0
STUB
  chmod +x "$override_dir/apm"
}

@test "apply relinks the agmsg roster even when it fails partway through" {
  build_own_fixture
  OVERRIDE_BIN_DIR="$FIXTURE_BASE/override-bin"
  fail_apm_compile "$OVERRIDE_BIN_DIR" "$FIXTURE_CALL_LOG"

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
  [ "$FIXTURE_SHARED_STATUS" -eq 0 ]

  [ -L "$FIXTURE_SHARED_AGMSG_SKILL_DIR/db" ]
  [ -L "$FIXTURE_SHARED_AGMSG_SKILL_DIR/teams" ]
}

@test "the agmsg:state:restore recovery task is idempotent after apply already relinked the roster" {
  build_own_fixture

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
  build_own_fixture
  chmod 555 "$FIXTURE_HOME/.agents/skills"

  run run_sync_local_skills sample-skill
  chmod 755 "$FIXTURE_HOME/.agents/skills"

  [ "$status" -ne 0 ]
  [ -L "$AGMSG_SKILL_DIR/db" ]
  [ -L "$AGMSG_SKILL_DIR/teams" ]
}

@test "apply:skills:local relinks the agmsg roster on success too" {
  build_own_fixture

  run run_sync_local_skills sample-skill
  [ "$status" -eq 0 ]

  [ -L "$AGMSG_SKILL_DIR/db" ]
  [ -L "$AGMSG_SKILL_DIR/teams" ]
}

@test "apply relinks the roster immediately after the skill-tree reconcile, not only at the end" {
  # cmd_apply now runs agmsg-state.sh restore twice on a successful run: once
  # right after replace_skill_targets_from_stage (closing the roster window
  # before the remaining apply steps run) and once more at the end (the
  # existing failure-path guarantee, idempotent to repeat). Fixing this count
  # at exactly 2 pins that contract — 1 would mean the mid-apply relink
  # regressed back out, and >2 would mean it started running more than once.
  [ "$FIXTURE_SHARED_STATUS" -eq 0 ]

  db_linked_count=$(grep -c '^agmsg db linked:' "$FIXTURE_SHARED_OUTPUT_FILE")
  teams_linked_count=$(grep -c '^agmsg teams linked:' "$FIXTURE_SHARED_OUTPUT_FILE")

  [ "$db_linked_count" -eq 2 ]
  [ "$teams_linked_count" -eq 2 ]
}
