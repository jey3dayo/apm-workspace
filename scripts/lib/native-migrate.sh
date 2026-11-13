migrate_rollback_command() {
  local home="$1" real_home="$2" stamp="$3"
  printf 'bash %q migrate-rollback ' "$SCRIPT_DIR/native.sh"
  if [ "$real_home" = 1 ]; then printf '%q ' --real-home; else printf '%q %q ' --home "$home"; fi
  printf '%q %q' --stamp "$stamp"
}

assert_not_checkout() {
  local home="$1" repo
  if [ -e "$home/.apm/.git" ] || [ -L "$home/.apm/.git" ] || [ -e "$home/.apm/catalog" ] || [ -L "$home/.apm/catalog" ]; then
    fail "$home/.apm is an authoring checkout (.git or catalog/), and apm writes its manifest and lock there. Move the checkout out of $home/.apm first (docs/native-distribution.md)."
  fi
  repo="$(physical_path "$REPO_ROOT")"
  case "$repo/" in
    "$(physical_path "$home/.apm")/"*) fail "this repository ($repo) is inside $home/.apm, the directory migrate writes" ;;
  esac
}

result_has() {
  grep -qxF "$2" "$1/result.txt"
}

# "<root>/<entry>" for each entry the previous native lock deployed that the roots of $1 lack now.
dropped_entries() {
  local home="$1" stamp="$2" deployed root name
  deployed="$(migrate_deployed_record "$home" "$stamp")"
  [ -f "$deployed" ] || return 0
  while IFS=$'\t' read -r root name; do
    [ -n "$root" ] || continue
    if [ ! -e "$home/$root/$name" ] && [ ! -L "$home/$root/$name" ]; then printf '%s/%s\n' "$root" "$name"; fi
  done <"$deployed"
}

# The two facts of the real HOME that decide what a rehearsal means: whether a previous native lock exists, and what
# ~/.apm is. A rehearsal taken in another state is not accepted by migrate.
home_state_lines() {
  local home="$1" apm_state=absent
  if [ -e "$home/.apm/.git" ] || [ -d "$home/.apm/catalog" ]; then
    apm_state=checkout
  elif [ -e "$home/.apm" ] || [ -L "$home/.apm" ]; then
    apm_state=consumer
  fi
  if [ -f "$home/.apm/apm.lock.yaml" ]; then printf 'previous_lock=present\n'; else printf 'previous_lock=absent\n'; fi
  printf 'home_apm=%s\n' "$apm_state"
}

assert_migrate_rehearsal() {
  local home="$1" sha="$2" dir="$3" want
  [ -f "$dir/result.txt" ] || fail "--rehearsal $dir has no result.txt; run rehearse --migrate and pass its rehearsal-<UTC> directory"
  for want in mode=migrate "home=$home" "source_ref=$sha" "workspace_only=$WORKSPACE_ONLY" install_status=0 compile_status=0 \
    reinstate_status=0 agmsg_status=0 lost=0 baseline_skips=0; do
    result_has "$dir" "$want" || fail "the rehearsal $dir does not show $want; run rehearse --migrate again for this HOME, --source-ref and --workspace-only until it is clean"
  done
  for want in $(home_state_lines "$home"); do
    result_has "$dir" "$want" || fail "the rehearsal $dir was taken when the HOME was in another state (it does not show $want); take a backup and run rehearse --migrate again now"
  done
  [ -f "$dir/dropped.txt" ] || fail "the rehearsal $dir has no dropped.txt; run rehearse --migrate again"
  [ -f "$dir/skipped.txt" ] && [ ! -L "$dir/skipped.txt" ] || fail "the rehearsal $dir has no plain skipped.txt; run rehearse --migrate again"
  [ -f "$dir/auto-approved-skips.txt" ] && [ ! -L "$dir/auto-approved-skips.txt" ] || fail "the rehearsal $dir has no plain auto-approved-skips.txt; run rehearse --migrate again"
  [ -f "$dir/pristine-entries.txt" ] && [ ! -L "$dir/pristine-entries.txt" ] || fail "the rehearsal $dir has no plain pristine-entries.txt; run rehearse --migrate again"
}

# The entries migrate drops must be the ones the rehearsal dropped, because the rehearsal is what allowed them. The rollback
# that follows a mismatch keeps every file.
assert_dropped_as_rehearsed() {
  local home="$1" stamp="$2" dir="$3" actual
  actual="$home/.apm/native-migrate-$stamp.dropped.txt"
  dropped_entries "$home" "$stamp" >"$actual"
  [ "$(sort "$actual")" = "$(sort "$dir/dropped.txt")" ] ||
    fail "migrate dropped other entries than the rehearsal did (compare $actual with $dir/dropped.txt); the roots are rolled back"
}

assert_skipped_as_rehearsed() {
  local home="$1" stamp="$2" dir="$3" name actual
  for name in skipped auto-approved-skips; do
    actual="$home/.apm/native-migrate-$stamp.$name.txt"
    [ -f "$actual" ] && [ ! -L "$actual" ] || fail "migrate has no plain $name.txt; the roots are rolled back"
    [ "$(LC_ALL=C sort "$actual")" = "$(LC_ALL=C sort "$dir/$name.txt")" ] ||
      fail "migrate replaced different entries than the rehearsal did (compare $actual with $dir/$name.txt); the roots are rolled back"
  done
}

# Copies the files migrate must not change (owner-only, permissions kept) so a change can be undone. Contents are never
# logged. saved.txt lists, one file at a time and only once it is settled, whether the file was there (present, copy
# finished) or not (absent); a restore touches only the files listed, so a failure part way leaves the others alone.
save_untouched() {
  local home="$1" stamp="$2" dir path
  dir="$home/.apm/native-migrate-$stamp.untouched"
  (umask 077 && mkdir -p "$dir") || fail "cannot create $dir"
  : >"$dir/saved.txt"
  for path in $MIGRATE_UNTOUCHED_FILES; do
    if [ -f "$home/$path" ]; then
      (umask 077 && mkdir -p "$(dirname "$dir/$path")") || fail "cannot create $dir/$(dirname "$path")"
      cp -p "$home/$path" "$dir/$path" || fail "cannot copy $home/$path"
      printf 'present\t%s\n' "$path" >>"$dir/saved.txt"
    else
      printf 'absent\t%s\n' "$path" >>"$dir/saved.txt"
    fi
  done
}

changed_untouched_files() {
  local home="$1" stamp="$2" dir kind path
  dir="$home/.apm/native-migrate-$stamp.untouched"
  [ -f "$dir/saved.txt" ] || return 0
  while IFS=$'\t' read -r kind path; do
    [ -n "$path" ] || continue
    if [ "$kind" = present ]; then
      if [ ! -f "$home/$path" ] || [ "$(sha256 <"$home/$path")" != "$(sha256 <"$dir/$path")" ]; then printf '%s\n' "$path"; fi
    elif [ -e "$home/$path" ] || [ -L "$home/$path" ]; then
      printf '%s\n' "$path"
    fi
  done <"$dir/saved.txt"
}

# Puts the saved copy back; the version migrate left stays beside it as <path>.changed-<stamp>. A file that is a working
# link is written through, so the link stays and its target gets the old content.
restore_untouched() {
  local home="$1" stamp="$2" dir path
  dir="$home/.apm/native-migrate-$stamp.untouched"
  [ -f "$dir/saved.txt" ] || return 0
  for path in $(changed_untouched_files "$home" "$stamp"); do
    if [ -L "$home/$path" ] && [ -e "$home/$path" ] && [ -f "$dir/$path" ]; then
      cp -p "$home/$path" "$home/$path.changed-$stamp" || fail "cannot keep $home/$path as $path.changed-$stamp"
      cat "$dir/$path" >"$home/$path" || fail "cannot restore $home/$path"
    else
      if [ -e "$home/$path" ] || [ -L "$home/$path" ]; then
        mv "$home/$path" "$home/$path.changed-$stamp" || fail "cannot move $home/$path aside"
      fi
      if [ -f "$dir/$path" ]; then cp -p "$dir/$path" "$home/$path" || fail "cannot restore $home/$path"; fi
    fi
    log "restored $home/$path; the version migrate left is $home/$path.changed-$stamp"
  done
}

# Fails, and lists them in <HOME>/.apm/native-migrate-<stamp>.lost.txt, when a path of the roots that existed before migrate
# is gone and is not in the allowlist of rehearse. The same check as the rehearsal, made on the HOME migrate wrote.
assert_no_unexpected_loss() {
  local home="$1" stamp="$2" before="$3" dir lost_file
  lost_file="$home/.apm/native-migrate-$stamp.lost.txt"
  dir="$(mktemp -d "$home/.apm/.native-migrate.XXXXXX")" || fail "cannot create a temporary directory in $home/.apm"
  grep -v '^$' <<<"$before" >"$dir/before" || true
  migrate_roots_snapshot "$home" >"$dir/after"
  LC_ALL=C comm -23 "$dir/before" "$dir/after" >"$dir/lost-all"
  allowed_lost_paths "$dir/lost-all" "$home" "$(migrate_deployed_record "$home" "$stamp")" | cut -f1 >"$dir/allowed"
  LC_ALL=C comm -23 "$dir/lost-all" "$dir/allowed" >"$lost_file"
  rm -rf "$dir"
  [ ! -s "$lost_file" ] || fail "these files of the roots existed before migrate and are gone, and are not in the allowlist (listed in $lost_file; they are kept in <root>.bak-$stamp):
$(head -n 20 "$lost_file" | sed 's/^/  /')"
}

migrate_roots_snapshot() {
  rehearsal_snapshot "$1" <(tr ' ' '\n' <<<"$MIGRATE_ROOTS")
}

manifest_is_rendered() {
  case "$(head -n 1 "$1/.apm/apm.yml" 2>/dev/null || true)" in
    "# Rendered by scripts/native.sh"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Runs from the EXIT trap of cmd_migrate once the roots may have moved: undo the move, keep every file, keep the exit status.
# Each step runs in its own subshell so that a fail in one cannot skip the next.
migrate_failure() {
  local status=$?
  trap - EXIT
  log "migrate failed (exit $status)"
  if [ -f "$(migrate_record "$MIGRATE_HOME" "$MIGRATE_STAMP")" ]; then
    log "rolling the roots back"
    (rollback_roots "$MIGRATE_HOME" "$MIGRATE_STAMP") ||
      log "the automatic rollback failed; fix the cause, then run: $(migrate_rollback_command "$MIGRATE_HOME" "$REAL_HOME" "$MIGRATE_STAMP")"
    if [ "$MIGRATE_AGMSG_LINKED" = 1 ]; then
      (agmsg_state "$MIGRATE_HOME" restore) || log "the agmsg links were not restored; run mise run agmsg:state:restore"
    fi
  fi
  if (restore_untouched "$MIGRATE_HOME" "$MIGRATE_STAMP"); then
    rm -rf "${MIGRATE_HOME:?}/.apm/native-migrate-$MIGRATE_STAMP.untouched"
  else
    log "the files $MIGRATE_UNTOUCHED_FILES were not restored; the copies are in $MIGRATE_HOME/.apm/native-migrate-$MIGRATE_STAMP.untouched"
  fi
  if manifest_is_rendered "$MIGRATE_HOME"; then
    log "only the roots were rolled back: $MIGRATE_HOME/.apm/apm.yml is still the rendered manifest, so ~/.apm stays the native consumer. To go back to the checkout state, move the consumer ~/.apm aside and put ~/.apm.checkout-<UTC> back; the old tools are at commit 0bcce09 (docs/native-distribution.md, the section on moving the checkout)"
  fi
  exit "$status"
}

cmd_migrate() {
  parse_options "$@"
  [ -n "$SOURCE_REF" ] || fail "migrate needs --source-ref; deploying never moves a pin on its own"
  [ -n "$REHEARSAL" ] || fail "migrate needs --rehearsal <the rehearsal-<UTC> directory of a clean rehearse --migrate>"
  local home sha edited links manifest roots_before changed rehearsal_dir
  home="$(target_home migrate)"
  sha="$(resolve_source_sha "$SOURCE_REF")"
  assert_not_checkout "$home"
  if ! native_lock_held "$home"; then native_lock_command "$home" migrate "$@"; return; fi
  assert_same_render_mode "$home"
  rehearsal_dir="$(cd "$REHEARSAL" 2>/dev/null && pwd -P || printf '%s' "$REHEARSAL")"
  assert_migrate_rehearsal "$home" "$sha" "$rehearsal_dir"

  assert_default_apm_config "$home"
  assert_no_home_manifest "$home"
  python3 "$SCRIPT_DIR/native-home.py" check-design-rule "$home" "$REPO_ROOT" "$sha"
  edited="$(edited_generated_roots "$home")"
  [ -z "$edited" ] || fail "these roots keep APM's marker but were edited after compile, and apm compile would overwrite them:
$edited
Delete the marker line to keep the file as hand-written, or move it aside, then re-run."
  if [ "$REAL_HOME" = 1 ]; then links="$(real_home_shared_entries "$home")"; else links="$(shared_entries "$home")"; fi
  [ -z "$links" ] || fail "these entries of $home may share their data with files outside it, so writing them would change those files:
$links
Move them aside or make them plain directories and files of this HOME."

  assert_default_agmsg_store "$home"
  [ "$(pristine_entries "$home" | LC_ALL=C sort)" = "$(cat "$rehearsal_dir/pristine-entries.txt")" ] ||
    fail "the entries of the roots that match the previous lock changed since the rehearsal ($rehearsal_dir/pristine-entries.txt); nothing was changed. Take a backup and run rehearse --migrate again"
  manifest="$(render_manifest "$sha" "$WORKSPACE_ONLY")"
  roots_before="$(migrate_roots_snapshot "$home")"
  MIGRATE_HOME="$home" MIGRATE_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
  claim_migrate_record "$home" "$MIGRATE_STAMP"
  log "native-migrate stamp: $MIGRATE_STAMP"
  MIGRATE_AGMSG_LINKED=0
  if [ -L "$home/.agents/skills/agmsg/db" ]; then
    MIGRATE_AGMSG_LINKED=1
    agmsg_state "$home" save
  fi

  trap migrate_failure EXIT
  save_untouched "$home" "$MIGRATE_STAMP"
  install_manifest "$home" "$manifest"
  migrate_roots "$home" "$MIGRATE_STAMP"
  run_apm_install "$home"
  run_apm "$home" compile -g --clean
  reinstate_entries "$home" "$MIGRATE_STAMP" "$home/.apm/native-migrate-$MIGRATE_STAMP." "$rehearsal_dir/pristine-entries.txt"
  if [ "$MIGRATE_AGMSG_LINKED" = 1 ]; then agmsg_state "$home" restore; fi
  assert_dropped_as_rehearsed "$home" "$MIGRATE_STAMP" "$rehearsal_dir"
  assert_skipped_as_rehearsed "$home" "$MIGRATE_STAMP" "$rehearsal_dir"
  assert_no_unexpected_loss "$home" "$MIGRATE_STAMP" "$roots_before"
  changed="$(changed_untouched_files "$home" "$MIGRATE_STAMP")"
  [ -z "$changed" ] || fail "migrate changed these files, which it must leave alone (they are put back, and the changed versions kept as <file>.changed-$MIGRATE_STAMP): $(tr '\n' ' ' <<<"$changed")"
  rm -rf "${home:?}/.apm/native-migrate-$MIGRATE_STAMP.untouched"
  trap - EXIT

  log "migrated $home; the previous roots are kept as <root>.bak-$MIGRATE_STAMP (record: $(migrate_record "$home" "$MIGRATE_STAMP"))"
  log "to undo: $(migrate_rollback_command "$home" "$REAL_HOME" "$MIGRATE_STAMP")"
  printf '%s\n' "$MIGRATE_STAMP"
}

cmd_migrate_rollback() {
  parse_options "$@"
  [ -n "$STAMP" ] || fail "migrate-rollback needs --stamp <UTC stamp of the migrate>"
  assert_stamp "$STAMP"
  local home
  home="$(target_home migrate-rollback)"
  if ! native_lock_held "$home"; then native_lock_command "$home" migrate-rollback "$@"; return; fi
  rollback_roots "$home" "$STAMP"
  restore_agmsg_links "$home"
  log "rolled $home back to the roots of $STAMP; the roots native wrote are kept as <root>.native-$STAMP"
}
