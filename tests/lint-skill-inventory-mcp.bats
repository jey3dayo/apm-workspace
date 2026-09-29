#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/lint-skill-inventory-mcp.ts"
  FIXTURE_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

run_fixture() {
  APM_LINT_SKILL_INVENTORY_MANIFEST="$FIXTURE_DIR/apm.yml" \
    APM_LINT_SKILL_INVENTORY_DOC="$FIXTURE_DIR/skill-inventory.md" \
    run tsx "$SCRIPT_UNDER_TEST"
}

write_inventory() {
  local mcp_line="$1"
  cat >"$FIXTURE_DIR/skill-inventory.md" <<EOF
## global MCP（root apm.yml の mcp:）

${mcp_line}
EOF
}

@test "passes when inventory MCP names match apm.yml" {
  cat >"$FIXTURE_DIR/apm.yml" <<'EOF'
dependencies:
  mcp:
    - name: context7
    - name: linear
EOF
  write_inventory '`context7`, `linear`'

  run_fixture
  [ "$status" -eq 0 ]
}

@test "fails when inventory omits an MCP from apm.yml" {
  cat >"$FIXTURE_DIR/apm.yml" <<'EOF'
dependencies:
  mcp:
    - name: context7
    - name: linear
EOF
  write_inventory '`context7`'

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"linear"* ]]
}

@test "fails when inventory lists an MCP not in apm.yml" {
  cat >"$FIXTURE_DIR/apm.yml" <<'EOF'
dependencies:
  mcp:
    - name: context7
EOF
  write_inventory '`context7`, `codex`'

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex"* ]]
}
