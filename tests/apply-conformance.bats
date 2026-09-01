#!/usr/bin/env bats
#
# Executes `scripts/apm-workspace.sh apply` as a real subprocess against the
# shared tests/conformance fixture and asserts the official 8-step apply
# order (see plans/apply-core-phase3-conformance-fixture.md):
#   (1) stage assembly -> (2) MCP install -> (3) Codex MCP normalize ->
#   (4) compile -> (5) runtime asset + pi instructions distribution ->
#   (6) swap -> (7) legacy cleanup -> (8) private overlay
#
# The current bash implementation follows this order already (cmd_apply,
# apm-workspace.sh:960-986), so this suite is expected to be green. The
# PowerShell counterpart (tests/apply-conformance.Tests.ps1) currently
# drifts from this order and keeps its matching assertions skipped until
# plans/apply-core-phase1-ps-parity.md lands.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURE_LIB="$REPO_ROOT/tests/conformance/build-fixture.sh"
  FIXTURE_BASE="$(mktemp -d)"
  source "$FIXTURE_LIB"
  build_apply_fixture "$FIXTURE_BASE"
}

teardown() {
  rm -rf "$FIXTURE_BASE"
}

run_apply() {
  HOME="$FIXTURE_HOME" \
    PATH="$FIXTURE_BIN_DIR:$PATH" \
    APM_WORKSPACE_DIR="$FIXTURE_WORKSPACE_DIR" \
    bash "$REPO_ROOT/scripts/apm-workspace.sh" apply
}

@test "bash apply: succeeds against the conformance fixture" {
  run run_apply
  [ "$status" -eq 0 ]
}

@test "bash apply: calls apm install before apm compile (steps 2 then 4)" {
  run run_apply
  [ "$status" -eq 0 ]

  install_line=$(grep -n '^apm install' "$FIXTURE_CALL_LOG" | head -1 | cut -d: -f1)
  compile_line=$(grep -n '^apm compile' "$FIXTURE_CALL_LOG" | head -1 | cut -d: -f1)

  [ -n "$install_line" ]
  [ -n "$compile_line" ]
  [ "$install_line" -lt "$compile_line" ]
}

@test "bash apply: deploys the managed catalog skill to every runtime target" {
  run run_apply
  [ "$status" -eq 0 ]

  [ -f "$FIXTURE_HOME/.claude/skills/sample-skill/SKILL.md" ]
  [ -f "$FIXTURE_HOME/.agents/skills/sample-skill/SKILL.md" ]
}

@test "bash apply: runtime asset distribution (step 5) overwrites the compiled Codex output (step 4)" {
  run run_apply
  [ "$status" -eq 0 ]

  # compile_codex (step 4) writes the fixture apm stub's dummy compile
  # marker to ~/.codex/AGENTS.md; sync_managed_catalog_runtime_assets +
  # sync_pi_instructions (step 5) then copies the tracked catalog
  # instructions over the same path. Seeing the catalog instructions text
  # survive is only possible if step 5 really ran after step 4.
  [ "$(cat "$FIXTURE_HOME/.codex/AGENTS.md")" = "# instructions" ]
}

@test "bash apply: private skill overlay (step 8) survives the managed skill swap (step 6)" {
  run run_apply
  [ "$status" -eq 0 ]

  # replace_skill_targets_from_stage (step 6) does a full-tree swap of each
  # runtime target's skills root from the managed-only stage. If the private
  # overlay (step 8, sync_private_skills_into_targets) ran before the swap
  # instead of after, the swap would silently wipe it back out. Both the
  # managed skill and the private skill need to be present afterward.
  [ -d "$FIXTURE_HOME/.agents/skills/sample-skill" ]
  [ -d "$FIXTURE_HOME/.agents/skills/sample-private-skill" ]

  [ -d "$FIXTURE_HOME/.claude/skills/sample-skill" ]
  [ -L "$FIXTURE_HOME/.claude/skills/sample-private-skill" ]
  link_target=$(readlink "$FIXTURE_HOME/.claude/skills/sample-private-skill")
  [ "$link_target" = "$FIXTURE_PRIVATE_SKILL_DIR" ]
}

@test "bash apply: does not recreate the skills root directory itself" {
  # reconcile_skills_root_from_stage (apm-workspace.sh) reconciles child
  # entries under the skills root one at a time and never renames or removes
  # the root itself, unlike the old full-tree swap_staged_skill_tree_into_place
  # which replaced the whole root via rename. Seed a stale skill dir before
  # apply and record the root's inode: if apply is still recreating the root,
  # the inode changes; if it only reconciles children, the inode is stable
  # and the stale (unstaged) skill is still removed.
  mkdir -p "$FIXTURE_HOME/.agents/skills/stale-skill" "$FIXTURE_HOME/.claude/skills/stale-skill"
  agents_root_inode_before=$(ls -di "$FIXTURE_HOME/.agents/skills" | awk '{print $1}')
  claude_root_inode_before=$(ls -di "$FIXTURE_HOME/.claude/skills" | awk '{print $1}')

  run run_apply
  [ "$status" -eq 0 ]

  agents_root_inode_after=$(ls -di "$FIXTURE_HOME/.agents/skills" | awk '{print $1}')
  claude_root_inode_after=$(ls -di "$FIXTURE_HOME/.claude/skills" | awk '{print $1}')

  [ "$agents_root_inode_before" = "$agents_root_inode_after" ]
  [ "$claude_root_inode_before" = "$claude_root_inode_after" ]
  [ ! -e "$FIXTURE_HOME/.agents/skills/stale-skill" ]
  [ ! -e "$FIXTURE_HOME/.claude/skills/stale-skill" ]
  [ -f "$FIXTURE_HOME/.agents/skills/sample-skill/SKILL.md" ]
}

@test "bash apply: leaves no swap staging/backup directories under the skills root" {
  # Also seed a stale .apm-skills-backup.* left over from a hypothetical
  # crashed prior run (swap_staged_tree_into_place only cleans its own
  # staging/backup dirs on the success and handled-failure paths, not a hard
  # kill mid-swap) to prove reconcile_skills_root_from_stage sweeps these
  # explicitly now that it no longer replaces the whole root wholesale.
  mkdir -p "$FIXTURE_HOME/.agents/skills/.apm-skills-backup.99999"
  echo "stale" >"$FIXTURE_HOME/.agents/skills/.apm-skills-backup.99999/leftover"

  run run_apply
  [ "$status" -eq 0 ]

  run bash -c "find '$FIXTURE_HOME/.agents/skills' -mindepth 1 -maxdepth 1 -name '.apm-*'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run bash -c "find '$FIXTURE_HOME/.claude/skills' -mindepth 1 -maxdepth 1 -name '.apm-*'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
