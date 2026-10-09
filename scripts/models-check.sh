#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPERS_DIR="${MODELS_CHECK_SCRIPTS_DIR:-$REPO_ROOT/catalog/skills/agmsg-delegation/scripts}"
CALL_TIMEOUT="${MODELS_CHECK_TIMEOUT:-30}"

missing_count=0
extract_error_count=0
ALLOWLIST=""

with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$CALL_TIMEOUT" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$CALL_TIMEOUT" "$@"
  else
    "$@"
  fi
}

# Sets ALLOWLIST to "<role> <model>" lines ("all" for role-less arrays).
# Returns 1 when the helper is absent (SKIP) and 2 when extraction fails (ERROR counted).
load_allowlist() {
  local provider=$1 file=$2
  local line role models model declared=0 parsed=0
  local pattern='^[[:space:]]*(([a-z]+)\)[[:space:]]+)?allowed_models=\(([^)]*)\)'
  ALLOWLIST=""
  [ -f "$file" ] || return 1
  while IFS= read -r line; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line == *allowed_models=* ]] || continue
    declared=$((declared + 1))
    if [[ $line =~ $pattern ]]; then
      parsed=$((parsed + 1))
      role=${BASH_REMATCH[2]:-all}
      models=${BASH_REMATCH[3]}
      for model in $models; do
        ALLOWLIST+="$role $model"$'\n'
      done
    fi
  done <"$file"
  if [ "$declared" -ne "$parsed" ]; then
    extract_error_count=$((extract_error_count + 1))
    printf 'ERROR %s could not extract allowlist from %s: %d of %d allowed_models= declarations were not single-line arrays\n' \
      "$provider" "$file" "$((declared - parsed))" "$declared"
    return 2
  fi
  if [ -z "$ALLOWLIST" ]; then
    extract_error_count=$((extract_error_count + 1))
    printf 'ERROR %s could not extract allowlist from %s: no models found\n' "$provider" "$file"
    return 2
  fi
}

# Prints "<kind>:<family> <major> <minor>" or nothing when the id does not parse.
parse_family() {
  local id=$1
  if [[ $id =~ ^claude-([a-z]+)-([0-9]+)(-([0-9]{1,2}))?(-|$) ]]; then
    printf 'claude:%s %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]:-0}"
  elif [[ $id =~ ^gpt-([0-9]+)(\.([0-9]+))?-([a-z]+) ]]; then
    printf 'gpt:%s %s %s\n' "${BASH_REMATCH[4]}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]:-0}"
  elif [[ $id =~ ^deepseek/deepseek-v([0-9]+)-([a-z]+) ]]; then
    printf 'deepseek:%s %s 0\n' "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}"
  fi
}

allowlist_covers() {
  awk -v f="$2" -v maj="$3" -v min="$4" \
    '$1 == f && ($2 > maj || ($2 == maj && $3 >= min)) { found = 1 } END { exit !found }' <<<"$1"
}

report_provider() {
  local provider=$1 allowlist=$2 live=$3
  local role model parsed family major minor live_id live_parsed live_family live_major live_minor
  local seen="" allow_versions=""

  live=$(sed '/^[[:space:]]*$/d' <<<"$live")
  if [ -z "$live" ]; then
    skip "$provider" "live model list empty or unparseable"
    return
  fi

  while read -r role model; do
    [ -n "$model" ] || continue
    parsed=$(parse_family "$model")
    [ -z "$parsed" ] || allow_versions+="$parsed"$'\n'
    if grep -Fxq -- "$model" <<<"$live"; then
      printf 'OK %s %s %s\n' "$provider" "$role" "$model"
    else
      printf 'MISSING %s %s %s\n' "$provider" "$role" "$model"
      missing_count=$((missing_count + 1))
    fi
  done <<<"$allowlist"

  while read -r role model; do
    [ -n "$model" ] || continue
    parsed=$(parse_family "$model")
    [ -n "$parsed" ] || continue
    read -r family major minor <<<"$parsed"
    while IFS= read -r live_id; do
      [ -n "$live_id" ] || continue
      live_parsed=$(parse_family "$live_id")
      [ -n "$live_parsed" ] || continue
      read -r live_family live_major live_minor <<<"$live_parsed"
      [ "$live_family" = "$family" ] || continue
      if [ "$live_major" -gt "$major" ] || { [ "$live_major" -eq "$major" ] && [ "$live_minor" -gt "$minor" ]; }; then
        if allowlist_covers "$allow_versions" "$live_family" "$live_major" "$live_minor"; then
          continue
        fi
        local key="$provider $family $live_major.$live_minor"
        if ! grep -Fxq -- "$key" <<<"$seen"; then
          seen+="$key"$'\n'
          printf 'NEWER %s %s %s.%s (allowlisted %s is %s.%s)\n' \
            "$provider" "${family#*:}" "$live_major" "$live_minor" "$model" "$major" "$minor"
        fi
      fi
    done <<<"$live"
  done <<<"$allowlist"
}

skip() {
  printf 'SKIP %s %s\n' "$1" "$2"
}

check_codex() {
  local helper="$HELPERS_DIR/run-codex-worker.sh"
  local cache="${CODEX_HOME:-$HOME/.codex}/models_cache.json"
  local allowlist live fetched_at rc=0

  load_allowlist codex "$helper" || rc=$?
  if [ "$rc" -eq 1 ]; then
    skip codex "helper not found: $helper"
    return
  elif [ "$rc" -ne 0 ]; then
    return
  fi
  allowlist=$ALLOWLIST
  if ! command -v jq >/dev/null 2>&1; then
    skip codex "jq not found"
    return
  fi
  if [ ! -f "$cache" ]; then
    skip codex "models cache not found: $cache"
    return
  fi
  if ! live=$(with_timeout jq -r '.models[]?.slug | strings' "$cache" 2>/dev/null); then
    skip codex "could not read model slugs from $cache"
    return
  fi
  fetched_at=$(jq -r '.fetched_at // "unknown"' "$cache" 2>/dev/null || echo unknown)
  printf 'INFO codex models_cache fetched_at=%s\n' "$fetched_at"
  report_provider codex "$allowlist" "$live"
}

check_cursor() {
  local helper="$HELPERS_DIR/run-cursor-worker.sh"
  local bin="${AGMSG_CURSOR_BIN:-$HOME/.local/bin/cursor-agent}"
  local allowlist live rc=0

  load_allowlist cursor "$helper" || rc=$?
  if [ "$rc" -eq 1 ]; then
    skip cursor "helper not found: $helper"
    return
  elif [ "$rc" -ne 0 ]; then
    return
  fi
  allowlist=$ALLOWLIST
  if [ ! -x "$bin" ]; then
    skip cursor "cursor-agent not executable: $bin"
    return
  fi
  if ! live=$(with_timeout "$bin" models 2>/dev/null); then
    skip cursor "cursor-agent models failed or timed out"
    return
  fi
  live=$(awk 'index($0, " - ") { print $1 }' <<<"$live")
  report_provider cursor "$allowlist" "$live"
}

resolve_opencode_bin() {
  local candidate
  if [ -n "${AGMSG_OPENCODE_BIN:-}" ]; then
    printf '%s' "$AGMSG_OPENCODE_BIN"
    return
  fi
  if command -v mise >/dev/null 2>&1; then
    candidate=$(mise which opencode 2>/dev/null || true)
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s' "$candidate"
    fi
  fi
}

check_opencode() {
  local helper="$HELPERS_DIR/run-opencode-worker.sh"
  local allowlist bin provider providers live provider_allowlist rc=0

  load_allowlist opencode "$helper" || rc=$?
  if [ "$rc" -eq 1 ]; then
    skip opencode "helper not found: $helper"
    return
  elif [ "$rc" -ne 0 ]; then
    return
  fi
  allowlist=$ALLOWLIST
  bin=$(resolve_opencode_bin)
  if [ -z "$bin" ] || [ ! -x "$bin" ]; then
    skip opencode "opencode not executable: ${bin:-unresolved}"
    return
  fi
  providers=$(awk '{ n = split($2, p, "/"); if (n > 1) print p[1] }' <<<"$allowlist" | sort -u)
  for provider in $providers; do
    if ! live=$(with_timeout "$bin" models "$provider" 2>/dev/null); then
      skip "opencode/$provider" "opencode models failed or timed out"
      continue
    fi
    provider_allowlist=$(awk -v p="$provider/" 'index($2, p) == 1' <<<"$allowlist")
    report_provider "opencode/$provider" "$provider_allowlist" "$live"
  done
}

check_codex
check_cursor
check_opencode

if [ "$missing_count" -gt 0 ] || [ "$extract_error_count" -gt 0 ]; then
  printf 'models:check failed: %d MISSING allowlisted model(s), %d allowlist extraction ERROR(s)\n' \
    "$missing_count" "$extract_error_count" >&2
  exit 1
fi
