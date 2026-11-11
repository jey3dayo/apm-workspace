# The catalog package carries only catalog/.apm/skills, catalog/.apm/agents and the one catalog instruction, while APM
# installs .apm/<primitive>/** whatever the package type. Prints a message when catalog/.apm holds anything else.
catalog_apm_dir_claim_message() {
  apm_dir="$(tracked_catalog_dir)/.apm"
  if [ -L "$apm_dir" ]; then
    printf 'catalog/.apm is a symlink; validate:catalog needs a real directory there. Replace the link with a directory.\n'
    return 0
  fi
  [ -d "$apm_dir" ] || return 0

  # A failed scan must claim: an unreadable directory would otherwise hide what the catalog package would carry.
  if ! non_regular_entries=$(cd "$apm_dir" && find . -mindepth 1 ! -type d ! -type f) ||
    ! regular_files=$(cd "$apm_dir" && find . -mindepth 1 -type f); then
    printf 'catalog/.apm could not be fully read, so validate:catalog cannot tell what it holds. Make every entry under catalog/.apm readable first.\n'
    return 0
  fi
  # The classification below reads paths line by line, so a name with a newline could pose as SKILL.md; claim it instead.
  newline=$(printf '\n_')
  newline=${newline%_}
  if ! newline_entries=$(cd "$apm_dir" && find . -mindepth 1 -name "*$newline*") || [ -n "$newline_entries" ]; then
    printf 'catalog/.apm holds an entry whose name contains a newline, which the catalog guard cannot classify. Rename it.\n'
    return 0
  fi

  claimed_entry=$({
    printf '%s\n' "$non_regular_entries" | sed -n 's#^\./#N #p'
    printf '%s\n' "$regular_files" | sed -n 's#^\./#F #p'
  } | awk -v instructions_file="$CATALOG_INSTRUCTIONS_FILE_NAME" '
    {
      kind = substr($0, 1, 1)
      entry = substr($0, 3)
      entries[++count] = entry
      kinds[count] = kind
      if (kind == "F" && entry ~ /^skills\/.+\/SKILL\.md$/) {
        skill_dir = entry
        sub(/\/SKILL\.md$/, "", skill_dir)
        skill_dirs[skill_dir] = 1
      }
    }
    END {
      for (i = 1; i <= count; i++) {
        entry = entries[i]
        if (kinds[i] != "F") { print entry; continue }
        if (entry ~ /^agents\/[^\/]+\.agent\.md$/) continue
        if (entry == "instructions/" instructions_file) continue
        enclosed = 0
        if (entry ~ /^skills\//) {
          parent = entry
          while (sub(/\/[^\/]*$/, "", parent)) {
            if (parent in skill_dirs) { enclosed = 1; break }
          }
        }
        if (!enclosed) print entry
      }
    }' | sort | sed -n 1p)
  [ -n "$claimed_entry" ] || return 0

  case "$claimed_entry" in
    skills/* | agents/* | instructions/*)
      if [ -f "$apm_dir/$claimed_entry" ] && [ ! -L "$apm_dir/$claimed_entry" ]; then
        printf 'catalog/.apm holds %s, which is outside the allowed catalog layout: it keeps only files inside a skill directory (one holding SKILL.md), agents named agents/<name>.agent.md and instructions/%s. Move it into a skill, rename the agent, or merge the instruction into instructions/%s.\n' "$claimed_entry" "$CATALOG_INSTRUCTIONS_FILE_NAME" "$CATALOG_INSTRUCTIONS_FILE_NAME"
        return 0
      fi
      ;;
  esac
  printf 'catalog/.apm holds %s, but the catalog package carries only catalog/.apm/skills, catalog/.apm/agents and the catalog instruction. Move it out of catalog/.apm.\n' "$claimed_entry"
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
  # Deploy using the logical skill name (the final namespace segment). Target
  # collision validation prevents two sources from claiming the same path.
  printf '%s\n' "${1##*:}"
}

locked_external_skill_records() {
  lock_path="$WORKSPACE_DIR/apm.lock.yaml"
  [ -f "$lock_path" ] || fail "Lock file not found: $lock_path"

  awk -f "$APM_AWK_DIR/lockfile-dependencies.awk" "$lock_path"
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

managed_skill_ids() {
  skill_ids_from_root "$(tracked_catalog_skills_root)"
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
  source_skill_count=$(tracked_catalog_skill_ids | awk 'NF { count++ } END { print count + 0 }')
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

# Fields: name|home-relative root|config file|skills root override|agents face.
# The config file is the root context `apm compile -g` writes from the catalog
# instruction; no sync writes it.
# A "-" config file marks a target without one: OpenCode gets the guide from
# sync_opencode_instructions; see docs/package-decisions.md.
# A "-" skills override marks a target with no skills face. An "apm" agents face
# marks a target whose agents/ is filled from an APM render of
# catalog/.apm/agents: the sync neither writes nor prunes it, and doctor compares
# its content. A "-" agents face
# marks one that must not receive the catalog agents at all (any agents/ is
# removed). OpenCode takes both "-" faces:
# it reads skills from ~/.claude/skills and ~/.agents/skills already, and it
# rejects the Claude-format agents (object `tools`, hex `color`) at startup, so
# it only gets commands. Codex opts out of agents too: codex-cli
# only discovers `~/.codex/agents/*.toml`, and the catalog's Claude-format
# `.md` agent files are silently ignored there (or rejected once renamed to
# `.toml`, on the `tools`/`color` fields).
managed_catalog_runtime_targets() {
  cat <<'EOF'
claude|.claude|CLAUDE.md||apm
codex|.codex|AGENTS.md|.agents|-
cursor|.cursor|AGENTS.md||apm
opencode|.config/opencode|-|-|-
EOF
}

# Binds one managed_catalog_runtime_targets record to RT_* globals, keeping the
# pipe layout in one place. Returns non-zero at EOF to drive `while` loops.
read_runtime_target() {
  IFS='|' read -r RT_TARGET_NAME RT_TARGET_DIR RT_CONFIG_NAME RT_SKILLS_DIR RT_AGENTS_FACE
}

managed_catalog_skill_inventory() {
  skill_ids=$(managed_skill_ids)
  managed_catalog_runtime_targets | while read_runtime_target; do
    printf '%s\n' "$skill_ids" | while IFS= read -r skill_id; do
      [ -n "$skill_id" ] || continue
      printf '%s|%s|%s\n' "$RT_TARGET_NAME" "$skill_id" "$(format_skill_name "$skill_id")"
    done
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
