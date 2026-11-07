#!/usr/bin/env bats

# lint-memory.sh runs against throwaway memory directories built per test.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/catalog/.apm/skills/memory-audit/scripts/lint-memory.sh"
  MEM="$BATS_TEST_TMPDIR/memory"
  mkdir -p "$MEM"
}

write_memory() {
  # $1: slug, $2: body line
  cat >"$MEM/$1.md" <<EOF
---
name: $1
description: "summary of $1"
metadata:
  type: project
---

$2
EOF
}

write_clean_pair() {
  write_memory alpha "see [[beta]]"
  write_memory beta "standalone"
  printf '# Memory Index\n\n- [Alpha](alpha.md) — a\n- [Beta](beta.md) — b\n' >"$MEM/MEMORY.md"
}

@test "a consistent directory passes" {
  write_clean_pair
  run "$SCRIPT_UNDER_TEST" "$MEM"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a link to an unwritten memory is a note and does not fail" {
  write_clean_pair
  write_memory alpha "see [[gone]]"
  run "$SCRIPT_UNDER_TEST" "$MEM"
  [ "$status" -eq 0 ]
  [[ "$output" == *"note: alpha.md links to unwritten [[gone]]"* ]]
}

@test "a memory missing from the index is reported" {
  write_clean_pair
  write_memory gamma "orphan"
  run "$SCRIPT_UNDER_TEST" "$MEM"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gamma.md is not listed in MEMORY.md"* ]]
}

@test "an index entry for a missing file is reported" {
  write_clean_pair
  printf -- '- [Ghost](ghost.md) — x\n' >>"$MEM/MEMORY.md"
  run "$SCRIPT_UNDER_TEST" "$MEM"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MEMORY.md points to missing ghost.md"* ]]
}

@test "a name that differs from the file name is reported" {
  write_clean_pair
  sed -i.bak 's/^name: beta$/name: other/' "$MEM/beta.md"
  rm -f "$MEM/beta.md.bak"
  run "$SCRIPT_UNDER_TEST" "$MEM"
  [ "$status" -eq 1 ]
  [[ "$output" == *"beta.md declares name 'other'"* ]]
}

@test "an unknown type is reported" {
  write_clean_pair
  sed -i.bak 's/type: project/type: note/' "$MEM/beta.md"
  rm -f "$MEM/beta.md.bak"
  run "$SCRIPT_UNDER_TEST" "$MEM"
  [ "$status" -eq 1 ]
  [[ "$output" == *"beta.md has type 'note'"* ]]
}

@test "a file without frontmatter is reported" {
  write_clean_pair
  printf 'no frontmatter here\n' >"$MEM/beta.md"
  run "$SCRIPT_UNDER_TEST" "$MEM"
  [ "$status" -eq 1 ]
  [[ "$output" == *"beta.md has no frontmatter"* ]]
}

@test "an index-only directory with no memories passes" {
  printf '# Memory Index\n' >"$MEM/MEMORY.md"
  run "$SCRIPT_UNDER_TEST" "$MEM"
  [ "$status" -eq 0 ]
}

@test "a missing directory or MEMORY.md exits 2" {
  run "$SCRIPT_UNDER_TEST" "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
  run "$SCRIPT_UNDER_TEST" "$MEM"
  [ "$status" -eq 2 ]
}
