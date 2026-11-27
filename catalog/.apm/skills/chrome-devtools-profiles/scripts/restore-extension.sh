#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: restore-extension.sh <target-profile> [template-name=_template]

  Copies Default/Extensions/<ext-id> and Default/Secure Preferences from the
  template into the target, then runs verify-profile.sh on the target. Chrome 158
  discards a restored registration at startup; use reinstall-extension.py to
  recover a registration. The
  target's Secure Preferences and Preferences go to
  $BACKUP_DIR/<target>-<timestamp>/. An existing Default/Extensions/<ext-id> in
  the target is moved to $BACKUP_DIR/<target>-<timestamp>/Extensions-<ext-id>/
  before the template's copy is placed.

env: PROFILES_DIR  (default: $HOME/.cache/chrome-devtools-mcp/profiles)
     BACKUP_DIR    (default: $HOME/.cache/chrome-devtools-mcp/profile-backups)
     CHROME_BIN    (read by verify-profile.sh)

exit: 0 restored and verified, 1 failed (changes rolled back),
      2 usage or validation error, 3 profile in use
USAGE
  exit 2
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

BACKUP_DIR="${BACKUP_DIR:-$HOME/.cache/chrome-devtools-mcp/profile-backups}"

started=0
finished=0
secure_touched=0
prefs_touched=0
ext_moved=0
ext_copied=0
had_secure=0
had_prefs=0

remove_restored_extension() {
  local path="$target/Default/Extensions/$EXT_ID"
  [ -n "$target" ] && [ -n "$EXT_ID" ] || return 1
  case "$path" in
    "$target"/Default/Extensions/?*) rm -rf -- "$path" ;;
    *) return 1 ;;
  esac
}

restore_file() {
  local name=$1 had=$2
  if [ "$had" = 1 ]; then
    cp -p "$backup/$name" "$target/Default/$name" ||
      echo "WARNING: could not restore $name from $backup" >&2
  else
    rm -f -- "$target/Default/$name"
  fi
}

rollback() {
  local path="$target/Default/Extensions/$EXT_ID"
  if singleton_present "$target" || process_uses_dir "$target"; then
    echo "WARNING: $target is in use; not rolling back. Restore from $backup manually" >&2
    return
  fi
  echo "rolling back changes to $target (backup kept at $backup)" >&2
  [ "$secure_touched" = 1 ] && restore_file "Secure Preferences" "$had_secure"
  [ "$prefs_touched" = 1 ] && restore_file "Preferences" "$had_prefs"
  if [ "$ext_copied" = 1 ]; then
    remove_restored_extension || echo "WARNING: could not remove restored $EXT_ID" >&2
  fi
  if [ "$ext_moved" = 1 ]; then
    if [ -e "$path" ] || [ -L "$path" ]; then
      echo "WARNING: $path still exists; original $EXT_ID kept at $backup/Extensions-$EXT_ID" >&2
    else
      mv -- "$backup/Extensions-$EXT_ID" "$path" ||
        echo "WARNING: could not move original $EXT_ID back from $backup/Extensions-$EXT_ID" >&2
    fi
  fi
  return 0
}

on_exit() {
  local rc=$?
  set +e
  if [ "$started" = 1 ] && [ "$finished" = 0 ]; then
    rollback
    [ "$rc" -ne 0 ] || rc=1
  fi
  exit "$rc"
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage
case "$1" in -h | --help) usage ;; esac
target_name=$1
template_name=${2:-_template}
validate_name "$target_name"
validate_name "$template_name"
[ "$target_name" != "$template_name" ] || die "target and template must differ" 2
normalize_profiles_dir

target="$PROFILES_DIR/$target_name"
template="$PROFILES_DIR/$template_name"

[ -d "$target/Default" ] || die "target profile not found: $target"
[ -d "$template/Default" ] || die "template profile not found: $template"
assert_not_running "$target"
assert_not_running "$template"
check_profile "$template" 0 >/dev/null || die "template has no complete $EXT_ID registration with its files: $template"
[ -d "$template/Default/Extensions/$EXT_ID" ] || die "template has no Default/Extensions/$EXT_ID: $template"

backup="$BACKUP_DIR/$target_name-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
mkdir "$backup"
if [ -f "$target/Default/Secure Preferences" ]; then
  cp -p "$target/Default/Secure Preferences" "$backup/Secure Preferences"
  had_secure=1
fi
if [ -f "$target/Default/Preferences" ]; then
  cp -p "$target/Default/Preferences" "$backup/Preferences"
  had_prefs=1
fi
if [ -d "$target/Default/Extensions" ]; then
  ls -la "$target/Default/Extensions" >"$backup/extensions-listing.txt"
else
  echo "(Default/Extensions absent)" >"$backup/extensions-listing.txt"
fi
echo "backup: $backup"

before=$(check_profile "$target" 0) || true
echo "before: $before"

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
started=1

mkdir -p "$target/Default/Extensions"
if [ -L "$target/Default/Extensions/$EXT_ID" ] || [ -e "$target/Default/Extensions/$EXT_ID" ]; then
  mv -- "$target/Default/Extensions/$EXT_ID" "$backup/Extensions-$EXT_ID"
  ext_moved=1
fi
ext_copied=1
cp -a "$template/Default/Extensions/$EXT_ID" "$target/Default/Extensions/"
secure_touched=1
cp -p "$template/Default/Secure Preferences" "$target/Default/Secure Preferences"

after=$(check_profile "$target" 0) || true
echo "after: $after"

prefs_touched=1
"$script_dir/verify-profile.sh" "$target_name" || die "verification failed after restore"

finished=1
echo "RESTORE OK $target_name"
