#!/usr/bin/env bats
#
# scripts/models-check.sh は helper の allowed_models を provider の現行一覧と
# 突き合わせる。helper は MODELS_CHECK_SCRIPTS_DIR の fixture で差し替え、
# provider 側は CODEX_HOME / AGMSG_CURSOR_BIN / AGMSG_OPENCODE_BIN の stub で与える。

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/models-check.sh"
  REAL_HELPERS="$REPO_ROOT/catalog/skills/agmsg-delegation/scripts"
  FIXTURE_DIR="$(mktemp -d)"
  mkdir -p "$FIXTURE_DIR/helpers" "$FIXTURE_DIR/codex"
  export CODEX_HOME="$FIXTURE_DIR/codex"
  export MODELS_CHECK_SCRIPTS_DIR="$FIXTURE_DIR/helpers"

  cat >"$FIXTURE_DIR/helpers/run-codex-worker.sh" <<'SH'
case "$role" in
implement) allowed_models=(gpt-6-luna gpt-5.6-terra) ;;
review) allowed_models=(gpt-6-sol) ;;
esac
SH
  cat >"$FIXTURE_DIR/helpers/run-cursor-worker.sh" <<'SH'
case "$role" in
implement) allowed_models=(claude-sonnet-5-thinking-high) ;;
review) allowed_models=(claude-opus-5-5-high) ;;
esac
SH
  cat >"$FIXTURE_DIR/helpers/run-opencode-worker.sh" <<'SH'
allowed_models=(deepseek/deepseek-v4-flash)
SH

  write_codex_cache gpt-6-luna gpt-5.6-terra gpt-6-sol
  write_cursor_stub claude-sonnet-5-thinking-high claude-opus-5-5-high
  write_opencode_stub deepseek deepseek/deepseek-v4-flash
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

write_codex_cache() {
  printf '%s\n' "$@" | jq -R '{slug: .}' | jq -s '{fetched_at: "2026-01-02T03:04:05Z", models: .}' \
    >"$FIXTURE_DIR/codex/models_cache.json"
}

write_cursor_stub() {
  {
    printf 'Available models\n\nauto - Auto (default)\n'
    local id
    for id in "$@"; do printf '%s - Display name of %s\n' "$id" "$id"; done
  } >"$FIXTURE_DIR/cursor.txt"
  cat >"$FIXTURE_DIR/cursor-agent" <<SH
#!/bin/sh
cat "$FIXTURE_DIR/cursor.txt"
SH
  chmod +x "$FIXTURE_DIR/cursor-agent"
}

write_opencode_stub() {
  local provider=$1
  shift
  printf '%s\n' "$@" >"$FIXTURE_DIR/opencode-$provider.txt"
  cat >"$FIXTURE_DIR/opencode" <<SH
#!/bin/sh
[ "\$1" = models ] || exit 2
if [ "\${3:-}" = --verbose ]; then
  [ -f "$FIXTURE_DIR/opencode-verbose-fail" ] && exit 1
  if [ -f "$FIXTURE_DIR/opencode-\$2.verbose.txt" ]; then
    cat "$FIXTURE_DIR/opencode-\$2.verbose.txt"
    exit 0
  fi
fi
cat "$FIXTURE_DIR/opencode-\$2.txt"
SH
  chmod +x "$FIXTURE_DIR/opencode"
}

write_opencode_verbose() {
  local provider=$1 id=$2 status=$3
  cat >"$FIXTURE_DIR/opencode-$provider.verbose.txt" <<JSON
$provider/other-model
{
  "id": "other-model",
  "providerID": "$provider",
  "status": "active",
  "limit": { "context": 1000 }
}
$id
{
  "id": "${id#*/}",
  "providerID": "$provider",
  "name": "Display",
  "status": "$status",
  "cost": { "input": 1, "output": 2 },
  "limit": { "context": 1000 }
}
JSON
}

write_codex_cache_json() {
  printf '%s\n' "$1" >"$FIXTURE_DIR/codex/models_cache.json"
}

run_check() {
  run env AGMSG_CURSOR_BIN="$FIXTURE_DIR/cursor-agent" AGMSG_OPENCODE_BIN="$FIXTURE_DIR/opencode" \
    bash "$SCRIPT"
}

# "<role> <model>" per single-line allowed_models declaration, same shape the script reports.
real_allowlist() {
  sed -nE 's/^[[:space:]]*(([a-z]+)\)[[:space:]]+)?allowed_models=\(([^)]*)\).*/\2|\3/p' "$1" |
    while IFS='|' read -r role models; do
      for m in $models; do printf '%s %s\n' "${role:-all}" "$m"; done
    done
}

models_of() {
  awk '{ print $2 }' <<<"$1" | sort -u
}

@test "all allowlisted models present reports OK per role and exits 0" {
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK codex implement gpt-6-luna"* ]]
  [[ "$output" == *"OK codex review gpt-6-sol"* ]]
  [[ "$output" == *"OK cursor review claude-opus-5-5-high"* ]]
  [[ "$output" == *"OK opencode/deepseek all deepseek/deepseek-v4-flash"* ]]
  [[ "$output" == *"fetched_at=2026-01-02T03:04:05Z"* ]]
  [[ "$output" != *MISSING* ]]
  [[ "$output" != *NEWER* ]]
}

@test "an allowlisted model absent from the live list is MISSING and exits 1" {
  write_cursor_stub claude-sonnet-5-thinking-high
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING cursor review claude-opus-5-5-high"* ]]
  [[ "$output" == *"OK cursor implement claude-sonnet-5-thinking-high"* ]]
}

@test "a missing opencode model is MISSING and exits 1" {
  write_opencode_stub deepseek deepseek/deepseek-flash
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING opencode/deepseek all deepseek/deepseek-v4-flash"* ]]
}

@test "a newer family version warns once per family and keeps exit 0" {
  write_cursor_stub claude-sonnet-5-thinking-high claude-opus-5-5-high \
    claude-sonnet-5-5-low claude-sonnet-5-5-medium claude-sonnet-5-5-high
  write_codex_cache gpt-6-luna gpt-5.6-terra gpt-6-sol gpt-6.1-sol
  write_opencode_stub deepseek deepseek/deepseek-v4-flash deepseek/deepseek-v5-flash
  run_check
  [ "$status" -eq 0 ]
  [ "$(grep -c '^NEWER cursor sonnet 5.5' <<<"$output")" -eq 1 ]
  [[ "$output" == *"NEWER codex sol 6.1"* ]]
  [[ "$output" == *"NEWER opencode/deepseek flash 5.0"* ]]
  [[ "$output" != *MISSING* ]]
}

@test "a newer version already covered by the allowlist is not reported" {
  cat >"$FIXTURE_DIR/helpers/run-codex-worker.sh" <<'SH'
implement) allowed_models=(gpt-6-sol gpt-6.1-sol) ;;
SH
  write_codex_cache gpt-6-sol gpt-6.1-sol
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" != *"NEWER codex"* ]]
}

@test "missing provider CLIs and cache are SKIP and keep exit 0" {
  rm "$FIXTURE_DIR/codex/models_cache.json"
  run env AGMSG_CURSOR_BIN=/no/such/cursor-agent AGMSG_OPENCODE_BIN=/no/such/opencode bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP codex"* ]]
  [[ "$output" == *"SKIP cursor"* ]]
  [[ "$output" == *"SKIP opencode"* ]]
  [[ "$output" != *MISSING* ]]
}

@test "a failing provider call is SKIP and keeps exit 0" {
  printf '#!/bin/sh\nexit 1\n' >"$FIXTURE_DIR/cursor-agent"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP cursor"* ]]
}

@test "allowlists are read from the real helper scripts" {
  unset MODELS_CHECK_SCRIPTS_DIR
  local codex cursor opencode
  codex=$(real_allowlist "$REAL_HELPERS/run-codex-worker.sh")
  cursor=$(real_allowlist "$REAL_HELPERS/run-cursor-worker.sh")
  opencode=$(real_allowlist "$REAL_HELPERS/run-opencode-worker.sh")
  [ -n "$codex" ] && [ -n "$cursor" ] && [ -n "$opencode" ]
  # shellcheck disable=SC2046
  write_codex_cache $(models_of "$codex")
  # shellcheck disable=SC2046
  write_cursor_stub $(models_of "$cursor")
  # shellcheck disable=SC2046
  write_opencode_stub deepseek $(models_of "$opencode")
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" != *MISSING* ]]
  [[ "$output" != *SKIP* ]]
  [[ "$output" != *ERROR* ]]
  local role model
  while read -r role model; do
    [[ "$output" == *"OK codex $role $model"* ]]
  done <<<"$codex"
  while read -r role model; do
    [[ "$output" == *"OK cursor $role $model"* ]]
  done <<<"$cursor"
  while read -r role model; do
    [[ "$output" == *"OK opencode/${model%%/*} $role $model"* ]]
  done <<<"$opencode"
}

@test "a helper with no parsable declaration is an ERROR and exits 1" {
  printf 'echo no allowlist here\n' >"$FIXTURE_DIR/helpers/run-codex-worker.sh"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR codex could not extract allowlist from"* ]]
  [[ "$output" != *"OK codex"* ]]
}

@test "a multi-line allowed_models array next to a single-line one is a partial-extraction ERROR" {
  cat >"$FIXTURE_DIR/helpers/run-codex-worker.sh" <<'SH'
case "$role" in
implement) allowed_models=(gpt-6-luna) ;;
review) allowed_models=(
  gpt-6-sol
  gpt-6.1-sol
) ;;
esac
SH
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR codex could not extract allowlist from"* ]]
  [[ "$output" != *"OK codex"* ]]
}

@test "an ERROR is reported even when the provider CLI is absent" {
  printf 'echo no allowlist here\n' >"$FIXTURE_DIR/helpers/run-cursor-worker.sh"
  run env AGMSG_CURSOR_BIN=/no/such/cursor-agent AGMSG_OPENCODE_BIN=/no/such/opencode bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR cursor could not extract allowlist"* ]]
}

@test "a cursor list with no model lines is SKIP, not MISSING, and exits 0" {
  printf '#!/bin/sh\nprintf "Available models\\n\\n"\n' >"$FIXTURE_DIR/cursor-agent"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP cursor live model list empty or unparseable"* ]]
  [[ "$output" != *MISSING* ]]
}

@test "an empty codex models cache is SKIP, not MISSING, and exits 0" {
  printf '{"fetched_at": "2026-01-02T03:04:05Z", "models": []}\n' >"$FIXTURE_DIR/codex/models_cache.json"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP codex live model list empty or unparseable"* ]]
  [[ "$output" != *MISSING* ]]
}

@test "codex cache entries without string slugs are SKIP, not MISSING" {
  printf '{"models": [{"slug": null}, {"name": "x"}]}\n' >"$FIXTURE_DIR/codex/models_cache.json"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP codex live model list empty or unparseable"* ]]
  [[ "$output" != *MISSING* ]]
}

@test "an empty opencode list is SKIP, not MISSING, and exits 0" {
  : >"$FIXTURE_DIR/opencode-deepseek.txt"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP opencode/deepseek live model list empty or unparseable"* ]]
  [[ "$output" != *MISSING* ]]
}

@test "an opencode response with no provider/id lines is SKIP, not MISSING, and exits 0" {
  write_opencode_stub deepseek "Available models" "models deepseek"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP opencode/deepseek live model list empty or unparseable"* ]]
  [[ "$output" != *MISSING* ]]
}

@test "opencode ids are extracted from surrounding header and whitespace noise" {
  write_opencode_stub deepseek "Available models" "  deepseek/deepseek-v4-flash  " "other/deepseek-v4-flash"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK opencode/deepseek all deepseek/deepseek-v4-flash"* ]]
}

@test "a codex slug with an upgrade is RETIRING with date and successor and exits 0" {
  write_codex_cache_json '{"fetched_at":"2026-01-02T03:04:05Z","models":[
    {"slug":"gpt-6-luna","visibility":"list","upgrade":null},
    {"slug":"gpt-5.6-terra","visibility":"list","upgrade":{"model":"gpt-6.1-sol","migration_markdown":"retires","retirement_at":"2026-10-14T19:00:00Z"}},
    {"slug":"gpt-6-sol","visibility":"list","upgrade":null}]}'
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"RETIRING codex implement gpt-5.6-terra (retires 2026-10-14T19:00:00Z, upgrade to gpt-6.1-sol)"* ]]
  [ "$(grep -c '^RETIRING' <<<"$output")" -eq 1 ]
}

@test "a codex upgrade without usable fields is RETIRING with unknown values" {
  write_codex_cache_json '{"models":[
    {"slug":"gpt-6-luna","upgrade":{}},
    {"slug":"gpt-5.6-terra","upgrade":"gpt-7"},
    {"slug":"gpt-6-sol","upgrade":null}]}'
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"RETIRING codex implement gpt-6-luna (retires unknown, upgrade to unknown)"* ]]
  [[ "$output" == *"RETIRING codex implement gpt-5.6-terra (retires unknown, upgrade to unknown)"* ]]
}

@test "a codex upgrade of false is RETIRING with unknown values" {
  write_codex_cache_json '{"models":[
    {"slug":"gpt-6-luna","upgrade":false},
    {"slug":"gpt-5.6-terra","upgrade":null},
    {"slug":"gpt-6-sol","upgrade":null}]}'
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"RETIRING codex implement gpt-6-luna (retires unknown, upgrade to unknown)"* ]]
}

@test "a failed codex retirement read is INFO, keeps the OK lines and exits 0" {
  mkdir -p "$FIXTURE_DIR/bin"
  cat >"$FIXTURE_DIR/bin/jq" <<SH
#!/bin/sh
for a in "\$@"; do [ "\$a" = --arg ] && exit 5; done
exec "$(command -v jq)" "\$@"
SH
  chmod +x "$FIXTURE_DIR/bin/jq"
  PATH="$FIXTURE_DIR/bin:$PATH" run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO codex retirement status unavailable"* ]]
  [[ "$output" == *"OK codex implement gpt-6-luna"* ]]
  [[ "$output" == *"OK codex review gpt-6-sol"* ]]
  [[ "$output" != *RETIRING* ]]
}

@test "a hidden codex slug without an upgrade is RETIRING hidden and exits 0" {
  write_codex_cache_json '{"models":[
    {"slug":"gpt-6-luna","visibility":"list","upgrade":null},
    {"slug":"gpt-5.6-terra","visibility":"list","upgrade":null},
    {"slug":"gpt-6-sol","visibility":"hide","upgrade":null}]}'
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"RETIRING codex review gpt-6-sol (hidden from the model list)"* ]]
  [[ "$output" == *"OK codex review gpt-6-sol"* ]]
}

@test "listed codex slugs without an upgrade are not RETIRING" {
  write_codex_cache_json '{"models":[
    {"slug":"gpt-6-luna","visibility":"list","upgrade":null},
    {"slug":"gpt-5.6-terra","visibility":"list"},
    {"slug":"gpt-6-sol","visibility":"list","upgrade":null}]}'
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" != *RETIRING* ]]
}

@test "a deprecated opencode model is RETIRING and exits 0" {
  write_opencode_verbose deepseek deepseek/deepseek-v4-flash deprecated
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK opencode/deepseek all deepseek/deepseek-v4-flash"* ]]
  [[ "$output" == *"RETIRING opencode/deepseek all deepseek/deepseek-v4-flash (status deprecated)"* ]]
}

@test "active and beta opencode models are not RETIRING" {
  local status_name
  for status_name in active beta; do
    write_opencode_verbose deepseek deepseek/deepseek-v4-flash "$status_name"
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" != *RETIRING* ]]
    [[ "$output" != *"INFO opencode"* ]]
  done
}

@test "a failing opencode --verbose call is INFO and keeps the OK line and exit 0" {
  : >"$FIXTURE_DIR/opencode-verbose-fail"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO opencode/deepseek retirement status unavailable"* ]]
  [[ "$output" == *"OK opencode/deepseek all deepseek/deepseek-v4-flash"* ]]
  [[ "$output" != *"SKIP opencode"* ]]
}

@test "unparseable opencode --verbose output is INFO and exits 0" {
  printf 'deepseek/deepseek-v4-flash\n{ not json\n' >"$FIXTURE_DIR/opencode-deepseek.verbose.txt"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO opencode/deepseek retirement status unavailable"* ]]
  [[ "$output" != *RETIRING* ]]
}
