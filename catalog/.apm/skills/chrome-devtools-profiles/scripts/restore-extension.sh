#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: restore-extension.sh <target-profile> [template-name=_template]

  Copies Default/Extensions/<ext-id> and Default/Secure Preferences from the
  template into the target, then runs verify-profile.sh on the target. A backup of
  the target's Secure Preferences goes to $BACKUP_DIR/<target>-<timestamp>/.
  Aborts if the target already has Default/Extensions/<ext-id>.

env: PROFILES_DIR  (default: $HOME/.cache/chrome-devtools-mcp/profiles)
     BACKUP_DIR    (default: $HOME/.cache/chrome-devtools-mcp/profile-backups)
     CHROME_BIN    (read by verify-profile.sh)

exit: 0 restored and verified, 1 failed (changes rolled back),
      2 usage or validation error, 3 profile in use
USAGE
  exit 2
}

EXT_ID="aeblfdkhhhdcdjpifhhbdiojplfjncoa"
PROFILES_DIR="${PROFILES_DIR:-$HOME/.cache/chrome-devtools-mcp/profiles}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.cache/chrome-devtools-mcp/profile-backups}"
export PROFILES_DIR

die() {
  echo "error: $1" >&2
  exit "${2:-1}"
}

validate_name() {
  case "$1" in
    "" | . | -* | */* | *..*) die "invalid profile name: '$1'" 2 ;;
  esac
}

singleton_present() {
  local f
  for f in SingletonLock SingletonSocket SingletonCookie; do
    if [ -L "$1/$f" ] || [ -e "$1/$f" ]; then
      return 0
    fi
  done
  return 1
}

process_uses_dir() {
  local needle="--user-data-dir=$1" ps_out line rest
  ps_out=$(ps -axo pid=,command=) || die "ps failed; cannot check running Chrome" 3
  while IFS= read -r line; do
    rest=$line
    while [[ $rest == *"$needle"* ]]; do
      rest=${rest#*"$needle"}
      if [ -z "$rest" ] || [[ $rest == " "* ]]; then
        return 0
      fi
    done
  done <<<"$ps_out"
  return 1
}

assert_not_running() {
  if singleton_present "$1"; then
    die "profile in use (Singleton* present): $1" 3
  fi
  if process_uses_dir "$1"; then
    die "profile in use (Chrome process holds --user-data-dir): $1" 3
  fi
}

check_profile() {
  python3 -I - "$1" "$EXT_ID" "$2" <<'PY'
import json
import os
import sys

profile, ext_id, strict = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
default = os.path.join(profile, "Default")


def read_json(name):
    try:
        with open(os.path.join(default, name), "rb") as f:
            raw = f.read()
    except OSError:
        return None, None
    try:
        return len(raw), json.loads(raw)
    except ValueError:
        return len(raw), None


def as_dict(value):
    return value if isinstance(value, dict) else {}


size, secure = read_json("Secure Preferences")
_, prefs = read_json("Preferences")
settings = as_dict(as_dict(as_dict(secure).get("extensions")).get("settings"))
entry = as_dict(settings.get(ext_id))
registered = all(key in entry for key in ("manifest", "path", "from_webstore"))
registered = registered and entry["from_webstore"] is True
rel = entry.get("path")
path_exists = False
if registered and isinstance(rel, str) and rel:
    extensions_dir = os.path.realpath(os.path.join(default, "Extensions"))
    full = os.path.realpath(os.path.join(extensions_dir, rel))
    inside = not os.path.isabs(rel) and os.path.commonpath([extensions_dir, full]) == extensions_dir
    path_exists = inside and full != extensions_dir and os.path.isdir(full)
exit_type = as_dict(as_dict(prefs).get("profile")).get("exit_type")
if prefs is None:
    exit_type = "unreadable"

yes_no = lambda flag: "yes" if flag else "no"
print(
    "secure_preferences_bytes=%s settings_keys=%d ext_registered=%s "
    "ext_path_exists=%s ext_dir=%s exit_type=%s"
    % (
        "missing" if size is None else size,
        len(settings),
        yes_no(registered),
        yes_no(path_exists),
        yes_no(os.path.isdir(os.path.join(default, "Extensions", ext_id))),
        exit_type,
    )
)
ok = registered and path_exists
if strict:
    ok = ok and prefs is not None and exit_type != "Crashed"
sys.exit(0 if ok else 1)
PY
}

started=0
finished=0
secure_touched=0
ext_touched=0
had_secure=0

remove_restored_extension() {
  local path="$target/Default/Extensions/$EXT_ID"
  [ -n "$target" ] && [ -n "$EXT_ID" ] || return 1
  case "$path" in
    "$target"/Default/Extensions/?*) rm -rf -- "$path" ;;
    *) return 1 ;;
  esac
}

rollback() {
  if singleton_present "$target" || process_uses_dir "$target"; then
    echo "WARNING: $target is in use; not rolling back. Restore from $backup manually" >&2
    return
  fi
  echo "rolling back changes to $target (backup kept at $backup)" >&2
  if [ "$secure_touched" = 1 ]; then
    if [ "$had_secure" = 1 ]; then
      cp -p "$backup/Secure Preferences" "$target/Default/Secure Preferences" ||
        echo "WARNING: could not restore Secure Preferences from $backup" >&2
    else
      rm -f -- "$target/Default/Secure Preferences"
    fi
  fi
  if [ "$ext_touched" = 1 ]; then
    remove_restored_extension || echo "WARNING: could not remove restored $EXT_ID" >&2
  fi
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

target="$PROFILES_DIR/$target_name"
template="$PROFILES_DIR/$template_name"

[ -d "$target/Default" ] || die "target profile not found: $target"
[ -d "$template/Default" ] || die "template profile not found: $template"
assert_not_running "$target"
assert_not_running "$template"
check_profile "$template" 0 >/dev/null || die "template has no complete $EXT_ID registration with its files: $template"
[ -d "$template/Default/Extensions/$EXT_ID" ] || die "template has no Default/Extensions/$EXT_ID: $template"
if [ -L "$target/Default/Extensions/$EXT_ID" ] || [ -e "$target/Default/Extensions/$EXT_ID" ]; then
  die "target already has Default/Extensions/$EXT_ID; refusing to overwrite: $target"
fi

backup="$BACKUP_DIR/$target_name-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
mkdir "$backup"
if [ -f "$target/Default/Secure Preferences" ]; then
  cp -p "$target/Default/Secure Preferences" "$backup/Secure Preferences"
  had_secure=1
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

ext_touched=1
mkdir -p "$target/Default/Extensions"
cp -a "$template/Default/Extensions/$EXT_ID" "$target/Default/Extensions/"
secure_touched=1
cp -p "$template/Default/Secure Preferences" "$target/Default/Secure Preferences"

after=$(check_profile "$target" 0) || true
echo "after: $after"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
"$script_dir/verify-profile.sh" "$target_name" || die "verification failed after restore"

finished=1
echo "RESTORE OK $target_name"
