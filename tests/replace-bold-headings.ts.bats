#!/usr/bin/env bats
#
# Pins the --dry-run (check-mode) exit-code contract for
# scripts/replace-bold-headings.ts: format:check and both lefthook gates rely
# on --dry-run failing when it finds replacement candidates, not just
# reporting them and exiting 0.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/replace-bold-headings.ts"
  FIXTURE_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

@test "--dry-run exits non-zero when it finds a bold-heading pattern to replace" {
  printf '%s\n' '**メリット**:' >"$FIXTURE_DIR/sample.md"

  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/sample.md" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"Found"*"pattern"* ]]
}

@test "--dry-run exits zero when no bold-heading pattern is found" {
  printf '%s\n' '# Already a heading' >"$FIXTURE_DIR/sample.md"

  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/sample.md" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"No bold heading/label patterns found."* ]]
}

@test "write mode (no --dry-run) still exits zero after applying replacements" {
  printf '%s\n' '**メリット**:' >"$FIXTURE_DIR/sample.md"

  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/sample.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Replaced"*"pattern"* ]]
}

@test "--dry-run reaches skills under catalog/.apm/skills but still skips other .apm/skills trees" {
  mkdir -p "$FIXTURE_DIR/catalog/.apm/skills/demo" "$FIXTURE_DIR/manual-skills/.apm/skills/demo"
  printf '%s\n' '**メリット**:' >"$FIXTURE_DIR/catalog/.apm/skills/demo/SKILL.md"
  printf '%s\n' '**メリット**:' >"$FIXTURE_DIR/manual-skills/.apm/skills/demo/SKILL.md"

  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/catalog" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"Found 1 bold heading/label pattern(s) across 1 file(s)."* ]]

  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/manual-skills" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"No markdown files found."* ]]
}
