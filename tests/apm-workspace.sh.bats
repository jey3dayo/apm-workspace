#!/usr/bin/env bats
#
# Behavioral unit tests for the pure, side-effect-free helpers in
# scripts/apm-workspace.sh. Sourcing the script from bats leaves
# ${BASH_SOURCE[0]} != $0, so the bottom-of-file dispatch guard keeps the
# command dispatch from running on load.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
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
  run format_skill_name "superpowers:using-superpowers"
  [ "$status" -eq 0 ]
  [ "$output" = "using-superpowers" ]
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

@test "Jina MCP ownership is guarded by tracked APM guidance" {
  run rg -F 'This manifest entry is the source of truth; runtime MCP blocks are deployed outputs.' "$WORKSPACE_DIR/apm.yml"
  [ "$status" -eq 0 ]

  run rg -F 'MCP 設定を永続変更する前に、次の ownership gate を完了する' "$WORKSPACE_DIR/catalog/AGENTS.md"
  [ "$status" -eq 0 ]

  run rg -F '`~/.codex/config.toml` の MCP block 編集、`codex mcp add` / `codex mcp remove`' "$WORKSPACE_DIR/catalog/skills/apm-usage/SKILL.md"
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

  PATH="$fake_bin:/usr/bin:/bin" run resolve_1password_mcp_command

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
