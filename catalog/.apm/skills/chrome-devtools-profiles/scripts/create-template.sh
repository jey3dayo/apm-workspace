#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: create-template.sh <source-profile> [template-name=_template]

  Builds $PROFILES_DIR/<template-name> from $PROFILES_DIR/<source-profile> by
  copying only an allowlist into $PROFILES_DIR/.<template-name>.partial-<pid>,
  cleaning Default/Preferences, running verify-profile.sh on it, and then
  renaming it to <template-name>. Both profiles must be stopped; the template
  must not exist yet.

  Kept (when present):
    Default/: Extensions, Local Extension Settings, Managed Extension Settings,
              Extension State, Extension Rules, Extension Scripts, Preferences,
              Secure Preferences, IndexedDB/chrome-extension_*
    profile root: the ROOT_FILES list in this script (empty)
  Everything else (cookies, history, sync extension data, ...) is not copied.

env: PROFILES_DIR  (default: $HOME/.cache/chrome-devtools-mcp/profiles)
     CHROME_BIN    (read by verify-profile.sh)

exit: 0 created and verified, 1 failed (the partial copy is kept and holds data
      from the source profile), 2 usage or validation error, 3 profile in use
USAGE
  exit 2
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

ROOT_FILES=()

DEFAULT_ENTRIES=(
  "Extensions" "Local Extension Settings" "Managed Extension Settings"
  "Extension State" "Extension Rules" "Extension Scripts"
  "Preferences" "Secure Preferences"
)

copy_entry() {
  local from=$1/$2 to=$3
  if [ -L "$from" ]; then
    die "refusing to copy symlink: $from"
  fi
  [ -e "$from" ] || return 0
  rsync -a -- "$from" "$to/" || die "copy failed: $from"
}

copy_allowlist() {
  local name entry
  for name in ${ROOT_FILES[@]+"${ROOT_FILES[@]}"}; do
    copy_entry "$src" "$name" "$partial"
  done
  if [ -L "$src/Default" ]; then
    die "refusing to copy symlink: $src/Default"
  fi
  mkdir -p "$partial/Default"
  for name in "${DEFAULT_ENTRIES[@]}"; do
    copy_entry "$src/Default" "$name" "$partial/Default"
  done
  if [ -L "$src/Default/IndexedDB" ]; then
    die "refusing to copy symlink: $src/Default/IndexedDB"
  fi
  if [ -d "$src/Default/IndexedDB" ]; then
    mkdir -p "$partial/Default/IndexedDB"
    for entry in "$src/Default/IndexedDB"/chrome-extension_*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      copy_entry "$src/Default/IndexedDB" "${entry##*/}" "$partial/Default/IndexedDB"
    done
  fi
}

clean_preferences() {
  python3 -I - "$1" <<'PY'
import copy
import json
import os
import sys

path = sys.argv[1]
with open(path, "rb") as f:
    prefs = json.load(f)
if not isinstance(prefs, dict):
    sys.exit("Preferences is not a JSON object")

extensions_before = ("extensions" in prefs, copy.deepcopy(prefs.get("extensions")))
changes = []
DROP_KEYS = {"zerosuggest", "webauthn", "gaia_cookie", "google", "enterprise_profile_guid"}


def empty_like(value):
    if isinstance(value, dict):
        return {}
    if isinstance(value, list):
        return []
    return value


def clear_at(*keys):
    parent = prefs
    for key in keys[:-1]:
        parent = parent.get(key) if isinstance(parent, dict) else None
    if isinstance(parent, dict) and keys[-1] in parent:
        parent[keys[-1]] = empty_like(parent[keys[-1]])
        changes.append("cleared " + ".".join(keys))


def drop_keys(node, trail):
    if not isinstance(node, dict):
        return
    for key in list(node):
        if key in DROP_KEYS:
            del node[key]
            changes.append("removed " + ".".join(trail + [key]))
        else:
            drop_keys(node[key], trail + [key])


profile = prefs.get("profile")
content_settings = profile.get("content_settings") if isinstance(profile, dict) else None
exceptions = content_settings.get("exceptions") if isinstance(content_settings, dict) else None
if isinstance(exceptions, dict):
    for category in exceptions:
        exceptions[category] = {}
    changes.append("cleared profile.content_settings.exceptions.*")

clear_at("login_detection", "oauth_signed_in_origins")
clear_at("web_apps", "daily_metrics")
clear_at("sessions", "event_log")
clear_at("https_upgrade_navigations")

media = prefs.get("media")
if isinstance(media, dict):
    engagement = media.get("engagement")
    version = engagement.get("schema_version") if isinstance(engagement, dict) else None
    prefs["media"] = {} if version is None else {"engagement": {"schema_version": version}}
    changes.append("reduced media")

for key in [k for k in prefs if k != "extensions"]:
    if key in DROP_KEYS:
        del prefs[key]
        changes.append("removed " + key)
    else:
        drop_keys(prefs[key], [key])

if extensions_before != ("extensions" in prefs, prefs.get("extensions")):
    sys.exit("extensions section changed during cleanup; Preferences not written")

tmp = path + ".tmp"
with open(tmp, "wb") as f:
    f.write(json.dumps(prefs, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))
os.chmod(tmp, os.stat(path).st_mode & 0o777)
os.replace(tmp, path)
for change in changes:
    print("preferences: " + change)
PY
}

partial_made=""

on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$partial_made" ]; then
    echo "partial template kept at $partial; it holds data from $src, delete it if not needed" >&2
  fi
  exit "$rc"
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage
case "$1" in -h | --help) usage ;; esac
source_name=$1
template_name=${2:-_template}
validate_name "$source_name"
validate_name "$template_name"
[ "$source_name" != "$template_name" ] || die "source and template must differ" 2
normalize_profiles_dir

src="$PROFILES_DIR/$source_name"
dest="$PROFILES_DIR/$template_name"
partial_name=".$template_name.partial-$$"
partial="$PROFILES_DIR/$partial_name"

[ -d "$src" ] || die "source profile not found: $src"
if [ -L "$dest" ] || [ -e "$dest" ]; then
  die "template already exists: $dest"
fi
if [ -L "$partial" ] || [ -e "$partial" ]; then
  die "partial template already exists: $partial"
fi
assert_not_running "$src"
assert_not_running "$dest"
command -v rsync >/dev/null 2>&1 || die "rsync is required"

mkdir "$partial"
partial_made=1
trap on_exit EXIT
copy_allowlist
[ -f "$partial/Default/Preferences" ] || die "Preferences missing in template: $partial/Default/Preferences"
clean_preferences "$partial/Default/Preferences" || die "Preferences cleanup failed"

"$script_dir/verify-profile.sh" "$partial_name" || die "verification failed"
if [ -L "$dest" ] || [ -e "$dest" ]; then
  die "template appeared during creation: $dest"
fi
mv -- "$partial" "$dest"
partial_made=""
echo "CREATE OK $template_name"
