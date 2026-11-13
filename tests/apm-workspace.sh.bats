#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/apm-workspace.sh"
}

@test "catalog instruction allowlist accepts the scoped design rule and still rejects another instruction" {
  local fixture
  fixture="$BATS_TEST_TMPDIR/catalog-layout"
  mkdir -p "$fixture/catalog/.apm/instructions"
  printf 'guide\n' >"$fixture/catalog/.apm/instructions/ai-collaboration.instructions.md"
  printf 'design\n' >"$fixture/catalog/.apm/instructions/claude-md-design.instructions.md"
  run bash -c '
    WORKSPACE_DIR="$1" CATALOG_DIR_NAME=catalog CATALOG_INSTRUCTIONS_FILE_NAME=ai-collaboration.instructions.md
    . "$2/scripts/lib/workspace-core.sh"
    . "$2/scripts/lib/catalog-inventory.sh"
    catalog_apm_dir_claim_message
  ' bash "$fixture" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf 'other\n' >"$fixture/catalog/.apm/instructions/other.instructions.md"
  run bash -c '
    WORKSPACE_DIR="$1" CATALOG_DIR_NAME=catalog CATALOG_INSTRUCTIONS_FILE_NAME=ai-collaboration.instructions.md
    . "$2/scripts/lib/workspace-core.sh"
    . "$2/scripts/lib/catalog-inventory.sh"
    catalog_apm_dir_claim_message
  ' bash "$fixture" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"instructions/other.instructions.md"* ]]
}

make_doctor_fixture() {
  doctor_workspace_dir="$(mktemp -d)"
  doctor_home="$(mktemp -d)"
  doctor_bin="$(mktemp -d)"

  git -C "$doctor_workspace_dir" init -q
  mkdir -p \
    "$doctor_workspace_dir/catalog/.apm/skills" \
    "$doctor_workspace_dir/catalog/.apm/agents" \
    "$doctor_workspace_dir/catalog/commands" \
    "$doctor_workspace_dir/catalog/rules"
  printf 'dependencies: []\n' >"$doctor_workspace_dir/apm.yml"
  mkdir -p "$doctor_workspace_dir/catalog/.apm/instructions"
  printf -- '---\ndescription: fixture guide\n---\n\n# instructions\n' >"$doctor_workspace_dir/catalog/.apm/instructions/ai-collaboration.instructions.md"

  cat >"$doctor_bin/apm" <<'EOF'
#!/bin/sh
case "$1" in
  --version) printf '%s\n' 'apm test fixture' ;;
  deps|compile) ;;
esac
EOF
  chmod +x "$doctor_bin/apm"

  for target_dir in .claude .codex .cursor .config/opencode; do
    mkdir -p "$doctor_home/$target_dir/agents" "$doctor_home/$target_dir/commands" "$doctor_home/$target_dir/rules"
  done
  mkdir -p \
    "$doctor_home/.claude/skills" \
    "$doctor_home/.agents/skills" \
    "$doctor_home/.cursor/skills" \
    "$doctor_home/.config/opencode/skills"
  printf '# config\n' >"$doctor_home/.claude/CLAUDE.md"
  printf '# config\n' >"$doctor_home/.codex/AGENTS.md"
  printf '# config\n' >"$doctor_home/.cursor/AGENTS.md"
}

doctor_fixture_env() {
  # Pin XDG_STATE_HOME into the fixture explicitly: agmsg-state.sh (and the
  # doctor check mirroring it) fall back to "$HOME/.local/state" only when
  # XDG_STATE_HOME is unset, but this session's real XDG_STATE_HOME is set
  # and would otherwise leak in here, making the agmsg roster link check
  # compare against the live machine's state root instead of the fixture's.
  env HOME="$doctor_home" XDG_STATE_HOME="$doctor_home/.local/state" PATH="$doctor_bin:$PATH" APM_WORKSPACE_DIR="$doctor_workspace_dir" "$@"
}

@test "doctor succeeds when all managed catalog outputs are present with the right type" {
  make_doctor_fixture

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -eq 0 ]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

make_holds_fixture() {
  holds_workspace_dir="$(mktemp -d)"
  held_sha="4a712f2aeba8f0b2070f7533b827c7cac78c9fdf"
  bumped_sha="0123456789abcdef0123456789abcdef01234567"

  git -C "$holds_workspace_dir" init -q
  mkdir -p "$holds_workspace_dir/docs"
  printf 'fujibee/agmsg %s hidden character, see docs/package-decisions.md\n' "$held_sha" >"$holds_workspace_dir/docs/dependency-holds.txt"
}

write_holds_fixture_pin() {
  printf 'dependencies:\n  apm:\n    - fujibee/agmsg#%s\n' "$1" >"$holds_workspace_dir/apm.yml"
  printf 'dependencies:\n- repo_url: fujibee/agmsg\n  resolved_commit: %s\n' "$1" >"$holds_workspace_dir/apm.lock.yaml"
}

@test "validate fails when a held dependency is pinned to a different commit" {
  make_holds_fixture
  write_holds_fixture_pin "$bumped_sha"

  run env APM_WORKSPACE_DIR="$holds_workspace_dir" bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"fujibee/agmsg"* ]]
  [[ "$output" == *"$held_sha"* ]]
  [[ "$output" == *"$bumped_sha"* ]]
  rm -rf "$holds_workspace_dir"
}

@test "validate fails when a nested dependency of a held repo is pinned to a different commit" {
  make_holds_fixture
  printf 'dependencies:\n  apm:\n    - fujibee/agmsg#%s\n    - fujibee/agmsg/skills/extra#%s\n' "$held_sha" "$bumped_sha" >"$holds_workspace_dir/apm.yml"
  printf 'dependencies:\n- repo_url: fujibee/agmsg\n  resolved_commit: %s\n- repo_url: fujibee/agmsg\n  virtual_path: skills/extra\n  resolved_commit: %s\n' "$held_sha" "$bumped_sha" >"$holds_workspace_dir/apm.lock.yaml"

  run env APM_WORKSPACE_DIR="$holds_workspace_dir" bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"held dependency fujibee/agmsg"* ]]
  [[ "$output" == *"$bumped_sha"* ]]
  rm -rf "$holds_workspace_dir"
}

@test "validate passes when a held dependency stays on its held commit" {
  make_holds_fixture
  write_holds_fixture_pin "$held_sha"

  run env APM_WORKSPACE_DIR="$holds_workspace_dir" bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -eq 0 ]
  rm -rf "$holds_workspace_dir"
}
