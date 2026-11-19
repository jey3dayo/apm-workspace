#!/usr/bin/env bash
# Launch a profile twice with chrome-devtools-mcp equivalent flags and confirm the
# extension registration survives. The flags matter: with the real keychain Chrome
# stubs the Web Store registration in Secure Preferences right after startup.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: verify-profile.sh <profile>

  Starts $PROFILES_DIR/<profile> with MCP-equivalent flags, waits, stops only the
  Chrome it started, and checks the extension registration. Two cycles.

env: PROFILES_DIR  (default: $HOME/.cache/chrome-devtools-mcp/profiles)
     CHROME_BIN    (default: /Applications/Google Chrome.app/Contents/MacOS/Google Chrome)

exit: 0 verified, 1 check or launch failed, 2 usage or validation error,
      3 profile in use
USAGE
  exit 2
}

EXT_ID="aeblfdkhhhdcdjpifhhbdiojplfjncoa"
PROFILES_DIR="${PROFILES_DIR:-$HOME/.cache/chrome-devtools-mcp/profiles}"
CHROME_BIN="${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
SETTLE_SECONDS=15
STOP_TIMEOUT=30
IDLE_TIMEOUT=15

CHROME_FLAGS=(
  --allow-pre-commit-input
  --disable-background-networking
  --disable-background-timer-throttling
  --disable-backgrounding-occluded-windows
  --disable-breakpad
  --disable-client-side-phishing-detection
  --disable-component-extensions-with-background-pages
  --disable-crash-reporter
  --disable-default-apps
  --disable-dev-shm-usage
  "--disable-features=Translate,AcceptCHFrame,MediaRouter,OptimizationHints,WebUIReloadButton,WebUIOmniboxPopup,WebUIOmniboxAimPopup,ProcessPerSiteUpToMainFrameThreshold,IsolateSandboxedIframes"
  --disable-hang-monitor
  --disable-infobars
  --disable-ipc-flooding-protection
  --disable-popup-blocking
  --disable-prompt-on-repost
  --disable-renderer-backgrounding
  --disable-search-engine-choice-screen
  --disable-sync
  --enable-automation
  --enable-features=PdfOopif
  --export-tagged-pdf
  --force-color-profile=srgb
  --generate-pdf-document-outline
  --hide-crash-restore-bubble
  --metrics-recording-only
  --no-first-run
  --password-store=basic
  --use-mock-keychain
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

chrome_pid=""

pid_alive() { kill -0 "$1" 2>/dev/null; }

cleanup() {
  if [ -n "$chrome_pid" ] && pid_alive "$chrome_pid"; then
    kill -TERM "$chrome_pid" 2>/dev/null || true
  fi
}

stop_chrome() {
  local i
  kill -TERM "$chrome_pid" 2>/dev/null || true
  for ((i = 0; i < STOP_TIMEOUT; i++)); do
    if ! pid_alive "$chrome_pid"; then
      wait "$chrome_pid" 2>/dev/null || true
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_idle() {
  local i
  for ((i = 0; i < IDLE_TIMEOUT; i++)); do
    if ! process_uses_dir "$1"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

remove_singletons() {
  local f
  [ -n "$1" ] || die "empty profile dir"
  for f in SingletonLock SingletonSocket SingletonCookie; do
    if [ -L "$1/$f" ] || [ -e "$1/$f" ]; then
      rm -f -- "${1:?}/$f"
    fi
  done
}

run_cycle() {
  local n=$1 dir=$2 i report
  assert_not_running "$dir"
  "$CHROME_BIN" "${CHROME_FLAGS[@]}" --user-data-dir="$dir" --no-default-browser-check about:blank >/dev/null 2>&1 &
  chrome_pid=$!
  for ((i = 0; i < SETTLE_SECONDS; i++)); do
    sleep 1
    pid_alive "$chrome_pid" || break
  done
  if ! pid_alive "$chrome_pid"; then
    chrome_pid=""
    die "cycle $n: Chrome exited before ${SETTLE_SECONDS}s"
  fi
  if ! stop_chrome; then
    local pid=$chrome_pid
    chrome_pid=""
    die "cycle $n: Chrome (pid $pid) did not exit within ${STOP_TIMEOUT}s after SIGTERM; left running"
  fi
  chrome_pid=""
  wait_for_idle "$dir" || die "cycle $n: Chrome processes still hold $dir after exit"
  remove_singletons "$dir"
  if report=$(check_profile "$dir" 1); then
    echo "cycle $n: $report"
  else
    echo "cycle $n: $report"
    die "cycle $n: verification failed for $dir"
  fi
}

[ $# -eq 1 ] || usage
case "$1" in -h | --help) usage ;; esac
validate_name "$1"
profile=$1
dir="$PROFILES_DIR/$profile"

[ -d "$dir/Default" ] || die "profile not found: $dir"
assert_not_running "$dir"
[ -x "$CHROME_BIN" ] || die "CHROME_BIN is not executable: $CHROME_BIN"

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_cycle 1 "$dir"
run_cycle 2 "$dir"
echo "VERIFY OK $profile"
