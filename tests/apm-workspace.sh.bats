#!/usr/bin/env bats
#
# Behavioral unit tests for scripts/apm-workspace.sh: the pure,
# side-effect-free helpers, the public command dispatch surface (invoked as a
# subprocess), and fixture-backed guards such as assert_catalog_stage_safety
# that protect the tracked catalog from destructive resets. Sourcing the
# script from bats leaves ${BASH_SOURCE[0]} != $0, so the bottom-of-file
# dispatch guard keeps the command dispatch from running on load.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Sourcing the script re-derives its own REPO_ROOT from $0 (the bats
  # runner), clobbering the value above. Subprocess-invocation tests need the
  # real repo root, so keep a copy that survives sourcing.
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/apm-workspace.sh"
  source "$REPO_ROOT/scripts/apm-workspace.sh"
}

# --- validate_skill_id -------------------------------------------------------

@test "validate_skill_id accepts a plain id" {
  run validate_skill_id "foo"
  [ "$status" -eq 0 ]
}

@test "validate_skill_id accepts a hyphenated id" {
  run validate_skill_id "foo-bar"
  [ "$status" -eq 0 ]
}

@test "validate_skill_id accepts a namespaced id" {
  run validate_skill_id "a:b:c"
  [ "$status" -eq 0 ]
}

@test "validate_skill_id accepts dots and underscores" {
  run validate_skill_id "a.b_c"
  [ "$status" -eq 0 ]
}

@test "validate_skill_id rejects an empty id" {
  run validate_skill_id ""
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a single dot" {
  run validate_skill_id "."
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a double dot" {
  run validate_skill_id ".."
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a forward slash" {
  run validate_skill_id "a/b"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a backslash" {
  run validate_skill_id "a\\b"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a leading colon" {
  run validate_skill_id ":lead"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a trailing colon" {
  run validate_skill_id "trail:"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects doubled colons" {
  run validate_skill_id "a::b"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a space" {
  run validate_skill_id "bad space"
  [ "$status" -ne 0 ]
}

@test "validate_skill_id rejects a leading hyphen" {
  run validate_skill_id "-leading"
  [ "$status" -ne 0 ]
}

# --- validate_skill_path_segments -------------------------------------------

@test "validate_skill_path_segments accepts a run of valid segments" {
  run validate_skill_path_segments "a:b:c" a b c
  [ "$status" -eq 0 ]
}

@test "validate_skill_path_segments rejects a run containing .." {
  run validate_skill_path_segments "a:..:c" a .. c
  [ "$status" -ne 0 ]
}

@test "validate_skill_path_segments rejects a run containing an empty segment" {
  run validate_skill_path_segments "a::c" a "" c
  [ "$status" -ne 0 ]
}

# --- skill_id_to_manifest_path ----------------------------------------------

@test "skill_id_to_manifest_path converts a:b:c to a/b/c" {
  run skill_id_to_manifest_path "a:b:c"
  [ "$status" -eq 0 ]
  [ "$output" = "a/b/c" ]
}

@test "skill_id_to_manifest_path leaves a single segment unchanged" {
  run skill_id_to_manifest_path "a"
  [ "$status" -eq 0 ]
  [ "$output" = "a" ]
}

# --- format_skill_name ------------------------------------------------------

@test "format_skill_name uses the logical leaf of a namespaced id" {
  run format_skill_name "sample:spec-init"
  [ "$status" -eq 0 ]
  [ "$output" = "spec-init" ]
}

@test "format_skill_name uses the final segment of a nested namespaced id" {
  run format_skill_name "mattpocock:engineering:wayfinder"
  [ "$status" -eq 0 ]
  [ "$output" = "wayfinder" ]
}

# --- workspace_remote_to_repo_reference -------------------------------------

@test "manifest helpers read git dependency subsets" {
  workspace_dir="$(mktemp -d)"
  cat >"$workspace_dir/apm.yml" <<'EOF'
dependencies:
  apm:
    - git: nextlevelbuilder/ui-ux-pro-max-skill
      skills:
        - design
        - ui-ux-pro-max
    - modem-dev/hunk/skills/hunk-review
EOF
  WORKSPACE_DIR="$workspace_dir"

  run manifest_external_references
  [ "$status" -eq 0 ]
  [ "$output" = $'nextlevelbuilder/ui-ux-pro-max-skill\nmodem-dev/hunk/skills/hunk-review' ]

  subset_output="$(manifest_external_skill_subset "nextlevelbuilder/ui-ux-pro-max-skill")"
  [ "$subset_output" = $'design\nui-ux-pro-max' ]

  rm -rf "$workspace_dir"
}

@test "manifest skill subset parsing emits no awk warnings" {
  workspace_dir="$(mktemp -d)"
  cat >"$workspace_dir/apm.yml" <<'EOF'
dependencies:
  apm:
    - git: nextlevelbuilder/ui-ux-pro-max-skill
      skills:
        - ui-ux-pro-max
EOF
  WORKSPACE_DIR="$workspace_dir"

  run manifest_external_skill_subset "nextlevelbuilder/ui-ux-pro-max-skill"
  [ "$status" -eq 0 ]
  [ "$output" = "ui-ux-pro-max" ]

  rm -rf "$workspace_dir"
}

@test "upgrade uses the interactive apm update command" {
  run rg -F 'run = ["apm update -g", { task = "deploy" }]' "$WORKSPACE_DIR/mise.toml"
  [ "$status" -eq 0 ]
}

@test "audit smoke preserves manifest targets" {
  run rg -F 'apm install --only apm &&' "$WORKSPACE_DIR/scripts/apm-workspace.sh"
  [ "$status" -eq 0 ]
}

# --- host-local MCP bootstrap ----------------------------------------------

@test "resolve_1password_mcp_command prefers a native command" {
  fake_bin="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/1password-mcp"
  chmod +x "$fake_bin/1password-mcp"

  PATH="$fake_bin:$PATH" run resolve_1password_mcp_command

  [ "$status" -eq 0 ]
  [ "$output" = "$fake_bin/1password-mcp" ]
  rm -rf "$fake_bin"
}

@test "resolve_1password_mcp_command converts the Windows app alias under WSL" {
  fake_bin="$(mktemp -d)"
  cat >"$fake_bin/cmd.exe" <<'EOF'
#!/usr/bin/env bash
printf 'C:\\Users\\sample\\AppData\\Local\\Microsoft\\WindowsApps\\1password-mcp.exe\r\n'
EOF
  cat >"$fake_bin/wslpath" <<'EOF'
#!/usr/bin/env bash
printf '/mnt/c/Users/sample/AppData/Local/Microsoft/WindowsApps/1password-mcp.exe\n'
EOF
  chmod +x "$fake_bin/cmd.exe" "$fake_bin/wslpath"

  APM_1PASSWORD_MCP_APP_PATHS="" PATH="$fake_bin:/usr/bin:/bin" run resolve_1password_mcp_command

  [ "$status" -eq 0 ]
  [ "$output" = "/mnt/c/Users/sample/AppData/Local/Microsoft/WindowsApps/1password-mcp.exe" ]
  rm -rf "$fake_bin"
}

@test "mise bootstrap keeps host MCP setup tasks hidden" {
  run rg -U '\[tasks\.bootstrap\]\n(?:.*\n)*?hide = true' "$WORKSPACE_DIR/mise.toml"
  [ "$status" -eq 0 ]

  run rg -U '\[tasks\."setup:mcp:host"\]\n(?:.*\n)*?hide = true' "$WORKSPACE_DIR/mise.toml"
  [ "$status" -eq 0 ]
}

@test "normalize_codex_mcp_config removes only top-level MCP identity fields" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/.codex"
  cat >"$workspace_dir/.codex/config.toml" <<'EOF'
[mcp_servers.context7]
command = "npx"
id = ""

[mcp_servers.context7.env]
id = "preserve nested"

[other]
id = "preserve"
EOF

  WORKSPACE_DIR="$workspace_dir"
  normalize_codex_mcp_config
  config="$(<"$workspace_dir/.codex/config.toml")"

  [[ "$config" != *'id = ""'* ]]
  [[ "$config" == *'id = "preserve nested"'* ]]
  [[ "$config" == *'id = "preserve"'* ]]

  rm -rf "$workspace_dir"
}

@test "external lock matching ignores GitHub reference casing" {
  workspace_dir="$(mktemp -d)"
  cat >"$workspace_dir/apm.yml" <<'EOF'
dependencies:
  apm:
    - Lum1104/Understand-Anything/understand-anything-plugin/skills/understand
EOF
  WORKSPACE_DIR="$workspace_dir"
  locked_external_skill_records() {
    printf '%s\n' 'lum1104/understand-anything|understand-anything-plugin/skills/understand|abc123|main'
  }
  external_skill_content_dir() {
    printf '%s\n' '/tmp/understand'
  }

  run collect_external_skill_records
  [ "$status" -eq 0 ]
  [ "$output" = $'external\tunderstand\t/tmp/understand\tlum1104/understand-anything/understand-anything-plugin/skills/understand' ]

  locked_external_skill_records() {
    printf '%s\n' 'lum1104/understand-anything|understand-anything-plugin/skills/Understand|abc123|main'
  }
  run collect_external_skill_records
  [ "$status" -ne 0 ]

  rm -rf "$workspace_dir"
}

@test "workspace_remote_to_repo_reference parses an https remote" {
  run workspace_remote_to_repo_reference "https://github.com/owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

@test "workspace_remote_to_repo_reference parses a git@ remote" {
  run workspace_remote_to_repo_reference "git@github.com:owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

# --- is_path_under_dir ------------------------------------------------------

@test "sync_managed_catalog_runtime_assets replaces managed agent trees" {
  workspace_dir="$(mktemp -d)"
  runtime_home="$(mktemp -d)"
  target_root="$runtime_home/.claude"

  mkdir -p "$workspace_dir/catalog/agents" "$target_root/agents" "$target_root/commands"
  printf '%s\n' 'current' >"$workspace_dir/catalog/agents/current.md"
  printf '%s\n' 'old' >"$target_root/agents/current.md"
  printf '%s\n' 'stale' >"$target_root/agents/stale.md"
  printf '%s\n' 'outside' >"$target_root/commands/untouched.md"

  WORKSPACE_DIR="$workspace_dir"
  HOME="$runtime_home"
  managed_catalog_runtime_targets() {
    printf '%s\n' 'claude|.claude|CLAUDE.md|.claude'
  }

  run sync_managed_catalog_runtime_assets

  [ "$status" -eq 0 ]
  [ "$(<"$target_root/agents/current.md")" = "current" ]
  [ ! -e "$target_root/agents/stale.md" ]
  [ "$(<"$target_root/commands/untouched.md")" = "outside" ]

  rm -rf "$workspace_dir" "$runtime_home"
}

@test "is_path_under_dir returns 0 for a child path" {
  parent="$(mktemp -d)"
  mkdir -p "$parent/child"
  run is_path_under_dir "$parent/child" "$parent"
  [ "$status" -eq 0 ]
  rm -rf "$parent"
}

@test "is_path_under_dir returns 1 for a sibling outside the directory" {
  base="$(mktemp -d)"
  other="$(mktemp -d)"
  run is_path_under_dir "$other" "$base"
  [ "$status" -eq 1 ]
  rm -rf "$base" "$other"
}

@test "is_path_under_dir returns 0 for identical paths" {
  dir="$(mktemp -d)"
  run is_path_under_dir "$dir" "$dir"
  [ "$status" -eq 0 ]
  rm -rf "$dir"
}

@test "is_path_under_dir returns 1 for a sibling whose name has the directory's name as a string prefix" {
  base="$(mktemp -d)"
  mkdir -p "$base/b" "$base/bc"
  run is_path_under_dir "$base/bc" "$base/b"
  [ "$status" -eq 1 ]
  rm -rf "$base"
}

@test "repair_local_package_cache_entry refuses an empty package name (would rm -rf the cache root)" {
  workspace_dir="$(mktemp -d)"
  source_dir="$(mktemp -d)"
  printf '%s\n' 'content' >"$source_dir/file.md"
  WORKSPACE_DIR="$workspace_dir"
  mkdir -p "$workspace_dir/apm_modules/jey3dayo/apm-workspace/keep-me"

  run repair_local_package_cache_entry "" "$source_dir"

  [ "$status" -ne 0 ]
  # The cache root and its existing contents must be untouched.
  [ -d "$workspace_dir/apm_modules/jey3dayo/apm-workspace/keep-me" ]

  rm -rf "$workspace_dir" "$source_dir"
}

# --- stage_codex_skill_records ----------------------------------------------

@test "stage_codex_skill_records preserves symlinks inside a skill source instead of dereferencing them" {
  source_dir="$(mktemp -d)"
  stage_root="$(mktemp -d)"
  printf '%s\n' 'real' >"$source_dir/real-file.md"
  ln -s /nonexistent-target "$source_dir/link.md"

  skill_records=$(printf 'personal\tfoo\t%s\tcatalog\n' "$source_dir")
  run stage_codex_skill_records "$skill_records" "$stage_root"

  [ "$status" -eq 0 ]
  staged_skill_path="$stage_root/codex/skills/foo"
  [ "$(<"$staged_skill_path/real-file.md")" = "real" ]
  [ -L "$staged_skill_path/link.md" ]
  [ "$(readlink "$staged_skill_path/link.md")" = "/nonexistent-target" ]

  rm -rf "$source_dir" "$stage_root"
}

# --- public command dispatch surface ----------------------------------------

@test "help lists the current public command set" {
  run bash "$SCRIPT_UNDER_TEST" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"refresh"* ]]
  [[ "$output" == *"validate:catalog"* ]]
  [[ "$output" == *"prepare:catalog"* ]]
  [[ "$output" == *"install:catalog"* ]]
  [[ "$output" == *"apply:skills:local"* ]]
  [[ "$output" == *"repair:local-package-cache"* ]]
  [[ "$output" == *"smoke:catalog"* ]]
  [[ "$output" == *"audit:ci:smoke"* ]]
}

@test "help does not list retired command names" {
  run bash "$SCRIPT_UNDER_TEST" help
  [ "$status" -eq 0 ]
  [[ "$output" != *"release:catalog"* ]]
  [[ "$output" != *"format-catalog-metadata"* ]]
  [[ "$output" != *"check-catalog-metadata"* ]]
  [[ "$output" != *"validate-internal"* ]]
  [[ "$output" != *"stage-internal"* ]]
  [[ "$output" != *"register-internal"* ]]
  [[ "$output" != *"migrate-internal"* ]]
}

@test "unknown command exits non-zero with a diagnosable message" {
  run bash "$SCRIPT_UNDER_TEST" definitely-not-a-command
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
}

# --- assert_catalog_stage_safety --------------------------------------------

# Builds a temp workspace with a tracked catalog and a matching
# .catalog-build/catalog tree, both containing $1 skills (and one file each
# under agents/commands/rules unless suppressed by the caller after the
# fact). Sets WORKSPACE_DIR and CATALOG_BUILD_ROOT to point at it, along with
# FIXTURE_WORKSPACE_DIR for teardown. Must be called directly (not inside a
# command substitution) so those global assignments are not lost to a
# subshell.
make_catalog_fixture() {
  tracked_skill_count="$1"
  build_skill_count="$2"
  workspace_dir="$(mktemp -d)"

  tracked_dir="$workspace_dir/catalog"
  build_dir="$workspace_dir/.catalog-build/catalog"

  mkdir -p "$tracked_dir/skills" "$tracked_dir/agents" "$tracked_dir/commands" "$tracked_dir/rules"
  mkdir -p "$build_dir/skills" "$build_dir/agents" "$build_dir/commands" "$build_dir/rules"

  printf 'dependencies: []\n' >"$tracked_dir/apm.yml"
  printf '# catalog\n' >"$tracked_dir/README.md"
  printf '# instructions\n' >"$tracked_dir/AGENTS.md"
  printf 'agent\n' >"$tracked_dir/agents/sample.md"
  printf 'command\n' >"$tracked_dir/commands/sample.md"
  printf 'rule\n' >"$tracked_dir/rules/sample.md"

  printf 'dependencies: []\n' >"$build_dir/apm.yml"
  printf '# catalog\n' >"$build_dir/README.md"
  printf '# instructions\n' >"$build_dir/AGENTS.md"
  printf 'agent\n' >"$build_dir/agents/sample.md"
  printf 'command\n' >"$build_dir/commands/sample.md"
  printf 'rule\n' >"$build_dir/rules/sample.md"

  index=0
  while [ "$index" -lt "$tracked_skill_count" ]; do
    mkdir -p "$tracked_dir/skills/skill-$index"
    touch "$tracked_dir/skills/skill-$index/SKILL.md"
    index=$((index + 1))
  done

  index=0
  while [ "$index" -lt "$build_skill_count" ]; do
    mkdir -p "$build_dir/skills/skill-$index"
    touch "$build_dir/skills/skill-$index/SKILL.md"
    index=$((index + 1))
  done

  WORKSPACE_DIR="$workspace_dir"
  CATALOG_BUILD_ROOT="$workspace_dir/.catalog-build"
  FIXTURE_WORKSPACE_DIR="$workspace_dir"
}

@test "assert_catalog_stage_safety refuses a partial request without the override" {
  make_catalog_fixture 2 2

  run assert_catalog_stage_safety 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Refusing to prepare a partial catalog"* ]]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "assert_catalog_stage_safety allows a partial request with the shrink override" {
  make_catalog_fixture 2 2

  APM_ALLOW_CATALOG_SHRINK=1 run assert_catalog_stage_safety 1
  [ "$status" -eq 0 ]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "assert_catalog_stage_safety refuses a build that would shrink tracked skills" {
  make_catalog_fixture 2 1

  run assert_catalog_stage_safety 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"would shrink skills from"* ]]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "assert_catalog_stage_safety refuses an incomplete catalog build" {
  make_catalog_fixture 2 2
  rm -f "$workspace_dir/.catalog-build/catalog/apm.yml"

  run assert_catalog_stage_safety 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"catalog build is incomplete"* ]]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "assert_catalog_stage_safety refuses a build with no skills" {
  make_catalog_fixture 2 2
  rm -rf "$workspace_dir/.catalog-build/catalog/skills"
  mkdir -p "$workspace_dir/.catalog-build/catalog/skills"

  run assert_catalog_stage_safety 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"catalog build has no skills"* ]]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "assert_catalog_stage_safety refuses a build that would empty agents" {
  make_catalog_fixture 2 2
  rm -f "$workspace_dir/.catalog-build/catalog/agents/sample.md"

  run assert_catalog_stage_safety 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"would empty agents"* ]]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "assert_catalog_stage_safety passes for a fully valid fixture" {
  make_catalog_fixture 2 2

  run assert_catalog_stage_safety 0
  [ "$status" -eq 0 ]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

# --- ensure_workspace_scaffold -----------------------------------------------

@test "ensure_workspace_scaffold fails when apm.yml is missing" {
  workspace_dir="$(mktemp -d)"
  WORKSPACE_DIR="$workspace_dir"
  ensure_workspace_repo() { :; }

  run ensure_workspace_scaffold
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing workspace apm.yml"* ]]

  rm -rf "$workspace_dir"
}

@test "ensure_workspace_scaffold succeeds when apm.yml is present" {
  workspace_dir="$(mktemp -d)"
  printf 'dependencies: []\n' >"$workspace_dir/apm.yml"
  WORKSPACE_DIR="$workspace_dir"
  ensure_workspace_repo() { :; }

  run ensure_workspace_scaffold
  [ "$status" -eq 0 ]

  rm -rf "$workspace_dir"
}

# --- remove_internal_target_links --------------------------------------------

@test "remove_internal_target_links removes symlinks but preserves real directories" {
  runtime_home="$(mktemp -d)"
  link_source="$(mktemp -d)"
  HOME="$runtime_home"

  mkdir -p "$runtime_home/.claude/skills"
  ln -s "$link_source" "$runtime_home/.claude/skills/linked-skill"
  mkdir -p "$runtime_home/.claude/skills/real-skill"
  printf 'keep me\n' >"$runtime_home/.claude/skills/real-skill/note.md"

  run remove_internal_target_links "linked-skill"$'\n'"real-skill"

  [ "$status" -eq 0 ]
  [ ! -e "$runtime_home/.claude/skills/linked-skill" ]
  [ -d "$runtime_home/.claude/skills/real-skill" ]
  [ "$(<"$runtime_home/.claude/skills/real-skill/note.md")" = "keep me" ]

  rm -rf "$runtime_home" "$link_source"
}

# --- cleanup_legacy_workspace_skill_targets ---------------------------------

@test "cleanup_legacy_workspace_skill_targets removes physical skills but preserves bridges and adjacent files" {
  workspace_dir="$(mktemp -d)"
  bridge_source="$workspace_dir/.apm/skills/workspace-only"
  mkdir -p "$bridge_source" "$workspace_dir/.agents/skills/stale-skill" "$workspace_dir/.claude/skills/stale-skill" "$workspace_dir/.agents/skills/notes"
  printf '# stale\n' >"$workspace_dir/.agents/skills/stale-skill/SKILL.md"
  printf '# stale\n' >"$workspace_dir/.claude/skills/stale-skill/SKILL.md"
  printf 'keep me\n' >"$workspace_dir/.agents/skills/notes/README.md"
  ln -s "$bridge_source" "$workspace_dir/.agents/skills/workspace-only"
  ln -s "$bridge_source" "$workspace_dir/.claude/skills/workspace-only"
  WORKSPACE_DIR="$workspace_dir"

  run cleanup_legacy_workspace_skill_targets

  [ "$status" -eq 0 ]
  [ ! -e "$workspace_dir/.agents/skills/stale-skill" ]
  [ ! -e "$workspace_dir/.claude/skills/stale-skill" ]
  [ -L "$workspace_dir/.agents/skills/workspace-only" ]
  [ -L "$workspace_dir/.claude/skills/workspace-only" ]
  [ "$(<"$workspace_dir/.agents/skills/notes/README.md")" = "keep me" ]

  rm -rf "$workspace_dir"
}

# --- assert_catalog_cache_freshness ------------------------------------------
#
# The tracked side of the comparison must be git-tracked files (`git
# ls-files`), never a raw filesystem walk: gitignored build artifacts
# (.pytest_cache/, __pycache__/, etc.) can exist under catalog/ without ever
# being part of the deployed package, and must never be reported as missing
# from the cache. Every fixture below `git init`s the tracked catalog dir and
# `git add`s the files meant to count as tracked.

_git_track() {
  dir="$1"
  git -C "$dir" init -q
  git -C "$dir" add -A
}

@test "assert_catalog_cache_freshness cache_freshness passes when cache matches tracked" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/catalog/skills/foo" "$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo"
  printf 'a\n' >"$workspace_dir/catalog/skills/foo/SKILL.md"
  printf 'a\n' >"$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo/SKILL.md"
  _git_track "$workspace_dir/catalog"

  WORKSPACE_DIR="$workspace_dir"

  run assert_catalog_cache_freshness

  [ "$status" -eq 0 ]

  rm -rf "$workspace_dir"
}

@test "assert_catalog_cache_freshness cache_freshness fails with remedy when a tracked file is missing from cache" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/catalog/skills/new-skill" "$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog"
  printf 'a\n' >"$workspace_dir/catalog/skills/new-skill/SKILL.md"
  _git_track "$workspace_dir/catalog"

  WORKSPACE_DIR="$workspace_dir"

  run assert_catalog_cache_freshness

  [ "$status" -ne 0 ]
  [[ "$output" == *"new-skill"* ]]
  [[ "$output" == *"deploy:fresh"* ]]

  rm -rf "$workspace_dir"
}

@test "assert_catalog_cache_freshness cache_freshness fails with remedy when the cache directory is absent" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/catalog/skills/foo"
  printf 'a\n' >"$workspace_dir/catalog/skills/foo/SKILL.md"
  _git_track "$workspace_dir/catalog"

  WORKSPACE_DIR="$workspace_dir"

  run assert_catalog_cache_freshness

  [ "$status" -ne 0 ]
  [[ "$output" == *"deploy:fresh"* ]]

  rm -rf "$workspace_dir"
}

@test "assert_catalog_cache_freshness cache_freshness passes when the cache has an extra file not tracked" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/catalog/skills/foo" "$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo"
  printf 'a\n' >"$workspace_dir/catalog/skills/foo/SKILL.md"
  printf 'a\n' >"$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo/SKILL.md"
  printf 'metadata\n' >"$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo/extra.json"
  _git_track "$workspace_dir/catalog"

  WORKSPACE_DIR="$workspace_dir"

  run assert_catalog_cache_freshness

  [ "$status" -eq 0 ]

  rm -rf "$workspace_dir"
}

@test "assert_catalog_cache_freshness cache_freshness truncates the message for many missing files" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/catalog/skills" "$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog"
  for i in $(seq 1 20); do
    printf 'a\n' >"$workspace_dir/catalog/skills/file-$i.md"
  done
  _git_track "$workspace_dir/catalog"

  WORKSPACE_DIR="$workspace_dir"

  run assert_catalog_cache_freshness

  [ "$status" -ne 0 ]
  [[ "$output" == *"20"* ]]
  [[ "$output" != *"file-20.md"* ]]

  rm -rf "$workspace_dir"
}

@test "assert_catalog_cache_freshness cache_freshness ignores gitignored untracked files under tracked_dir" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/catalog/skills/foo" "$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo"
  printf 'a\n' >"$workspace_dir/catalog/skills/foo/SKILL.md"
  printf 'a\n' >"$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo/SKILL.md"

  mkdir -p "$workspace_dir/catalog/skills/foo/__pycache__"
  printf '*.pyc\n' >"$workspace_dir/catalog/skills/foo/.gitignore"
  printf '*.pyc\n' >"$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo/.gitignore"
  printf 'compiled\n' >"$workspace_dir/catalog/skills/foo/__pycache__/module.cpython-314.pyc"

  _git_track "$workspace_dir/catalog"

  WORKSPACE_DIR="$workspace_dir"

  run assert_catalog_cache_freshness

  [ "$status" -eq 0 ]
  [[ "$output" != *"pycache"* ]]

  rm -rf "$workspace_dir"
}

@test "assert_catalog_cache_freshness passes when a tracked dotfile is present in the cache" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/catalog/skills/foo" "$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo"
  printf 'a\n' >"$workspace_dir/catalog/skills/foo/SKILL.md"
  printf 'a\n' >"$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo/SKILL.md"
  printf '\n' >"$workspace_dir/catalog/.gitkeep"
  printf '\n' >"$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/.gitkeep"
  _git_track "$workspace_dir/catalog"

  WORKSPACE_DIR="$workspace_dir"

  run assert_catalog_cache_freshness

  [ "$status" -eq 0 ]

  rm -rf "$workspace_dir"
}

@test "assert_catalog_cache_freshness fails when a tracked dotfile is missing from the cache" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/catalog/skills/foo" "$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo"
  printf 'a\n' >"$workspace_dir/catalog/skills/foo/SKILL.md"
  printf 'a\n' >"$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo/SKILL.md"
  printf '\n' >"$workspace_dir/catalog/.gitkeep"
  _git_track "$workspace_dir/catalog"

  WORKSPACE_DIR="$workspace_dir"

  run assert_catalog_cache_freshness

  [ "$status" -ne 0 ]
  [[ "$output" == *".gitkeep"* ]]

  rm -rf "$workspace_dir"
}

@test "assert_catalog_cache_freshness fails when a cached file's contents differ from the tracked file" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/catalog/skills/foo" "$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo"
  printf 'a\n' >"$workspace_dir/catalog/skills/foo/SKILL.md"
  printf 'DIFFERENT\n' >"$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo/SKILL.md"
  _git_track "$workspace_dir/catalog"

  WORKSPACE_DIR="$workspace_dir"

  run assert_catalog_cache_freshness

  [ "$status" -ne 0 ]
  [[ "$output" == *"different contents"* ]]
  [[ "$output" == *"deploy:fresh"* ]]

  rm -rf "$workspace_dir"
}

# --- assert_tracked_catalog_published ----------------------------------------

_setup_published_workspace() {
  remote_dir="$1"
  workspace_dir="$2"

  git init -q --bare "$remote_dir"
  git clone -q "$remote_dir" "$workspace_dir"
  git -C "$workspace_dir" config user.email "test@example.com"
  git -C "$workspace_dir" config user.name "Test"
  git -C "$workspace_dir" checkout -q -b main
  mkdir -p "$workspace_dir/catalog/skills/foo"
  printf 'a\n' >"$workspace_dir/catalog/skills/foo/SKILL.md"
  git -C "$workspace_dir" add -A
  git -C "$workspace_dir" commit -q -m "init"
  git -C "$workspace_dir" push -q -u origin main
}

@test "assert_tracked_catalog_published fails when the tracked catalog has uncommitted changes" {
  remote_dir="$(mktemp -d)"
  workspace_dir="$(mktemp -d)"
  rmdir "$workspace_dir"
  _setup_published_workspace "$remote_dir" "$workspace_dir"

  printf 'dirty\n' >"$workspace_dir/catalog/skills/foo/SKILL.md"

  WORKSPACE_DIR="$workspace_dir"

  run assert_tracked_catalog_published

  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted changes"* ]]

  rm -rf "$remote_dir" "$workspace_dir"
}

@test "assert_tracked_catalog_published fails when the tracked catalog has unpushed commits" {
  remote_dir="$(mktemp -d)"
  workspace_dir="$(mktemp -d)"
  rmdir "$workspace_dir"
  _setup_published_workspace "$remote_dir" "$workspace_dir"

  printf 'b\n' >"$workspace_dir/catalog/skills/foo/extra.md"
  git -C "$workspace_dir" add -A
  git -C "$workspace_dir" commit -q -m "unpushed"

  WORKSPACE_DIR="$workspace_dir"

  run assert_tracked_catalog_published

  [ "$status" -ne 0 ]
  [[ "$output" == *"commits not on"* ]]

  rm -rf "$remote_dir" "$workspace_dir"
}

@test "assert_tracked_catalog_published fails closed when the workspace is not a git repository" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/catalog/skills/foo"
  printf 'a\n' >"$workspace_dir/catalog/skills/foo/SKILL.md"
  # No `git init`: git status/rev-list must fail, and the gate must not treat
  # that failure as "clean" / "pushed".

  WORKSPACE_DIR="$workspace_dir"

  run assert_tracked_catalog_published

  [ "$status" -ne 0 ]

  rm -rf "$workspace_dir"
}

@test "assert_catalog_cache_freshness fails closed when git ls-files fails" {
  workspace_dir="$(mktemp -d)"
  mkdir -p "$workspace_dir/catalog/skills/foo" "$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo"
  printf 'a\n' >"$workspace_dir/catalog/skills/foo/SKILL.md"
  printf 'a\n' >"$workspace_dir/apm_modules/jey3dayo/apm-workspace/catalog/skills/foo/SKILL.md"
  # Deliberately do NOT git-init the tracked catalog dir: `git ls-files` fails
  # (not a git repository), and the gate must not treat that as "no tracked
  # files" and pass vacuously.

  WORKSPACE_DIR="$workspace_dir"

  run assert_catalog_cache_freshness

  [ "$status" -ne 0 ]

  rm -rf "$workspace_dir"
}
