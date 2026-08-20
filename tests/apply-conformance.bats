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
