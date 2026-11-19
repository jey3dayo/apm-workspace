# shellcheck shell=bash
# Shared by create-template.sh, verify-profile.sh and restore-extension.sh.

EXT_ID="aeblfdkhhhdcdjpifhhbdiojplfjncoa"

die() {
  echo "error: $1" >&2
  exit "${2:-1}"
}

validate_name() {
  case "$1" in
    "" | . | -* | */* | *..*) die "invalid profile name: '$1'" 2 ;;
  esac
}

# Child processes get the normalized value, so the --user-data-dir= match in
# process_uses_dir does not depend on how the caller spelled the path.
normalize_profiles_dir() {
  PROFILES_DIR="${PROFILES_DIR:-$HOME/.cache/chrome-devtools-mcp/profiles}"
  [ -d "$PROFILES_DIR" ] || die "profiles dir not found: $PROFILES_DIR" 2
  PROFILES_DIR=$(CDPATH='' cd -- "$PROFILES_DIR" && pwd -L) || die "cannot resolve profiles dir: $PROFILES_DIR" 2
  export PROFILES_DIR
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

# check_profile <profile-dir> <strict: 0|1>; prints one summary line, exits 0 only when sound.
check_profile() {
  python3 -I - "$1" "$EXT_ID" "$2" <<'PY'
import json
import os
import stat
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
reasons_absent = "disable_reasons" not in entry
reasons = entry.get("disable_reasons")
enabled = reasons_absent or (isinstance(reasons, list) and not reasons) or (type(reasons) is int and reasons == 0)
rel = entry.get("path")
path_exists = False
manifest_file = False
if registered and isinstance(rel, str) and rel:
    extensions_dir = os.path.realpath(os.path.join(default, "Extensions"))
    full = os.path.realpath(os.path.join(extensions_dir, rel))
    inside = not os.path.isabs(rel) and os.path.commonpath([extensions_dir, full]) == extensions_dir
    path_exists = inside and full != extensions_dir and os.path.isdir(full)
    if path_exists:
        try:
            manifest_file = stat.S_ISREG(os.lstat(os.path.join(full, "manifest.json")).st_mode)
        except OSError:
            manifest_file = False
exit_type = as_dict(as_dict(prefs).get("profile")).get("exit_type")
if prefs is None:
    exit_type = "unreadable"

yes_no = lambda flag: "yes" if flag else "no"
print(
    "secure_preferences_bytes=%s settings_keys=%d ext_registered=%s "
    "ext_path_exists=%s manifest_file=%s ext_dir=%s disable_reasons=%s exit_type=%s"
    % (
        "missing" if size is None else size,
        len(settings),
        yes_no(registered),
        yes_no(path_exists),
        yes_no(manifest_file),
        yes_no(os.path.isdir(os.path.join(default, "Extensions", ext_id))),
        "absent" if reasons_absent else json.dumps(reasons, separators=(",", ":")),
        exit_type,
    )
)
ok = registered and path_exists and enabled and manifest_file
if strict:
    ok = ok and prefs is not None and exit_type != "Crashed"
sys.exit(0 if ok else 1)
PY
}
