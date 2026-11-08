#!/usr/bin/env bats

# Behavioral tests for scripts/lint-catalog-leaks.ts. Every fixture is kept
# under a temporary catalog so the real managed catalog is never modified.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/lint-catalog-leaks.ts"
  FIXTURE_DIR="$(mktemp -d)"
  mkdir -p "$FIXTURE_DIR/catalog/agents" "$FIXTURE_DIR/catalog/.apm/skills"
  touch "$FIXTURE_DIR/catalog/agents/existing-agent.md"
  # Point at a fixture path so a real local denylist never leaks into tests.
  export APM_LEAK_DENYLIST="$FIXTURE_DIR/denylist.txt"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

run_fixture() {
  run tsx "$SCRIPT_UNDER_TEST" "$FIXTURE_DIR/catalog/agents" "$FIXTURE_DIR/catalog/.apm/skills"
}

@test "fails on an unresolved (use deployment) reference" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/broken.md" <<'EOF'
(use deployment)
EOF

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"deployment"* ]]
}

@test "fails on an unresolved decorated Agent reference" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/broken.md" <<'EOF'
- 🤖 **Agent: route53-operations** - DNS management
EOF

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"route53-operations"* ]]
}

@test "passes an empty Agent label without reading the next line" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/ok.md" <<'EOF'
# Example

Agent:

aws ecr describe-images --repository-name example
EOF

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" != *"aws"* ]]
}

@test "fails on a backticked agent reference" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/broken.md" <<'EOF'
データベース関連操作は `database-operations` agent へ委譲する。
EOF

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"database-operations"* ]]
}

@test "passes references to existing agents" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/ok.md" <<'EOF'
(use existing-agent)
EOF

  run_fixture
  [ "$status" -eq 0 ]
}

@test "passes excluded built-in agents" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/ok.md" <<'EOF'
(use Explore)
(use general-purpose)
EOF

  run_fixture
  [ "$status" -eq 0 ]
}

@test "warns on a concrete profile value" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/warn.md" <<'EOF'
aws --profile aws-example-admin-role
EOF

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *"aws-example-admin-role"* ]]
  [[ "$output" == *"warn.md:1"* ]]
}

@test "does not warn on profile placeholders" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/ok.md" <<'EOF'
--profile $AWS_PROFILE
--profile <your-profile>
EOF

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" != *"warning(s)"* ]]
}

@test "warns on an AWS account ID in an ARN" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/warn.md" <<'EOF'
arn:aws:lambda:ap-northeast-1:123456789012:function:x
EOF

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning(s)"* ]]
  [[ "$output" == *"warn.md:1"* ]]
}

@test "does not warn on an account-less S3 ARN" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/ok.md" <<'EOF'
arn:aws:s3:::example-bucket
EOF

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" != *"warning(s)"* ]]
}

@test "warns on an absolute repository checkout path" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/warn.md" <<'EOF'
/Users/alice/src/github.com/org/repo
EOF

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning(s)"* ]]
  [[ "$output" == *"warn.md:1"* ]]
}

@test "does not warn on a non-checkout user path" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/ok.md" <<'EOF'
/Users/alice/.agents/skills/agmsg/scripts/join.sh
EOF

  run_fixture
  [ "$status" -eq 0 ]
  [[ "$output" != *"warning(s)"* ]]
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

@test "does not match a denylisted term inside a longer token" {
  printf 'org\n' >"$APM_LEAK_DENYLIST"
  cat >"$FIXTURE_DIR/catalog/.apm/skills/ok.md" <<'EOF'
sha256:abcorg123 organization
EOF

  run_fixture
  [ "$status" -eq 0 ]
}

@test "skips the denylist when the file is absent" {
  cat >"$FIXTURE_DIR/catalog/.apm/skills/ok.md" <<'EOF'
example-org
EOF

  run_fixture
  [ "$status" -eq 0 ]
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

@test "checks non-markdown files under explicit targets" {
  printf 'example-org\n' >"$APM_LEAK_DENYLIST"
  printf 'owner: example-org\n' >"$FIXTURE_DIR/catalog/.apm/skills/notes.txt"

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"notes.txt:1: denylisted organization term"* ]]
}

@test "checks denylisted terms in file names" {
  printf 'example-org\n' >"$APM_LEAK_DENYLIST"
  printf 'clean\n' >"$FIXTURE_DIR/catalog/.apm/skills/example-org-notes.txt"

  run_fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"denylisted organization term in path"* ]]
  [[ "$output" != *"example-org"* ]]
}
