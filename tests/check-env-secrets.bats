#!/usr/bin/env bats

SENTINEL="SENTINEL-VALUE-MUST-NOT-LEAK"

setup_file() {
  # ユーザーの global gitignore が `.env*` を無視していると、fixture が untracked
  # にも tracked にもならず全ケースが 0 になる。テストは環境から切り離す。
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null
  TEMPLATE="$BATS_FILE_TMPDIR/template"
  mkdir -p "$TEMPLATE"
  git -C "$TEMPLATE" init -q .
  git -C "$TEMPLATE" config core.excludesFile /dev/null
  printf 'x\n' >"$TEMPLATE/README"
  git -C "$TEMPLATE" add README
  git -C "$TEMPLATE" -c user.email=t@example -c user.name=t commit -qm init
}

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/catalog/.apm/skills/atomic-commit/scripts/check-env-secrets.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  # helper の一時物が残らないことを見るため、専用の TMPDIR を与える。
  SCRATCH="$BATS_TEST_TMPDIR/scratch"
  mkdir -p "$SCRATCH"
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null
  TEMPLATE="$BATS_FILE_TMPDIR/template"
  cp -R "$TEMPLATE" "$REPO"
  # cp -R で index の stat 情報が変わり dirty に見えるため、比較のみで吸収する。
  git -C "$REPO" update-index --refresh -q >/dev/null 2>&1 || true
}

check() {
  run env TMPDIR="$SCRATCH" "$SCRIPT" "$REPO"
}

commit_env() {
  git -C "$REPO" add -- "$1"
  git -C "$REPO" -c user.email=t@example -c user.name=t commit -qm "add $1"
}

stage_env() {
  git -C "$REPO" add -- "$1"
}

assert_no_sentinel() {
  [[ "$output" != *"$SENTINEL"* ]]
}

assert_scratch_clean() {
  [ -z "$(ls -A "$SCRATCH")" ]
}

@test "a dotenvx-managed file passes and leaves no temporary files" {
  printf 'DOTENV_PUBLIC_KEY=dummy-public\nAPI_KEY=encrypted:dummy\n' >"$REPO/.env.production"
  stage_env .env.production
  check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  assert_scratch_clean
}

@test "a plain secret staged in the index is reported even when the work tree hides it" {
  printf 'DOTENV_PUBLIC_KEY=dummy-public\nAPI_KEY=encrypted:dummy\n' >"$REPO/.env.production"
  commit_env .env.production
  printf 'DOTENV_PUBLIC_KEY=dummy-public\nAPI_KEY=%s\n' "$SENTINEL" >"$REPO/.env.production"
  git -C "$REPO" add .env.production
  printf 'DOTENV_PUBLIC_KEY=dummy-public\nAPI_KEY=encrypted:dummy\n' >"$REPO/.env.production"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *".env.production: API_KEY"* ]]
  assert_no_sentinel
  assert_scratch_clean
}

@test "an untracked .env in a subdirectory is reported with its path" {
  mkdir -p "$REPO/sub"
  printf 'SENTRY_DSN=%s\n' "$SENTINEL" >"$REPO/sub/.env.staging"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"sub/.env.staging: SENTRY_DSN"* ]]
  assert_no_sentinel
}
