# agmsg-state.sh restores the links under the default store (it runs without XDG_STATE_HOME), so a db or teams link that
# points anywhere else would be repointed at an empty default store, leaving the history behind.
assert_default_agmsg_store() {
  local home="$1" name target
  for name in db teams; do
    [ -L "$home/.agents/skills/agmsg/$name" ] || continue
    target="$(readlink "$home/.agents/skills/agmsg/$name")"
    [ "$target" = "$home/.local/state/agmsg/$name" ] ||
      fail "$home/.agents/skills/agmsg/$name points at $target, not at $home/.local/state/agmsg/$name, the only store agmsg-state.sh relinks to. Nothing was changed; move the data to the default store (or relink it) first."
  done
}

# The previous rendered manifest records whether it was rendered with --workspace-only; the previous lock lists packages
# only a full render deploys, so a change of mode would make every external package look dropped.
assert_same_render_mode() {
  local home="$1" previous
  [ -f "$home/.apm/apm.yml" ] || return 0
  previous="$(sed -n 's/^# native-render: workspace_only=\([01]\)$/\1/p' "$home/.apm/apm.yml" | head -n 1)"
  [ -z "$previous" ] || [ "$previous" = "$WORKSPACE_ONLY" ] ||
    fail "the previous manifest of $home was rendered with workspace_only=$previous, this run uses workspace_only=$WORKSPACE_ONLY; the previous lock would make every external package look dropped. Use the same mode."
}

# The links of the migrated roots that migrate would refuse: broken, or leading outside the HOME (escaping_link_line).
root_escaping_links() {
  local home="$1" root link
  for root in $MIGRATE_ROOTS; do
    [ -e "$home/$root" ] || [ -L "$home/$root" ] || continue
    find "$home/$root" -type l | LC_ALL=C sort | while IFS= read -r link; do
      escaping_link_line "$home" "$link"
    done
  done
}

agmsg_state() {
  env -u XDG_STATE_HOME HOME="$1" bash "$REPO_ROOT/scripts/agmsg-state.sh" "$2" >&2
}

assert_stamp() {
  [[ "$1" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || fail "--stamp must be a UTC stamp such as 20261109T120000Z"
}

migrate_record() {
  printf '%s/.apm/native-migrate-%s.txt\n' "$1" "$2"
}

# Creates the record exclusively (noclobber), so only the run that owns a stamp may move roots or roll them back; a second
# run that drew the same stamp stops here, before it sets the failure trap.
claim_migrate_record() {
  local home="$1" stamp="$2" record
  record="$(migrate_record "$home" "$stamp")"
  mkdir -p "$home/.apm"
  (set -o noclobber && : >"$record") 2>/dev/null || fail "$record already exists: another migrate drew the same stamp. Nothing was changed; run again."
}

migrate_deployed_record() {
  printf '%s/.apm/native-migrate-%s.deployed.txt\n' "$1" "$2"
}

migrate_previous_lock() {
  printf '%s/.apm/native-migrate-%s.previous-lock.yaml\n' "$1" "$2"
}

# "<root><TAB><top-level entry>" for each entry of MIGRATE_ROOTS that the previous apm.lock.yaml of this HOME lists in a
# deployed_files list (the lock a native deployment left; there is none before the first migrate).
previous_deployed_entries() {
  local lock="$1/.apm/apm.lock.yaml"
  [ -f "$lock" ] || return 0
  awk -v roots="$MIGRATE_ROOTS" '
    BEGIN { n = split(roots, root, " ") }
    /^[[:space:]]*- / {
      line = $0
      sub(/^[[:space:]]*- /, "", line)
      gsub(/["\047]/, "", line)
      for (i = 1; i <= n; i++) {
        prefix = root[i] "/"
        if (index(line, prefix) != 1) continue
        rest = substr(line, length(prefix) + 1)
        sub(/\/.*/, "", rest)
        if (rest != "") print root[i] "\t" rest
      }
    }
  ' "$lock" | LC_ALL=C sort -u
}

# Moves each of MIGRATE_ROOTS to <root>.bak-<stamp> and records what it did in <HOME>/.apm/native-migrate-<stamp>.txt
# (claimed by claim_migrate_record first)
# (a "moved" line is written before the move and a "done" line after it, so a root without "done" may not have moved;
# rollback adds "restored" per root, so it can resume).
# Nothing is deleted. A root that does not exist is recorded as absent; a backup name already taken fails before any move.
migrate_roots() {
  local home="$1" stamp="$2" root record
  record="$(migrate_record "$home" "$stamp")"
  { [ -f "$record" ] && [ ! -s "$record" ]; } || fail "$record was not claimed (claim_migrate_record). Nothing was moved."
  for root in $MIGRATE_ROOTS; do
    if [ -e "$home/$root.bak-$stamp" ] || [ -L "$home/$root.bak-$stamp" ]; then
      fail "$home/$root.bak-$stamp already exists. Nothing was moved."
    fi
  done
  mkdir -p "$home/.apm"
  previous_deployed_entries "$home" >"$(migrate_deployed_record "$home" "$stamp")"
  if [ -f "$home/.apm/apm.lock.yaml" ] && [ ! -L "$home/.apm/apm.lock.yaml" ]; then
    cp -p "$home/.apm/apm.lock.yaml" "$(migrate_previous_lock "$home" "$stamp")" || fail "cannot copy the previous apm.lock.yaml"
  fi
  for root in $MIGRATE_ROOTS; do
    if [ -e "$home/$root" ] || [ -L "$home/$root" ]; then
      printf 'moved\t%s\n' "$root" >>"$record"
      mv "$home/$root" "$home/$root.bak-$stamp" || fail "cannot move $home/$root aside"
      printf 'done\t%s\n' "$root" >>"$record"
      log "moved $home/$root to $home/$root.bak-$stamp"
    else
      printf 'absent\t%s\n' "$root" >>"$record"
      log "$home/$root does not exist; nothing to move"
    fi
  done
}

# inside: the link stays a link (it points into the root); outside: its content is copied; broken: reinstate fails.
link_scope() {
  local home="$1" root="$2" bak="$3" entry="$4" target rest resolved bakp
  target="$(readlink "$entry")"
  case "$target" in
    "$home/$root")
      echo inside
      return
      ;;
    "$home/$root/"*)
      rest="${target#"$home/$root/"}"
      if [ -e "$bak/$rest" ] || [ -e "$home/$root/$rest" ]; then echo inside; else echo broken; fi
      return
      ;;
  esac
  if [ ! -e "$entry" ] || ! resolved="$(realpath "$entry" 2>/dev/null)"; then
    echo broken
    return
  fi
  bakp="$(cd "$bak" && pwd -P)"
  case "$resolved/" in
    "$bakp/"*) echo inside ;;
    *) echo outside ;;
  esac
}

# Links among the directories reinstate writes into and copies from (the roots, their .bak-<stamp>, the tool directories
# above them and .apm, where the reports go) that leave the HOME or are broken: a copy through one would write outside it.
reinstate_escaping_links() {
  local home="$1" stamp="$2" root path
  for path in .agents .claude .cursor .apm; do
    if [ -L "$home/$path" ]; then escaping_link_line "$home" "$home/$path"; fi
  done
  for root in $MIGRATE_ROOTS; do
    for path in "$root" "$root.bak-$stamp"; do
      if [ -L "$home/$path" ]; then escaping_link_line "$home" "$home/$path"; fi
    done
  done
}

# True when the old entry differs in more than runtime state: agmsg's run/ db teams (agmsg-state.sh restores the links
# after this step) and the synced-skill cache that a running Claude Code recreates during migrate.
reinstate_differs() {
  case "$3" in
    .claude/skills/synced) return 1 ;;
    .agents/skills/agmsg) ! diff -rq -x .apm-pin -x run -x db -x teams "$1" "$2" >/dev/null 2>&1 ;;
    *) ! diff -rq -x .apm-pin "$1" "$2" >/dev/null 2>&1 ;;
  esac
}

# "<sha256>  <entry>/<path inside it>" for each deployed_file_hashes record of the lock under <root>/<entry> (a single-file
# entry is its own record). A record with a quoted key is not read, so it shows up as a mismatch.
lock_entry_hashes() {
  awk -v root="$2" -v name="$3" '
    BEGIN { exact = root "/" name }
    /^[^ ]/ { mode = ""; next }
    /^  [A-Za-z_]+:/ { mode = ($0 == "  deployed_file_hashes:") ? "hashes" : ""; next }
    mode == "hashes" && /^    [^ ]/ {
      record = substr($0, 5)
      split_at = index(record, ": sha256:")
      if (!split_at) next
      path = substr(record, 1, split_at - 1)
      if (path != exact && index(path, exact "/") != 1) next
      if (index(path, "/__pycache__/") || path ~ /\/\.apm-pin$/) next
      printf "%s  %s\n", substr(record, split_at + 9), substr(path, length(root) + 2)
    }
  ' "$1" | LC_ALL=C sort
}

entry_file_hashes() {
  local hasher=(shasum -a 256)
  if command -v sha256sum >/dev/null 2>&1; then hasher=(sha256sum); fi
  (cd "$1" && find "$2" -type f -not -path '*/__pycache__/*' -not -name .apm-pin -print0 | xargs -0 -r "${hasher[@]}") | LC_ALL=C sort
}

# True when the old entry is what apm itself deployed: every file hashes as the previous lock recorded it, and the lock
# records no other file. Replacing it loses nothing (it stays in <root>.bak-<stamp>); a link, an unlisted file or a
# changed byte leaves it to --allow-skip.
previous_lock_matches() {
  local home="$1" stamp="$2" root="$3" name="$4" lock expected actual
  lock="$(migrate_previous_lock "$home" "$stamp")"
  [ -f "$lock" ] && [ ! -L "$lock" ] || return 1
  [ -z "$(find "$home/$root.bak-$stamp/$name" ! -type f ! -type d -print -quit)" ] || return 1
  expected="$(lock_entry_hashes "$lock" "$root" "$name")"
  [ -n "$expected" ] || return 1
  actual="$(entry_file_hashes "$home/$root.bak-$stamp" "$name")" || return 1
  [ "$expected" = "$actual" ]
}

# Puts back the top-level entries of each <root>.bak-<stamp> that the root lacks now (apm did not deploy them), except
# the entries the previous native lock listed as deployed (native-migrate-<stamp>.deployed.txt): those were not deployed this
# time. An entry that exists is left alone; one whose content differs from the old entry is listed in <report>skipped.txt, or in <report>auto-approved-skips.txt when previous_lock_matches. A link that leaves its root is
# copied, so nothing in the HOME depends on the place it pointed at; a broken link fails the whole step before anything
# is copied. <report>reinstated.txt lists what was put back.
reinstate_entries() {
  local home="$1" stamp="$2" report="${3:-}" root bak entry name scope found=0 broken="" plan="" escaping deployed skipped="" approved=""
  deployed="$(migrate_deployed_record "$home" "$stamp")"
  escaping="$(reinstate_escaping_links "$home" "$stamp")"
  [ -z "$escaping" ] || fail "these links of $home lead outside it or are broken, so copying into the roots would write outside the HOME; nothing was copied:
$escaping"
  for root in $MIGRATE_ROOTS; do
    bak="$home/$root.bak-$stamp"
    if [ ! -e "$bak" ] && [ ! -L "$bak" ]; then continue; fi
    found=1
    while IFS= read -r -d '' entry; do
      name="$(basename "$entry")"
      if [ -e "$home/$root/$name" ] || [ -L "$home/$root/$name" ]; then
        if reinstate_differs "$entry" "$home/$root/$name" "$root/$name"; then
          if previous_lock_matches "$home" "$stamp" "$root" "$name"; then
            approved="$approved$root/$name"$'\n'
          else
            skipped="$skipped$root/$name"$'\n'
          fi
        fi
        continue
      fi
      if [ -f "$deployed" ] && grep -qxF "$root"$'\t'"$name" "$deployed"; then continue; fi
      scope=plain
      if [ -L "$entry" ]; then scope="$(link_scope "$home" "$root" "$bak" "$entry")"; fi
      if [ "$scope" = broken ]; then
        broken="$broken  $entry -> $(readlink "$entry")"$'\n'
      else
        plan="$plan$root"$'\t'"$name"$'\t'"$scope"$'\n'
      fi
    done < <(find -H "$bak" -mindepth 1 -maxdepth 1 -print0)
  done
  [ "$found" = 1 ] || fail "no <root>.bak-$stamp of $MIGRATE_ROOTS exists in $home"
  [ -z "$broken" ] || fail "these entries are broken links, so they cannot be put back; nothing was copied:
$broken"
  if [ -n "$report" ]; then
    mkdir -p "$(dirname "${report}x")" || fail "cannot create the directory of ${report}"
    printf '%s' "$skipped" >"${report}skipped.txt"
    printf '%s' "$approved" >"${report}auto-approved-skips.txt"
    : >"${report}reinstated.txt"
    [ -z "$skipped" ] || log "warning: the entries of the old roots listed in ${report}skipped.txt share a name with what apm deployed, so they were not put back although their content differs from the old entry; if one is a private override of a catalog skill, put it back by hand"
  fi
  while IFS=$'\t' read -r root name scope; do
    [ -n "$root" ] || continue
    mkdir -p "$home/$root" || fail "cannot create $home/$root"
    bak="$home/$root.bak-$stamp"
    if [ "$scope" = outside ]; then
      cp -cpRL "$bak/$name" "$home/$root/$name" 2>/dev/null || {
        rm -rf "${home:?}/$root/$name"
        cp -pRL "$bak/$name" "$home/$root/$name" || fail "cannot copy $bak/$name"
      }
    else
      clone_copy "$bak/$name" "$home/$root/$name" || fail "cannot copy $bak/$name"
    fi
    log "reinstated $root/$name ($scope)"
    if [ -n "$report" ]; then printf '%s/%s\t%s\n' "$root" "$name" "$scope" >>"${report}reinstated.txt"; fi
  done <<<"$plan"
}

record_has() {
  grep -qxF "$1"$'\t'"$2" "$3"
}

# The state a rollback leaves when it stops between moving the backup back and writing "restored": the backup is gone, the
# root exists, and the root native wrote is kept beside it. A backup deleted by hand leaves no <root>.native-<stamp>.
restored_but_unrecorded() {
  { [ -e "$1" ] || [ -L "$1" ]; } && { [ -e "$1.native-$2" ] || [ -L "$1.native-$2" ]; }
}

# Moves the current roots to <root>.native-<stamp> and each <root>.bak-<stamp> back, and records "restored" per root, so a
# run that stopped part way is finished by running it again. Nothing is deleted, and a name already taken fails before any
# move. A root whose move never finished (no "done", no backup) is left as it is; a backup that is gone after "done"
# (deleted by hand) fails before any move.
rollback_roots() {
  local home="$1" stamp="$2" record kind root current lines
  record="$(migrate_record "$home" "$stamp")"
  [ -f "$record" ] || fail "$record does not exist; nothing to roll back"
  lines="$(cat "$record")"
  while IFS=$'\t' read -r kind root; do
    [ -n "$kind" ] || continue
    current="$home/$root"
    case "$kind" in
      moved)
        record_has restored "$root" "$record" && continue
        if [ ! -e "$current.bak-$stamp" ] && [ ! -L "$current.bak-$stamp" ] && record_has "done" "$root" "$record"; then
          restored_but_unrecorded "$current" "$stamp" && continue
          fail "$current.bak-$stamp is missing. Nothing was changed."
        fi
        ;;
      absent) record_has restored "$root" "$record" && continue ;;
      done | restored) continue ;;
      *) fail "$record holds an unknown line: $kind $root" ;;
    esac
    if { [ -e "$current" ] || [ -L "$current" ]; } && { [ -e "$current.native-$stamp" ] || [ -L "$current.native-$stamp" ]; }; then
      fail "$current.native-$stamp already exists. Nothing was changed."
    fi
  done <<<"$lines"
  while IFS=$'\t' read -r kind root; do
    case "$kind" in moved | absent) ;; *) continue ;; esac
    current="$home/$root"
    record_has restored "$root" "$record" && continue
    if [ "$kind" = moved ] && [ ! -e "$current.bak-$stamp" ] && [ ! -L "$current.bak-$stamp" ] && record_has "done" "$root" "$record" && restored_but_unrecorded "$current" "$stamp"; then
      log "$current is already back in place (a rollback stopped before it wrote the line); recording it"
      printf 'restored\t%s\n' "$root" >>"$record"
      continue
    fi
    if [ "$kind" = moved ] && [ ! -e "$current.bak-$stamp" ] && [ ! -L "$current.bak-$stamp" ]; then
      log "$current was never moved aside (the migrate stopped first); left as it is"
      continue
    fi
    if [ -e "$current" ] || [ -L "$current" ]; then
      mv "$current" "$current.native-$stamp" || fail "cannot move $current aside"
      log "moved $current to $current.native-$stamp"
    fi
    if [ "$kind" = moved ]; then
      mv "$current.bak-$stamp" "$current" || fail "cannot move $current.bak-$stamp back"
      log "moved $current.bak-$stamp back to $current"
    fi
    printf 'restored\t%s\n' "$root" >>"$record"
  done <<<"$lines"
}

restore_agmsg_links() {
  local home="$1"
  if [ -L "$home/.agents/skills/agmsg/db" ] || [ -L "$home/.agents/skills/agmsg/teams" ]; then
    agmsg_state "$home" restore
  fi
}

# The reason a lost path (relative to HOME) is no loss, or nothing. Every entry is a full path under one of MIGRATE_ROOTS,
# except the .apm-pin basename rule and the entries dropped from the catalog; docs/native-distribution.md lists them.
# Anything else counts as lost. $2 is the HOME the roots are read in, $3 the deployed record of migrate_roots.
allowed_lost_reason() {
  local path="$1" home="$2" deployed="$3" root rest name
  for root in $MIGRATE_ROOTS; do
    case "$path" in
      "$root/"*)
        rest="${path#"$root/"}"
        name="${rest%%/*}"
        if [ -f "$deployed" ] && [ ! -e "$home/$root/$name" ] && [ ! -L "$home/$root/$name" ] &&
          grep -qxF "$root"$'\t'"$name" "$deployed"; then
          echo "deployed by the previous native lock and not deployed this time"
          return
        fi
        ;;
    esac
  done
  case "$path" in
    .agents/skills/agmsg/run | .agents/skills/agmsg/run/*)
      echo "agmsg runtime state; the old path rebuilt the agmsg directory too, and apm replaces it"
      return
      ;;
    .claude/skills/synced | .claude/skills/synced/*)
      echo "Claude Code's synced-skill cache; the running session recreates it"
      return
      ;;
    .agents/skills/agmsg/apm.yml | .claude/skills/agmsg/apm.yml | \
      .agents/skills/agmsg/.apm | .claude/skills/agmsg/.apm | \
      .agents/skills/agmsg/.apm/.plugin-skill-sources.json | .claude/skills/agmsg/.apm/.plugin-skill-sources.json)
      echo "metadata the old path's stage wrote; the agmsg scripts do not read it"
      return
      ;;
  esac
  case "$path" in
    */__pycache__ | */__pycache__/* | *.pyc)
      echo "Python bytecode cache; regenerable"
      return
      ;;
  esac
  if [ "$(basename "$path")" = .apm-pin ]; then
    for root in $MIGRATE_ROOTS; do
      case "$path" in
        "$root/"*)
          echo "pin marker inside a root that migrate moved aside"
          return
          ;;
      esac
    done
  fi
}

# Tab-separated <path> <reason> for each lost path that is no loss. $2 and $3 are the arguments of allowed_lost_reason.
allowed_lost_paths() {
  local path reason
  while IFS= read -r path; do
    reason="$(allowed_lost_reason "$path" "$2" "$3")"
    if [ -n "$reason" ]; then printf '%s\t%s\n' "$path" "$reason"; fi
  done <"$1"
}
