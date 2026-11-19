#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: create-template.sh <source-profile> [template-name=_template]

  Copies $PROFILES_DIR/<source-profile> to $PROFILES_DIR/<template-name>, strips
  site data and personal preferences, then runs verify-profile.sh on the copy.
  Both profiles must be stopped; the template must not exist yet.

env: PROFILES_DIR  (default: $HOME/.cache/chrome-devtools-mcp/profiles)
     CHROME_BIN    (read by verify-profile.sh)

exit: 0 created and verified, 1 failed (a failed copy is kept for inspection),
      2 usage or validation error, 3 profile in use
USAGE
  exit 2
}

PROFILES_DIR="${PROFILES_DIR:-$HOME/.cache/chrome-devtools-mcp/profiles}"
export PROFILES_DIR

SITE_FILES=(
  "History" "Favicons" "Top Sites" "Shortcuts" "Web Data" "Account Web Data"
  "Cookies" "Login Data" "Login Data For Account" "Affiliation Database"
  "Network Action Predictor" "DIPS" "DIPS-wal" "Device Bound Sessions"
  "ServerCertificate" "heavy_ad_intervention_opt_out.db"
  "declarative_performance_observer.db"
)

SITE_DIRS=(
  "Network" "Sessions" "Sessions_Encrypted" "Session Storage" "Local Storage"
  "Service Worker" "WebStorage" "Storage" "Shared Dictionary"
  "Site Characteristics Database" "shared_proto_db" "blob_storage" "Cache"
  "Code Cache" "GPUCache" "Download Service" "ClientCertificates" "Sync Data"
  "AutofillStrikeDatabase" "AutofillAiModelCache" "Web Applications"
  "PersistentOriginTrials" "chrome_cart_db" "commerce_subscription_db"
  "discounts_db" "discount_infos_db" "parcel_tracking_db"
)

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

remove_entry() {
  local base=$1 name=$2
  [ -n "$base" ] && [ -n "$name" ] || die "empty path component"
  case "$base" in
    "$dest" | "$dest"/*) ;;
    *) die "refusing to delete outside $dest: $base" ;;
  esac
  case "$name" in
    . | .. | */*) die "invalid entry name: $name" ;;
  esac
  [ ! -L "$base" ] || die "refusing to delete through symlink: $base"
  if [ -L "$base/$name" ] || [ -e "$base/$name" ]; then
    rm -rf -- "${base:?}/${name:?}"
  fi
}

strip_site_data() {
  local default=$1/Default name entry
  for name in "${SITE_FILES[@]}"; do
    remove_entry "$default" "$name"
    remove_entry "$default" "$name-journal"
  done
  for name in "${SITE_DIRS[@]}"; do
    remove_entry "$default" "$name"
  done
  remove_entry "$1" "BrowserMetrics"
  remove_entry "$1" "BrowserMetrics-spare.pma"
  for entry in "$default"/IndexedDB/*; do
    name=${entry##*/}
    case "$name" in
      chrome-extension_*) continue ;;
    esac
    remove_entry "$default/IndexedDB" "$name"
  done
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

[ $# -ge 1 ] && [ $# -le 2 ] || usage
case "$1" in -h | --help) usage ;; esac
source_name=$1
template_name=${2:-_template}
validate_name "$source_name"
validate_name "$template_name"
[ "$source_name" != "$template_name" ] || die "source and template must differ" 2

src="$PROFILES_DIR/$source_name"
dest="$PROFILES_DIR/$template_name"

[ -d "$src" ] || die "source profile not found: $src"
if [ -L "$dest" ] || [ -e "$dest" ]; then
  die "template already exists: $dest"
fi
assert_not_running "$src"
assert_not_running "$dest"
command -v rsync >/dev/null 2>&1 || die "rsync is required"

rsync -a --exclude=SingletonLock --exclude=SingletonSocket --exclude=SingletonCookie "$src/" "$dest/" ||
  die "copy failed; partial template left at $dest"
strip_site_data "$dest"
[ -f "$dest/Default/Preferences" ] || die "Preferences missing in template: $dest/Default/Preferences"
clean_preferences "$dest/Default/Preferences" || die "Preferences cleanup failed; template left at $dest"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
"$script_dir/verify-profile.sh" "$template_name" || die "verification failed; template left at $dest for inspection"
echo "CREATE OK $template_name"
