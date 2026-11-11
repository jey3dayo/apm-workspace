# Every symlink of the scratch HOME ends up inside it, so nothing apm writes there reaches the real files.
isolate_scratch_links() {
  local home="$1" scratch="$2" link target resolved orig
  local store="$home/.local/state/agmsg/"
  while IFS= read -r link; do
    target="$(readlink "$link")"
    case "$target" in
      "$store"*)
        rm -f "$link"
        ln -s "$scratch/.local/state/agmsg/${target#"$store"}" "$link"
        ;;
      *)
        if [ ! -e "$link" ] || ! resolved="$(realpath "$link" 2>/dev/null)"; then
          # A relative link can point at a file of the HOME that the backup did not copy; resolve it in the HOME.
          orig="$home${link#"$scratch"}"
          if [ -e "$orig" ] && resolved="$(realpath "$orig" 2>/dev/null)"; then
            rm -f "$link"
            cp -cpRL "$resolved" "$link" 2>/dev/null || cp -pRL "$resolved" "$link" ||
              fail "cannot reproduce $orig -> $target in the scratch HOME"
            continue
          fi
          rm -f "$link"
          log "removed the broken link $link -> $target from the scratch HOME"
          continue
        fi
        case "$resolved/" in
          "$scratch/"*) ;;
          *)
            rm -f "$link"
            cp -cpRL "$resolved" "$link" 2>/dev/null || {
              rm -rf "$link"
              cp -pRL "$resolved" "$link"
            }
            ;;
        esac
        ;;
    esac
  done < <(find "$scratch" -type l | LC_ALL=C sort)
}

rehearsal_snapshot() {
  local scratch="$1" present="$2" path
  (cd "$scratch" && while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -e "$path" ] || [ -L "$path" ]; then find "$path"; fi
  done <"$present" | LC_ALL=C sort)
}

# apm 0.35.0 deletes deployed files it considers stale and `apm install --dry-run` does not preview that, so the same
# install and compile run on a clone of the backup first and the files that disappeared are counted.
cmd_rehearse() {
  parse_options "$@"
  [ -n "$SOURCE_REF" ] || fail "rehearse needs --source-ref"
  local home sha dir rehearsal scratch path manifest shared lost stamp escaping mode=plain
  local install_status=0 compile_status=skipped agmsg_status=0 linked=0 reinstate_status=skipped allowed_lost=0 baseline_skips=0 dropped=0
  home="$(target_home rehearse)"
  if ! native_lock_held "$home"; then native_lock_command "$home" rehearse "$@"; return; fi
  assert_default_apm_config "$home"
  assert_no_home_manifest "$home"
  assert_completed_backup "$home"
  escaping="$(root_escaping_links "$home")"
  [ -z "$escaping" ] || fail "these links in $MIGRATE_ROOTS of $home are broken or lead outside it, which migrate refuses and a rehearsal would hide by copying or dropping them. Replace each with a copy of its content (docs/native-distribution.md), run backup again, then re-run:
$escaping"
  assert_default_agmsg_store "$home"
  if [ "$MIGRATE" = 1 ]; then assert_same_render_mode "$home"; fi
  sha="$(resolve_source_sha "$SOURCE_REF")"
  dir="$(cd "$BACKUP_DIR" && pwd -P)"
  rehearsal="$(mktemp -d "$dir/rehearsal-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
  scratch="$rehearsal/home"
  mkdir "$scratch"
  : >"$rehearsal/apm.log"

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    mkdir -p "$(dirname "$scratch/$path")"
    clone_copy "$dir/home/$path" "$scratch/$path"
  done <"$dir/present.txt"
  if [ -e "$home/.apm/apm_modules" ] || [ -L "$home/.apm/apm_modules" ]; then
    mkdir -p "$scratch/.apm"
    clone_copy "$home/.apm/apm_modules" "$scratch/.apm/apm_modules"
  fi
  if [ -d "$dir/agmsg-state" ]; then
    mkdir -p "$scratch/.local/state"
    clone_copy "$dir/agmsg-state" "$scratch/.local/state/agmsg"
  fi
  assert_default_apm_config "$scratch"
  assert_no_home_manifest "$scratch"
  isolate_scratch_links "$home" "$scratch"
  shared="$(shared_entries "$scratch")"
  [ -z "$shared" ] || fail "the scratch HOME $scratch still shares data with files outside it:
$shared"

  rehearsal_snapshot "$scratch" "$dir/present.txt" >"$rehearsal/before.txt"
  manifest="$(render_manifest "$sha" "$WORKSPACE_ONLY")"
  mkdir -p "$scratch/.apm"
  rm -f "$scratch/.apm/apm.yml"
  printf '%s\n' "$manifest" >"$scratch/.apm/apm.yml"

  if [ -L "$scratch/.agents/skills/agmsg/db" ]; then
    linked=1
    agmsg_state "$scratch" save
  fi
  if [ "$MIGRATE" = 1 ]; then
    mode=migrate
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    claim_migrate_record "$scratch" "$stamp"
    migrate_roots "$scratch" "$stamp"
  fi
  run_apm_install "$scratch" 2>&1 | tee -a "$rehearsal/apm.log" >&2 || install_status=$?
  if [ "$install_status" -eq 0 ]; then
    compile_status=0
    run_apm "$scratch" compile -g --clean 2>&1 | tee -a "$rehearsal/apm.log" >&2 || compile_status=$?
  fi
  if [ "$MIGRATE" = 1 ] && [ "$install_status" = 0 ] && [ "$compile_status" = 0 ]; then
    reinstate_status=0
    (reinstate_entries "$scratch" "$stamp" "$rehearsal/") || reinstate_status=$?
  fi
  if [ "$linked" = 1 ]; then agmsg_state "$scratch" restore || agmsg_status=1; fi
  baseline_skips="$(grep -c 'no trustworthy local deployment baseline' "$rehearsal/apm.log" || true)"

  rehearsal_snapshot "$scratch" "$dir/present.txt" >"$rehearsal/after.txt"
  LC_ALL=C comm -23 "$rehearsal/before.txt" "$rehearsal/after.txt" >"$rehearsal/lost-all.txt"
  if [ "$MIGRATE" = 1 ]; then
    allowed_lost_paths "$rehearsal/lost-all.txt" "$scratch" "$(migrate_deployed_record "$scratch" "$stamp")" >"$rehearsal/allowed-lost.txt"
    LC_ALL=C comm -23 "$rehearsal/lost-all.txt" <(cut -f1 "$rehearsal/allowed-lost.txt") >"$rehearsal/lost.txt"
    allowed_lost="$(wc -l <"$rehearsal/allowed-lost.txt" | tr -d ' ')"
  else
    cp "$rehearsal/lost-all.txt" "$rehearsal/lost.txt"
  fi
  lost="$(wc -l <"$rehearsal/lost.txt" | tr -d ' ')"
  if [ "$MIGRATE" = 1 ]; then
    dropped_entries "$scratch" "$stamp" >"$rehearsal/dropped.txt"
    dropped="$(wc -l <"$rehearsal/dropped.txt" | tr -d ' ')"
  else
    : >"$rehearsal/dropped.txt"
  fi
  printf 'mode=%s\nhome=%s\nsource_ref=%s\nworkspace_only=%s\ninstall_status=%s\ncompile_status=%s\nreinstate_status=%s\nagmsg_status=%s\nlost=%s\nallowed_lost=%s\ndropped=%s\nbaseline_skips=%s\n%s\n' \
    "$mode" "$home" "$sha" "$WORKSPACE_ONLY" "$install_status" "$compile_status" "$reinstate_status" "$agmsg_status" "$lost" "$allowed_lost" "$dropped" "$baseline_skips" "$(cat "$dir/home-state.txt")" \
    >"$rehearsal/result.txt"

  if [ "$install_status" = 0 ] && [ "$compile_status" = 0 ] && [ "$agmsg_status" = 0 ] && [ "$lost" = 0 ] &&
    { [ "$MIGRATE" = 0 ] || { [ "$reinstate_status" = 0 ] && [ "$baseline_skips" = 0 ]; }; }; then
    log "rehearsal clean ($mode): install and compile ran on a clone of $dir and lost no file ($rehearsal)"
    return 0
  fi
  log "rehearsal failed ($mode): install=$install_status compile=$compile_status reinstate=$reinstate_status agmsg=$agmsg_status lost=$lost baseline_skips=$baseline_skips ($rehearsal/result.txt)"
  if [ "$lost" != 0 ]; then
    log "files that disappeared, all in $rehearsal/lost.txt:"
    head -n 20 "$rehearsal/lost.txt" | sed 's/^/  /' >&2
  fi
  exit 1
}
