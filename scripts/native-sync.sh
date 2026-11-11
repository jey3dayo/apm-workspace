#!/usr/bin/env bash
# Sourced by native.sh so sync's internal stages use the same HOME and loss guards.

sync_usage() {
  cat <<'EOF'
Usage: scripts/native.sh sync [--source-ref SHA] [--https]
                             [--allow-drop ROOT/ENTRY] [--allow-skip ROOT/ENTRY]
                             [--home DISPOSABLE_DIR | --real-home]

Defaults to the real HOME and HEAD. HEAD must be clean and equal the source repository's current main SHA.
Takes a fresh backup, rehearses migrate, checks the reports, moves caches aside, migrates, writes the OpenCode guide,
runs doctor, and reports before/after entry counts. Existing native guards remain active. No sessions are closed.

--allow-drop and --allow-skip are repeatable exact paths from the rehearsal reports. Missing or extra approvals stop
before real migration; review the reports printed on failure, then re-run with the intended paths only.
--https uses invocation-only Git config to keep GitHub URLs on HTTPS. Original Git config files are unchanged.
Logs, the backup and rehearsal remain under tmp/native-sync/ in this checkout. Caches are moved, never deleted.
Failures after migrate has claimed a stamp print its rollback command; rollback restores only the four roots.
Use the backup and docs/native-distribution.md for the other files and for restoring caches.
EOF
}

sync_native() {
  bash "$SCRIPT_DIR/native.sh" "$@"
}

sync_workspace() {
  native_workspace "$SYNC_HOME" "$@"
}

sync_exact_entry() {
  local path="$1" root name
  for root in $MIGRATE_ROOTS; do
    case "$path" in
      "$root/"*)
        name="${path#"$root/"}"
        [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && return 0
        ;;
    esac
  done
  fail "expected an exact migrated ROOT/ENTRY path, got: $path"
}

sync_https_rule() {
  local file="$1" prefix="$2" https
  case "$prefix" in
    https://github.com/*) https="$prefix" ;;
    git@github.com:*) https="https://github.com/${prefix#git@github.com:}" ;;
    ssh://git@github.com/*) https="https://github.com/${prefix#ssh://git@github.com/}" ;;
    *) return ;;
  esac
  git -C "$REPO_ROOT" config --file "$file" --add "url.$https.insteadOf" "$prefix"
}

sync_https() {
  local globals system directory file path entry prefix
  globals="$(git -C "$REPO_ROOT" var GIT_CONFIG_GLOBAL)" || fail "cannot discover Git global config paths"
  system="$(GIT_CONFIG_NOSYSTEM=0 git -C "$REPO_ROOT" var GIT_CONFIG_SYSTEM)" || fail "cannot discover Git system config paths"
  mkdir -p "$REPO_ROOT/tmp/native-https"
  directory="$(mktemp -d "$REPO_ROOT/tmp/native-https/run.XXXXXX")"
  for file in "$directory/global" "$directory/system"; do
    for prefix in "$SOURCE_URL" https://github.com/ git@github.com: ssh://git@github.com/; do sync_https_rule "$file" "$prefix"; done
  done
  # Git chooses the first equal-length insteadOf match; put transport rules before the original config includes.
  {
    git -C "$REPO_ROOT" config --null --get-regexp '^url\..*\.insteadof$' || [ "$?" = 1 ]
  } | while IFS= read -r -d '' entry; do
    prefix="${entry#*$'\n'}"
    for file in "$directory/global" "$directory/system"; do sync_https_rule "$file" "$prefix"; done
  done
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in /*) ;; *) path="$PWD/$path" ;; esac
    git -C "$REPO_ROOT" config --file "$directory/global" --add include.path "$path"
  done <<<"$globals"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in /*) ;; *) path="$PWD/$path" ;; esac
    git -C "$REPO_ROOT" config --file "$directory/system" --add include.path "$path"
  done <<<"$system"
  export GIT_CONFIG_GLOBAL="$directory/global" GIT_CONFIG_SYSTEM="$directory/system" APM_NATIVE_HTTPS=1
}

sync_assert_source() {
  local sha="$1" remote dirty resolved
  [ "$(git -C "$REPO_ROOT" rev-parse --verify HEAD)" = "$sha" ] || fail "local HEAD must equal --source-ref $sha"
  dirty="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" || fail "cannot inspect the source checkout"
  [ -z "$dirty" ] || fail "native:sync requires a clean source checkout"
  if [ "${APM_NATIVE_HTTPS:-0}" = 1 ]; then
    case "$SOURCE_URL" in
      https://github.com/* | git@github.com:* | ssh://git@github.com/*)
        resolved="$(git -C "$REPO_ROOT" ls-remote --get-url -- "$SOURCE_URL")" || fail "cannot check HTTPS source URL"
        case "$resolved" in https://github.com/*) ;; *) fail "Git did not resolve the source URL to GitHub HTTPS; no remote request was made" ;; esac
        ;;
    esac
  fi
  remote="$(git -C "$REPO_ROOT" ls-remote --exit-code -- "$SOURCE_URL" refs/heads/main)" || fail "cannot verify the source repository's main SHA"
  [ "$remote" = "$sha"$'\t'refs/heads/main ] || fail "local source $sha differs from the source repository's current main: $remote"
}

sync_counts() {
  local home="$1" root count
  for root in $MIGRATE_ROOTS; do
    count=0
    if [ -d "$home/$root" ]; then count="$(find -H "$home/$root" -mindepth 1 -maxdepth 1 -print0 | tr -cd '\000' | wc -c | tr -d ' ')"; fi
    printf '%s\t%s\n' "$root" "$count"
  done
}

sync_stage() {
  local stage="$1"
  shift
  log "native:sync: $stage (log: $SYNC_RUN/$stage.log)"
  "$@" 2>&1 | tee "$SYNC_RUN/$stage.log"
}

sync_review_entries() {
  local file="$1" approved="$2" kind="$3" path actual
  [ -f "$file" ] && [ ! -L "$file" ] || fail "missing plain rehearsal report: $file"
  while IFS= read -r path; do
    [ -n "$path" ] || fail "blank path in $file"
    sync_exact_entry "$path"
  done <"$file"
  actual="$(LC_ALL=C sort -u "$file")"
  [ "$actual" = "$(printf '%s' "$approved" | LC_ALL=C sort -u)" ] || {
    log "Review $file and approve only intended paths with --allow-$kind ROOT/ENTRY (extra approvals also fail):"
    cat "$file" >&2
    log "Original entries remain in $SYNC_RUN/backup/home; proposed entries are in the rehearsal's home directory."
    fail "the reported $kind list differs from the exact approvals"
  }
}

sync_review_rehearsal() {
  local rehearsal="$1" sha="$2" stamp deployed="" want candidate
  WORKSPACE_ONLY=0
  assert_migrate_rehearsal "$SYNC_HOME" "$sha" "$rehearsal"
  for want in lost-all.txt allowed-lost.txt lost.txt apm.log; do
    [ -f "$rehearsal/$want" ] && [ ! -L "$rehearsal/$want" ] || fail "missing plain rehearsal report: $rehearsal/$want"
  done
  LC_ALL=C sort -cu "$rehearsal/lost-all.txt" || fail "lost-all report must be sorted and unique"
  [ ! -s "$rehearsal/lost.txt" ] || fail "rehearsal lost files; review $rehearsal/lost.txt"
  for candidate in "$rehearsal/home/.apm"/native-migrate-*.deployed.txt; do
    [ -f "$candidate" ] && [ ! -L "$candidate" ] || continue
    [ -z "$deployed" ] || fail "expected one rehearsal deployment record in $rehearsal"
    deployed="$candidate"
  done
  [ -n "$deployed" ] || fail "missing rehearsal deployment record in $rehearsal"
  stamp="${deployed##*/native-migrate-}"
  stamp="${stamp%.deployed.txt}"
  assert_stamp "$stamp"
  allowed_lost_paths "$rehearsal/lost-all.txt" "$rehearsal/home" "$deployed" >"$SYNC_RUN/expected-allowed-lost.txt"
  cmp -s "$SYNC_RUN/expected-allowed-lost.txt" "$rehearsal/allowed-lost.txt" || fail "allowed-lost report does not match native loss rules: $rehearsal/allowed-lost.txt"
  LC_ALL=C comm -23 "$rehearsal/lost-all.txt" <(cut -f1 "$rehearsal/allowed-lost.txt") >"$SYNC_RUN/unapproved-loss.txt"
  [ ! -s "$SYNC_RUN/unapproved-loss.txt" ] || fail "loss outside native allowed-lost rules; review $SYNC_RUN/unapproved-loss.txt"
  for want in "allowed_lost=$(wc -l <"$rehearsal/allowed-lost.txt" | tr -d ' ')" "dropped=$(wc -l <"$rehearsal/dropped.txt" | tr -d ' ')"; do
    result_has "$rehearsal" "$want" || fail "rehearsal report count differs: $want"
  done
  if [ -f "$rehearsal/apm.log" ] && grep -q 'no trustworthy local deployment baseline' "$rehearsal/apm.log"; then fail "rehearsal skipped a deployment baseline; review $rehearsal/apm.log"; fi
  sync_review_entries "$rehearsal/dropped.txt" "$SYNC_ALLOW_DROP" drop
  sync_review_entries "$rehearsal/skipped.txt" "$SYNC_ALLOW_SKIP" skip
}

sync_move_caches() {
  local path source destination parent
  for path in .cache/apm Library/Caches/apm; do
    source="$SYNC_HOME/$path"
    if [ ! -e "$source" ] && [ ! -L "$source" ]; then continue; fi
    parent="$(physical_path "$(dirname "$source")")"
    case "$parent/" in "$SYNC_HOME/"*) ;; *) fail "cache parent leaves HOME: $parent" ;; esac
    destination="$source.native-aside-${SYNC_RUN##*/}"
    [ ! -e "$destination" ] && [ ! -L "$destination" ] || fail "cache aside path already exists: $destination"
  done
  for path in .cache/apm Library/Caches/apm; do
    source="$SYNC_HOME/$path"
    if [ ! -e "$source" ] && [ ! -L "$source" ]; then continue; fi
    destination="$source.native-aside-${SYNC_RUN##*/}"
    mv -n "$source" "$destination"
    [ ! -e "$source" ] && [ ! -L "$source" ] || fail "cache could not be moved without overwriting $destination"
    printf '%s\t%s\n' "$source" "$destination" >>"$SYNC_RUN/cache-aside.txt"
    log "cache kept at $destination"
  done
}

sync_migrate_stamp() {
  local lines
  [ -f "$SYNC_RUN/migrate.log" ] || return 1
  lines="$(sed -nE 's/^native-migrate stamp: ([0-9]{8}T[0-9]{6}Z)$/\1/p' "$SYNC_RUN/migrate.log")"
  [[ "$lines" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || return 1
  [ -f "$(migrate_record "$SYNC_HOME" "$lines")" ] && [ ! -L "$(migrate_record "$SYNC_HOME" "$lines")" ] || return 1
  printf '%s\n' "$lines"
}

sync_finish() {
  local status=$? stamp="" source destination
  trap - EXIT
  stamp="$(sync_migrate_stamp)" || stamp=""
  if [ "$status" != 0 ]; then log "native:sync stopped (exit $status); backup and logs: $SYNC_RUN"; fi
  if [ -n "$stamp" ]; then
    printf 'Rollback of the four roots: %s\n' "$(migrate_rollback_command "$SYNC_HOME" "$SYNC_REAL_HOME" "$stamp")" >&2
    log "Other native outputs require the backup at $SYNC_RUN/backup (docs/native-distribution.md)."
  elif [ -f "$SYNC_RUN/migrate.log" ]; then
    log "No unique recorded migrate stamp was confirmed; inspect $SYNC_RUN/migrate.log before choosing a rollback."
  fi
  if [ -s "$SYNC_RUN/cache-aside.txt" ]; then
    log "Caches remain aside (move a regenerated cache to a fresh name before restoring; delete neither copy):"
    while IFS=$'\t' read -r source destination; do printf '  %q -> %q\n' "$destination" "$source" >&2; done <"$SYNC_RUN/cache-aside.txt"
  fi
  exit "$status"
}

cmd_sync() (
  local source_ref=HEAD https=0 home_dir="" real_home=1 selected_home="" sha backup rehearsal path stamp
  local sync_args=(sync "$@")
  SYNC_ALLOW_DROP="" SYNC_ALLOW_SKIP=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help)
        sync_usage
        return
        ;;
      --source-ref | --home | --allow-drop | --allow-skip)
        [ $# -ge 2 ] || fail "$1 needs a value"
        case "$1" in
          --source-ref) source_ref="$2" ;;
          --home)
            [ "$selected_home" != real ] || fail "pass either --home or --real-home"
            home_dir="$2"
            real_home=0
            selected_home=disposable
            ;;
          --allow-drop)
            sync_exact_entry "$2"
            SYNC_ALLOW_DROP+="$2"$'\n'
            ;;
          --allow-skip)
            sync_exact_entry "$2"
            SYNC_ALLOW_SKIP+="$2"$'\n'
            ;;
        esac
        shift 2
        ;;
      --https)
        https=1
        shift
        ;;
      --real-home)
        [ "$selected_home" != disposable ] || fail "pass either --home or --real-home"
        selected_home=real
        shift
        ;;
      *) fail "unknown sync option: $1" ;;
    esac
  done
  HOME_DIR="$home_dir" REAL_HOME="$real_home"
  SYNC_HOME="$(target_home sync)" SYNC_REAL_HOME="$real_home"
  assert_not_checkout "$SYNC_HOME"
  if ! native_lock_held "$SYNC_HOME"; then
    native_lock_command "$SYNC_HOME" "${sync_args[@]}"
    return
  fi
  [ "$https" = 0 ] || sync_https
  sha="$(git -C "$REPO_ROOT" rev-parse --verify "$source_ref^{commit}")" || fail "--source-ref must be a local commit"
  sync_assert_source "$sha"
  python3 "$SCRIPT_DIR/native-home.py" check-opencode "$SYNC_HOME"
  local home_args=(--real-home)
  if [ "$real_home" = 0 ]; then home_args=(--home "$SYNC_HOME"); fi
  assert_backup_dir_outside_targets "$SYNC_HOME" "$(physical_path "$REPO_ROOT/tmp/native-sync")"
  mkdir -p "$REPO_ROOT/tmp/native-sync"
  SYNC_RUN="$(mktemp -d "$REPO_ROOT/tmp/native-sync/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
  trap sync_finish EXIT
  log "native:sync source=$sha home=$SYNC_HOME logs=$SYNC_RUN"
  sync_counts "$SYNC_HOME" >"$SYNC_RUN/before-counts.txt"
  sync_stage plan sync_native plan --source-ref "$sha"
  backup="$SYNC_RUN/backup"
  sync_stage backup sync_native backup "${home_args[@]}" --backup-dir "$backup"
  sync_stage rehearse sync_native rehearse "${home_args[@]}" --backup-dir "$backup" --source-ref "$sha" --migrate
  rehearsal=""
  for path in "$backup"/rehearsal-*; do
    [ -d "$path" ] || continue
    [ -z "$rehearsal" ] || fail "expected one fresh rehearsal under $backup"
    rehearsal="$path"
  done
  [ -n "$rehearsal" ] || fail "no rehearsal directory under $backup"
  sync_review_rehearsal "$rehearsal" "$sha"
  sync_assert_source "$sha"
  sync_move_caches
  sync_stage migrate sync_native migrate "${home_args[@]}" --source-ref "$sha" --rehearsal "$rehearsal"
  stamp="$(sync_migrate_stamp)" || fail "migrate did not print one valid recorded stamp; inspect $SYNC_RUN/migrate.log"
  sync_review_entries "$SYNC_HOME/.apm/native-migrate-$stamp.dropped.txt" "$SYNC_ALLOW_DROP" drop
  sync_review_entries "$SYNC_HOME/.apm/native-migrate-$stamp.skipped.txt" "$SYNC_ALLOW_SKIP" skip
  sync_stage opencode sync_workspace sync:opencode
  sync_stage doctor sync_workspace doctor
  sync_stage doctor-intake sync_workspace doctor-intake
  sync_counts "$SYNC_HOME" >"$SYNC_RUN/after-counts.txt"
  awk -F '\t' 'NR == FNR { before[$1] = $2; next } { printf "%s: %d -> %d (%+d)\n", $1, before[$1], $2, $2 - before[$1] }' \
    "$SYNC_RUN/before-counts.txt" "$SYNC_RUN/after-counts.txt"
  log "native:sync completed: $sha (backup and logs: $SYNC_RUN)"
)
