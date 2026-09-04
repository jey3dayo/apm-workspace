#!/usr/bin/env bats
#
# Behavioral tests for scripts/lint-frontmatter.ts (invoked directly via
# tsx, matching the subprocess-invocation style used in
# replace-bold-headings.ts.bats). Guards the gate added after an unquoted
# ": " inside a `description` scalar broke YAML frontmatter and still passed
# `mise run check` (catalog/agents/{docs-manager,error-fixer,
# monitoring-alerts,researcher,serena}.md, fixed in commit 5efd532).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/lint-frontmatter.ts"
  FIXTURE_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

@test "fails on an unquoted ': ' inside a description scalar (the real regression)" {
  mkdir -p "$FIXTURE_DIR/agents"
  cat >"$FIXTURE_DIR/agents/broken.md" <<'EOF'
---
name: broken
description: Use for reviewing docs: check size limits, fix problems.
tools: "*"
---

Body.
EOF

  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/agents"
  [ "$status" -ne 0 ]
  [[ "$output" == *"broken.md"* ]]
  [[ "$output" == *"syntax error"* ]]
}

@test "passes well-formed frontmatter" {
  mkdir -p "$FIXTURE_DIR/agents"
  cat >"$FIXTURE_DIR/agents/ok.md" <<'EOF'
---
name: ok
description: "Use for reviewing docs: check size limits, fix problems."
tools: "*"
---

Body.
EOF

  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/agents"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checked 1 file"* ]]
}

@test "skips a markdown file with no frontmatter instead of failing it" {
  mkdir -p "$FIXTURE_DIR/skills"
  cat >"$FIXTURE_DIR/skills/reference.md" <<'EOF'
# Just a reference doc

No frontmatter here at all.
EOF

  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/skills"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checked 0 file"* ]]
}

@test "fails an agent frontmatter missing the required 'name' key" {
  mkdir -p "$FIXTURE_DIR/agents"
  cat >"$FIXTURE_DIR/agents/no-name.md" <<'EOF'
---
description: "Missing the name key."
tools: "*"
---

Body.
EOF

  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/agents"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no-name.md"* ]]
  [[ "$output" == *"'name'"* ]]
}

@test "fails a SKILL.md missing the required 'description' key" {
  mkdir -p "$FIXTURE_DIR/skills/my-skill"
  cat >"$FIXTURE_DIR/skills/my-skill/SKILL.md" <<'EOF'
---
name: my-skill
---

Body.
EOF

  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/skills"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKILL.md"* ]]
  [[ "$output" == *"'description'"* ]]
}

@test "the current catalog passes (regression guard)" {
  run tsx "$SCRIPT_UNDER_TEST" \
    "$REPO_ROOT/catalog/agents" \
    "$REPO_ROOT/catalog/skills" \
    "$REPO_ROOT/catalog/commands" \
    "$REPO_ROOT/catalog/rules"
  [ "$status" -eq 0 ]
}
