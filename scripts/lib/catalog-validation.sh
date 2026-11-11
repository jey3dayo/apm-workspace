#!/usr/bin/env bash
# catalog 検証関連の関数
# catalog の構造検証、skill ID 検証、manifest 検証などを扱う

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

skill_path_from_root() {
  SKILL_PATH_ROOT="$1"
  skill_id="$2"
  validate_skill_id "$skill_id"
  old_ifs=$IFS
  IFS=':'
  # shellcheck disable=SC2086
  set -- $skill_id
  IFS=$old_ifs
  validate_skill_path_segments "$skill_id" "$@"

  SKILL_PATH="$SKILL_PATH_ROOT"
  for segment in "$@"; do
    SKILL_PATH="$SKILL_PATH/$segment"
  done
}

skill_id_to_manifest_path() {
  skill_path_from_root "" "$1"
  printf '%s\n' "${SKILL_PATH#/}"
}

catalog_build_dir() {
  printf '%s/%s\n' "$CATALOG_BUILD_ROOT" "$CATALOG_DIR_NAME"
}

catalog_build_skills_root() {
  printf '%s/.apm/skills\n' "$(catalog_build_dir)"
}

catalog_build_agents_root() {
  printf '%s/.apm/agents\n' "$(catalog_build_dir)"
}

catalog_build_commands_root() {
  printf '%s/commands\n' "$(catalog_build_dir)"
}

catalog_build_rules_root() {
  printf '%s/rules\n' "$(catalog_build_dir)"
}

catalog_build_claude_rules_root() {
  printf '%s/claude/rules\n' "$(catalog_build_dir)"
}

catalog_build_instructions_path() {
  printf '%s/.apm/instructions/%s\n' "$(catalog_build_dir)" "$CATALOG_INSTRUCTIONS_FILE_NAME"
}

tracked_catalog_dir() {
  printf '%s/%s\n' "$WORKSPACE_DIR" "$CATALOG_DIR_NAME"
}

tracked_catalog_skills_root() {
  printf '%s/.apm/skills\n' "$(tracked_catalog_dir)"
}

tracked_catalog_agents_root() {
  printf '%s/.apm/agents\n' "$(tracked_catalog_dir)"
}

tracked_catalog_commands_root() {
  printf '%s/commands\n' "$(tracked_catalog_dir)"
}

tracked_catalog_rules_root() {
  printf '%s/rules\n' "$(tracked_catalog_dir)"
}

tracked_catalog_claude_rules_root() {
  printf '%s/claude/rules\n' "$(tracked_catalog_dir)"
}

tracked_catalog_instructions_path() {
  printf '%s/.apm/instructions/%s\n' "$(tracked_catalog_dir)" "$CATALOG_INSTRUCTIONS_FILE_NAME"
}

catalog_instructions_body() {
  awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter { if ($0 == "---") in_frontmatter = 0; next }
    !started && $0 == "" { next }
    { started = 1; print }
  ' "$1"
}

write_catalog_instructions_body() {
  destination_path="$1"
  body_path=$(mktemp "${TMPDIR:-/tmp}/apm-instructions-body.XXXXXX")
  catalog_instructions_body "$(tracked_catalog_instructions_path)" >"$body_path"
  copy_managed_catalog_file "$body_path" "$destination_path"
  rm -f "$body_path"
}

legacy_catalog_instructions_blobs() {
  instructions_relative_path="$CATALOG_DIR_NAME/.apm/instructions/$CATALOG_INSTRUCTIONS_FILE_NAME"
  version_body=$(mktemp "${TMPDIR:-/tmp}/apm-instructions-version.XXXXXX")
  {
    catalog_instructions_body "$(tracked_catalog_instructions_path)" | git hash-object --stdin
    { git -C "$WORKSPACE_DIR" log --all --format= --raw --no-abbrev -- "$CATALOG_DIR_NAME/AGENTS.md" 2>/dev/null || true; } |
      awk 'NF >= 4 && $4 !~ /^0+$/ { print $4 }'
    { git -C "$WORKSPACE_DIR" log --all --format= --raw --no-abbrev -- "$instructions_relative_path" 2>/dev/null || true; } |
      awk 'NF >= 4 && $4 !~ /^0+$/ { print $4 }' | sort -u |
      while IFS= read -r instruction_blob; do
        git -C "$WORKSPACE_DIR" cat-file blob "$instruction_blob" >"$version_body" 2>/dev/null || continue
        catalog_instructions_body "$version_body" | git hash-object --stdin
      done
  } | sort -u
  rm -f "$version_body"
}

is_legacy_catalog_instructions_copy() {
  candidate_path="$1"
  known_blobs="$2"
  candidate_blob=$(git hash-object --no-filters -- "$candidate_path") || return 1
  grep -qxF -- "$candidate_blob" <<<"$known_blobs"
}

apm_root_lines() {
  awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1"
}

apm_root_has_marker() {
  LC_ALL=C awk -v marker="$APM_GENERATED_ROOT_MARKER" '
    BEGIN {
      leading_space = "^([\t\n\v\f\r\034\035\036\037 ]|\302[\205\240]|\341\232\200|\342\200[\200-\212\250\251\257]|\342\201\237|\343\200\200)+"
    }
    { sub(/\r$/, ""); gsub(/\r/, "\n"); sub(leading_space, "") }
    $0 != "" { found = index($0, marker) == 1; exit }
    END { exit !found }
  ' "$1"
}

has_valid_apm_build_id() {
  build_id_line='^<!-- Build ID: [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f] -->$'
  recorded_build_id=$(apm_root_lines "$1" | awk -v pattern="$build_id_line" '
    $0 ~ pattern { count++; build_id = substr($0, 16, 12) }
    END { if (count == 1) print build_id }
  ')
  [ -n "$recorded_build_id" ] || return 1
  computed_build_id=$(apm_root_lines "$1" | awk -v pattern="$build_id_line" '
    $0 ~ pattern { next }
    { if (joined++) printf "\n"; printf "%s", $0 }
  ' | file_sha256 - | cut -c1-12)
  [ "$recorded_build_id" = "$computed_build_id" ]
}

user_root_state() {
  root_path="$1"
  known_blobs="$2"
  if [ ! -e "$root_path" ] && [ ! -L "$root_path" ]; then
    printf 'absent\n'
  elif [ -L "$root_path" ] || [ ! -f "$root_path" ]; then
    printf 'not-regular\n'
  elif apm_root_has_marker "$root_path"; then
    if has_valid_apm_build_id "$root_path"; then
      printf 'generated\n'
    else
      printf 'edited-generated\n'
    fi
  elif is_legacy_catalog_instructions_copy "$root_path" "$known_blobs"; then
    printf 'legacy\n'
  else
    printf 'hand-written\n'
  fi
}

catalog_apm_dir_claim_message() {
  apm_dir="$(tracked_catalog_dir)/.apm"
  if [ -L "$apm_dir" ]; then
    printf 'catalog/.apm is a symlink; validate:catalog needs a real directory there. Replace the link with a directory.\n'
    return 0
  fi
  [ -d "$apm_dir" ] || return 0

  if ! non_regular_entries=$(cd "$apm_dir" && find . -mindepth 1 ! -type d ! -type f) ||
    ! regular_files=$(cd "$apm_dir" && find . -mindepth 1 -type f); then
    printf 'catalog/.apm could not be fully read, so validate:catalog cannot tell what it holds. Make every entry under catalog/.apm readable first.\n'
    return 0
  fi
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
        printf 'catalog/.apm holds %s, which the catalog build does not carry: it keeps only files inside a skill directory (one holding SKILL.md), agents named agents/<name>.agent.md and instructions/%s. Move it into a skill, rename the agent, or merge the instruction into instructions/%s.\n' "$claimed_entry" "$CATALOG_INSTRUCTIONS_FILE_NAME" "$CATALOG_INSTRUCTIONS_FILE_NAME"
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
  printf '%s\n' "${1##*:}"
}

locked_external_skill_records() {
  lock_path="$WORKSPACE_DIR/apm.lock.yaml"
  [ -f "$lock_path" ] || fail "Lock file not found: $lock_path"

  awk -f "$APM_AWK_DIR/lockfile-dependencies.awk" "$lock_path"
}

reset_catalog_build_dir() {
  destination_dir=$(catalog_build_dir)
  rm -rf "$destination_dir"
  mkdir -p "$destination_dir"
  mkdir -p "$(catalog_build_skills_root)"
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

managed_skill_content_dir() {
  skill_path_from_root "$(tracked_catalog_skills_root)" "$1"
  source_dir="$SKILL_PATH"

  [ -f "$source_dir/SKILL.md" ] || fail "Managed catalog skill missing SKILL.md: $source_dir"
  printf '%s\n' "$source_dir"
}

copy_managed_skill_into_catalog() {
  skill_id="$1"
  skills_root="$2"
  source_dir=$(managed_skill_content_dir "$skill_id")
  skill_path_from_root "$skills_root" "$skill_id"
  destination_dir="$SKILL_PATH"

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

copy_managed_claude_rule_assets_into_catalog() {
  destination_dir="$1"
  source_dir=$(tracked_catalog_claude_rules_root)
  [ -d "$source_dir" ] || return 0
  mkdir -p "$destination_dir"
  cp -R "$source_dir"/. "$destination_dir"
}

ensure_workspace_mise_file() {
  if [ ! -f "$MISE_DESTINATION" ]; then
    fail "Missing workspace mise.toml: $MISE_DESTINATION"
  fi
}

sync_opencode_instructions() {
  [ -f "$(tracked_catalog_instructions_path)" ] || return 0
  known_blobs=$(legacy_catalog_instructions_blobs)
  opencode_state=$(user_root_state "$OPENCODE_INSTRUCTIONS_OUTPUT" "$known_blobs")
  case "$opencode_state" in
    legacy) write_catalog_instructions_body "$OPENCODE_INSTRUCTIONS_OUTPUT" ;;
    absent)
      claude_state=$(user_root_state "$HOME/.claude/CLAUDE.md" "$known_blobs")
      case "$claude_state" in
        absent | legacy | generated) write_catalog_instructions_body "$OPENCODE_INSTRUCTIONS_OUTPUT" ;;
        *) log "Not writing $OPENCODE_INSTRUCTIONS_OUTPUT: OpenCode falls back to $HOME/.claude/CLAUDE.md ($claude_state), which is not the catalog guide." ;;
      esac
      ;;
    *) warn "Leaving $OPENCODE_INSTRUCTIONS_OUTPUT as is ($opencode_state): it is not a copy of any committed version of the catalog guide, so OpenCode reads it instead of the guide. If it is a copy deployed from an uncommitted guide, move it aside and re-run sync:opencode." ;;
  esac
}

unpinned_external_references() {
  manifest_path="$WORKSPACE_DIR/apm.yml"
  [ -f "$manifest_path" ] || return 0

  awk -f "$APM_AWK_DIR/manifest-unpinned-refs.awk" "$manifest_path"
}

managed_skill_ids() {
  skill_ids_from_root "$(tracked_catalog_skills_root)"
}

requested_catalog_skill_ids() {
  if [ "$#" -gt 0 ]; then
    for skill_id in "$@"; do
      validate_skill_id "$skill_id"
      if ! tracked_catalog_skill_ids | awk -v target="$skill_id" '$0 == target { found = 1; exit } END { exit(found ? 0 : 1) }'; then
        fail "Requested catalog skill is not tracked in catalog/.apm/skills: $skill_id"
      fi
      printf '%s\n' "$skill_id"
    done
    return 0
  fi

  tracked_catalog_skill_ids
}

validate_manifest_sha_pins() {
  manifest_path="$WORKSPACE_DIR/apm.yml"
  lock_path="$WORKSPACE_DIR/apm.lock.yaml"
  [ -f "$manifest_path" ] || return 0

  pins=$(awk -f "$APM_AWK_DIR/manifest-ref-normalize.awk" -f "$APM_AWK_DIR/manifest-sha-pins.awk" "$manifest_path")
  [ -n "$pins" ] || return 0

  if [ ! -f "$lock_path" ]; then
    error "Lock file not found: $lock_path"
    fail "apm.yml SHA pins differ from apm.lock.yaml; update the pinned entries of apm.lock.yaml to the same commits (no task re-resolves the root lock on a native HOME)."
  fi

  unmatched=$({
    locked_external_skill_records
    printf '@@\n'
    printf '%s\n' "$pins"
  } | awk -f "$APM_AWK_DIR/manifest-sha-pins-check.awk")
  unmatched_count=0
  if [ -n "$unmatched" ]; then
    while IFS= read -r unmatched_line; do
      error "apm.yml pin not in apm.lock.yaml: $unmatched_line"
      unmatched_count=$((unmatched_count + 1))
    done <<EOF
$unmatched
EOF
  fi

  if [ "$unmatched_count" -gt 0 ]; then
    fail "apm.yml SHA pins differ from apm.lock.yaml; update the pinned entries of apm.lock.yaml to the same commits (no task re-resolves the root lock on a native HOME)."
  fi
}

cmd_validate() {
  require_apm
  ensure_workspace_repo
  ensure_workspace_scaffold
  (
    cd "$WORKSPACE_DIR"
    apm compile --validate
  )
  validate_manifest_sha_pins
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

managed_catalog_runtime_targets() {
  cat <<'EOF'
claude|.claude|CLAUDE.md||apm
codex|.codex|AGENTS.md|.agents|-
cursor|.cursor|AGENTS.md||apm
opencode|.config/opencode|-|-|-
EOF
}

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

cmd_validate_catalog() {
  ensure_workspace_repo
  ensure_workspace_scaffold

  has_failure=0
  source_skill_ids=$(tracked_catalog_skill_ids)
  source_agent_paths=$(managed_agent_relative_paths)
  source_command_paths=$(managed_command_relative_paths)
  source_rule_paths=$(managed_rule_relative_paths)
  tracked_manifest="$(tracked_catalog_dir)/apm.yml"
  tracked_readme="$(tracked_catalog_dir)/README.md"
  tracked_instructions="$(tracked_catalog_instructions_path)"

  if [ ! -f "$tracked_manifest" ]; then
    error "Tracked catalog manifest is missing: $tracked_manifest"
    has_failure=1
  fi

  if [ ! -f "$tracked_readme" ]; then
    error "Tracked catalog README is missing: $tracked_readme"
    has_failure=1
  fi

  if ! manifest_has_catalog_reference; then
    error "Global apm.yml is missing the managed catalog ref"
    has_failure=1
  fi


  if [ ! -f "$tracked_instructions" ]; then
    error "Tracked catalog is missing instructions: $tracked_instructions"
    has_failure=1
  else
    if ! awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { exit } NR > 1 && /^description:[[:space:]]*[^[:space:]]/ { found = 1 } END { exit !found }' "$tracked_instructions"; then
      error "Catalog instructions need YAML frontmatter with a description: $tracked_instructions"
      has_failure=1
    fi
    if [ -z "$(catalog_instructions_body "$tracked_instructions" | awk 'NF { print; exit }')" ]; then
      error "Catalog instructions have no body: $tracked_instructions"
      has_failure=1
    fi
  fi

  if [ -e "$(tracked_catalog_dir)/AGENTS.md" ] || [ -L "$(tracked_catalog_dir)/AGENTS.md" ]; then
    error "catalog/AGENTS.md is no longer deployed; edit $tracked_instructions instead"
    has_failure=1
  fi

  instruction_rule_name="${CATALOG_INSTRUCTIONS_FILE_NAME%.instructions.md}.md"
  for rules_root in "$(tracked_catalog_rules_root)" "$(tracked_catalog_claude_rules_root)"; do
    if [ -e "$rules_root/$instruction_rule_name" ]; then
      error "Catalog rule collides with the Claude rule APM writes for the catalog instructions: $rules_root/$instruction_rule_name"
      has_failure=1
    fi
  done

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

  apm_dir_claim_message=$(catalog_apm_dir_claim_message)
  if [ -n "$apm_dir_claim_message" ]; then
    error "$apm_dir_claim_message"
    has_failure=1
  fi

  claude_rules_root=$(tracked_catalog_claude_rules_root)
  if [ -d "$claude_rules_root" ]; then
    claude_rule_names=$(relative_file_list "$claude_rules_root" | awk -F/ '{ print $NF }' | awk 'NF')
    regular_rule_names=$(relative_file_list "$(tracked_catalog_rules_root)" | awk -F/ '{ print $NF }' | awk 'NF' | sort)
    claude_rule_collisions=$(printf '%s\n' "$claude_rule_names" | while IFS= read -r claude_rule_name; do
      [ -n "$claude_rule_name" ] || continue
      if printf '%s\n' "$regular_rule_names" | grep -qxF -- "$claude_rule_name"; then
        printf '%s\n' "$claude_rule_name"
      fi
    done)
    if [ -n "$claude_rule_collisions" ]; then
      printf '%s\n' "$claude_rule_collisions" | while IFS= read -r claude_rule_name; do
        [ -n "$claude_rule_name" ] || continue
        error "Claude rules file name collides with catalog rules: $claude_rule_name"
      done
      has_failure=1
    fi
    claude_rule_count=$(printf '%s\n' "$claude_rule_names" | awk 'NF { count++ } END { print count + 0 }')
  else
    claude_rule_count=0
  fi

  [ "$has_failure" -eq 0 ] || fail "Catalog validation failed"
  source_skill_count=$(printf '%s\n' "$source_skill_ids" | awk 'NF { count++ } END { print count + 0 }')
  source_agent_count=$(printf '%s\n' "$source_agent_paths" | awk 'NF { count++ } END { print count + 0 }')
  source_command_count=$(printf '%s\n' "$source_command_paths" | awk 'NF { count++ } END { print count + 0 }')
  source_rule_count=$(printf '%s\n' "$source_rule_paths" | awk 'NF { count++ } END { print count + 0 }')
  log "Catalog validation passed ($source_skill_count skills, $source_agent_count agents, $source_command_count commands, $source_rule_count rules, $claude_rule_count claude-rules)"
}
