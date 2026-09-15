#!/usr/bin/env bats
#
# Locks the pre-push `test:sh` glob to a `tests/*.bats` wildcard: an
# individual-file listing silently leaves every new suite out of the push gate.
# Scope is bats only — the PS lane is deliberately ungated (see AGENTS.md).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LEFTHOOK_FILE="$REPO_ROOT/lefthook.yml"
  FIXTURE_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

extract_pre_push_test_sh_glob() {
  awk '
    /^pre-push:/ { in_pre_push = 1; next }
    in_pre_push && /^[^[:space:]]/ { in_pre_push = 0 }
    !in_pre_push { next }
    /^[[:space:]]*- name: test:sh[[:space:]]*$/ { in_job = 1; next }
    in_job && /^[[:space:]]*- name:/ { in_job = 0 }
    in_job && /glob:/ { print; exit }
  ' "$1"
}

@test "pre-push test:sh job wildcards tests/*.bats" {
  glob_line="$(extract_pre_push_test_sh_glob "$LEFTHOOK_FILE")"
  [ -n "$glob_line" ]
  [[ "$glob_line" == *"tests/*.bats"* ]]
}

@test "negative fixture detects a test:sh job that enumerates individual bats files" {
  # Built inline: pinning the real glob's text would break this case whenever
  # an unrelated path is added to it.
  fixture="$FIXTURE_DIR/lefthook.yml"
  cat >"$fixture" <<'EOF'
pre-push:
  jobs:
    - name: test:sh
      glob: "{scripts/apm-workspace.sh,tests/apm-workspace.sh.bats,mise.toml,mise/test.toml}"
      run: mise run test:sh
EOF

  glob_line="$(extract_pre_push_test_sh_glob "$fixture")"
  [ -n "$glob_line" ]
  [[ "$glob_line" != *"tests/*.bats"* ]]
}

@test "checker does not fall back to scanning the pre-commit section" {
  fixture="$FIXTURE_DIR/lefthook.yml"
  cat >"$fixture" <<'EOF'
pre-commit:
  jobs:
    - name: test:sh
      glob: "tests/*.bats"
      run: mise run test:sh

pre-push:
  jobs:
    - name: other-job
      run: true
EOF

  glob_line="$(extract_pre_push_test_sh_glob "$fixture")"
  [ -z "$glob_line" ]
}
