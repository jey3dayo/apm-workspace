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

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

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
normalize_profiles_dir
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
