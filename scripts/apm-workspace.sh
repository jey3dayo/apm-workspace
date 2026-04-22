#!/usr/bin/env bash
set -euo pipefail

COMMAND="${1:-help}"
if [ "$#" -gt 0 ]; then
  shift
fi

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORKSPACE_DIR="${APM_WORKSPACE_DIR:-$HOME/.apm}"
WORKSPACE_REPO="${APM_WORKSPACE_REPO:-https://github.com/jey3dayo/apm-workspace.git}"
CODEX_OUTPUT="${APM_CODEX_OUTPUT:-$HOME/.codex/AGENTS.md}"
MISE_DESTINATION="$WORKSPACE_DIR/mise.toml"
CATALOG_BUILD_ROOT="$WORKSPACE_DIR/.catalog-build"
CATALOG_DIR_NAME="catalog"

have_command() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

error() {
  printf 'error: %s\n' "$*" >&2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  if ! have_command "$1"; then
    fail "$1 not found. Install it first."
  fi
}

require_apm() {
  if ! have_command apm; then
    fail "apm not found. Run 'cd $WORKSPACE_DIR && mise install' (or install it in another shell) before retrying."
  fi
}

validate_skill_id() {
  skill_id="$1"

  case "$skill_id" in
    "" | . | .. | */* | *\\* | :* | *: | *::*)
      fail "Invalid skill id: $skill_id"
      ;;
  esac

  case "$skill_id" in
    [A-Za-z0-9]*)
      ;;
    *)
      fail "Invalid skill id: $skill_id"
      ;;
  esac

  case "$skill_id" in
    *[!A-Za-z0-9._:-]*)
      fail "Invalid skill id: $skill_id"
      ;;
  esac
}

validate_skill_path_segments() {
  original_value="$1"
  shift

  if [ "$#" -eq 0 ]; then
    fail "Invalid skill path: $original_value"
  fi

  for segment in "$@"; do
    case "$segment" in
      "" | . | .. | */* | *\\*)
        fail "Invalid skill path: $original_value"
        ;;
      [A-Za-z0-9]*)
        ;;
      *)
        fail "Invalid skill path: $original_value"
        ;;
    esac

    case "$segment" in
      *[!A-Za-z0-9._-]*)
        fail "Invalid skill path: $original_value"
        ;;
    esac
  done
}

skill_id_to_manifest_path() {
  skill_id="$1"
  old_ifs=$IFS
  IFS=':'
  # shellcheck disable=SC2086
  set -- $skill_id
  IFS=$old_ifs
  validate_skill_path_segments "$skill_id" "$@"
  printf '%s' "$1"
  shift
  for segment in "$@"; do
    printf '/%s' "$segment"
  done
  printf '\n'
}

workspace_project_name() {
  if [ -n "${APM_WORKSPACE_NAME:-}" ]; then
    printf '%s\n' "$APM_WORKSPACE_NAME"
    return 0
  fi

  basename "${WORKSPACE_REPO%.git}"
}

workspace_author_name() {
  git config user.name 2>/dev/null || printf '%s\n' "${USER:-${USERNAME:-unknown}}"
}

ensure_workspace_repo() {
  require_command git

  if [ ! -e "$WORKSPACE_DIR" ]; then
    log "Cloning $WORKSPACE_REPO into $WORKSPACE_DIR"
    git clone "$WORKSPACE_REPO" "$WORKSPACE_DIR"
  elif [ -d "$WORKSPACE_DIR" ] && [ ! -d "$WORKSPACE_DIR/.git" ]; then
    if [ -n "$(ls -A "$WORKSPACE_DIR" 2>/dev/null)" ]; then
      fail "$WORKSPACE_DIR exists but is not an empty directory or git checkout."
    fi

    log "Cloning $WORKSPACE_REPO into existing empty directory $WORKSPACE_DIR"
    (
      cd "$WORKSPACE_DIR"
      git clone "$WORKSPACE_REPO" .
    )
  elif [ ! -d "$WORKSPACE_DIR" ]; then
    fail "$WORKSPACE_DIR exists but is not a directory."
  fi

  if [ ! -d "$WORKSPACE_DIR/.git" ]; then
    fail "$WORKSPACE_DIR exists but is not a git checkout."
  fi

}

ensure_gitignore_entry() {
  entry="$1"
  gitignore_path="$WORKSPACE_DIR/.gitignore"
  touch "$gitignore_path"

  if ! grep -qxF "$entry" "$gitignore_path"; then
    printf '\n%s\n' "$entry" >>"$gitignore_path"
  fi
}

normalize_workspace_gitignore() {
  gitignore_path="$WORKSPACE_DIR/.gitignore"
  [ -f "$gitignore_path" ] || return 0

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/apm-gitignore.XXXXXX")
  awk '
    BEGIN {
      entries[1] = "/.apm/"
      entries[2] = "/apm_modules/"
      entries[3] = "/.catalog-build/"
    }
    function append(line) {
      lines[++line_count] = line
    }
    {
      if ($0 == "# APM dependencies" || $0 == "apm_modules/") {
        next
      }
      for (i = 1; i <= 3; i++) {
        if ($0 == entries[i]) {
          seen[entries[i]] = 1
          next
        }
      }
      append($0)
    }
    END {
      for (i = 1; i <= 3; i++) {
        if (!seen[entries[i]]) {
          if (line_count > 0 && lines[line_count] != "") {
            append("")
          }
          append(entries[i])
        }
      }
      while (line_count > 0 && lines[line_count] == "") {
        line_count--
      }
      for (i = 1; i <= line_count; i++) {
        print lines[i]
      }
    }
  ' "$gitignore_path" >"$tmp_file"
  mv "$tmp_file" "$gitignore_path"
}

write_workspace_manifest_template() {
  manifest_path="$WORKSPACE_DIR/apm.yml"
  project_name=$(workspace_project_name)
  author_name=$(workspace_author_name)

  cat >"$manifest_path" <<EOF
name: $project_name
version: 1.0.0
description: APM project for $project_name
author: $author_name
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
  mcp: []
scripts: {}
EOF
}

ensure_workspace_scaffold() {
  ensure_workspace_repo
  ensure_gitignore_entry '/.apm/'
  ensure_gitignore_entry '/apm_modules/'
  ensure_gitignore_entry '/.catalog-build/'

  if [ ! -f "$WORKSPACE_DIR/apm.yml" ]; then
    log "Writing bootstrap apm.yml in $WORKSPACE_DIR"
    write_workspace_manifest_template
  fi
}

catalog_build_dir() {
  printf '%s/%s\n' "$CATALOG_BUILD_ROOT" "$CATALOG_DIR_NAME"
}

catalog_build_skills_root() {
  printf '%s/.apm/skills\n' "$(catalog_build_dir)"
}

catalog_build_agents_root() {
  printf '%s/agents\n' "$(catalog_build_dir)"
}

catalog_build_commands_root() {
  printf '%s/commands\n' "$(catalog_build_dir)"
}

catalog_build_rules_root() {
  printf '%s/rules\n' "$(catalog_build_dir)"
}

catalog_build_instructions_path() {
  printf '%s/AGENTS.md\n' "$(catalog_build_dir)"
}

tracked_catalog_dir() {
  printf '%s/%s\n' "$WORKSPACE_DIR" "$CATALOG_DIR_NAME"
}

tracked_catalog_skills_root() {
  printf '%s/catalog/skills\n' "$WORKSPACE_DIR"
}

tracked_catalog_agents_root() {
  printf '%s/agents\n' "$(tracked_catalog_dir)"
}

tracked_catalog_commands_root() {
  printf '%s/commands\n' "$(tracked_catalog_dir)"
}

tracked_catalog_rules_root() {
  printf '%s/rules\n' "$(tracked_catalog_dir)"
}

tracked_catalog_instructions_path() {
  printf '%s/AGENTS.md\n' "$(tracked_catalog_dir)"
}

tracked_catalog_relative_path() {
  printf '%s\n' "$CATALOG_DIR_NAME"
}

skill_ids_from_root() {
  skills_root="$1"
  [ -d "$skills_root" ] || return 0

  (
    cd "$skills_root"
    find . -type f -name SKILL.md | sed 's#^\./##' | sed 's#/SKILL\.md$##' | sed 's#/#:#g' | sort -u
  )
}

format_skill_name() {
  target="$1"
  source_skill_id="$2"

  case "$target" in
    codex)
      case "$source_skill_id" in
        superpowers:*)
          printf 'superpowers-%s\n' "${source_skill_id#superpowers:}"
          ;;
        *)
          printf '%s\n' "$source_skill_id"
          ;;
      esac
      ;;
    *)
      printf '%s\n' "$source_skill_id"
      ;;
  esac
}

write_catalog_manifest_template() {
  destination_dir="$1"
  cat >"$destination_dir/apm.yml" <<EOF
name: $CATALOG_DIR_NAME
version: 1.0.0
description: Managed catalog package for global APM rollout
dependencies:
  apm: []
  mcp: []
scripts: {}
EOF
}

locked_external_skill_records() {
  lock_path="$WORKSPACE_DIR/apm.lock.yaml"
  [ -f "$lock_path" ] || fail "Lock file not found: $lock_path"

  awk '
    function indent_level(line, trimmed) {
      trimmed = line
      sub(/^[[:space:]]+/, "", trimmed)
      return length(line) - length(trimmed)
    }
    function flush_record() {
      if (repo_url != "" && resolved_commit != "") {
        printf "%s|%s|%s\n", repo_url, virtual_path, resolved_commit
      }
    }
    /^[^[:space:]#-][^:]*:/ {
      if (in_dependencies && repo_url != "") {
        flush_record()
        repo_url = ""
        resolved_commit = ""
        virtual_path = ""
        record_indent = -1
      }

      split($0, parts, ":")
      key = parts[1]
      in_dependencies = (key == "dependencies")
      dependencies_indent = in_dependencies ? 0 : -1
      next
    }
    !in_dependencies {
      next
    }
    /^[[:space:]]*-[[:space:]]+repo_url:[[:space:]]+/ {
      flush_record()
      repo_url = substr($0, index($0, ":") + 1)
      sub(/^[[:space:]]+/, "", repo_url)
      resolved_commit = ""
      virtual_path = ""
      record_indent = indent_level($0)
      next
    }
    /^[[:space:]]+resolved_commit:[[:space:]]+/ {
      if (repo_url == "" || indent_level($0) <= record_indent) {
        next
      }
      resolved_commit = substr($0, index($0, ":") + 1)
      sub(/^[[:space:]]+/, "", resolved_commit)
      next
    }
    /^[[:space:]]+virtual_path:[[:space:]]+/ {
      if (repo_url == "" || indent_level($0) <= record_indent) {
        next
      }
      virtual_path = substr($0, index($0, ":") + 1)
      sub(/^[[:space:]]+/, "", virtual_path)
      next
    }
    END {
      flush_record()
    }
  ' "$lock_path"
}

write_catalog_readme() {
  destination_dir="$1"
  cat >"$destination_dir/README.md" <<EOF
# $CATALOG_DIR_NAME

This directory contains the managed catalog for the global APM workspace.

- Edit personal skills in \`~/.apm/catalog/skills/<id>/\`
- Edit shared guidance in \`~/.apm/catalog/AGENTS.md\`, \`agents/**\`, \`commands/**\`, and \`rules/**\`
- \`skills\` are authored under \`catalog/skills/**\` and staged into the published package
- \`commands/**\` stays top-level because it is runtime-synced shared guidance, not nested skill package content
- Edit this directory directly, then run \`mise run stage-catalog\` before commit/push
- Install ref: \`jey3dayo/apm-workspace/catalog#main\`
EOF
}

normalize_tracked_catalog_metadata() {
  ensure_workspace_repo
  ensure_workspace_scaffold

  tracked_dir=$(tracked_catalog_dir)
  mkdir -p "$tracked_dir"
  write_catalog_manifest_template "$tracked_dir"
  write_catalog_readme "$tracked_dir"
}

check_tracked_catalog_metadata() {
  ensure_workspace_repo
  ensure_workspace_scaffold

  tracked_dir=$(tracked_catalog_dir)
  expected_dir=$(mktemp -d "${TMPDIR:-/tmp}/apm-catalog-metadata.XXXXXX")
  write_catalog_manifest_template "$expected_dir"
  write_catalog_readme "$expected_dir"

  has_failure=0
  if [ ! -f "$tracked_dir/apm.yml" ] || ! cmp -s "$tracked_dir/apm.yml" "$expected_dir/apm.yml"; then
    error "Tracked catalog manifest is not normalized"
    has_failure=1
  fi

  if [ ! -f "$tracked_dir/README.md" ] || ! cmp -s "$tracked_dir/README.md" "$expected_dir/README.md"; then
    error "Tracked catalog README is not normalized"
    has_failure=1
  fi

  rm -rf "$expected_dir"
  [ "$has_failure" -eq 0 ] || fail "Catalog metadata check failed"
}

reset_catalog_build_dir() {
  destination_dir=$(catalog_build_dir)
  rm -rf "$destination_dir"
  mkdir -p "$destination_dir"
  mkdir -p "$(catalog_build_skills_root)"
}

reset_tracked_catalog_dir() {
  destination_dir=$(tracked_catalog_dir)
  rm -rf "$destination_dir"
  mkdir -p "$destination_dir"
}

workspace_remote_to_repo_reference() {
  remote_url="$1"

  case "$remote_url" in
    https://github.com/*)
      repo_ref=${remote_url#https://github.com/}
      repo_ref=${repo_ref%.git}
      repo_ref=${repo_ref%/}
      printf '%s\n' "$repo_ref"
      ;;
    git@github.com:*)
      repo_ref=${remote_url#git@github.com:}
      repo_ref=${repo_ref%.git}
      printf '%s\n' "$repo_ref"
      ;;
    *)
      fail "Unsupported workspace remote URL for catalog reference: $remote_url"
      ;;
  esac
}

workspace_remote_url() {
  remote_name="${1:-origin}"
  ensure_workspace_repo

  if remote_url=$(git -C "$WORKSPACE_DIR" remote get-url "$remote_name" 2>/dev/null); then
    printf '%s\n' "$remote_url"
    return 0
  fi

  if [ "$remote_name" = "origin" ]; then
    printf '%s\n' "$WORKSPACE_REPO"
    return 0
  fi

  fail "Could not resolve remote URL for '$remote_name'"
}

workspace_repo_reference() {
  remote_name="${1:-origin}"
  workspace_remote_to_repo_reference "$(workspace_remote_url "$remote_name")"
}

workspace_tracking_info() {
  current_branch=$(git -C "$WORKSPACE_DIR" branch --show-current 2>/dev/null || true)
  [ -n "$current_branch" ] || fail "Cannot register catalog from a detached HEAD. Check out a tracking branch first."

  remote_name=$(git -C "$WORKSPACE_DIR" config --get "branch.$current_branch.remote" 2>/dev/null || true)
  merge_ref=$(git -C "$WORKSPACE_DIR" config --get "branch.$current_branch.merge" 2>/dev/null || true)
  [ -n "$remote_name" ] && [ -n "$merge_ref" ] || fail "Branch '$current_branch' has no upstream tracking branch. Push it first."

  merge_branch=${merge_ref#refs/heads/}
  printf '%s\036%s\n' "$remote_name" "$merge_branch"
}

tracked_catalog_reference() {
  tracking_info=$(workspace_tracking_info)
  remote_name=${tracking_info%%"$(printf '\036')"*}
  branch_name=${tracking_info#*"$(printf '\036')"}
  printf '%s/%s#%s\n' "$(workspace_repo_reference "$remote_name")" "$(tracked_catalog_relative_path)" "$branch_name"
}

assert_tracked_catalog_published() {
  tracked_relative_path=$(tracked_catalog_relative_path)
  tracked_dir=$(tracked_catalog_dir)

  [ -d "$tracked_dir" ] || fail "Tracked catalog missing: $tracked_dir. Run 'mise run stage-catalog' first."

  dirty=$(git -C "$WORKSPACE_DIR" status --porcelain -- "$tracked_relative_path" 2>/dev/null || true)
  [ -z "$dirty" ] || fail "Tracked catalog has uncommitted changes. Commit and push $tracked_relative_path before registering it."

  tracking_info=$(workspace_tracking_info)
  remote_name=${tracking_info%%"$(printf '\036')"*}
  branch_name=${tracking_info#*"$(printf '\036')"}
  upstream="$remote_name/$branch_name"
  unpushed=$(git -C "$WORKSPACE_DIR" rev-list "$upstream..HEAD" -- "$tracked_relative_path" 2>/dev/null || true)
  [ -z "$unpushed" ] || fail "Tracked catalog has commits not on $upstream. Push the branch before registering it."
}

managed_skill_content_dir() {
  skill_id="$1"
  validate_skill_id "$skill_id"
  source_dir="$(tracked_catalog_skills_root)"
  old_ifs=$IFS
  IFS=':'
  # shellcheck disable=SC2086
  set -- $skill_id
  IFS=$old_ifs
  validate_skill_path_segments "$skill_id" "$@"
  for segment in "$@"; do
    source_dir="$source_dir/$segment"
  done

  [ -f "$source_dir/SKILL.md" ] || fail "Managed catalog skill missing SKILL.md: $source_dir"
  printf '%s\n' "$source_dir"
}

copy_managed_skill_into_catalog() {
  skill_id="$1"
  skills_root="$2"
  validate_skill_id "$skill_id"
  source_dir=$(managed_skill_content_dir "$skill_id")

  destination_dir="$skills_root"
  old_ifs=$IFS
  IFS=':'
  # shellcheck disable=SC2086
  set -- $skill_id
  IFS=$old_ifs
  validate_skill_path_segments "$skill_id" "$@"
  for segment in "$@"; do
    destination_dir="$destination_dir/$segment"
  done

  mkdir -p "$destination_dir"
  cp -R "$source_dir"/. "$destination_dir"
}

copy_managed_instructions_into_catalog() {
  destination_path="$1"
  source_path=$(tracked_catalog_instructions_path)
  [ -f "$source_path" ] || fail "Managed catalog instructions missing: $source_path"
  destination_dir=$(dirname "$destination_path")
  mkdir -p "$destination_dir"
  cp "$source_path" "$destination_path"
}

copy_managed_agent_assets_into_catalog() {
  destination_dir="$1"
  source_dir=$(tracked_catalog_agents_root)
  [ -d "$source_dir" ] || fail "Managed catalog agents missing: $source_dir"
  mkdir -p "$destination_dir"
  cp -R "$source_dir"/. "$destination_dir"
}

copy_managed_command_assets_into_catalog() {
  destination_dir="$1"
  source_dir=$(tracked_catalog_commands_root)
  [ -d "$source_dir" ] || fail "Managed catalog commands missing: $source_dir"
  mkdir -p "$destination_dir"
  cp -R "$source_dir"/. "$destination_dir"
}

copy_managed_rule_assets_into_catalog() {
  destination_dir="$1"
  source_dir=$(tracked_catalog_rules_root)
  [ -d "$source_dir" ] || fail "Managed catalog rules missing: $source_dir"
  mkdir -p "$destination_dir"
  cp -R "$source_dir"/. "$destination_dir"
}

legacy_skill_content_dir() {
  skill_id="$1"
  validate_skill_id "$skill_id"
  skill_root="$LEGACY_SKILLS_DIR/$skill_id"

  if [ ! -d "$skill_root" ]; then
    fail "Legacy skill not found: $skill_root"
  fi

  if [ -f "$skill_root/SKILL.md" ]; then
    printf '%s\n' "$skill_root"
    return 0
  fi

  if [ -f "$skill_root/skills/SKILL.md" ]; then
    printf '%s\n' "$skill_root/skills"
    return 0
  fi

  fail "Legacy skill content dir missing SKILL.md: $skill_root"
}

manifest_has_local_packages() {
  manifest_path="$WORKSPACE_DIR/apm.yml"

  if [ ! -f "$manifest_path" ]; then
    return 1
  fi

  grep -qE '^[[:space:]]*-[[:space:]]+\./packages/' "$manifest_path"
}

refresh_workspace_checkout() {
  ensure_workspace_repo

  if [ -n "$(git -C "$WORKSPACE_DIR" status --porcelain 2>/dev/null || true)" ]; then
    warn "$WORKSPACE_DIR has local changes; skipping git pull."
    return 0
  fi

  current_branch=$(git -C "$WORKSPACE_DIR" branch --show-current 2>/dev/null || true)
  remote_name=$(git -C "$WORKSPACE_DIR" config --get "branch.$current_branch.remote" 2>/dev/null || true)
  merge_ref=$(git -C "$WORKSPACE_DIR" config --get "branch.$current_branch.merge" 2>/dev/null || true)
  merge_branch=${merge_ref#refs/heads/}
  upstream="$remote_name/$merge_branch"

  if [ -z "$current_branch" ] || [ -z "$remote_name" ] || [ -z "$merge_ref" ]; then
    return 0
  fi

  if ! git -C "$WORKSPACE_DIR" show-ref --verify --quiet "refs/remotes/$upstream"; then
    return 0
  fi

  log "Updating $WORKSPACE_DIR from $upstream"
  git -C "$WORKSPACE_DIR" pull --ff-only
}

ensure_workspace_mise_file() {
  if [ ! -f "$MISE_DESTINATION" ]; then
    fail "Missing workspace mise.toml: $MISE_DESTINATION"
  fi
}

compile_codex() {
  require_apm
  mkdir -p "$(dirname "$CODEX_OUTPUT")"
  (
    cd "$WORKSPACE_DIR"
    apm compile --target codex --output "$CODEX_OUTPUT"
  )
}

internal_deploy_target_roots() {
  printf '%s\n' \
    "$HOME/.claude/skills" \
    "$HOME/.cursor/skills" \
    "$HOME/.opencode/skills" \
    "$HOME/.copilot/skills"
}

internal_target_skill_path() {
  target_root="$1"
  skill_id="$2"
  path="$target_root"
  old_ifs=$IFS
  IFS=':'
  # shellcheck disable=SC2086
  set -- $skill_id
  IFS=$old_ifs
  validate_skill_path_segments "$skill_id" "$@"
  for segment in "$@"; do
    path="$path/$segment"
  done
  printf '%s\n' "$path"
}

legacy_internal_cleanup_alias() {
  skill_id="$1"
  case "$skill_id" in
    brainstorming | dispatching-parallel-agents | executing-plans | finishing-a-development-branch | receiving-code-review | requesting-code-review | subagent-driven-development | systematic-debugging | test-driven-development | using-git-worktrees | using-superpowers | verification-before-completion | writing-plans | writing-skills)
      printf 'superpowers:%s\n' "$skill_id"
      ;;
  esac
}

internal_cleanup_skill_ids() {
  skill_ids="$1"

  {
    printf '%s\n' "$skill_ids"
    printf '%s\n' "$skill_ids" | while IFS= read -r skill_id; do
      [ -n "$skill_id" ] || continue
      legacy_internal_cleanup_alias "$skill_id"
    done
  } | awk 'NF && !seen[$0]++'
}

remove_internal_target_links() {
  skill_ids="$1"

  internal_deploy_target_roots | while IFS= read -r target_root; do
    [ -d "$target_root" ] || continue

    printf '%s\n' "$skill_ids" | while IFS= read -r skill_id; do
      [ -n "$skill_id" ] || continue
      target_path=$(internal_target_skill_path "$target_root" "$skill_id")
      literal_target_path="$target_root/$skill_id"

      for candidate_path in "$literal_target_path" "$target_path"; do
        [ -e "$candidate_path" ] || continue

        if [ -L "$candidate_path" ]; then
          rm -f "$candidate_path"
          log "Removed existing symlink skill target before APM install: $candidate_path"
        fi
      done
    done
  done
}

relative_file_list() {
  root_dir="$1"
  if [ ! -d "$root_dir" ]; then
    return 0
  fi

  (
    cd "$root_dir"
    find . -type f | sed 's#^\./##' | sort
  )
}

migrate_package() {
  package_relative_path="$1"
  (
    cd "$WORKSPACE_DIR"
    apm install "./packages/$package_relative_path"
  )
}

apm_install_has_diagnostics_failure() {
  output_file="$1"
  grep -Eq '\[[xX]\][[:space:]]+[1-9][0-9]* packages failed:' "$output_file" \
    || grep -Eq 'Installed .* with [1-9][0-9]* error\(s\)\.' "$output_file"
}

run_workspace_install_command() {
  output_file=$(mktemp)
  pushd "$WORKSPACE_DIR" >/dev/null || fail "Workspace not found: $WORKSPACE_DIR"
  if apm install "$@" >"$output_file" 2>&1; then
    status=0
  else
    status=$?
  fi
  popd >/dev/null || true

  cat "$output_file"
  if [ "$status" -ne 0 ]; then
    rm -f "$output_file"
    fail "apm install failed: $*"
  fi
  if apm_install_has_diagnostics_failure "$output_file"; then
    rm -f "$output_file"
    fail "apm install reported integration diagnostics: $*"
  fi

  rm -f "$output_file"
}

install_workspace_mcp_dependencies() {
  run_workspace_install_command -g --only mcp
}

cmd_apply() {
  require_apm
  ensure_workspace_repo
  ensure_workspace_scaffold
  cmd_validate_catalog
  ensure_workspace_mise_file

  if manifest_has_local_packages; then
    fail "apm 0.8.11 cannot deploy ./packages/* dependencies at user scope yet. Remove local package refs from ~/.apm/apm.yml and keep the global manifest on upstream refs such as jey3dayo/apm-workspace/catalog#main."
  fi

  apply_stage_root=$(mktemp -d "${TMPDIR:-/tmp}/apm-apply.XXXXXX")
  trap 'rm -rf "$apply_stage_root"' RETURN

  build_target_skill_trees "$apply_stage_root"
  sync_managed_catalog_runtime_assets
  replace_skill_targets_from_stage "$apply_stage_root"
  install_workspace_mcp_dependencies
  normalize_workspace_gitignore
  compile_codex

  trap - RETURN
  rm -rf "$apply_stage_root"
}

cmd_update() {
  require_apm
  ensure_workspace_repo
  refresh_workspace_checkout
  ensure_workspace_scaffold
  cmd_validate_catalog

  if manifest_has_local_packages; then
    fail "apm 0.8.11 cannot update ./packages/* dependencies at user scope yet. Refresh stopped before deps update; remove local package refs from ~/.apm/apm.yml first."
  fi

  (
    cd "$WORKSPACE_DIR"
    apm deps update -g
  )
}

cmd_format_catalog_metadata() {
  normalize_tracked_catalog_metadata
}

cmd_check_catalog_metadata() {
  check_tracked_catalog_metadata
}

lock_pinned_reference_map() {
  locked_external_skill_records | awk -F '|' '
    {
      canonical = $1
      if ($2 != "") {
        canonical = canonical "/" $2
      }
      printf "%s\t%s#%s\n", canonical, canonical, $3
    }
  '
}

unpinned_external_references() {
  manifest_path="$WORKSPACE_DIR/apm.yml"
  [ -f "$manifest_path" ] || return 0

  awk '
    function indent_level(line, trimmed) {
      trimmed = line
      sub(/^[[:space:]]+/, "", trimmed)
      return length(line) - length(trimmed)
    }
    /^[^[:space:]#][^:]*:/ {
      split($0, parts, ":")
      key = parts[1]
      in_dependencies = (key == "dependencies")
      dependencies_indent = in_dependencies ? 0 : -1
      in_apm = 0
      apm_indent = -1
      next
    }
    !in_dependencies {
      next
    }
    /^[[:space:]]+[^:#][^:]*:/ {
      current_indent = indent_level($0)
      line = $0
      sub(/^[[:space:]]+/, "", line)
      split(line, parts, ":")
      key = parts[1]

      if (current_indent <= dependencies_indent) {
        in_dependencies = 0
        dependencies_indent = -1
        in_apm = 0
        apm_indent = -1
        next
      }

      if (current_indent == dependencies_indent + 2 && key == "apm") {
        in_apm = 1
        apm_indent = current_indent
        next
      }

      if (in_apm && current_indent <= apm_indent) {
        in_apm = 0
        apm_indent = -1
      }
      next
    }
    !in_apm {
      next
    }
    /^[[:space:]]*-[[:space:]]+/ {
      if (indent_level($0) < apm_indent) {
        next
      }
      ref = $2
      if (ref ~ /^jey3dayo\/apm-workspace\/catalog(#|$)/) {
        next
      }
      if (ref ~ /^\.\//) {
        next
      }
      if (ref !~ /#/) {
        print ref
      }
    }
  ' "$manifest_path"
}

cmd_pin_external() {
  ensure_workspace_repo
  ensure_workspace_scaffold

  manifest_path="$WORKSPACE_DIR/apm.yml"
  [ -f "$manifest_path" ] || fail "Manifest not found: $manifest_path"

  map_file=$(mktemp)
  awk 'BEGIN { FS = "\t" } { print $1 "\t" $2 }' <<EOF >"$map_file"
$(lock_pinned_reference_map)
EOF

  updated_file=$(mktemp)
  awk -v map_file="$map_file" '
    BEGIN {
      FS = "\t"
      while ((getline < map_file) > 0) {
        pinned[$1] = $2
      }
      close(map_file)
      updated = 0
    }
    {
      if (match($0, /^([[:space:]]*-[[:space:]]+)([^[:space:]]+)[[:space:]]*$/, m)) {
        ref = m[2]
        if (index(ref, "#") == 0 && (ref in pinned)) {
          print m[1] pinned[ref]
          updated++
          next
        }
      }
      print
    }
    END {
      printf "%d\n", updated > "/dev/stderr"
    }
  ' "$manifest_path" >"$updated_file" 2>"$updated_file.count"

  updated_count=$(tr -d '\r\n' <"$updated_file.count")
  if [ "${updated_count:-0}" -eq 0 ]; then
    rm -f "$map_file" "$updated_file" "$updated_file.count"
    log "No external dependencies needed pinning."
    return 0
  fi

  cat "$updated_file" >"$manifest_path"
  rm -f "$map_file" "$updated_file" "$updated_file.count"
  log "Pinned $updated_count external dependency references in apm.yml"
}

managed_skill_ids() {
  skill_ids_from_root "$(tracked_catalog_skills_root)"
}

cmd_validate() {
  require_apm
  ensure_workspace_repo
  ensure_workspace_scaffold
  (
    cd "$WORKSPACE_DIR"
    apm compile --validate
  )
}

managed_agent_relative_paths() {
  tracked_catalog_agent_relative_paths
}

tracked_catalog_agent_relative_paths() {
  relative_file_list "$(tracked_catalog_agents_root)"
}

managed_command_relative_paths() {
  tracked_catalog_command_relative_paths
}

tracked_catalog_command_relative_paths() {
  relative_file_list "$(tracked_catalog_commands_root)"
}

managed_rule_relative_paths() {
  tracked_catalog_rule_relative_paths
}

tracked_catalog_rule_relative_paths() {
  relative_file_list "$(tracked_catalog_rules_root)"
}

file_content_equal() {
  expected_path="$1"
  actual_path="$2"

  [ -f "$expected_path" ] || return 1
  [ -f "$actual_path" ] || return 1

  expected_hash=$(sha256sum "$expected_path" | awk '{print $1}')
  actual_hash=$(sha256sum "$actual_path" | awk '{print $1}')
  [ "$expected_hash" = "$actual_hash" ]
}

tracked_catalog_skill_ids() {
  skill_ids_from_root "$(tracked_catalog_skills_root)"
}

manifest_has_catalog_reference() {
  manifest_path="$WORKSPACE_DIR/apm.yml"
  [ -f "$manifest_path" ] || return 1
  repo_reference=$(workspace_remote_to_repo_reference "$WORKSPACE_REPO")
  grep -q "${repo_reference}/${CATALOG_DIR_NAME}#" "$manifest_path"
}

print_catalog_summary() {
  source_skill_count=$(managed_skill_ids | awk 'NF { count++ } END { print count + 0 }')
  source_agent_count=$(managed_agent_relative_paths | awk 'NF { count++ } END { print count + 0 }')
  source_command_count=$(managed_command_relative_paths | awk 'NF { count++ } END { print count + 0 }')
  source_rule_count=$(managed_rule_relative_paths | awk 'NF { count++ } END { print count + 0 }')
  tracked_manifest=no
  [ -f "$(tracked_catalog_dir)/apm.yml" ] && tracked_manifest=yes
  global_ref=no
  manifest_has_catalog_reference && global_ref=yes
  instructions=missing
  [ -f "$(tracked_catalog_instructions_path)" ] && instructions=present
  status=drift
  if [ "$tracked_manifest" = yes ] && [ "$global_ref" = yes ] && [ "$instructions" = present ]; then
    status=ok
  fi

  printf 'catalog: skills=%s agents=%s commands=%s rules=%s instructions=%s tracked-manifest=%s global-ref=%s status=%s\n' \
    "$source_skill_count" \
    "$source_agent_count" \
    "$source_command_count" \
    "$source_rule_count" \
    "$instructions" "$tracked_manifest" "$global_ref" "$status"
}

managed_catalog_runtime_targets() {
  cat <<'EOF'
claude|.claude|CLAUDE.md|
codex|.codex|AGENTS.md|.agents
cursor|.cursor|AGENTS.md|
opencode|.opencode|CLAUDE.md|
openclaw|.openclaw|CLAUDE.md|
EOF
}

managed_catalog_skill_inventory() {
  skill_ids=$(managed_skill_ids)
  managed_catalog_runtime_targets | while IFS='|' read -r target_name _target_dir _config_name; do
    printf '%s\n' "$skill_ids" | while IFS= read -r skill_id; do
      [ -n "$skill_id" ] || continue
      printf '%s|%s|%s\n' "$target_name" "$skill_id" "$(format_skill_name "$target_name" "$skill_id")"
    done
  done
}

manifest_external_references() {
  manifest_path="$WORKSPACE_DIR/apm.yml"
  [ -f "$manifest_path" ] || return 0

  awk '
    function indent_level(line, trimmed) {
      trimmed = line
      sub(/^[[:space:]]+/, "", trimmed)
      return length(line) - length(trimmed)
    }
    /^[^[:space:]#][^:]*:/ {
      split($0, parts, ":")
      key = parts[1]
      in_dependencies = (key == "dependencies")
      dependencies_indent = in_dependencies ? 0 : -1
      in_apm = 0
      apm_indent = -1
      next
    }
    !in_dependencies {
      next
    }
    /^[[:space:]]+[^:#][^:]*:/ {
      current_indent = indent_level($0)
      line = $0
      sub(/^[[:space:]]+/, "", line)
      split(line, parts, ":")
      key = parts[1]

      if (current_indent <= dependencies_indent) {
        in_dependencies = 0
        dependencies_indent = -1
        in_apm = 0
        apm_indent = -1
        next
      }

      if (current_indent == dependencies_indent + 2 && key == "apm") {
        in_apm = 1
        apm_indent = current_indent
        next
      }

      if (in_apm && current_indent <= apm_indent) {
        in_apm = 0
        apm_indent = -1
      }
      next
    }
    !in_apm {
      next
    }
    /^[[:space:]]*-[[:space:]]+/ {
      if (indent_level($0) <= apm_indent) {
        next
      }
      ref = $2
      if (ref ~ /^jey3dayo\/apm-workspace\/catalog(#|$)/) {
        next
      }
      if (ref ~ /^\.\//) {
        next
      }
      print ref
    }
  ' "$manifest_path"
}

manifest_external_reference_keys() {
  manifest_external_references | awk '
    NF {
      print $0
      base = $0
      sub(/#.*/, "", base)
      print base
    }
  ' | awk 'NF && !seen[$0]++'
}

external_skill_relative_path() {
  virtual_path="$1"

  if [ -z "$virtual_path" ]; then
    printf '\n'
    return 0
  fi

  case "$virtual_path" in
    skills/*)
      relative_path=${virtual_path#skills/}
      ;;
    */skills/*)
      relative_path=${virtual_path#*/skills/}
      ;;
    *)
      fail "Invalid external skill virtual path: $virtual_path"
      ;;
  esac

  case "$relative_path" in
    .*/*)
      relative_path=${relative_path#*/}
      ;;
  esac

  [ -n "$relative_path" ] || fail "Invalid external skill virtual path: $virtual_path"

  printf '%s\n' "$relative_path"
}

external_skill_id_from_virtual_path() {
  virtual_path="$1"
  relative_path=$(external_skill_relative_path "$virtual_path")

  [ -n "$relative_path" ] || fail "Invalid external skill virtual path: $virtual_path"

  old_ifs=$IFS
  IFS='/'
  # shellcheck disable=SC2086
  set -- $relative_path
  IFS=$old_ifs
  validate_skill_path_segments "$virtual_path" "$@"

  skill_id="$1"
  shift
  for segment in "$@"; do
    skill_id="$skill_id:$segment"
  done
  validate_skill_id "$skill_id"
  printf '%s\n' "$skill_id"
}

external_skill_id_from_record() {
  repo_url="$1"
  virtual_path="$2"

  if [ "$repo_url" = "obra/superpowers" ] && [ -n "$virtual_path" ]; then
    skill_id=$(external_skill_id_from_virtual_path "$virtual_path")
    printf 'superpowers:%s\n' "$skill_id"
    return 0
  fi

  if [ -z "$virtual_path" ]; then
    old_ifs=$IFS
    IFS='/'
    # shellcheck disable=SC2086
    set -- $repo_url
    IFS=$old_ifs
    validate_skill_path_segments "$repo_url" "$@"
    skill_id="${!#}"
    validate_skill_id "$skill_id"
    printf '%s\n' "$skill_id"
    return 0
  fi

  external_skill_id_from_virtual_path "$virtual_path"
}

external_skill_content_dir() {
  repo_url="$1"
  virtual_path="$2"
  resolved_commit="$3"
  apm_modules_root="$WORKSPACE_DIR/apm_modules"
  relative_path=$(external_skill_relative_path "$virtual_path")

  [ -d "$apm_modules_root" ] || fail "External skill cache missing: $apm_modules_root"

  found_path=""
  candidate_paths=""
  if [ -n "$virtual_path" ]; then
    candidate_paths=$(printf '%s\n%s\n%s\n' \
      "$apm_modules_root/$repo_url/$virtual_path" \
      "$apm_modules_root/$repo_url/$resolved_commit/$virtual_path" \
      "$apm_modules_root/$resolved_commit/$repo_url/$virtual_path")
  else
    candidate_paths=$(printf '%s\n%s\n%s\n' \
      "$apm_modules_root/$repo_url" \
      "$apm_modules_root/$repo_url/$resolved_commit" \
      "$apm_modules_root/$resolved_commit/$repo_url")
  fi

  if [ -n "$relative_path" ] && [ "$relative_path" != "$virtual_path" ]; then
    candidate_paths=$(printf '%s\n%s\n%s\n%s\n' \
      "$candidate_paths" \
      "$apm_modules_root/$repo_url/$relative_path" \
      "$apm_modules_root/$repo_url/$resolved_commit/$relative_path" \
      "$apm_modules_root/$resolved_commit/$repo_url/$relative_path")
  fi

  while IFS= read -r candidate_path; do
    [ -n "$candidate_path" ] || continue
    [ -f "$candidate_path/SKILL.md" ] || continue
    if [ -n "$found_path" ] && [ "$found_path" != "$candidate_path" ]; then
      fail "Ambiguous external skill cache paths for $repo_url/$virtual_path"
    fi
    found_path="$candidate_path"
  done <<EOF
$candidate_paths
EOF

  if [ -n "$found_path" ]; then
    printf '%s\n' "$found_path"
    return 0
  fi

  if [ -z "$virtual_path" ]; then
    fail "Missing external skill cache for $repo_url@$resolved_commit"
  fi

  search_matches=$(
    rg --files -uu "$apm_modules_root" -g 'SKILL.md' 2>/dev/null | awk -v root="$apm_modules_root/" -v suffix1="$virtual_path" -v suffix2="$relative_path" -v repo="$repo_url" -v commit="$resolved_commit" '
      function matches_suffix(rel, suffix, expected) {
        if (suffix == "") {
          return 0
        }

        expected = "/" suffix "/SKILL.md"
        return length(rel) >= length(expected) && substr(rel, length(rel) - length(expected) + 1) == expected
      }
      {
        rel = $0
        if (index(rel, root) == 1) {
          rel = substr(rel, length(root) + 1)
        }
        if (!matches_suffix(rel, suffix1) && !matches_suffix(rel, suffix2)) {
          next
        }

        score = 0
        if (index(rel, repo) > 0) {
          score += 10
        }
        if (commit != "" && index(rel, commit) > 0) {
          score += 1
        }
        directory = rel
        sub(/\/SKILL\.md$/, "", directory)
        print score "\t" root directory
      }
    ' | sort -t "$(printf '\t')" -k1,1nr -k2,2
  ) || true

  best_match=$(printf '%s\n' "$search_matches" | awk -F '\t' '
    NR == 1 {
      best_score = $1
      best_path = $2
      top_count = 1
      next
    }
    $1 == best_score {
      top_count++
    }
    END {
      if (best_path == "") {
        exit 1
      }
      if (top_count != 1) {
        exit 2
      }
      print best_path
    }
  ')
  best_status=$?
  case "$best_status" in
    0)
      printf '%s\n' "$best_match"
      ;;
    1)
      fail "Missing external skill cache for $repo_url/$virtual_path@$resolved_commit"
      ;;
    *)
      fail "Ambiguous external skill cache for $repo_url/$virtual_path@$resolved_commit"
      ;;
  esac
}

collect_personal_skill_records() {
  managed_skill_ids | while IFS= read -r skill_id; do
    [ -n "$skill_id" ] || continue
    source_path=$(managed_skill_content_dir "$skill_id")
    printf 'personal\t%s\t%s\tcatalog\n' "$skill_id" "$source_path"
  done
}

collect_external_skill_records() {
  manifest_refs_file=$(mktemp "${TMPDIR:-/tmp}/apm-manifest-refs.XXXXXX")
  manifest_keys_file=$(mktemp "${TMPDIR:-/tmp}/apm-manifest-keys.XXXXXX")
  lock_records_file=$(mktemp "${TMPDIR:-/tmp}/apm-lock-records.XXXXXX")
  matched_keys_file=$(mktemp "${TMPDIR:-/tmp}/apm-lock-matches.XXXXXX")
  : >"$matched_keys_file"

  manifest_external_references >"$manifest_refs_file"
  manifest_external_reference_keys >"$manifest_keys_file"
  locked_external_skill_records >"$lock_records_file"

  if [ ! -s "$manifest_refs_file" ] && [ ! -s "$lock_records_file" ]; then
    rm -f "$manifest_refs_file" "$manifest_keys_file" "$lock_records_file" "$matched_keys_file"
    return 0
  fi

  has_failure=0
  while IFS='|' read -r repo_url virtual_path resolved_commit; do
    [ -n "$repo_url" ] || continue
    canonical_ref="$repo_url"
    if [ -n "$virtual_path" ]; then
      canonical_ref="$canonical_ref/$virtual_path"
    fi

    if [ "$canonical_ref" = "jey3dayo/apm-workspace/catalog" ]; then
      continue
    fi

    if ! awk -v key="$canonical_ref" '$0 == key { found = 1; exit } END { exit(found ? 0 : 1) }' "$manifest_keys_file"; then
      error "External lock record is not declared in apm.yml: $canonical_ref"
      has_failure=1
      continue
    fi

    printf '%s\n' "$canonical_ref" >>"$matched_keys_file"
    printf '%s#%s\n' "$canonical_ref" "$resolved_commit" >>"$matched_keys_file"

    source_skill_id=$(external_skill_id_from_record "$repo_url" "$virtual_path")
    source_path=$(external_skill_content_dir "$repo_url" "$virtual_path" "$resolved_commit")
    printf 'external\t%s\t%s\t%s\n' "$source_skill_id" "$source_path" "$canonical_ref"
  done <"$lock_records_file"

  while IFS= read -r manifest_ref; do
    [ -n "$manifest_ref" ] || continue
    required_key="$manifest_ref"
    case "$required_key" in
      *#*)
        ;;
      *)
        required_key=${required_key%%#*}
        ;;
    esac

    if ! awk -v key="$required_key" '$0 == key { found = 1; exit } END { exit(found ? 0 : 1) }' "$matched_keys_file"; then
      error "External manifest ref is missing from apm.lock.yaml: $manifest_ref"
      has_failure=1
    fi
  done <"$manifest_refs_file"

  rm -f "$manifest_refs_file" "$manifest_keys_file" "$lock_records_file" "$matched_keys_file"
  [ "$has_failure" -eq 0 ] || fail "External skill state is inconsistent"
}

deployment_plan_record() {
  printf 'target_name=%s\ttarget_dir=%s\tsource_kind=%s\tsource_skill_id=%s\tdeployed_skill_name=%s\tsource_path=%s\tsource_ref=%s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

deployment_plan_record_field() {
  record="$1"
  field_name="$2"

  printf '%s\n' "$record" | awk -F '\t' -v key="$field_name" '
    {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          print substr($i, length(prefix) + 1)
          exit
        }
      }
    }
  '
}

build_deployment_plan_entries() {
  skill_records="$1"

  printf '%s\n' "$skill_records" | while IFS=$'\t' read -r source_kind source_skill_id source_path source_ref; do
    [ -n "$source_skill_id" ] || continue
    managed_catalog_runtime_targets | while IFS='|' read -r target_name target_dir _config_name; do
      deployed_skill_name=$(format_skill_name "$target_name" "$source_skill_id")
      validate_skill_id "$deployed_skill_name"
      deployment_plan_record \
        "$target_name" \
        "$target_dir" \
        "$source_kind" \
        "$source_skill_id" \
        "$deployed_skill_name" \
        "$source_path" \
        "$source_ref"
    done
  done
}

validate_deployment_collisions() {
  skill_records="$1"
  deployment_plan="$2"

  printf '%s\n' "$skill_records" | awk -F '\t' '
    NF < 4 {
      next
    }
    {
      if ($2 in seen) {
        printf "error: duplicate source skill id detected: %s\n", $2 > "/dev/stderr"
        status = 1
      }
      seen[$2] = $1
    }
    END {
      exit status
    }
  ' || fail "Deployment source records collided"

  printf '%s\n' "$deployment_plan" | awk -F '\t' '
    function field_value(name, i, prefix) {
      prefix = name "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          return substr($i, length(prefix) + 1)
        }
      }
      return ""
    }
    NF == 0 {
      next
    }
    {
      target_name = field_value("target_name")
      source_kind = field_value("source_kind")
      source_skill_id = field_value("source_skill_id")
      deployed_skill_name = field_value("deployed_skill_name")

      if (deployed_skill_name == "") {
        printf "error: invalid deployed skill name for %s (%s)\n", source_skill_id, target_name > "/dev/stderr"
        status = 1
        next
      }

      key = target_name "\t" deployed_skill_name
      owner = source_kind ":" source_skill_id
      if (key in seen) {
        printf "error: target skill collision for %s/%s (%s vs %s)\n", target_name, deployed_skill_name, seen[key], owner > "/dev/stderr"
        status = 1
      }
      seen[key] = owner
    }
    END {
      exit status
    }
  ' || fail "Deployment target records collided"
}

stage_target_skill_records() {
  deployment_plan="$1"
  stage_root="$2"

  managed_catalog_runtime_targets | while IFS='|' read -r target_name _target_dir _config_name; do
    mkdir -p "$stage_root/$target_name/skills"
  done

  printf '%s\n' "$deployment_plan" | while IFS= read -r plan_record; do
    [ -n "$plan_record" ] || continue
    target_name=$(deployment_plan_record_field "$plan_record" target_name)
    deployed_skill_name=$(deployment_plan_record_field "$plan_record" deployed_skill_name)
    source_path=$(deployment_plan_record_field "$plan_record" source_path)
    [ -n "$target_name" ] || continue
    stage_skills_root="$stage_root/$target_name/skills"
    staged_skill_path=$(internal_target_skill_path "$stage_skills_root" "$deployed_skill_name")
    mkdir -p "$staged_skill_path"
    cp -R "$source_path"/. "$staged_skill_path"
  done
}

build_target_skill_trees() {
  stage_root="$1"
  personal_skill_records=$(collect_personal_skill_records)
  external_skill_records=$(collect_external_skill_records)
  skill_records=$(printf '%s\n%s\n' "$personal_skill_records" "$external_skill_records" | awk 'NF')
  deployment_plan=$(build_deployment_plan_entries "$skill_records")

  validate_deployment_collisions "$skill_records" "$deployment_plan"
  stage_target_skill_records "$deployment_plan" "$stage_root"
}

swap_staged_skill_tree_into_place() {
  staged_skills_root="$1"
  target_skills_root="$2"
  target_parent_dir=$(dirname "$target_skills_root")
  staging_copy_root="$target_parent_dir/.apm-skills-next.$$"
  backup_root="$target_parent_dir/.apm-skills-backup.$$"

  mkdir -p "$target_parent_dir"
  rm -rf "$staging_copy_root" "$backup_root"
  cp -R "$staged_skills_root" "$staging_copy_root"

  if [ -e "$target_skills_root" ] || [ -L "$target_skills_root" ]; then
    mv "$target_skills_root" "$backup_root"
  fi

  if mv "$staging_copy_root" "$target_skills_root"; then
    rm -rf "$backup_root"
    return 0
  fi

  rm -rf "$staging_copy_root"
  if [ -e "$backup_root" ] || [ -L "$backup_root" ]; then
    mv "$backup_root" "$target_skills_root" || true
  fi
  fail "Failed to replace skill target: $target_skills_root"
}

replace_skill_targets_from_stage() {
  stage_root="$1"

  managed_catalog_runtime_targets | while IFS='|' read -r target_name target_dir _config_name skills_dir; do
    target_root="$HOME/$target_dir"
    skills_root_dir="${skills_dir:-$target_dir}"
    legacy_skills_root="$target_root/skills"
    target_skills_root="$HOME/$skills_root_dir/skills"
    staged_skills_root="$stage_root/$target_name/skills"
    [ -d "$staged_skills_root" ] || mkdir -p "$staged_skills_root"
    if [ "$legacy_skills_root" != "$target_skills_root" ] && { [ -e "$legacy_skills_root" ] || [ -L "$legacy_skills_root" ]; }; then
      rm -rf "$legacy_skills_root"
    fi
    swap_staged_skill_tree_into_place "$staged_skills_root" "$target_skills_root"
  done
}

copy_managed_catalog_file() {
  source_path="$1"
  destination_path="$2"
  mkdir -p "$(dirname "$destination_path")"
  if [ -L "$destination_path" ]; then
    rm -f "$destination_path"
  elif [ -d "$destination_path" ]; then
    fail "Refusing to replace directory target: $destination_path"
  fi
  cp "$source_path" "$destination_path"
}

remove_symlink_entries() {
  target_dir="$1"
  if [ -L "$target_dir" ]; then
    rm -f "$target_dir"
    return 0
  fi
  [ -d "$target_dir" ] || return 0
  find "$target_dir" -type l -exec rm -f {} +
}

sync_managed_catalog_runtime_assets() {
  tracked_dir=$(tracked_catalog_dir)
  [ -d "$tracked_dir" ] || fail "Tracked catalog missing: $tracked_dir. Run 'mise run stage-catalog' first."

  instructions_source=$(tracked_catalog_instructions_path)
  agents_source=$(tracked_catalog_agents_root)
  commands_source=$(tracked_catalog_commands_root)
  rules_source=$(tracked_catalog_rules_root)

  managed_catalog_runtime_targets | while IFS='|' read -r _target_name target_dir config_name; do
    target_root="$HOME/$target_dir"
    mkdir -p "$target_root"

    if [ -f "$instructions_source" ]; then
      copy_managed_catalog_file "$instructions_source" "$target_root/$config_name"
    fi

    if [ -d "$agents_source" ]; then
      mkdir -p "$target_root/agents"
      remove_symlink_entries "$target_root/agents"
      cp -R "$agents_source"/. "$target_root/agents"
    fi

    if [ -d "$commands_source" ]; then
      mkdir -p "$target_root/commands"
      remove_symlink_entries "$target_root/commands"
      cp -R "$commands_source"/. "$target_root/commands"
    fi

    if [ -d "$rules_source" ]; then
      mkdir -p "$target_root/rules"
      remove_symlink_entries "$target_root/rules"
      cp -R "$rules_source"/. "$target_root/rules"
    fi
  done
}

cmd_validate_catalog() {
  ensure_workspace_repo
  ensure_workspace_scaffold

  has_failure=0
  source_skill_ids=$(managed_skill_ids)
  source_agent_paths=$(managed_agent_relative_paths)
  source_command_paths=$(managed_command_relative_paths)
  source_rule_paths=$(managed_rule_relative_paths)
  tracked_manifest="$(tracked_catalog_dir)/apm.yml"
  tracked_readme="$(tracked_catalog_dir)/README.md"
  tracked_instructions="$(tracked_catalog_instructions_path)"

  expected_dir=$(mktemp -d "${TMPDIR:-/tmp}/apm-catalog-expected.XXXXXX")
  write_catalog_manifest_template "$expected_dir"
  write_catalog_readme "$expected_dir"

  if [ ! -f "$tracked_manifest" ]; then
    error "Tracked catalog manifest is missing: $tracked_manifest"
    has_failure=1
  elif ! cmp -s "$tracked_manifest" "$expected_dir/apm.yml"; then
    error "Tracked catalog manifest is not normalized"
    has_failure=1
  fi

  if [ ! -f "$tracked_readme" ]; then
    error "Tracked catalog README is missing: $tracked_readme"
    has_failure=1
  elif ! cmp -s "$tracked_readme" "$expected_dir/README.md"; then
    error "Tracked catalog README is not normalized"
    has_failure=1
  fi

  rm -rf "$expected_dir"

  if ! manifest_has_catalog_reference; then
    error "Global apm.yml is missing the managed catalog ref"
    has_failure=1
  fi

  if [ ! -f "$tracked_instructions" ]; then
    error "Tracked catalog is missing instructions: $tracked_instructions"
    has_failure=1
  fi

  for required_root in "$(tracked_catalog_skills_root):skills" "$(tracked_catalog_agents_root):agents" "$(tracked_catalog_commands_root):commands" "$(tracked_catalog_rules_root):rules"; do
    root_path=${required_root%%:*}
    root_label=${required_root#*:}
    if [ ! -d "$root_path" ]; then
      error "Tracked catalog is missing $root_label: $root_path"
      has_failure=1
    fi
  done

  if [ -z "$(printf '%s\n' "$source_skill_ids" | awk 'NF { print; exit }')" ]; then
    error "Tracked catalog has no managed skills"
    has_failure=1
  fi

  [ "$has_failure" -eq 0 ] || fail "Catalog validation failed"
  source_skill_count=$(printf '%s\n' "$source_skill_ids" | awk 'NF { count++ } END { print count + 0 }')
  source_agent_count=$(printf '%s\n' "$source_agent_paths" | awk 'NF { count++ } END { print count + 0 }')
  source_command_count=$(printf '%s\n' "$source_command_paths" | awk 'NF { count++ } END { print count + 0 }')
  source_rule_count=$(printf '%s\n' "$source_rule_paths" | awk 'NF { count++ } END { print count + 0 }')
  log "Catalog validation passed ($source_skill_count skills, $source_agent_count agents, $source_command_count commands, $source_rule_count rules)"
}

cmd_doctor() {
  require_apm
  ensure_workspace_repo
  ensure_workspace_scaffold
  (
    cd "$WORKSPACE_DIR"
    printf 'apm: %s\n' "$(apm --version)"
    printf 'workspace: %s\n' "$WORKSPACE_DIR"
    printf 'manifest: %s\n' "$(test -f apm.yml && printf present || printf missing)"
    printf 'branch: %s\n' "$(git branch --show-current 2>/dev/null || printf detached)"
    printf 'remote:\n'
    git remote -v || true
    printf 'targets:\n'
    inventory_file=$(mktemp "${TMPDIR:-/tmp}/apm-skill-inventory.XXXXXX")
    codex_mcp_config="$HOME/.codex/config.toml"
    managed_catalog_skill_inventory >"$inventory_file"
    managed_catalog_runtime_targets | while IFS='|' read -r target_name target_dir config_name skills_dir; do
      target_root="$HOME/$target_dir"
      skills_root_dir="${skills_dir:-$target_dir}"
      target_skills_root="$HOME/$skills_root_dir/skills"
      if [ -e "$target_root/$config_name" ]; then config_state=present; else config_state=missing; fi
      if [ -e "$target_root/agents" ]; then agents_state=present; else agents_state=missing; fi
      if [ -e "$target_root/commands" ]; then commands_state=present; else commands_state=missing; fi
      if [ -e "$target_root/rules" ]; then rules_state=present; else rules_state=missing; fi
      if [ -e "$target_skills_root" ]; then skills_state=present; else skills_state=missing; fi
      printf '  %s: config=%s agents=%s commands=%s rules=%s skills=%s\n' "$target_name" "$config_state" "$agents_state" "$commands_state" "$rules_state" "$skills_state"
    done
    printf 'codex mcp config: %s\n' "$(test -f "$codex_mcp_config" && printf present || printf missing)"
    printf 'target skill inventory: entries=%s\n' "$(awk 'NF { count++ } END { print count + 0 }' "$inventory_file")"
    rm -f "$inventory_file"
    printf 'external pins: unpinned=%s\n' "$(unpinned_external_references | awk 'NF { count++ } END { print count + 0 }')"
    print_catalog_summary
    apm deps list -g
  )
}

cmd_seed_catalog_build() {
  skill_ids=$(managed_skill_ids)
  ensure_workspace_repo
  ensure_workspace_scaffold
  ensure_workspace_mise_file

  reset_catalog_build_dir
  write_catalog_manifest_template "$(catalog_build_dir)"
  write_catalog_readme "$(catalog_build_dir)"
  copy_managed_instructions_into_catalog "$(catalog_build_instructions_path)"
  copy_managed_agent_assets_into_catalog "$(catalog_build_agents_root)"
  copy_managed_command_assets_into_catalog "$(catalog_build_commands_root)"
  copy_managed_rule_assets_into_catalog "$(catalog_build_rules_root)"

  printf '%s\n' "$skill_ids" | while IFS= read -r skill_id; do
    [ -n "$skill_id" ] || continue
    copy_managed_skill_into_catalog "$skill_id" "$(catalog_build_skills_root)"
  done

  log "Seeded catalog build at ~/.apm/.catalog-build/$CATALOG_DIR_NAME from: $(printf '%s' "$skill_ids" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
}

cmd_bundle_catalog() {
  cmd_seed_catalog_build "$@"
  log "Built catalog package at ~/.apm/.catalog-build/$CATALOG_DIR_NAME"
}

cmd_stage_catalog() {
  cmd_bundle_catalog "$@"

  tracked_dir=$(tracked_catalog_dir)
  reset_tracked_catalog_dir
  cp -R "$(catalog_build_dir)"/. "$tracked_dir"

  reference=$(tracked_catalog_reference)
  log "Updated ~/.apm/catalog at $tracked_dir"
  log "Candidate upstream ref: $reference"
  log "Push the updated apm-workspace repo before using 'apm install -g $reference'."
}

cmd_register_catalog() {
  require_apm
  skill_ids=$(managed_skill_ids)
  cleanup_skill_ids=$(internal_cleanup_skill_ids "$skill_ids")
  ensure_workspace_repo
  ensure_workspace_scaffold
  ensure_workspace_mise_file
  assert_tracked_catalog_published
  cmd_validate_catalog

  remove_internal_target_links "$cleanup_skill_ids"

  reference=$(tracked_catalog_reference)
  run_workspace_install_command -g "$reference"
  normalize_workspace_gitignore
  sync_managed_catalog_runtime_assets
  log "Registered catalog from upstream ref: $reference"
}

assert_catalog_release_ready() {
  local dirty tracking_info remote_name branch_name upstream unpushed

  ensure_workspace_repo

  dirty=$(git -C "$WORKSPACE_DIR" status --porcelain 2>/dev/null) || fail "Failed to inspect git status for $WORKSPACE_DIR"
  if [[ -n "${dirty//$'\n'/}" ]]; then
    fail "Working tree is dirty after stage-catalog. Commit or stash changes, push the branch, then rerun catalog:release."
  fi

  tracking_info=$(workspace_tracking_info)
  remote_name=${tracking_info%%"$(printf '\036')"*}
  branch_name=${tracking_info#*"$(printf '\036')"}
  upstream="$remote_name/$branch_name"

  unpushed=$(git -C "$WORKSPACE_DIR" rev-list "$upstream..HEAD" 2>/dev/null) || fail "Failed to compare HEAD against $upstream"
  if [[ -n "${unpushed//$'\n'/}" ]]; then
    fail "Branch has commits not on $upstream. Push before running catalog:release."
  fi
}

cmd_release_catalog() {
  require_apm
  ensure_workspace_repo
  ensure_workspace_scaffold
  ensure_workspace_mise_file

  cmd_stage_catalog "$@"
  assert_catalog_release_ready
  cmd_register_catalog "$@"
}

cmd_smoke_catalog() {
  require_apm
  skill_ids=$(managed_skill_ids)

  cmd_bundle_catalog "$@"

  temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/apm-catalog-smoke.XXXXXX")
  (
    cd "$temp_dir"
    apm install "$(catalog_build_dir)" --target codex
  ) || fail "apm install failed for catalog smoke test. Temp workspace: $temp_dir"

  printf '%s\n' "$skill_ids" | while IFS= read -r skill_id; do
    [ -n "$skill_id" ] || continue
    source_relative_path=$(skill_id_to_manifest_path "$skill_id")
    installed_skill_name=$(format_skill_name codex "$skill_id")
    installed_relative_path=$(skill_id_to_manifest_path "$installed_skill_name")

    if [ ! -f "$temp_dir/.agents/skills/$installed_relative_path/SKILL.md" ]; then
      fail "Smoke test failed: expected installed skill file missing: $temp_dir/.agents/skills/$installed_relative_path/SKILL.md"
    fi

    expected_files=$(relative_file_list "$(catalog_build_skills_root)/$source_relative_path")
    actual_files=$(relative_file_list "$temp_dir/.agents/skills/$installed_relative_path")
    if [ "$expected_files" != "$actual_files" ]; then
      fail "Smoke test failed: installed skill tree for $skill_id differed from catalog."
    fi
  done

  rm -rf "$temp_dir"
  log "Smoke verified catalog via temp project install: $(printf '%s' "$skill_ids" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
}

cmd_help() {
  cat <<EOF
Usage: scripts/apm-workspace.sh <command> [args...]

Commands:
  apply              Offline deploy user-scope-compatible dependencies and compile Codex output
  update             Refresh the checkout and dependencies only; does not deploy
  format-catalog-metadata  Normalize tracked catalog apm.yml and README.md
  check-catalog-metadata   Check tracked catalog apm.yml and README.md normalization
  pin-external       Pin external manifest refs to lockfile commits
  validate           Validate the ~/.apm workspace
  validate:catalog   Fail when ~/.apm/catalog is not normalized or missing required assets
  doctor             Inspect workspace and target state
  bundle-catalog     Build ~/.apm/.catalog-build/catalog as the catalog package artifact
  stage-catalog      Rewrite ~/.apm/catalog into its normalized publishable layout and print its upstream ref
  register-catalog   Install the catalog ref after commit/push
  release-catalog    Stage, require a clean pushed branch, then install the catalog ref
  smoke-catalog      Smoke-test the generated catalog package via temp project install

Environment overrides:
  APM_WORKSPACE_DIR
  APM_WORKSPACE_REPO
  APM_WORKSPACE_NAME
  APM_CODEX_OUTPUT
EOF
}

case "$COMMAND" in
  apply) cmd_apply ;;
  update) cmd_update ;;
  format-catalog-metadata) cmd_format_catalog_metadata ;;
  check-catalog-metadata) cmd_check_catalog_metadata ;;
  pin-external) cmd_pin_external ;;
  validate) cmd_validate ;;
  validate:catalog) cmd_validate_catalog ;;
  doctor) cmd_doctor ;;
  bundle-catalog) cmd_bundle_catalog "$@" ;;
  stage-catalog) cmd_stage_catalog "$@" ;;
  register-catalog) cmd_register_catalog "$@" ;;
  release-catalog) cmd_release_catalog "$@" ;;
  smoke-catalog) cmd_smoke_catalog "$@" ;;
  help | -h | --help) cmd_help ;;
  *)
    fail "unknown command: $COMMAND"
    ;;
esac
