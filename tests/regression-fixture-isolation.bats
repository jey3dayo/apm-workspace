#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CHECKER="$REPO_ROOT/catalog/skills/orchestrator-worker/scripts/check-fixture-isolation.py"
  FIXTURE="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$FIXTURE"
}

@test "rejects a node_modules link to a shared workspace dependency directory" {
  mkdir -p "$BATS_TEST_TMPDIR/shared-workspace/node_modules"
  ln -s "$BATS_TEST_TMPDIR/shared-workspace/node_modules" "$FIXTURE/node_modules"

  run python3 "$CHECKER" "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"dependency link escapes fixture root: node_modules"* ]]
}

@test "rejects a pnpm store link outside the fixture root" {
  mkdir -p "$FIXTURE/node_modules" "$BATS_TEST_TMPDIR/shared-pnpm-store"
  ln -s "$BATS_TEST_TMPDIR/shared-pnpm-store" "$FIXTURE/node_modules/.pnpm-store"

  run python3 "$CHECKER" "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"dependency link escapes fixture root: node_modules/.pnpm-store"* ]]
}

@test "rejects a root pnpm store link outside the fixture root" {
  mkdir -p "$BATS_TEST_TMPDIR/shared-root-pnpm-store"
  ln -s "$BATS_TEST_TMPDIR/shared-root-pnpm-store" "$FIXTURE/.pnpm-store"

  run python3 "$CHECKER" "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"dependency link escapes fixture root: .pnpm-store"* ]]
}

@test "finds shared dependency links in nested workspace packages" {
  mkdir -p "$FIXTURE/packages/reader" "$BATS_TEST_TMPDIR/shared-reader-deps"
  ln -s "$BATS_TEST_TMPDIR/shared-reader-deps" "$FIXTURE/packages/reader/node_modules"

  run python3 "$CHECKER" "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"dependency link escapes fixture root: packages/reader/node_modules"* ]]
}

@test "rejects an external package link reached through an in-fixture scope link" {
  mkdir -p "$FIXTURE/node_modules" "$FIXTURE/vendor/acme" "$BATS_TEST_TMPDIR/shared-reader"
  ln -s "$FIXTURE/vendor/acme" "$FIXTURE/node_modules/@acme"
  ln -s "$BATS_TEST_TMPDIR/shared-reader" "$FIXTURE/vendor/acme/reader"

  run python3 "$CHECKER" "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"dependency link escapes fixture root: node_modules/@acme/reader"* ]]
}

@test "rejects shallow pnpm and package links inside node_modules" {
  mkdir -p "$FIXTURE/node_modules" "$BATS_TEST_TMPDIR/shared-pnpm" "$BATS_TEST_TMPDIR/shared-package" \
    "$BATS_TEST_TMPDIR/shared-scoped-package"
  ln -s "$BATS_TEST_TMPDIR/shared-pnpm" "$FIXTURE/node_modules/.pnpm"
  ln -s "$BATS_TEST_TMPDIR/shared-package" "$FIXTURE/node_modules/left-pad"
  mkdir -p "$FIXTURE/node_modules/@acme"
  ln -s "$BATS_TEST_TMPDIR/shared-scoped-package" "$FIXTURE/node_modules/@acme/reader"

  run python3 "$CHECKER" "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"dependency link escapes fixture root: node_modules/.pnpm"* ]]
  [[ "$output" == *"dependency link escapes fixture root: node_modules/left-pad"* ]]
  [[ "$output" == *"dependency link escapes fixture root: node_modules/@acme/reader"* ]]
}

@test "allows independent dependency directories and links inside the fixture" {
  mkdir -p "$FIXTURE/.pnpm-store" "$FIXTURE/node_modules/.pnpm-store" "$FIXTURE/vendor/reader-deps" \
    "$FIXTURE/vendor/pnpm" "$FIXTURE/vendor/package" "$FIXTURE/vendor/scoped-package" \
    "$FIXTURE/packages/reader" "$FIXTURE/vendor/acme"
  ln -s "$FIXTURE/vendor/reader-deps" "$FIXTURE/packages/reader/node_modules"
  ln -s "$FIXTURE/vendor/pnpm" "$FIXTURE/node_modules/.pnpm"
  ln -s "$FIXTURE/vendor/package" "$FIXTURE/node_modules/left-pad"
  ln -s "$FIXTURE/vendor/acme" "$FIXTURE/node_modules/@acme"
  ln -s "$FIXTURE/vendor/scoped-package" "$FIXTURE/vendor/acme/reader"

  run python3 "$CHECKER" "$FIXTURE"

  [ "$status" -eq 0 ]
  [[ "$output" == "fixture dependency links stay inside the fixture root" ]]
}
