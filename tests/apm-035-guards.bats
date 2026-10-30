#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  mise_binary=$(command -v mise)
  fixture=$(mktemp -d "$repo_root/tmp/apm-guards.XXXXXX")
  export HOME="$fixture/home" APM_WORKSPACE_DIR="$fixture/workspace"
  export GUARD_CALLS="$fixture/calls" GUARD_PREVIEW="$fixture/preview"
  mkdir -p "$HOME" "$APM_WORKSPACE_DIR/apm_modules/owner/gist" "$fixture/bin"
  printf 'skill\n' >"$APM_WORKSPACE_DIR/apm_modules/owner/gist/SKILL.md"
  printf 'dependencies:\n  apm: []\n' >"$APM_WORKSPACE_DIR/apm.yml"
  printf 'dependencies: []\nlocal_deployed_files:\n- .agents/skills/local\n' >"$APM_WORKSPACE_DIR/apm.lock.yaml"
  printf '[>] Analyzing installed packages vs apm.yml...\n[+] No orphaned packages found. apm_modules/ is clean.\n' >"$GUARD_PREVIEW"
  cat >"$fixture/bin/apm" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GUARD_CALLS"
case "$*" in
  --version) printf 'APM CLI version 0.35.0\n' ;;
  'deps list -g')
    if [ "${GUARD_LIST_MODE:-self}" = clean ]; then printf 'installed packages\n'; exit 0; fi
    printf '%s\n' "${GUARD_LIST_ERROR:-[x] Error listing dependencies: Invalid local package path '': path segments must not be empty}"
    exit 1 ;;
  'deps tree -g') printf 'dependency tree\n'; exit "${GUARD_TREE_EXIT:-0}" ;;
  'prune --dry-run') cat "$GUARD_PREVIEW"; exit "${GUARD_PREVIEW_EXIT:-0}" ;;
  prune) mv "$APM_WORKSPACE_DIR/apm_modules/owner/gist" "$APM_WORKSPACE_DIR/deleted-gist"; exit "${GUARD_PRUNE_EXIT:-0}" ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$fixture/bin/apm"
  export PATH="$fixture/bin:$PATH"
  source "$repo_root/scripts/apm-workspace.sh"
  WORKSPACE_DIR="$APM_WORKSPACE_DIR"
}

teardown() {
  trash "$fixture"
}

doctor_fixture() {
  bash -e -s "$repo_root/scripts/apm-workspace.sh" <<'SH'
source "$1"
ensure_workspace_repo() { :; }
ensure_workspace_scaffold() { :; }
validate_codex_skill_target_tree() { :; }
validate_agmsg_roster_link() { :; }
tracked_catalog_instructions_path() { printf '%s/missing' "$APM_WORKSPACE_DIR"; }
tracked_catalog_agents_root() { printf '%s/missing' "$APM_WORKSPACE_DIR"; }
tracked_catalog_commands_root() { printf '%s/missing' "$APM_WORKSPACE_DIR"; }
tracked_catalog_rules_root() { printf '%s/missing' "$APM_WORKSPACE_DIR"; }
managed_catalog_skill_inventory() { :; }
managed_catalog_runtime_targets() { :; }
unpinned_external_references() { :; }
print_catalog_summary() { :; }
cmd_doctor
SH
}

changes_preview() {
  printf '[>] Analyzing installed packages vs apm.yml...\n[!] Found 1 orphaned package(s):\n[!]   - %s (would be removed)\n[*] Dry run complete - no changes made\n' "${1:-owner/gist}" >"$GUARD_PREVIEW"
}

@test "doctor recovers the precise local self-entry error without changing lock or cache" {
  cp "$APM_WORKSPACE_DIR/apm.lock.yaml" "$fixture/before"
  run doctor_fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *"reduced orphan detection"* ]]
  [[ "$output" == *"dependency tree"* ]]
  cmp "$fixture/before" "$APM_WORKSPACE_DIR/apm.lock.yaml"
  [ -f "$APM_WORKSPACE_DIR/apm_modules/owner/gist/SKILL.md" ]
  ! grep -qx prune "$GUARD_CALLS"
}

@test "doctor rejects unrelated error even when it contains the known error" {
  export GUARD_LIST_ERROR="[x] Error listing dependencies: Invalid local package path '': path segments must not be empty; unrelated failure"
  run doctor_fixture
  [ "$status" -ne 0 ]
  ! grep -q 'deps tree' "$GUARD_CALLS"
}

@test "doctor requires local deployed files before using fallback" {
  printf 'dependencies: []\n' >"$APM_WORKSPACE_DIR/apm.lock.yaml"
  run doctor_fixture
  [ "$status" -ne 0 ]
  ! grep -q 'deps tree' "$GUARD_CALLS"
}

@test "doctor propagates fallback tree and preview failures" {
  export GUARD_TREE_EXIT=3
  run doctor_fixture
  [ "$status" -ne 0 ]
  export GUARD_TREE_EXIT=0 GUARD_PREVIEW_EXIT=3
  run doctor_fixture
  [ "$status" -ne 0 ]
}

@test "doctor preserves successful deps list behavior" {
  export GUARD_LIST_MODE=clean
  run doctor_fixture
  [ "$status" -eq 0 ]
  ! grep -q 'deps tree\|prune' "$GUARD_CALLS"
}

@test "deploy fresh retains declared aliased gist and continues its existing stages" {
  printf 'dependencies:\n  apm:\n    - git: https://gist.github.com/owner/gist.git\n      alias: chosen\n' >"$APM_WORKSPACE_DIR/apm.yml"
  changes_preview
  export GUARD_APM_STUB="$fixture/bin/apm"
  cat >"$fixture/bash-env" <<'SH'
apm() { "${GUARD_APM_STUB:?fixture stub not configured}" "$@"; }
SH
  mkdir -p "$APM_WORKSPACE_DIR/scripts/lib"
  cat >"$APM_WORKSPACE_DIR/scripts/apm-stub.sh" <<'SH'
#!/usr/bin/env bash
exec "${GUARD_APM_STUB:?fixture stub not configured}" "$@"
SH
  cp "$repo_root/scripts/apm-workspace.sh" "$APM_WORKSPACE_DIR/scripts/"
  if [ -f "$repo_root/scripts/lib/prune-preview.awk" ]; then
    cp "$repo_root/scripts/lib/prune-preview.awk" "$APM_WORKSPACE_DIR/scripts/lib/"
  fi
  awk '
    /^\[tasks\."(prune:cache|deploy:fresh)"\]/ { active=1 }
    /^\[/ && !/^\[tasks\."(prune:cache|deploy:fresh)"\]/ { active=0 }
    active {
      if ($0 == "  \"apm prune\",") {
        print "  \"bash ./scripts/apm-stub.sh prune\","
      } else {
        print
      }
    }
  ' "$repo_root/mise.toml" >"$APM_WORKSPACE_DIR/mise.toml"
  cat >>"$APM_WORKSPACE_DIR/mise.toml" <<'TOML'
[tasks."repair:local-package-cache"]
run = "echo repaired"
[tasks.deploy]
run = "echo deployed"
TOML
  run env BASH_ENV="$fixture/bash-env" MISE_TRUSTED_CONFIG_PATHS="$APM_WORKSPACE_DIR" "$mise_binary" -C "$APM_WORKSPACE_DIR" run deploy:fresh
  [ "$status" -eq 0 ]
  [ -f "$APM_WORKSPACE_DIR/apm_modules/owner/gist/SKILL.md" ]
  [[ "$output" == *"Automatic prune skipped: aliased packages"* ]]
  grep -qx 'prune --dry-run' "$GUARD_CALLS"
  ! grep -qx prune "$GUARD_CALLS"
  [[ "$output" == *repaired* && "$output" == *deployed* ]]
}

@test "prune retains both lock-only alias packages and unprotected removal candidates" {
  changes_preview transitive/package
  printf 'dependencies:\n- repo_url: owner/transitive\n  alias: cached\n' >"$APM_WORKSPACE_DIR/apm.lock.yaml"
  run cmd_prune_cache
  [ "$status" -eq 0 ]
  [[ "$output" == *"aliased packages"* ]]
  printf 'dependencies: []\n' >"$APM_WORKSPACE_DIR/apm.lock.yaml"
  run cmd_prune_cache
  [ "$status" -eq 0 ]
  [[ "$output" == *"safety is unverified"* ]]
  ! grep -qx prune "$GUARD_CALLS"
}

@test "prune fails closed for failed unknown or inconsistent previews and symlinks" {
  export GUARD_PREVIEW_EXIT=2
  run cmd_prune_cache
  [ "$status" -ne 0 ]
  export GUARD_PREVIEW_EXIT=0
  printf 'new unsupported preview format\n' >"$GUARD_PREVIEW"
  run cmd_prune_cache
  [ "$status" -ne 0 ]
  changes_preview
  sed -i.bak 's/Found 1/Found 2/' "$GUARD_PREVIEW"
  run cmd_prune_cache
  [ "$status" -ne 0 ]
  ln -s "$fixture" "$APM_WORKSPACE_DIR/apm_modules/link"
  run cmd_prune_cache
  [ "$status" -ne 0 ]
  ! grep -qx prune "$GUARD_CALLS"
}

@test "prune propagates alias metadata read errors" {
  grep() { return 2; }
  run cmd_prune_cache
  unset -f grep
  [ "$status" -eq 2 ]
  [[ "$output" == *"Cannot read alias declarations"* ]]
  [ -f "$APM_WORKSPACE_DIR/apm_modules/owner/gist/SKILL.md" ]
}

@test "clean preview retains packages without running native prune" {
  run cmd_prune_cache
  [ "$status" -eq 0 ]
  [[ "$output" == *"native prune was not executed"* ]]
  [ -f "$APM_WORKSPACE_DIR/apm_modules/owner/gist/SKILL.md" ]
  ! grep -qx prune "$GUARD_CALLS"
}
