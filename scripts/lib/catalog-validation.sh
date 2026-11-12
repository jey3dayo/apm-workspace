# Reports manifest apm dependency entries that are not yet pinned to a
# lockfile commit. A structured mapping entry ("- git: <repo>" with a
# sibling "skills:" list) reports the repo value, never the literal "git:"
# key or the nested skill names under "skills:", and is skipped once it
# already carries a sibling "ref:" key (pinned).
unpinned_external_references() {
  manifest_path="$WORKSPACE_DIR/apm.yml"
  [ -f "$manifest_path" ] || return 0

  awk -f "$APM_AWK_DIR/manifest-unpinned-refs.awk" "$manifest_path"
}

# A deploy installs from apm.lock.yaml records, so a hand-bumped SHA pin
# in apm.yml that the lock does not carry deploys the old commit with exit 0.
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

validate_dependency_holds() {
  manifest_path="$WORKSPACE_DIR/apm.yml"
  holds_path="$WORKSPACE_DIR/docs/dependency-holds.txt"
  [ -f "$manifest_path" ] && [ -f "$holds_path" ] || return 0

  pins=$(awk -f "$APM_AWK_DIR/manifest-ref-normalize.awk" -f "$APM_AWK_DIR/manifest-sha-pins.awk" "$manifest_path")
  violations=$({
    printf '%s\n' "$pins"
    printf '@@\n'
    cat "$holds_path"
  } | awk -f "$APM_AWK_DIR/dependency-holds-check.awk")
  [ -n "$violations" ] || return 0

  while IFS='|' read -r held_repo held_sha actual_sha held_reason; do
    error "held dependency $held_repo: apm.yml pins $actual_sha, expected $held_sha ($held_reason)"
  done <<EOF
$violations
EOF
  fail "apm.yml does not match docs/dependency-holds.txt; to release a hold, delete its line in the same PR and record the decision in docs/package-decisions.md."
}

cmd_validate() {
  ensure_workspace_repo
  ensure_workspace_scaffold
  validate_dependency_holds
  validate_manifest_sha_pins
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
  workspace_log "Catalog validation passed ($source_skill_count skills, $source_agent_count agents, $source_command_count commands, $source_rule_count rules, $claude_rule_count claude-rules)"
}
