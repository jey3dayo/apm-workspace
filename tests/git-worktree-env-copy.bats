#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/catalog/skills/git-worktree/scripts/copy-env-files.sh"
  SOURCE_CHECKOUT="$BATS_TEST_TMPDIR/source"
  DESTINATION_WORKTREE="$BATS_TEST_TMPDIR/destination"
  OUTSIDE_SOURCE="$BATS_TEST_TMPDIR/outside-source"
  OUTSIDE_DESTINATION="$BATS_TEST_TMPDIR/outside-destination"
  mkdir -p "$SOURCE_CHECKOUT" "$DESTINATION_WORKTREE" "$OUTSIDE_SOURCE" "$OUTSIDE_DESTINATION"
  git -C "$SOURCE_CHECKOUT" init -q
  printf '.env.keys\n' >"$SOURCE_CHECKOUT/.gitignore"
}

@test "copies legitimate nested env files and prunes generated trees, nested checkouts, and symlinks" {
  mkdir -p \
    "$SOURCE_CHECKOUT/project/settings" \
    "$SOURCE_CHECKOUT/.worktrees/other" \
    "$SOURCE_CHECKOUT/node_modules/package" \
    "$SOURCE_CHECKOUT/.pnpm-store/package" \
    "$SOURCE_CHECKOUT/target/debug" \
    "$SOURCE_CHECKOUT/dist/assets" \
    "$SOURCE_CHECKOUT/.git/fixture"
  printf 'fake root env\n' >"$SOURCE_CHECKOUT/.env"
  printf 'fake key fixture\n' >"$SOURCE_CHECKOUT/.env.keys"
  printf 'fake nested env\n' >"$SOURCE_CHECKOUT/project/.env"
  printf 'fake nested env\n' >"$SOURCE_CHECKOUT/project/.env.local"
  printf 'fake nested key fixture\n' >"$SOURCE_CHECKOUT/project/settings/.env.keys"
  printf 'fake worktree env\n' >"$SOURCE_CHECKOUT/.worktrees/other/.env"
  printf 'fake dependency env\n' >"$SOURCE_CHECKOUT/node_modules/package/.env.local"
  printf 'fake pnpm store env\n' >"$SOURCE_CHECKOUT/.pnpm-store/package/.env"
  printf 'fake target env\n' >"$SOURCE_CHECKOUT/target/debug/.env.keys"
  printf 'fake dist env\n' >"$SOURCE_CHECKOUT/dist/assets/.env.local"
  mkdir -p "$SOURCE_CHECKOUT/nested-checkout"
  git -C "$SOURCE_CHECKOUT/nested-checkout" init -q
  printf 'fake nested checkout env\n' >"$SOURCE_CHECKOUT/nested-checkout/.env"
  printf 'fake git metadata env\n' >"$SOURCE_CHECKOUT/.git/fixture/.env"
  printf 'fake symlink escape env\n' >"$OUTSIDE_SOURCE/.env"
  ln -s "$OUTSIDE_SOURCE" "$SOURCE_CHECKOUT/source-link"

  run "$SCRIPT_UNDER_TEST" "$DESTINATION_WORKTREE" "$SOURCE_CHECKOUT"

  [ "$status" -eq 0 ]
  [ "$(cat "$DESTINATION_WORKTREE/.env")" = "fake root env" ]
  [ "$(cat "$DESTINATION_WORKTREE/.env.keys")" = "fake key fixture" ]
  [ "$(cat "$DESTINATION_WORKTREE/project/.env")" = "fake nested env" ]
  [ "$(cat "$DESTINATION_WORKTREE/project/.env.local")" = "fake nested env" ]
  [ "$(cat "$DESTINATION_WORKTREE/project/settings/.env.keys")" = "fake nested key fixture" ]
  [ ! -e "$DESTINATION_WORKTREE/.worktrees/other/.env" ]
  [ ! -e "$DESTINATION_WORKTREE/node_modules/package/.env.local" ]
  [ ! -e "$DESTINATION_WORKTREE/.pnpm-store/package/.env" ]
  [ ! -e "$DESTINATION_WORKTREE/target/debug/.env.keys" ]
  [ ! -e "$DESTINATION_WORKTREE/dist/assets/.env.local" ]
  [ ! -e "$DESTINATION_WORKTREE/nested-checkout/.env" ]
  [ ! -e "$DESTINATION_WORKTREE/.git/fixture/.env" ]
  [ ! -e "$DESTINATION_WORKTREE/source-link/.env" ]
}

@test "does not follow a destination symlink while creating a nested env path" {
  mkdir -p "$SOURCE_CHECKOUT/project"
  printf 'fake nested env\n' >"$SOURCE_CHECKOUT/project/.env.local"
  ln -s "$OUTSIDE_DESTINATION" "$DESTINATION_WORKTREE/project"

  run "$SCRIPT_UNDER_TEST" "$DESTINATION_WORKTREE" "$SOURCE_CHECKOUT"

  [ "$status" -eq 0 ]
  [ ! -e "$OUTSIDE_DESTINATION/.env.local" ]
}

@test "does not split a newline directory name when checking a destination symlink" {
  local env_parent=$'project\nextra'
  mkdir -p "$SOURCE_CHECKOUT/$env_parent"
  printf 'fake newline path env\n' >"$SOURCE_CHECKOUT/$env_parent/.env.local"
  ln -s "$OUTSIDE_DESTINATION" "$DESTINATION_WORKTREE/$env_parent"

  run "$SCRIPT_UNDER_TEST" "$DESTINATION_WORKTREE" "$SOURCE_CHECKOUT"

  [ "$status" -eq 0 ]
  [ ! -e "$OUTSIDE_DESTINATION/.env.local" ]
}

@test "treats glob characters in untracked env paths literally when checking tracked files" {
  mkdir -p "$SOURCE_CHECKOUT/sample-a" "$SOURCE_CHECKOUT/sample*"
  printf 'fake tracked env\n' >"$SOURCE_CHECKOUT/sample-a/.env"
  printf 'fake literal glob env\n' >"$SOURCE_CHECKOUT/sample*/.env"
  git -C "$SOURCE_CHECKOUT" add sample-a/.env

  run "$SCRIPT_UNDER_TEST" "$DESTINATION_WORKTREE" "$SOURCE_CHECKOUT"

  [ "$status" -eq 0 ]
  [ ! -e "$DESTINATION_WORKTREE/sample-a/.env" ]
  [ "$(cat "$DESTINATION_WORKTREE/sample*/.env")" = "fake literal glob env" ]
}

@test "fails when a non-directory blocks a destination env parent" {
  mkdir -p "$SOURCE_CHECKOUT/project"
  printf 'fake nested env\n' >"$SOURCE_CHECKOUT/project/.env.local"
  printf 'destination blocker\n' >"$DESTINATION_WORKTREE/project"

  run "$SCRIPT_UNDER_TEST" "$DESTINATION_WORKTREE" "$SOURCE_CHECKOUT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"error: destination directory unavailable for env path: project/.env.local"* ]]
}

@test "rejects a source directory that is not a Git checkout" {
  local non_git_source="$BATS_TEST_TMPDIR/non-git-source"
  mkdir -p "$non_git_source"
  printf 'fake root env\n' >"$non_git_source/.env"

  run "$SCRIPT_UNDER_TEST" "$DESTINATION_WORKTREE" "$non_git_source"

  [ "$status" -ne 0 ]
  [[ "$output" == *"error: source is not a Git checkout:"* ]]
  [ ! -e "$DESTINATION_WORKTREE/.env" ]
}

@test "fails without copying when find fails after partial output" {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/find" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$COPY_ENV_FAKE_FIND_FILE"
exit 7
EOF
  chmod +x "$fake_bin/find"
  printf 'fake root env\n' >"$SOURCE_CHECKOUT/.env"

  run env PATH="$fake_bin:$PATH" COPY_ENV_FAKE_FIND_FILE="$SOURCE_CHECKOUT/.env" \
    "$SCRIPT_UNDER_TEST" "$DESTINATION_WORKTREE" "$SOURCE_CHECKOUT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"error: failed to scan source checkout for env files"* ]]
  [ ! -e "$DESTINATION_WORKTREE/.env" ]
}
