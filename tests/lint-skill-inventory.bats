#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/lint-skill-inventory.ts"
  FIXTURE_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

run_fixture() {
  APM_LINT_SKILL_INVENTORY_MANIFEST="$FIXTURE_DIR/apm.yml" \
    APM_LINT_SKILL_INVENTORY_LOCK="$FIXTURE_DIR/apm.lock.yaml" \
    APM_LINT_SKILL_INVENTORY_DOC="$FIXTURE_DIR/skill-inventory.md" \
    run tsx "$SCRIPT_UNDER_TEST"
}

write_manifest() {
  cat >"$FIXTURE_DIR/apm.yml" <<'EOF'
dependencies:
  mcp:
    - name: context7
    - name: linear
EOF
}

write_lock() {
  cat >"$FIXTURE_DIR/apm.lock.yaml" <<'EOF'
lockfile_version: '2'
dependencies:
- repo_url: agavra/tuicr
  name: tuicr
  deployed_files:
  - .agents/skills/tuicr
  - .claude/skills/tuicr
  - .claude/skills/tuicr/SKILL.md
  - .claude/skills/tuicr/agents/openai.yaml
  deployed_file_hashes:
    .claude/skills/tuicr/SKILL.md: sha256:aaa
- repo_url: mattpocock/skills
  name: skills
  deployed_files:
  - .claude/skills/retro
  - .claude/skills/retro/SKILL.md
- repo_url: jey3dayo/apm-workspace
  name: catalog
  deployed_files:
  - .claude/skills/apm-usage
  - .claude/skills/apm-usage/SKILL.md
mcp_configs:
  context7:
    name: context7
EOF
}

write_inventory() {
  local mcp_line="$1"
  local skills_body="$2"
  cat >"$FIXTURE_DIR/skill-inventory.md" <<EOF
## global（外部スキル: root apm.yml）

${skills_body}

## global（自作 catalog: catalog/skills/）

- \`apm-usage\`

## global MCP（root apm.yml の mcp:）

${mcp_line}
EOF
}

write_matching_fixture() {
  write_manifest
  write_lock
  write_inventory '`context7`, `linear`' '- review: `tuicr`, `retro`（`apm.yml` を参照）'
}

@test "passes when inventory MCP names match apm.yml" {
  write_matching_fixture

  run_fixture
  [ "$status" -eq 0 ]
}

@test "fails when inventory omits an MCP from apm.yml" {
  write_matching_fixture
  write_inventory '`context7`' '- review: `tuicr`, `retro`'

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"linear"* ]]
}

@test "fails when inventory lists an MCP not in apm.yml" {
  write_matching_fixture
  write_inventory '`context7`, `linear`, `codex`' '- review: `tuicr`, `retro`'

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex"* ]]
}

@test "passes when inventory external skills match the lock, ignoring non-name tokens" {
  write_matching_fixture

  run_fixture
  [ "$status" -eq 0 ]
}

@test "fails naming a skill that is only in the lock" {
  write_matching_fixture
  write_inventory '`context7`, `linear`' '- review: `tuicr`'

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"only in apm.lock.yaml:   retro"* ]]
}

@test "fails naming a skill that is only in the inventory" {
  write_matching_fixture
  write_inventory '`context7`, `linear`' '- review: `tuicr`, `retro`, `ghost-skill`'

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"only in skill-inventory: ghost-skill"* ]]
}

@test "ignores skills deployed by the local jey3dayo/apm-workspace catalog" {
  write_matching_fixture
  write_inventory '`context7`, `linear`' '- review: `tuicr`, `retro`, `apm-usage`'

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"only in skill-inventory: apm-usage"* ]]
}

@test "fails when the external skills section is missing" {
  write_matching_fixture
  printf '## global MCP\n\n`context7`, `linear`\n' >"$FIXTURE_DIR/skill-inventory.md"

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"外部スキル"* ]]
}

@test "fails when the lock yields no external skills" {
  write_matching_fixture
  printf 'dependencies:\n- repo_url: jey3dayo/apm-workspace\n  deployed_files:\n  - .claude/skills/apm-usage\n' >"$FIXTURE_DIR/apm.lock.yaml"

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"no external skills"* ]]
}
