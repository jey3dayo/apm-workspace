log() {
  printf '%s\n' "$*" >&2
}

native_lock_held() {
  [ -n "${APM_NATIVE_LOCK_FD:-}" ] && python3 "$SCRIPT_DIR/native-home.py" check "$1"
}

native_lock_command() {
  local home="$1"
  shift
  python3 "$SCRIPT_DIR/native-home.py" run "$home" bash "$SCRIPT_DIR/native.sh" "$@"
}

native_workspace() {
  local home="$1"
  shift
  if [ "$1" = sync:opencode ]; then python3 "$SCRIPT_DIR/native-home.py" check-opencode "$home"; fi
  HOME="$home" APM_WORKSPACE_DIR="$REPO_ROOT" APM_OPENCODE_OUTPUT="$home/.config/opencode/AGENTS.md" \
    bash "$SCRIPT_DIR/apm-workspace.sh" "$@"
}

cmd_opencode() {
  if [ $# = 0 ]; then set -- --real-home; fi
  parse_options "$@"
  local home
  home="$(target_home opencode)"
  if ! native_lock_held "$home"; then native_lock_command "$home" opencode "$@"; return; fi
  native_workspace "$home" sync:opencode
}

physical_path() {
  local path="$1" rest=""
  while [ ! -d "$path" ]; do
    rest="/$(basename "$path")$rest"
    path="$(dirname "$path")"
  done
  printf '%s%s\n' "$(cd "$path" && pwd -P)" "$rest"
}

# The account's home from the user database, not $HOME, so a HOME override cannot hide the real one.
# APM_NATIVE_ACCOUNT_HOME stands in for it in tests, which never touch the real one.
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

# Also checks the user database HOME, so the test override cannot make the real HOME look disposable.
assert_disposable_home() {
  local dir="$1" home surface prefix
  case "/$dir/" in
    */../*) fail "--home $dir must not contain '..'" ;;
  esac
  [ -d "$dir" ] || fail "--home $dir is not an existing directory"
  dir="$(cd "$dir" && pwd -P)"
  assert_ssh_safe_home "$dir"
  for home in "$(account_home)" "$(user_db_home)"; do
    case "$home/" in
      "${dir%/}/"*) fail "--home $dir is the account's HOME or contains it; the cutover is not part of this script (docs/native-distribution.md)" ;;
    esac
    for surface in $PROTECTED_SURFACES; do
      for prefix in "$home/$surface/" "$(physical_path "$home/$surface")/"; do
        case "$dir/" in
          "$prefix"*) fail "--home $dir is inside $home/$surface" ;;
        esac
      done
    done
  done
  printf '%s\n' "$dir"
}

parse_options() {
  HOME_DIR="" SOURCE_REF="" WORKSPACE_ONLY=0 REAL_HOME=0 BACKUP_DIR="" STAMP="" REHEARSAL="" MIGRATE=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --home) [ $# -ge 2 ] || fail "--home needs a value"; HOME_DIR="$2"; shift 2 ;;
      --real-home) REAL_HOME=1; shift ;;
      --backup-dir) [ $# -ge 2 ] || fail "--backup-dir needs a value"; BACKUP_DIR="$2"; shift 2 ;;
      --source-ref) [ $# -ge 2 ] || fail "--source-ref needs a value"; SOURCE_REF="$2"; shift 2 ;;
      --stamp) [ $# -ge 2 ] || fail "--stamp needs a value"; STAMP="$2"; shift 2 ;;
      --rehearsal) [ $# -ge 2 ] || fail "--rehearsal needs a value"; REHEARSAL="$2"; shift 2 ;;
      --migrate) MIGRATE=1; shift ;;
      --workspace-only) WORKSPACE_ONLY=1; shift ;;
      *) fail "unknown option: $1" ;;
    esac
  done
}

# backup and rehearse: --home names a disposable HOME, --real-home the account's own. Exactly one of them.
target_home() {
  if [ "$REAL_HOME" = 1 ]; then
    [ -z "$HOME_DIR" ] || fail "pass either --home or --real-home, not both"
    account_home
  else
    [ -n "$HOME_DIR" ] || fail "$1 needs --home <disposable HOME>, or --real-home for the account's HOME"
    assert_disposable_home "$HOME_DIR"
  fi
}

# APM picks cache, config and temp locations from more than HOME (APM_CACHE_DIR, XDG_*, TMPDIR), and git honours
# tokens, proxies and askpass from the environment, so apm starts from an empty environment plus this allowlist, with
# its temp directory inside HOME.
# ssh splits UserKnownHostsFile on whitespace and reads quotes and backslashes, so a HOME holding them would send
# new host keys to a path outside it.
assert_ssh_safe_home() {
  case "$1" in
    *[[:space:]\"\\]*) fail "$1 contains whitespace, a quote or a backslash, which ssh would split into another path" ;;
  esac
}

# --trust-bin always, so a piped rehearse and a terminal migrate behave alike; allowExecutables limits which packages get bin/.
run_apm_install() {
  run_apm "$1" install -g --only apm --trust-bin
}

run_apm() {
  local home="$1" var
  shift
  assert_ssh_safe_home "$home"
  mkdir -p "$home/.cache/apm-native-tmp"
  # ssh takes its config and known_hosts from the account HOME, not $HOME; new host keys go to the target HOME.
  mkdir -p "$home/.ssh"
  local ssh_cmd
  ssh_cmd="ssh -F /dev/null -o $(printf '%q' "UserKnownHostsFile=$home/.ssh/known_hosts \"$(user_db_home)/.ssh/known_hosts\"")"
  local env_args=(HOME="$home" PATH="$PATH" TMPDIR="$home/.cache/apm-native-tmp" LANG="${LANG:-C.UTF-8}" GIT_SSH_COMMAND="$ssh_cmd")
  for var in LC_ALL TERM PYTHONUTF8 GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_CEILING_DIRECTORIES; do
    if [ -n "${!var:-}" ]; then env_args+=("$var=${!var}"); fi
  done
  if [ "${APM_NATIVE_HTTPS:-0}" = 1 ] && [ -n "${GIT_CONFIG_SYSTEM:-}" ]; then env_args+=("GIT_CONFIG_SYSTEM=$GIT_CONFIG_SYSTEM"); fi
  if [ -n "${GIT_CONFIG_COUNT:-}" ]; then
    [[ "$GIT_CONFIG_COUNT" =~ ^(0|[1-9][0-9]*)$ ]] && [ "$GIT_CONFIG_COUNT" -le 1000 ] || fail "invalid GIT_CONFIG_COUNT"
    env_args+=("GIT_CONFIG_COUNT=$GIT_CONFIG_COUNT")
    local i key value
    for ((i = 0; i < GIT_CONFIG_COUNT; i++)); do
      key="GIT_CONFIG_KEY_$i" value="GIT_CONFIG_VALUE_$i"
      [ -n "${!key:-}" ] && [ "${!value+x}" = x ] || fail "incomplete Git config environment at index $i"
      env_args+=("$key=${!key}" "$value=${!value}")
    done
  fi
  (cd "$home" && env -i "${env_args[@]}" "$APM_BIN" "$@")
}

# Anything apm could write through to a file outside HOME: a symlink in HOME that resolves outside it (or is broken),
# and a regular file there with another hard link.
shared_entries() {
  shared_entries_in "$1" "$1"
}

# The same test over the given paths of HOME only.
shared_entries_in() {
  local home="$1" path
  shift
  for path in "$@"; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    find "$path" -type l | LC_ALL=C sort | while IFS= read -r link; do
      escaping_link_line "$home" "$link"
    done
    find "$path" -type f -links +1 | LC_ALL=C sort | sed 's/^/  /; s/$/ (hard link)/'
  done
}

escaping_link_line() {
  local home="$1" link="$2" target
  # GNU realpath resolves a link whose last component is missing, so test the target first.
  if [ ! -e "$link" ] || ! target="$(realpath "$link" 2>/dev/null)"; then
    printf '  %s (broken)\n' "$link"
    return
  fi
  case "$target/" in
    "$home/"*) ;;
    *) printf '  %s -> %s\n' "$link" "$target" ;;
  esac
}

# migrate --real-home: the paths apm writes (REAL_HOME_WRITE_PATHS), and the tool directories above them only when they
# are links themselves, so the rest of the HOME is not walked.
real_home_shared_entries() {
  local home="$1" path
  for path in $REAL_HOME_TOOL_DIRS; do
    if [ -L "$home/$path" ]; then escaping_link_line "$home" "$home/$path"; fi
  done
  set --
  for path in $REAL_HOME_WRITE_PATHS; do set -- "$@" "$home/$path"; done
  shared_entries_in "$home" "$@"
}

# At user scope apm reads executable approvals from <HOME>/apm.yml when it exists, and only then from <HOME>/.apm/apm.yml
# (apm_cli/security/executables.py exec_trust_context_for_project), so the allowExecutables render writes would not apply.
assert_no_home_manifest() {
  if [ -e "$1/apm.yml" ] || [ -L "$1/apm.yml" ]; then
    fail "$1/apm.yml exists, and apm would read its executable approvals instead of those of $1/.apm/apm.yml. Move it aside, then re-run."
  fi
}

# apm reads ~/.apm/config.json with json.load and takes temp_dir and other locations from it. Decode it the same way
# and allow only default_client and prefer_ssh, which move no write location.
assert_default_apm_config() {
  local config="$1/.apm/config.json" extra
  [ -e "$config" ] || return 0
  extra="$(python3 -c 'import json, sys; print(" ".join(sorted(set(json.load(open(sys.argv[1], encoding="utf-8"))) - {"default_client", "prefer_ssh"})))' "$config")" ||
    fail "$config is not a JSON object apm could read"
  [ -z "$extra" ] || fail "$config sets $extra; only default_client and prefer_ssh may be set there"
}
