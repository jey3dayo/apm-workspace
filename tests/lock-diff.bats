#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/lock-diff.ts"
  FIXTURE_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

run_fixture() {
  APM_LOCK_DIFF_BASE="$FIXTURE_DIR/base.yaml" \
    APM_LOCK_DIFF_HEAD="$FIXTURE_DIR/head.yaml" \
    run tsx "$SCRIPT_UNDER_TEST"
}

write_lock() {
  local file="$1" commit_a="$2" commit_b="$3" artifacts="$4"
  cat >"$FIXTURE_DIR/$file" <<EOF
lockfile_version: '2'
dependencies:
- repo_url: owner/pkg-a
  resolved_commit: ${commit_a}
  deployed_files:
  - .agents/skills/a
- repo_url: owner/mono
  resolved_commit: ${commit_b}
  virtual_path: skills/one
- repo_url: owner/mono
  resolved_commit: 9999999999999999999999999999999999999999
  virtual_path: skills/two
deployments:
${artifacts}
mcp_servers:
- name: x
EOF
}

deployment() {
  printf -- '- kind: project-relative\n  target: %s\n  value: %s\n  scope: project\n' "$1" "$2"
}

@test "reports a moved resolved_commit and omits unchanged packages" {
  arts="$(deployment claude .claude/skills/a)"
  write_lock base.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 "$arts"
  write_lock head.yaml ccccccc2222222222222222222222222222222222 bbbbbbb1111111111111111111111111111111111 "$arts"

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *"owner/pkg-a: aaaaaaa -> ccccccc"* ]]
  [[ "$output" != *"skills/one"* ]]
  [[ "$output" != *"skills/two"* ]]
}

@test "reports none when no commit moved" {
  arts="$(deployment claude .claude/skills/a)"
  write_lock base.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 "$arts"
  write_lock head.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 "$arts"

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *$'== resolved_commit moves ==\nnone'* ]]
}

@test "lists removed artifacts in full" {
  write_lock base.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 \
    "$(deployment claude .claude/skills/a; deployment claude .claude/skills/gone/SKILL.md)"
  write_lock head.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 \
    "$(deployment claude .claude/skills/a)"

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed: 1"* ]]
  [[ "$output" == *"- .claude/skills/gone/SKILL.md"* ]]
}

@test "states removed: 0 when nothing was removed" {
  arts="$(deployment claude .claude/skills/a)"
  write_lock base.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 "$arts"
  write_lock head.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 \
    "$(deployment claude .claude/skills/a; deployment codex .agents/skills/new)"

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed: 0"* ]]
  [[ "$output" == *"+ .agents/skills/new"* ]]
}

@test "reports per-target count changes such as legacy to codex" {
  write_lock base.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 \
    "$(deployment claude .claude/skills/a; deployment legacy .agents/skills/a; deployment legacy .agents/skills/b)"
  write_lock head.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 \
    "$(deployment claude .claude/skills/a; deployment codex .agents/skills/a; deployment codex .agents/skills/b)"

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *"legacy: 2 -> 0"* ]]
  [[ "$output" == *"codex: 0 -> 2"* ]]
  [[ "$output" != *"claude:"* ]]
}

@test "distinguishes duplicate repo_url by virtual_path" {
  arts="$(deployment claude .claude/skills/a)"
  write_lock base.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 "$arts"
  write_lock head.yaml aaaaaaa1111111111111111111111111111111111 ddddddd3333333333333333333333333333333333 "$arts"

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *"owner/mono (skills/one): bbbbbbb -> ddddddd"* ]]
  [[ "$output" != *"skills/two"* ]]
}

@test "fails when the base file is missing" {
  write_lock head.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 \
    "$(deployment claude .claude/skills/a)"

  run_fixture
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read base"* ]]
}

@test "fails when a lock lacks the deployments section" {
  printf 'dependencies:\n- repo_url: owner/pkg-a\n  resolved_commit: abc\n' >"$FIXTURE_DIR/base.yaml"
  write_lock head.yaml aaaaaaa1111111111111111111111111111111111 bbbbbbb1111111111111111111111111111111111 \
    "$(deployment claude .claude/skills/a)"

  run_fixture
  [ "$status" -ne 0 ]
  [[ "$output" == *"deployments"* ]]
}
