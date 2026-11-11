#!/usr/bin/env bash
# native 配布の保護と移行処理
# backup, rehearse, migrate などで使用される関数

physical_path() {
  local path="$1" rest=""
  while [ ! -d "$path" ]; do
    rest="/$(basename "$path")$rest"
    path="$(dirname "$path")"
  done
  printf '%s%s\n' "$(cd "$path" && pwd -P)" "$rest"
}

user_db_home() {
  local user home
  user="$(id -un)"
  home="$(eval "printf '%s' ~$user")"
  physical_path "$home"
}

account_home() {
  if [ -n "${APM_NATIVE_ACCOUNT_HOME:-}" ]; then
    [ -d "$APM_NATIVE_ACCOUNT_HOME" ] || fail "APM_NATIVE_ACCOUNT_HOME=$APM_NATIVE_ACCOUNT_HOME is not a directory"
    physical_path "$APM_NATIVE_ACCOUNT_HOME"
    return
  fi
  user_db_home
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'; else shasum -a 256 | awk '{print $1}'; fi
}

root_lines() {
  awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1"
}

has_marker() {
  local first
  first="$(root_lines "$1" | LC_ALL=C sed -n '/[^[:space:]]/{p;q;}')"
  [ "${first#"$GENERATED_ROOT_MARKER"}" != "$first" ]
}

has_valid_build_id() {
  local pattern='^<!-- Build ID: [0-9a-f]{12} -->$' recorded computed
  recorded="$(root_lines "$1" | grep -E "$pattern" | sed -E 's/^<!-- Build ID: ([0-9a-f]{12}) -->$/\1/')"
  [ "$(printf '%s\n' "$recorded" | grep -c .)" = 1 ] || return 1
  computed="$(root_lines "$1" | grep -vE "$pattern" | awk '{ if (n++) printf "\n"; printf "%s", $0 }' | sha256 | cut -c1-12)"
  [ "$recorded" = "$computed" ]
}

edited_generated_roots() {
  local home="$1" root
  for root in $COMPILED_ROOTS; do
    if [ -f "$home/$root" ] && has_marker "$home/$root" && ! has_valid_build_id "$home/$root"; then
      printf '%s\n' "$home/$root"
    fi
  done
}

clone_copy() {
  cp -cpR "$1" "$2" 2>/dev/null || cp -pR "$1" "$2"
}

assert_backup_dir_outside_targets() {
  local home="$1" dir="$2" surface
  for surface in .apm .claude .codex .cursor .agents; do
    case "$dir/" in
      "$home/$surface/"*) fail "--backup-dir $dir must not be inside $home/$surface" ;;
    esac
  done
}

assert_completed_backup() {
  local home="$1"
  [ -n "$BACKUP_DIR" ] || fail "rehearse needs --backup-dir <a completed backup of this HOME>; run backup first"
  [ -f "$BACKUP_DIR/complete" ] || fail "$BACKUP_DIR is not a completed backup"
  grep -qxF "home=$home" "$BACKUP_DIR/complete" || fail "$BACKUP_DIR is a backup of another HOME"
  [ -f "$BACKUP_DIR/home-state.txt" ] || fail "$BACKUP_DIR does not record the state of the HOME (a backup of an older format); take a new backup with backup, then re-run"
  [ "$(cat "$BACKUP_DIR/home-state.txt")" = "$(home_state_lines "$home")" ] ||
    fail "$BACKUP_DIR was taken when the HOME was in another state ($(tr '\n' ' ' <"$BACKUP_DIR/home-state.txt")), and it is now $(home_state_lines "$home" | tr '\n' ' '); the clone would not show what migrate does. Take a new backup, then re-run"
}

assert_default_agmsg_store() {
  local home="$1" name target
  for name in db teams; do
    [ -L "$home/.agents/skills/agmsg/$name" ] || continue
    target="$(readlink "$home/.agents/skills/agmsg/$name")"
    [ "$target" = "$home/.local/state/agmsg/$name" ] ||
      fail "$home/.agents/skills/agmsg/$name points at $target, not at $home/.local/state/agmsg/$name, the only store agmsg-state.sh relinks to. Nothing was changed; move the data to the default store (or relink it) first."
  done
}

assert_same_render_mode() {
  local home="$1" previous
  [ -f "$home/.apm/apm.yml" ] || return 0
  previous="$(sed -n 's/^# native-render: workspace_only=\([01]\)$/\1/p' "$home/.apm/apm.yml" | head -n 1)"
  [ -z "$previous" ] || [ "$previous" = "$WORKSPACE_ONLY" ] ||
    fail "the previous manifest of $home was rendered with workspace_only=$previous, this run uses workspace_only=$WORKSPACE_ONLY; the previous lock would make every external package look dropped. Use the same mode."
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

claim_migrate_record() {
  local home="$1" stamp="$2" record
  record="$(migrate_record "$home" "$stamp")"
  mkdir -p "$home/.apm"
  (set -o noclobber && : >"$record") 2>/dev/null || fail "$record already exists: another migrate drew the same stamp. Nothing was changed; run again."
}

migrate_deployed_record() {
  printf '%s/.apm/native-migrate-%s.deployed.txt\n' "$1" "$2"
}

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

record_has() {
  grep -qxF "$1"$'\t'"$2" "$3"
}

restored_but_unrecorded() {
  { [ -e "$1" ] || [ -L "$1" ]; } && { [ -e "$1.native-$2" ] || [ -L "$1.native-$2" ]; }
}

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
