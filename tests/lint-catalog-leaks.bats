#!/usr/bin/env bats

# Behavioral tests for scripts/lint-catalog-leaks.ts. Every fixture is kept
# under a temporary catalog so the real managed catalog is never modified.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/lint-catalog-leaks.ts"
  FIXTURE_DIR="$(mktemp -d)"
  mkdir -p "$FIXTURE_DIR/catalog/.apm/agents" "$FIXTURE_DIR/catalog/.apm/skills"
  touch "$FIXTURE_DIR/catalog/.apm/agents/existing-agent.agent.md"
  # Point at a fixture path so a real local denylist never leaks into tests.
  export APM_LEAK_DENYLIST="$FIXTURE_DIR/denylist.txt"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

run_fixture() {
  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/catalog/.apm/agents" "$FIXTURE_DIR/catalog/.apm/skills"
}

@test "fails on a denylisted organization term without echoing it" {
  printf '# comment\nexample-org\n' >"$APM_LEAK_DENYLIST"
  cat >"$FIXTURE_DIR/catalog/.apm/skills/broken.md" <<'EOF'
Deploy to Example-Org/service first.
EOF

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken.md:1: denylisted organization term"* ]]
  [[ "$output" != *"Example-Org"* ]]
}

@test "redacts denylisted terms from other diagnostics and paths" {
  printf 'example-org\n' >"$APM_LEAK_DENYLIST"
  mkdir -p "$FIXTURE_DIR/catalog/.apm/skills/example-org-skill"
  cat >"$FIXTURE_DIR/catalog/.apm/skills/example-org-skill/SKILL.md" <<'EOF'
(use example-org-agent)
EOF

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"unresolved agent reference: <redacted>-agent"* ]]
  [[ "$output" != *"example-org"* ]]
}
