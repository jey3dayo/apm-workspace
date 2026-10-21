#!/usr/bin/env bats
#
# Git hooks export GIT_DIR for the repository that runs them. run-bats.sh must
# scrub it so suites cannot write into that repository (2026-10-21: a pre-push
# test:sh set core.bare, replaced the user identity and added test commits in
# the real checkout). The sentinel repo stands in for that checkout.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WORK="$(mktemp -d)"
  SENTINEL="$WORK/sentinel"
  sentinel_git init -q "$SENTINEL"
  sentinel_git -C "$SENTINEL" -c user.name=sentinel -c user.email=sentinel@example.invalid \
    commit -q --allow-empty -m sentinel
  sentinel_git -C "$SENTINEL" config --local apm.sentinel kept
}

teardown() {
  rm -rf "$WORK"
}

sentinel_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git "$@"
}

snapshot() {
  sentinel_git -C "$SENTINEL" config --local --list
  sentinel_git -C "$SENTINEL" for-each-ref --format='%(refname) %(objectname)'
  sentinel_git -C "$SENTINEL" rev-parse HEAD
}

# The same writes the leaking suites made: identity, a commit, a branch, core.bare.
suite_session() {
  cat <<'SH'
mkdir -p "$1/fixture" && cd "$1/fixture"
git init -q .
git config user.name t
git config user.email t@example.invalid
git commit -q --allow-empty -m junk
git branch other
git config core.bare true
SH
}

hook_env() {
  env GIT_DIR="$SENTINEL/.git" GIT_INDEX_FILE="$SENTINEL/.git/index" GIT_WORK_TREE="$SENTINEL" "$@"
}

@test "apm_isolate_git_env keeps a hook's GIT_DIR repo untouched" {
  before="$(snapshot)"
  run hook_env bash -c ". \"\$2/scripts/lib/git-test-env.sh\"; apm_isolate_git_env; set -e; $(suite_session)" _ "$WORK" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$(snapshot)" = "$before" ]
  # The writes landed in the fixture instead.
  sentinel_git -C "$WORK/fixture" rev-parse --verify -q refs/heads/other
}

@test "GIT_CONFIG and GIT_CONFIG_COUNT from the caller cannot redirect suite writes" {
  printf '[apm]\n\tsentinel = kept\n' >"$WORK/caller.gitconfig"
  cfg_before="$(cat "$WORK/caller.gitconfig")"
  before="$(snapshot)"
  run env GIT_DIR="$SENTINEL/.git" GIT_CONFIG="$WORK/caller.gitconfig" \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=leaked \
    bash -c ". \"\$2/scripts/lib/git-test-env.sh\"; apm_isolate_git_env; set -e; $(suite_session); [ \"\$(git log -1 --format=%an)\" = t ]" _ "$WORK" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$(cat "$WORK/caller.gitconfig")" = "$cfg_before" ]
  [ "$(snapshot)" = "$before" ]
}

@test "control: without isolation the same session writes into the sentinel" {
  before="$(snapshot)"
  run hook_env bash -c "$(suite_session)" _ "$WORK"
  [ "$(snapshot)" != "$before" ]
}

@test "run-bats.sh isolates the git env before starting bats" {
  isolate_line="$(grep -n '^apm_isolate_git_env' "$REPO_ROOT/scripts/run-bats.sh" | cut -d: -f1)"
  bats_line="$(grep -n '^bats ' "$REPO_ROOT/scripts/run-bats.sh" | cut -d: -f1)"
  [ -n "$isolate_line" ]
  [ -n "$bats_line" ]
  [ "$isolate_line" -lt "$bats_line" ]
}

@test "pre-push test:sh drops the hook's GIT_DIR before mise runs" {
  grep -Eq '^[[:space:]]+run: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE mise run test:sh$' "$REPO_ROOT/lefthook.yml"
}
