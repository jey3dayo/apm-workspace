#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  local root
  root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=tests/native-test-helpers.bash
  . "$root/tests/native-test-helpers.bash"
  FX="$(cd "$BATS_TEST_TMPDIR" && pwd -P)/sync-fixture"
  mkdir -p "$FX/home/.cache/apm" "$FX/home/Library/Caches/apm" "$FX/tmp" "$FX/template"
  copy_native_runtime "$root" "$FX/repo"
  cp "${NATIVE_SYNC_SOURCE:-$root}/scripts/native-sync.sh" "$FX/repo/scripts/native-sync.sh"
  printf 'tmp/\n' >"$FX/repo/.gitignore"
  printf 'fixture global config\n' >"$FX/gitconfig-sentinel"
  printf '[fixture]\n  keep = global-value\n' >"$FX/gitconfig"
  # shellcheck source=scripts/lib/git-test-env.sh
  . "$root/scripts/lib/git-test-env.sh"
  apm_isolate_git_env "$FX/gitconfig"
  export GIT_TEMPLATE_DIR="$FX/template"
  printf 'unix cache\n' >"$FX/home/.cache/apm/sentinel"
  printf 'mac cache\n' >"$FX/home/Library/Caches/apm/sentinel"
  mkdir -p "$FX/home/.agents/skills/existing"
  printf 'existing skill\n' >"$FX/home/.agents/skills/existing/SKILL.md"
  env GIT_CONFIG_GLOBAL="$FX/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_TEMPLATE_DIR="$FX/template" git init -q -b main "$FX/repo"
  git -C "$FX/repo" add scripts/native.sh scripts/native-sync.sh scripts/native-home.py scripts/lib .gitignore
  git -C "$FX/repo" -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m fixture
  env GIT_CONFIG_GLOBAL="$FX/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_TEMPLATE_DIR="$FX/template" git init --bare -q "$FX/remote.git"
  git -C "$FX/repo" push -q "$FX/remote.git" HEAD:refs/heads/main
  SHA="$(git -C "$FX/repo" rev-parse HEAD)"
  cat >"$FX/harness" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != --help ] && [ -z "${APM_NATIVE_LOCK_FD:-}" ]; then
  exec python3 "$SYNC_TEST_REPO/scripts/native-home.py" run "$HOME" bash "$0" "$@"
fi
. "$SYNC_TEST_REPO/scripts/native.sh"
. "$SYNC_TEST_REPO/scripts/native-sync.sh"

sync_native() {
  local command="$1" home rehearsal stamp=20261110T120000Z
  shift
  printf '%s\n' "$command" >>"$SYNC_TEST_CALLS"
  printf 'git-count=%s\n' "${GIT_CONFIG_COUNT:-0}" >>"$SYNC_TEST_CONFIG_LOG"
  git -C "$REPO_ROOT" config --get fixture.keep >>"$SYNC_TEST_CONFIG_LOG"
  git -C "$REPO_ROOT" ls-remote --get-url -- https://github.com/fixture-owner/repo.git >>"$SYNC_TEST_CONFIG_LOG"
  git -C "$REPO_ROOT" ls-remote --get-url -- git@github.com:fixture-owner/repo.git >>"$SYNC_TEST_CONFIG_LOG"
  if [ "${SYNC_TEST_FAIL:-}" = "$command" ]; then return 19; fi
  case "$command" in
    backup) cmd_backup "$@" ;;
    rehearse)
      parse_options "$@"
      home="$(target_home rehearse)"
      rehearsal="$BACKUP_DIR/rehearsal-20261110T115959Z.fixture"
      mkdir -p "$rehearsal/home/.apm"
      : >"$rehearsal/home/.apm/native-migrate-$stamp.deployed.txt"
      : >"$rehearsal/lost-all.txt"
      : >"$rehearsal/allowed-lost.txt"
      : >"$rehearsal/lost.txt"
      : >"$rehearsal/apm.log"
      printf '%s' "${SYNC_TEST_DROP:-}" >"$rehearsal/dropped.txt"
      printf '%s' "${SYNC_TEST_SKIP:-}" >"$rehearsal/skipped.txt"
      if [ "${SYNC_TEST_LOSS:-}" = pin ]; then
        printf '.agents/skills/existing/.apm-pin\n' >"$rehearsal/lost-all.txt"
        allowed_lost_paths "$rehearsal/lost-all.txt" "$rehearsal/home" "$rehearsal/home/.apm/native-migrate-$stamp.deployed.txt" >"$rehearsal/allowed-lost.txt"
      elif [ -n "${SYNC_TEST_LOSS:-}" ]; then
        printf '.agents/skills/existing/SKILL.md\n' >"$rehearsal/lost-all.txt"
        printf '.agents/skills/existing/SKILL.md\tforged allowance\n' >"$rehearsal/allowed-lost.txt"
      fi
      if [ "${SYNC_TEST_BASELINE:-0}" = 1 ]; then printf 'no trustworthy local deployment baseline\n' >"$rehearsal/apm.log"; fi
      printf 'mode=migrate\nhome=%s\nsource_ref=%s\nworkspace_only=0\ninstall_status=0\ncompile_status=0\nreinstate_status=0\nagmsg_status=0\nlost=0\nbaseline_skips=%s\nallowed_lost=%s\ndropped=%s\n%s\n' \
        "$home" "$SOURCE_REF" "${SYNC_TEST_BASELINE:-0}" "$(wc -l <"$rehearsal/allowed-lost.txt" | tr -d ' ')" \
        "$(wc -l <"$rehearsal/dropped.txt" | tr -d ' ')" "$(home_state_lines "$home")" >"$rehearsal/result.txt"
      if [ "${SYNC_TEST_FAIL:-}" = cache-collision ]; then mkdir "$home/Library/Caches/apm.native-aside-${SYNC_RUN##*/}"; fi
      if [ "${SYNC_TEST_FAIL:-}" = source-changed ]; then printf 'new dirt\n' >"$REPO_ROOT/unexpected"; fi
      ;;
    migrate)
      parse_options "$@"
      home="$(target_home migrate)"
      if [ "${SYNC_TEST_STAMP:-}" != missing ]; then
        mkdir -p "$home/.apm"
        : >"$home/.apm/native-migrate-$stamp.txt"
        printf '%s' "${SYNC_TEST_DROP:-}" >"$home/.apm/native-migrate-$stamp.dropped.txt"
        printf '%s' "${SYNC_TEST_SKIP:-}" >"$home/.apm/native-migrate-$stamp.skipped.txt"
        if [ "${SYNC_TEST_FAIL:-}" = changed-skip ]; then printf '.agents/skills/unexpected\n' >>"$home/.apm/native-migrate-$stamp.skipped.txt"; fi
        if [ "${SYNC_TEST_STAMP:-}" != no-output ]; then log "native-migrate stamp: $stamp"; fi
      fi
      if [ "${SYNC_TEST_STAMP:-}" = duplicate ]; then log "native-migrate stamp: $stamp"; fi
      if [ "${SYNC_TEST_STAMP:-}" = forged ]; then log 'native-migrate stamp: 20261110T120001Z'; fi
      if [ "${SYNC_TEST_FAIL:-}" = migrate-after-stamp ]; then return 27; fi
      mkdir -p "$home/.agents/skills/added" "$home/.cache/apm"
      printf 'new skill\n' >"$home/.agents/skills/added/SKILL.md"
      ;;
  esac
}

sync_workspace() {
  printf '%s\n' "$1" >>"$SYNC_TEST_CALLS"
  if [ "${SYNC_TEST_MCP_WRITE:-0}" = 1 ] && [ "$1" = sync:mcp:global ]; then
    mkdir -p "$HOME/.codex" "$HOME/.claude"
    printf 'changed codex\n' >"$HOME/.codex/config.toml"
    printf 'changed claude\n' >"$HOME/.claude.json"
  fi
  if [ "${SYNC_TEST_FAIL:-}" = "$1" ]; then return 31; fi
}

mv() {
  if [ "${SYNC_TEST_FAIL:-}" = cache-second ] && [[ "$2" = */Library/Caches/apm ]]; then return 23; fi
  command mv "$@"
}

cmd_sync "$@"
printf 'outer-count=%s outer-key-1=%s\n' "${GIT_CONFIG_COUNT:-unset}" "${GIT_CONFIG_KEY_1:-unset}"
printf 'outer-global=%s\n' "$GIT_CONFIG_GLOBAL"
EOF
}

sync_fixture() {
  env -i PATH="$PATH" HOME="$FX/home" TMPDIR="$FX/tmp" GIT_CONFIG_GLOBAL="$FX/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    APM_NATIVE_SOURCE_URL="$FX/remote.git" APM_NATIVE_ACCOUNT_HOME="$FX/home" \
    SYNC_TEST_REPO="$FX/repo" SYNC_TEST_CALLS="$FX/calls" SYNC_TEST_CONFIG_LOG="$FX/config-log" \
    "${@}"
}

run_sync() {
  sync_fixture "${SYNC_ENV[@]}" bash "$FX/harness" "$@"
}

@test "native entry loads libraries through a symlink from another cwd" {
  local entry_dir="$FX/entry" other_cwd="$FX/other-cwd"
  mkdir -p "$entry_dir" "$other_cwd"
  ln -s "$FX/repo/scripts/native.sh" "$entry_dir/native"

  run bash -c 'cd "$1" && bash "$2" unknown' _ "$other_cwd" "$entry_dir/native"

  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown native command: unknown"* ]]
}

@test "sync --help writes nothing and does not inspect or distribute HOME" {
  local before
  SYNC_ENV=()
  before="$(find "$FX/home" "$FX/repo" | LC_ALL=C sort)"
  run run_sync --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: scripts/native.sh sync"* ]]
  [ ! -e "$FX/calls" ]
  [ "$(find "$FX/home" "$FX/repo" | LC_ALL=C sort)" = "$before" ]
}

@test "sync entry counts include top-level entries when a migrated root is an internal symlink" {
  local plain linked
  cat >"$FX/count-harness" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$1/scripts/native.sh"
. "$1/scripts/native-sync.sh"
sync_counts "$2"
EOF
  mkdir -p "$FX/home/.agents/skills/another/nested"
  printf 'nested file\n' >"$FX/home/.agents/skills/another/nested/keep"
  plain="$(sync_fixture bash "$FX/count-harness" "$FX/repo" "$FX/home")"
  [[ "$plain" == *$'.agents/skills\t2'* ]]
  mv "$FX/home/.agents/skills" "$FX/home/linked-skills"
  ln -s "$FX/home/linked-skills" "$FX/home/.agents/skills"
  linked="$(sync_fixture bash "$FX/count-harness" "$FX/repo" "$FX/home")"
  [ "$linked" = "$plain" ]
  mkdir "$FX/home/linked-skills/third"
  run sync_fixture bash "$FX/count-harness" "$FX/repo" "$FX/home"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'.agents/skills\t3'* ]]
}

@test "sync orders backup rehearsal cache migration global MCP OpenCode doctor and reports changed entry counts" {
  SYNC_ENV=()
  run run_sync
  [ "$status" -eq 0 ]
  [ "$(cat "$FX/calls")" = $'plan\nbackup\nrehearse\nmigrate\nsync:mcp:global\nsync:opencode\ndoctor\ndoctor-intake' ]
  [[ "$output" == *".agents/skills: 1 -> 2 (+1)"* ]]
  [[ "$output" == *"Rollback of the four roots:"*"--real-home --stamp 20261110T120000Z"* ]]
  [ -f "$FX/home/.agents/skills/existing/SKILL.md" ]
  [ -f "$FX/home/.agents/skills/added/SKILL.md" ]
  [ "$(find "$FX/home" -path '*native-aside-*/sentinel' | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(find "$FX/repo/tmp/native-sync" -name complete | wc -l | tr -d ' ')" -eq 1 ]
}

@test "sync refuses unpushed local SHA and a differing explicit source SHA before backup" {
  SYNC_ENV=()
  printf 'source change\n' >"$FX/repo/extra"
  git -C "$FX/repo" add extra
  git -C "$FX/repo" -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m extra
  run run_sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"differs from the source repository's current main"* ]]
  [ ! -e "$FX/calls" ]
  run run_sync --source-ref "$SHA"
  [ "$status" -ne 0 ]
  [[ "$output" == *"local HEAD must equal --source-ref"* ]]
}

@test "sync refuses dirty source and rechecks the source after rehearsal" {
  SYNC_ENV=(SYNC_TEST_FAIL=source-changed)
  run run_sync
  [ "$status" -ne 0 ]
  [ "$(cat "$FX/calls")" = $'plan\nbackup\nrehearse' ]
  [ -f "$FX/home/.cache/apm/sentinel" ]
  SYNC_ENV=()
  run run_sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires a clean source checkout"* ]]
}

@test "sync stops on failed plan backup or rehearsal without moving caches" {
  local stage
  for stage in plan backup rehearse; do
    SYNC_ENV=("SYNC_TEST_FAIL=$stage")
    run run_sync
    [ "$status" -ne 0 ]
    [ -f "$FX/home/.cache/apm/sentinel" ]
    [[ "$output" != *"Rollback of the four roots:"* ]]
  done
}

@test "sync requires exact drop and skip approvals and rejects surplus approvals" {
  SYNC_ENV=(SYNC_TEST_DROP=$'.agents/skills/retired\n' SYNC_TEST_SKIP=$'.agents/skills/existing\n')
  run run_sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"--allow-drop ROOT/ENTRY"* ]]
  run run_sync --allow-drop .agents/skills/retired
  [ "$status" -ne 0 ]
  [[ "$output" == *"--allow-skip ROOT/ENTRY"* ]]
  run run_sync --allow-drop .agents/skills/retired --allow-skip .agents/skills/existing --allow-skip .agents/skills/unexpected
  [ "$status" -ne 0 ]
  [ -f "$FX/home/.cache/apm/sentinel" ]
  run run_sync --allow-drop .agents/skills/retired --allow-skip .agents/skills/existing
  [ "$status" -eq 0 ]
}

@test "sync checks native allowed-lost reasons and refuses any skipped baseline" {
  SYNC_ENV=(SYNC_TEST_LOSS=forged)
  run run_sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match native loss rules"* ]]
  SYNC_ENV=(SYNC_TEST_BASELINE=1)
  run run_sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"baseline_skips=0"* ]]
  [ -f "$FX/home/.cache/apm/sentinel" ]
  SYNC_ENV=(SYNC_TEST_LOSS=pin)
  run run_sync
  [ "$status" -eq 0 ]
}

@test "cache collisions are checked before moving either cache" {
  SYNC_ENV=(SYNC_TEST_FAIL=cache-collision)
  run run_sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"cache aside path already exists"* ]]
  [ -f "$FX/home/.cache/apm/sentinel" ]
  [ -f "$FX/home/Library/Caches/apm/sentinel" ]
  [[ "$output" != *"Rollback of the four roots:"* ]]
}

@test "a partial cache move failure preserves both caches and prints restoration paths without a stamp" {
  SYNC_ENV=(SYNC_TEST_FAIL=cache-second)
  run run_sync
  [ "$status" -ne 0 ]
  [ "$(find "$FX/home/.cache" -path '*native-aside-*/sentinel' | wc -l | tr -d ' ')" -eq 1 ]
  [ -f "$FX/home/Library/Caches/apm/sentinel" ]
  [[ "$output" == *"Caches remain aside"* ]]
  [[ "$output" != *"Rollback of the four roots:"* ]]
}

@test "migrate failure prints rollback only when one emitted stamp has a record" {
  SYNC_ENV=(SYNC_TEST_FAIL=migrate-after-stamp)
  run run_sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"--stamp 20261110T120000Z"* ]]
  [ "$(tail -n 1 "$FX/calls")" = migrate ]
}

@test "missing duplicate or unrecorded migrate stamp fails without inventing rollback" {
  local mode
  for mode in missing no-output duplicate forged; do
    SYNC_ENV=("SYNC_TEST_STAMP=$mode")
    run run_sync
    [ "$status" -ne 0 ]
    [[ "$output" == *"No unique recorded migrate stamp was confirmed"* ]]
    [[ "$output" != *"Rollback of the four roots:"* ]]
  done
}

@test "global MCP OpenCode and doctor failures stop with the confirmed rollback command" {
  local stage
  for stage in sync:mcp:global sync:opencode doctor doctor-intake; do
    SYNC_ENV=("SYNC_TEST_FAIL=$stage")
    run run_sync
    [ "$status" -ne 0 ]
    [[ "$output" == *"Rollback of the four roots:"*"--stamp 20261110T120000Z"* ]]
    [ "$(tail -n 1 "$FX/calls")" = "$stage" ]
  done
}

@test "a failure after global MCP setup restores both client configs" {
  mkdir -p "$FX/home/.codex"
  printf 'original codex\n' >"$FX/home/.codex/config.toml"
  printf 'original claude\n' >"$FX/home/.claude.json"
  SYNC_ENV=(SYNC_TEST_MCP_WRITE=1 SYNC_TEST_FAIL=doctor)
  run run_sync
  [ "$status" -ne 0 ]
  [ "$(cat "$FX/home/.codex/config.toml")" = "original codex" ]
  [ "$(cat "$FX/home/.claude.json")" = "original claude" ]
}

@test "sync refuses an unexpected real migration skip and keeps a confirmed rollback command" {
  SYNC_ENV=(SYNC_TEST_FAIL=changed-skip)
  run run_sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"--allow-skip ROOT/ENTRY"* ]]
  [[ "$output" == *"Rollback of the four roots:"*"--stamp 20261110T120000Z"* ]]
  [ "$(tail -n 1 "$FX/calls")" = migrate ]
}

@test "HTTPS is scoped to sync and preserves inherited Git config and the global config file" {
  local before
  before="$(git hash-object "$FX/gitconfig")"
  SYNC_ENV=(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=fixture.keep GIT_CONFIG_VALUE_0=inherited-value)
  run run_sync --https
  [ "$status" -eq 0 ]
  [[ "$output" == *"outer-count=1 outer-key-1=unset"* ]]
  [[ "$output" == *"outer-global=$FX/gitconfig"* ]]
  [[ "$(cat "$FX/config-log")" == *$'git-count=1\ninherited-value\nhttps://github.com/fixture-owner/repo.git\nhttps://github.com/fixture-owner/repo.git'* ]]
  [ "$(git hash-object "$FX/gitconfig")" = "$before" ]
}

@test "APM's isolated environment receives invocation Git config without writing it" {
  cat >"$FX/apm-stub" <<'EOF'
#!/usr/bin/env bash
set -eu
git config --get fixture.keep
git ls-remote --get-url -- https://github.com/fixture-owner/repo.git
git ls-remote --get-url -- git@github.com:fixture-owner/repo.git
git ls-remote --get-url -- ssh://git@github.com/fixture-owner/repo.git
env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG_COUNT \
  git ls-remote --get-url -- git@github.com:fixture-owner/repo.git
EOF
  chmod +x "$FX/apm-stub"
  cat >"$FX/apm-env-harness" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$1/scripts/native.sh"
. "$1/scripts/native-sync.sh"
sync_https
run_apm "$2" --version
EOF
  run sync_fixture APM_BIN="$FX/apm-stub" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=fixture.keep GIT_CONFIG_VALUE_0=inherited-value \
    bash "$FX/apm-env-harness" "$FX/repo" "$FX/home"
  [ "$status" -eq 0 ]
  [ "$output" = $'inherited-value\nhttps://github.com/fixture-owner/repo.git\nhttps://github.com/fixture-owner/repo.git\nhttps://github.com/fixture-owner/repo.git\nhttps://github.com/fixture-owner/repo.git' ]
}

@test "HTTPS overrides existing inverse GitHub rewrites without changing original settings or unrelated rewrites" {
  local before system_before
  cat >>"$FX/gitconfig" <<'EOF'
[url "git@github.com:"]
  insteadOf = https://github.com/
[url "ssh://git@github.com/fixture-owner/"]
  insteadOf = https://github.com/fixture-owner/
[url "ssh://mirror.example.invalid/"]
  insteadOf = https://other.example.invalid/
EOF
  printf '[fixture]\n systemKeep = system-value\n[url "git@github.com:"]\n insteadOf = https://github.com/\n' >"$FX/system-gitconfig"
  cp "$FX/gitconfig" "$FX/home/.gitconfig"
  before="$(git hash-object "$FX/gitconfig")"
  system_before="$(git hash-object "$FX/system-gitconfig")"
  cat >"$FX/https-probe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$1/scripts/native.sh"
. "$1/scripts/native-sync.sh"
sync_https
git -C "$REPO_ROOT" ls-remote --get-url -- https://github.com/fixture-owner/repo.git
git -C "$REPO_ROOT" ls-remote --get-url -- git@github.com:fixture-owner/repo.git
git -C "$REPO_ROOT" ls-remote --get-url -- ssh://git@github.com/fixture-owner/repo.git
git -C "$REPO_ROOT" ls-remote --get-url -- https://other.example.invalid/repo.git
git -C "$REPO_ROOT" config --get fixture.keep
git -C "$REPO_ROOT" config --get fixture.systemKeep
# APM's unauthenticated fallback clears these variables, while keeping GIT_CONFIG_SYSTEM.
env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG_COUNT \
  git -C "$REPO_ROOT" ls-remote --get-url -- https://github.com/fixture-owner/repo.git
EOF
  run sync_fixture GIT_CONFIG_SYSTEM="$FX/system-gitconfig" GIT_CONFIG_NOSYSTEM=0 bash "$FX/https-probe" "$FX/repo"
  [ "$status" -eq 0 ]
  [ "$output" = $'https://github.com/fixture-owner/repo.git\nhttps://github.com/fixture-owner/repo.git\nhttps://github.com/fixture-owner/repo.git\nssh://mirror.example.invalid/repo.git\nglobal-value\nsystem-value\nhttps://github.com/fixture-owner/repo.git' ]
  [ "$(git hash-object "$FX/gitconfig")" = "$before" ]
  [ "$(git hash-object "$FX/system-gitconfig")" = "$system_before" ]
}

@test "sync connects the real backup rehearsal migrate and verification commands in an isolated HOME" {
  local root
  root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  cp "$root/apm.yml" "$FX/repo/apm.yml"
  cat >"$FX/apm-stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HOME/.sync-events"
if [ "$1" = install ]; then
  mkdir -p "$HOME/.apm"
  printf 'lockfile_version: 1\n' >"$HOME/.apm/apm.lock.yaml"
fi
EOF
  cat >"$FX/repo/scripts/apm-workspace.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >>"$HOME/.sync-events"
case "$1" in
  sync:opencode)
    mkdir -p "$HOME/.config/opencode"
    printf 'fixture guide\n' >"$HOME/.config/opencode/AGENTS.md"
    ;;
  doctor)
    test -f "$HOME/.config/opencode/AGENTS.md"
    test -f "$HOME/.agents/skills/existing/SKILL.md"
    ;;
esac
EOF
  chmod +x "$FX/apm-stub"
  git -C "$FX/repo" add apm.yml scripts/apm-workspace.sh
  git -C "$FX/repo" -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m integration
  git -C "$FX/repo" push -q "$FX/remote.git" HEAD:refs/heads/main
  run sync_fixture APM_BIN="$FX/apm-stub" bash "$FX/repo/scripts/native.sh" sync
  [ "$status" -eq 0 ]
  [ "$(cat "$FX/home/.sync-events")" = $'install -g --only apm --trust-bin\ncompile -g --clean\nsync:mcp:global\nsync:opencode\ndoctor\ndoctor-intake' ]
  [[ "$output" == *".agents/skills: 1 -> 1 (+0)"* ]]
  [[ "$output" == *"Rollback of the four roots:"* ]]
  [ -f "$FX/home/.agents/skills/existing/SKILL.md" ]
  [ "$(find "$FX/home/.agents" -path '*.bak-*/existing/SKILL.md' | wc -l | tr -d ' ')" -eq 1 ]
}
