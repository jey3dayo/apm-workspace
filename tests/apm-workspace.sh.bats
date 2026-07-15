#!/usr/bin/env bats
#
# Behavioral unit tests for the pure, side-effect-free helpers in
# scripts/apm-workspace.sh. Sourcing the script from bats leaves
# ${BASH_SOURCE[0]} != $0, so the bottom-of-file dispatch guard keeps the
# command dispatch from running on load.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source "$REPO_ROOT/scripts/apm-workspace.sh"
}

# --- validate_skill_id -------------------------------------------------------

@test "validate_skill_id accepts a plain id" {
  run validate_skill_id "foo"
  [ "$status" -eq 0 ]
}

@test "validate_skill_id accepts a hyphenated id" {
  run validate_skill_id "foo-bar"
  [ "$status" -eq 0 ]
}

@test "validate_skill_id accepts a namespaced id" {
  run validate_skill_id "a:b:c"
  [ "$status" -eq 0 ]
}

@test "validate_skill_id accepts dots and underscores" {
  run validate_skill_id "a.b_c"
  [ "$status" -eq 0 ]
}

@test "validate_skill_id rejects an empty id" {
  run validate_skill_id ""
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a single dot" {
  run validate_skill_id "."
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a double dot" {
  run validate_skill_id ".."
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a forward slash" {
  run validate_skill_id "a/b"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a backslash" {
  run validate_skill_id "a\\b"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a leading colon" {
  run validate_skill_id ":lead"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a trailing colon" {
  run validate_skill_id "trail:"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects doubled colons" {
  run validate_skill_id "a::b"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a space" {
  run validate_skill_id "bad space"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a leading hyphen" {
  run validate_skill_id "-leading"
  [ "$status" -ne 0 ]
}

# --- validate_skill_path_segments -------------------------------------------

@test "validate_skill_path_segments accepts a run of valid segments" {
  run validate_skill_path_segments "a:b:c" a b c
  [ "$status" -eq 0 ]
}

@test "validate_skill_path_segments rejects a run containing .." {
  run validate_skill_path_segments "a:..:c" a .. c
  [ "$status" -ne 0 ]
}

@test "validate_skill_path_segments rejects a run containing an empty segment" {
  run validate_skill_path_segments "a::c" a "" c
  [ "$status" -ne 0 ]
}

# --- skill_id_to_manifest_path ----------------------------------------------

@test "skill_id_to_manifest_path converts a:b:c to a/b/c" {
  run skill_id_to_manifest_path "a:b:c"
  [ "$status" -eq 0 ]
  [ "$output" = "a/b/c" ]
}

@test "skill_id_to_manifest_path leaves a single segment unchanged" {
  run skill_id_to_manifest_path "a"
  [ "$status" -eq 0 ]
  [ "$output" = "a" ]
}

# --- format_skill_name ------------------------------------------------------

@test "format_skill_name uses the logical leaf of a namespaced id" {
  run format_skill_name "sample:spec-init"
  [ "$status" -eq 0 ]
  [ "$output" = "spec-init" ]
}

@test "format_skill_name uses the final segment of a nested namespaced id" {
  run format_skill_name "superpowers:using-superpowers"
  [ "$status" -eq 0 ]
  [ "$output" = "using-superpowers" ]
}

# --- workspace_remote_to_repo_reference -------------------------------------

@test "workspace_remote_to_repo_reference parses an https remote" {
  run workspace_remote_to_repo_reference "https://github.com/owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

@test "workspace_remote_to_repo_reference parses a git@ remote" {
  run workspace_remote_to_repo_reference "git@github.com:owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

# --- is_path_under_dir ------------------------------------------------------

@test "is_path_under_dir returns 0 for a child path" {
  parent="$(mktemp -d)"
  mkdir -p "$parent/child"
  run is_path_under_dir "$parent/child" "$parent"
  [ "$status" -eq 0 ]
  rm -rf "$parent"
}

@test "is_path_under_dir returns 1 for a sibling outside the directory" {
  base="$(mktemp -d)"
  other="$(mktemp -d)"
  run is_path_under_dir "$other" "$base"
  [ "$status" -eq 1 ]
  rm -rf "$base" "$other"
}

@test "is_path_under_dir returns 0 for identical paths" {
  dir="$(mktemp -d)"
  run is_path_under_dir "$dir" "$dir"
  [ "$status" -eq 0 ]
  rm -rf "$dir"
}
