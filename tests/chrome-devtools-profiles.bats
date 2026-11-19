#!/usr/bin/env bats

# Contract tests that never start Chrome: CHROME_BIN is a stub that exits at once,
# so verify-profile.sh fails fast after the static checks have passed.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPTS="$REPO_ROOT/catalog/.apm/skills/chrome-devtools-profiles/scripts"
  EXT_ID="aeblfdkhhhdcdjpifhhbdiojplfjncoa"
  export PROFILES_DIR="$BATS_TEST_TMPDIR/profiles"
  export BACKUP_DIR="$BATS_TEST_TMPDIR/backups"
  export CHROME_BIN="$BATS_TEST_TMPDIR/fake-chrome"
  export FAKE_CHROME_MARKER="$BATS_TEST_TMPDIR/chrome-called"
  mkdir -p "$PROFILES_DIR"
  cat >"$CHROME_BIN" <<'STUB'
#!/usr/bin/env bash
echo called >>"$FAKE_CHROME_MARKER"
for arg in "$@"; do
  case "$arg" in --user-data-dir=*) dir=${arg#*=} ;; esac
done
printf 'mutated-by-chrome' >"$dir/Default/Preferences"
exit 1
STUB
  chmod +x "$CHROME_BIN"
}

teardown() {
  if [ -n "${HOLDER_PID:-}" ]; then
    kill "$HOLDER_PID" 2>/dev/null || true
  fi
}

# make_profile <name> [stub]: a full registration, or a stubbed one whose files remain.
make_profile() {
  local default="$PROFILES_DIR/$1/Default"
  mkdir -p "$default/Extensions/$EXT_ID/1.0_0"
  printf '{"profile":{"exit_type":"Normal"}}' >"$default/Preferences"
  if [ "${2:-}" = stub ]; then
    printf '{"extensions":{"settings":{"%s":{"stub":true}}}}' "$EXT_ID" >"$default/Secure Preferences"
    printf 'original-manifest' >"$default/Extensions/$EXT_ID/1.0_0/manifest.json"
  else
    printf '{"extensions":{"settings":{"%s":{"manifest":{"name":"x"},"path":"%s/1.0_0","from_webstore":true,"disable_reasons":[]}}}}' \
      "$EXT_ID" "$EXT_ID" >"$default/Secure Preferences"
    printf '{"name":"x"}' >"$default/Extensions/$EXT_ID/1.0_0/manifest.json"
  fi
}

@test "all scripts reject invalid profile names with exit 2" {
  local name script
  for name in "../x" "" "-x"; do
    for script in verify-profile.sh restore-extension.sh create-template.sh; do
      run "$SCRIPTS/$script" "$name"
      [ "$status" -eq 2 ]
    done
  done
}

@test "a dangling SingletonLock symlink counts as in use (exit 3)" {
  make_profile victim
  make_profile _template
  ln -s "$BATS_TEST_TMPDIR/no-such-target" "$PROFILES_DIR/victim/SingletonLock"
  run "$SCRIPTS/verify-profile.sh" victim
  [ "$status" -eq 3 ]
  run "$SCRIPTS/restore-extension.sh" victim
  [ "$status" -eq 3 ]
  [ ! -e "$FAKE_CHROME_MARKER" ]
}

@test "restore aborts before writing when the template has no complete registration" {
  make_profile victim stub
  make_profile _template stub
  cp -p "$PROFILES_DIR/victim/Default/Secure Preferences" "$BATS_TEST_TMPDIR/secure.orig"
  run "$SCRIPTS/restore-extension.sh" victim
  [ "$status" -eq 1 ]
  cmp "$PROFILES_DIR/victim/Default/Secure Preferences" "$BATS_TEST_TMPDIR/secure.orig"
  [ ! -e "$FAKE_CHROME_MARKER" ]
}

@test "restore replaces an existing extension directory and rolls everything back when verify fails" {
  make_profile victim stub
  make_profile _template
  cp -p "$PROFILES_DIR/victim/Default/Secure Preferences" "$BATS_TEST_TMPDIR/secure.orig"
  cp -p "$PROFILES_DIR/victim/Default/Preferences" "$BATS_TEST_TMPDIR/prefs.orig"
  run "$SCRIPTS/restore-extension.sh" victim
  [ "$status" -eq 1 ]
  [ -e "$FAKE_CHROME_MARKER" ]
  cmp "$PROFILES_DIR/victim/Default/Secure Preferences" "$BATS_TEST_TMPDIR/secure.orig"
  cmp "$PROFILES_DIR/victim/Default/Preferences" "$BATS_TEST_TMPDIR/prefs.orig"
  [ "$(cat "$PROFILES_DIR/victim/Default/Extensions/$EXT_ID/1.0_0/manifest.json")" = "original-manifest" ]
}

@test "restore accepts PROFILES_DIR with a trailing slash and dot segments" {
  make_profile victim
  make_profile _template
  PROFILES_DIR="$BATS_TEST_TMPDIR/./profiles/" run "$SCRIPTS/restore-extension.sh" victim
  [ "$status" -eq 1 ]
  [ -e "$FAKE_CHROME_MARKER" ]
}

@test "in-use detection matches the real path whatever PROFILES_DIR spelling is given" {
  make_profile victim
  make_profile _template
  bash -c 'while :; do sleep 1; done' holder "--user-data-dir=$PROFILES_DIR/victim" &
  HOLDER_PID=$!
  PROFILES_DIR="$BATS_TEST_TMPDIR/./profiles/" run "$SCRIPTS/restore-extension.sh" victim
  [ "$status" -eq 3 ]
  [ ! -e "$FAKE_CHROME_MARKER" ]
}

@test "create-template keeps a partial copy without site data when verify fails" {
  make_profile src
  local default="$PROFILES_DIR/src/Default"
  mkdir -p "$default/GCM Store" "$default/Sync Extension Settings" \
    "$default/IndexedDB/chrome-extension_abc_0.indexeddb.leveldb" "$default/IndexedDB/https_site_0.indexeddb.leveldb"
  printf 'x' >"$default/Cookies"
  printf 'x' >"$default/History"
  printf 'x' >"$default/Extension Cookies"
  printf 'x' >"$PROFILES_DIR/src/Local State"

  run "$SCRIPTS/create-template.sh" src tmpl
  [ "$status" -eq 1 ]
  [ ! -e "$PROFILES_DIR/tmpl" ]
  local partials=("$PROFILES_DIR"/.tmpl.partial-*)
  [ "${#partials[@]}" -eq 1 ]
  local partial=${partials[0]}
  [ -d "$partial/Default/Extensions/$EXT_ID" ]
  [ -d "$partial/Default/IndexedDB/chrome-extension_abc_0.indexeddb.leveldb" ]
  [ ! -e "$partial/Default/IndexedDB/https_site_0.indexeddb.leveldb" ]
  [ ! -e "$partial/Default/Cookies" ]
  [ ! -e "$partial/Default/History" ]
  [ ! -e "$partial/Default/Extension Cookies" ]
  [ ! -e "$partial/Default/GCM Store" ]
  [ ! -e "$partial/Default/Sync Extension Settings" ]
  [ ! -e "$partial/Local State" ]
}
