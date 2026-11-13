assert_backup_dir_outside_targets() {
  local home="$1" dir="$2" surface
  for surface in .apm .claude .codex .cursor .agents; do
    case "$dir/" in
      "$home/$surface/"*) fail "--backup-dir $dir must not be inside $home/$surface" ;;
    esac
  done
}

cmd_backup() {
  parse_options "$@"
  [ -n "$BACKUP_DIR" ] || fail "backup needs --backup-dir <new directory>"
  local home dir path
  home="$(target_home backup)"
  if ! native_lock_held "$home"; then native_lock_command "$home" backup "$@"; return; fi
  dir="$(physical_path "$BACKUP_DIR")"
  assert_backup_dir_outside_targets "$home" "$dir"
  if [ -e "$dir" ] && [ -n "$(ls -A "$dir")" ]; then fail "--backup-dir $dir already has files; backups are never overwritten"; fi
  mkdir -p "$dir/home"
  : >"$dir/present.txt"
  : >"$dir/absent.txt"
  for path in $BACKUP_PATHS; do
    if [ -e "$home/$path" ] || [ -L "$home/$path" ]; then
      mkdir -p "$(dirname "$dir/home/$path")"
      clone_copy "$home/$path" "$dir/home/$path"
      printf '%s\n' "$path" >>"$dir/present.txt"
    else
      printf '%s\n' "$path" >>"$dir/absent.txt"
    fi
  done
  home_state_lines "$home" >"$dir/home-state.txt"
  printf 'home=%s\ncreated=%s\n' "$home" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$dir/complete"
  log "backed up $(wc -l <"$dir/present.txt" | tr -d ' ') paths of $home into $dir"
}

# APFS clones on macOS; a plain copy elsewhere. Symlinks stay symlinks.
clone_copy() {
  cp -cpR "$1" "$2" 2>/dev/null || cp -pR "$1" "$2"
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
