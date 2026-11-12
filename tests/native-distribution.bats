#!/usr/bin/env bats
#
# Runs scripts/native.sh with the real APM CLI against a disposable HOME. The authoring source is a fixture git
# repository holding this checkout's catalog/ and manual-skills/, reached through a host that cannot resolve
# (fixture.invalid) which the fixture's git config redirects to the local repository. docs/native-distribution.md
# records what is native and what stays manual.
#
# Every call gets `env -i` and a HOME under the fixture root. Where sandbox-exec exists (macOS) a profile also
# denies network access and writes outside the fixture root; elsewhere the HOME guards are the only protection.
#
# Shared source setup lives under BATS_FILE_TMPDIR or APM_NATIVE_FIXTURE_ROOT; mutable fixtures are per test.

bats_require_minimum_version 1.5.0

FIXTURE_URL=https://fixture.invalid/fixture-owner/apm-workspace.git

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
  # shellcheck source=../scripts/lib/git-test-env.sh
  . "$REPO_ROOT/scripts/lib/git-test-env.sh"
  apm_isolate_git_env

  REAL_HOME="$(cd "$HOME" && pwd -P)"
  export REAL_HOME
  if [ -n "${APM_NATIVE_FIXTURE_ROOT:-}" ]; then
    assert_fixture_root_allowed "$APM_NATIVE_FIXTURE_ROOT" || return 1
    mkdir -p "$APM_NATIVE_FIXTURE_ROOT"
    FX="$(cd "$(mktemp -d "$APM_NATIVE_FIXTURE_ROOT/run.XXXXXX")" && pwd -P)"
  else
    FX="$(cd "$BATS_FILE_TMPDIR" && pwd -P)"
  fi
  export FX
  assert_fixture_root_allowed "$FX" || return 1
  mkdir -p "$FX/tmp" "$FX/homes"

  APM_BIN="$(resolve_apm_bin)" || return 1
  export APM_BIN
  FIXTURE_PATH="$(dirname "$APM_BIN"):$(dirname "$(command -v git)"):/usr/bin:/bin:/usr/sbin:/sbin"
  export FIXTURE_PATH

  SANDBOX_EXEC=""
  if command -v sandbox-exec >/dev/null 2>&1; then
    SANDBOX_EXEC="$(command -v sandbox-exec)"
    write_sandbox_profile "$FX/sandbox.sb"
    assert_sandbox_confines_writes || return 1
  fi
  export SANDBOX_EXEC

  assert_apm_version || return 1
  build_source_repo "$FX/src/apm-workspace"
  printf '[url "file://%s"]\n\tinsteadOf = %s\n[protocol "file"]\n\tallow = always\n' "$SOURCE_REPO" "$FIXTURE_URL" >"$FX/gitconfig"
}

setup() {
  local file_fx="$FX"
  FX="$file_fx/tests/$BATS_TEST_NUMBER"
  mkdir -p "$FX/tmp" "$FX/homes"
  cp "$file_fx/gitconfig" "$FX/gitconfig"
  if [ -n "$SANDBOX_EXEC" ]; then
    write_sandbox_profile "$FX/sandbox.sb"
  fi
}

physical_path() {
  local path="$1" rest=""
  while [ ! -d "$path" ]; do
    rest="/$(basename "$path")$rest"
    path="$(dirname "$path")"
  done
  printf '%s%s\n' "$(cd "$path" && pwd -P)" "$rest"
}

# A scratch directory inside HOME is fine; HOME itself, its ancestors and real tool state are not.
assert_fixture_root_allowed() {
  local root surface prefix
  case "/$1/" in
    */../*) echo "the fixture root $1 must not contain '..'" >&2 && return 1 ;;
  esac
  root="$(physical_path "$1")"
  case "$REAL_HOME/" in
    "${root%/}/"*) echo "the fixture root $root must not be the invoking HOME or contain it" >&2 && return 1 ;;
  esac
  for surface in .apm .claude .codex .cursor .agents .config .cache .local Library; do
    for prefix in "$REAL_HOME/$surface/" "$(physical_path "$REAL_HOME/$surface")/"; do
      case "$root/" in
        "$prefix"*) echo "the fixture root $root must not be inside $REAL_HOME/$surface" >&2 && return 1 ;;
      esac
    done
  done
}

resolve_apm_bin() {
  local bin
  bin="$(command -v apm)" || {
    echo "apm is not on PATH; mise.toml pins it (pipx:apm-cli)" >&2
    return 1
  }
  case "$bin" in
    */shims/*) bin="$(mise which apm)" || return 1 ;;
  esac
  printf '%s\n' "$bin"
}

write_sandbox_profile() {
  cat >"$1" <<EOF
(version 1)
(allow default)
(deny network*)
(deny file-write*)
(allow file-write* (subpath "$FX") (literal "/dev/null") (literal "/dev/tty"))
EOF
}

# Fail closed: a sandbox that lets a write escape the fixture root would also let apm write to the real HOME.
assert_sandbox_confines_writes() {
  local probe="$FX.outside-probe" err
  "$SANDBOX_EXEC" -f "$FX/sandbox.sb" /usr/bin/touch "$probe" 2>/dev/null
  if [ -e "$probe" ]; then
    rm -f "$probe"
    echo "sandbox-exec did not block a write outside the fixture" >&2
    return 1
  fi
  err="$("$SANDBOX_EXEC" -f "$FX/sandbox.sb" /usr/bin/touch "$FX/tmp/inside-probe" 2>&1)" || {
    echo "sandbox-exec could not run a write inside the fixture (an enclosing sandbox?): $err" >&2
    return 1
  }
}

# A fresh HOME. The version-check stamp keeps apm from asking GitHub for a newer release.
new_home() {
  local home="$FX/homes/$1"
  mkdir -p "$home/.cache/apm"
  touch "$home/.cache/apm/last_version_check"
  printf '%s\n' "$home"
}

# No inherited environment (tokens, proxies, askpass, SSH agent), git reading only the fixture's global config, and
# the sandbox when there is one. HOME must be a direct child of $FX/homes.
fixture_exec() {
  local home
  home="$(cd "$1" 2>/dev/null && pwd -P)" || {
    echo "refusing to run with HOME=$1: not an existing directory" >&2
    return 97
  }
  shift
  case "$home" in
    "$FX"/homes/*/*) echo "refusing to run with HOME=$home: not a direct child of $FX/homes" >&2 && return 97 ;;
    "$FX"/homes/?*) ;;
    *) echo "refusing to run with HOME=$home outside the fixture" >&2 && return 97 ;;
  esac
  [ "$home" != "$REAL_HOME" ] || return 97
  local cmd=(env -i HOME="$home" TMPDIR="$FX/tmp" PATH="$FIXTURE_PATH" LANG="${LANG:-C.UTF-8}" PYTHONUTF8=1
    GIT_CONFIG_GLOBAL="$FX/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$FX"
    APM_BIN="$APM_BIN" APM_NATIVE_SOURCE_URL="$FIXTURE_URL")
  if [ -n "$SANDBOX_EXEC" ]; then
    cmd+=("$SANDBOX_EXEC" -f "$FX/sandbox.sb")
  fi
  (cd "$home" && "${cmd[@]}" "$@")
}

assert_apm_version() {
  local version
  version="$(fixture_exec "$(new_home version)" "$APM_BIN" --version 2>&1)" || {
    echo "apm at $APM_BIN does not run under the fixture isolation: $version" >&2
    return 1
  }
}

# The source repository holds this checkout's packages as they are now (committed or not), in one commit.
build_source_repo() {
  SOURCE_REPO="$1"
  mkdir -p "$SOURCE_REPO" "$FX/empty-git-template"
  cp -R "$REPO_ROOT/catalog" "$REPO_ROOT/manual-skills" "$SOURCE_REPO/"
  fixture_exec "$(new_home author)" /usr/bin/env GIT_TEMPLATE_DIR="$FX/empty-git-template" \
    GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' /bin/sh -c '
    cd "$1" && git init -q -b main && git add catalog manual-skills &&
      git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m source' sh "$SOURCE_REPO" || return 1
  SOURCE_SHA="$(git -C "$SOURCE_REPO" rev-parse HEAD)"
  export SOURCE_REPO SOURCE_SHA
}

seed_sentinels() {
  local home="$1"
  mkdir -p "$home/.claude/skills/private-copy" "$home/.agents/skills/herdr-automations" "$home/.codex" \
    "$home/.config/opencode" "$home/private-skills/private-link"
  echo "private copy" >"$home/.claude/skills/private-copy/SKILL.md"
  echo "private link target" >"$home/private-skills/private-link/SKILL.md"
  ln -s "$home/private-skills/private-link" "$home/.claude/skills/private-link"
  echo "tool-owned" >"$home/.agents/skills/herdr-automations/SKILL.md"
  echo 'model = "fixture"' >"$home/.codex/config.toml"
  echo '{"fixture": true}' >"$home/.claude/settings.json"
  echo "hand-written root" >"$home/.claude/CLAUDE.md"
  echo "opencode guide" >"$home/.config/opencode/AGENTS.md"
  echo "pi guide" >"$home/AGENTS.md"
}

sentinel_snapshot() {
  (cd "$1" && for f in .claude/skills/private-copy/SKILL.md .claude/skills/private-link .claude/skills/private-link/SKILL.md \
    .agents/skills/herdr-automations/SKILL.md .codex/config.toml .claude/settings.json .claude/CLAUDE.md \
    .config/opencode/AGENTS.md AGENTS.md; do
    if [ -L "$f" ]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"; else printf '%s %s\n' "$f" "$(git hash-object "$f")"; fi
  done)
}

real_native() {
  local home="$1"
  shift
  fixture_exec "$home" /usr/bin/env APM_NATIVE_ACCOUNT_HOME="$home" /bin/bash "$REPO_ROOT/scripts/native.sh" "$@"
}

real_native_with_stub() {
  local home="$1" stub="$2"
  shift 2
  fixture_exec "$home" /usr/bin/env APM_NATIVE_ACCOUNT_HOME="$home" APM_BIN="$stub" /bin/bash "$REPO_ROOT/scripts/native.sh" "$@"
}

backed_up_snapshot() {
  local path
  (cd "$1" && for path in .apm/apm.yml .apm/config.json .apm/apm.lock.yaml .apm/deployment-receipts .claude/skills .claude/agents .claude/rules .claude/commands \
    .claude/CLAUDE.md .codex/AGENTS.md .codex/rules .cursor/agents .cursor/rules .cursor/AGENTS.md .agents/skills \
    AGENTS.md .config/opencode/AGENTS.md; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    find "$path" \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r f; do
      if [ -L "$f" ]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"; else printf '%s %s\n' "$f" "$(git hash-object "$f")"; fi
    done
  done)
}

seed_agmsg() {
  local home="$1" name
  mkdir -p "$home/.agents/skills/agmsg"
  echo "agmsg skill" >"$home/.agents/skills/agmsg/SKILL.md"
  for name in db teams; do
    mkdir -p "$home/.local/state/agmsg/$name"
    echo "$name store" >"$home/.local/state/agmsg/$name/keep"
    ln -s "$home/.local/state/agmsg/$name" "$home/.agents/skills/agmsg/$name"
  done
}

roots_snapshot() {
  local home="$1" suffix="${2:-}" root f
  for root in .agents/skills .claude/skills .claude/agents .cursor/agents; do
    [ -e "$home/$root$suffix" ] || [ -L "$home/$root$suffix" ] || continue
    (cd "$home" && find "$root$suffix" \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r f; do
      if [ -L "$f" ]; then
        printf '%s -> %s\n' "$root${f#"$root$suffix"}" "$(readlink "$f")"
      else
        printf '%s %s\n' "$root${f#"$root$suffix"}" "$(git hash-object "$f")"
      fi
    done)
  done
}

seed_migrate_home() {
  local home="$1"
  seed_sentinels "$home"
  seed_agmsg "$home"
  mkdir -p "$home/.claude/skills/foo" "$home/.claude/agents" "$home/.cursor/agents"
  echo "old foo" >"$home/.claude/skills/foo/SKILL.md"
  echo "pin" >"$home/.claude/skills/foo/.apm-pin"
  echo "agent" >"$home/.claude/agents/my-agent.md"
  echo "cursor agent" >"$home/.cursor/agents/my-agent.md"
}

write_deploy_stub() {
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nmkdir -p "$HOME/.claude/skills/foo"\necho "deployed by apm" >"$HOME/.claude/skills/foo/SKILL.md"\n' >"$1"
  chmod +x "$1"
}

prepare_migrate() {
  local name="$1" stub="$2"
  M_HOME="$(new_home "$name")"
  M_BACKUP="$FX/backups/$name"
  seed_migrate_home "$M_HOME"
  real_native "$M_HOME" backup --real-home --backup-dir "$M_BACKUP"
  if [ "$stub" = real ]; then
    real_native "$M_HOME" rehearse --real-home --backup-dir "$M_BACKUP" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  else
    real_native_with_stub "$M_HOME" "$stub" rehearse --real-home --backup-dir "$M_BACKUP" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  fi
  M_REHEARSAL="$(dirname "$(compgen -G "$M_BACKUP/rehearsal-*/result.txt")")"
}

@test "backup copies the backed-up paths and the agmsg store, refuses to overwrite, and a clean rehearse loses nothing" {
  local home before backup="$FX/backups/real-clean" result
  home="$(new_home real-clean)"
  seed_sentinels "$home"
  seed_agmsg "$home"
  before="$(backed_up_snapshot "$home")"

  real_native "$home" backup --real-home --backup-dir "$backup"
  [ -f "$backup/complete" ]
  [ "$(cat "$backup/agmsg-state/db/keep")" = "db store" ]
  run real_native "$home" backup --real-home --backup-dir "$backup"
  [ "$status" -ne 0 ]
  [[ "$output" == *"never overwritten"* ]]

  real_native "$home" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  result="$(compgen -G "$backup/rehearsal-*/result.txt")"
  grep -qxF "mode=plain" "$result"
  grep -qxF "lost=0" "$result"
  grep -qxF "install_status=0" "$result"
  grep -qxF "compile_status=0" "$result"
  [ "$(backed_up_snapshot "$home")" = "$before" ]
  [ "$(readlink "$home/.agents/skills/agmsg/db")" = "$home/.local/state/agmsg/db" ]
}

@test "migrate keeps what apm does not deploy, leaves config.toml and settings.json alone, and migrate-rollback restores the roots byte for byte" {
  local stamp original sentinels listing_bak rollback_command
  prepare_migrate migrate-roundtrip real
  original="$(roots_snapshot "$M_HOME")"
  sentinels="$(sentinel_snapshot "$M_HOME")"
  [ -n "$original" ]

  run real_native "$M_HOME" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -eq 0 ]
  stamp="$(printf '%s\n' "$output" | tail -n 1)"
  [[ "$stamp" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
  printf -v rollback_command 'bash %q migrate-rollback %q %q %q' "$REPO_ROOT/scripts/native.sh" --real-home --stamp "$stamp"
  [[ "$output" == *"$rollback_command"* ]]
  grep -q "ref: $SOURCE_SHA" "$M_HOME/.apm/apm.yml"

  # apm deployed the workspace skills; what it does not own came back from the moved-aside roots.
  [ -f "$M_HOME/.claude/skills/ship/SKILL.md" ]
  [ -f "$M_HOME/.agents/skills/ship/SKILL.md" ]
  [ "$(cat "$M_HOME/.claude/skills/private-copy/SKILL.md")" = "private copy" ]
  [ ! -L "$M_HOME/.claude/skills/private-link" ]
  [ "$(cat "$M_HOME/.claude/skills/private-link/SKILL.md")" = "private link target" ]
  [ "$(cat "$M_HOME/.agents/skills/herdr-automations/SKILL.md")" = "tool-owned" ]
  [ "$(cat "$M_HOME/.claude/agents/my-agent.md")" = "agent" ]
  [ "$(cat "$M_HOME/.cursor/agents/my-agent.md")" = "cursor agent" ]
  [ "$(readlink "$M_HOME/.agents/skills/agmsg/db")" = "$M_HOME/.local/state/agmsg/db" ]
  [ "$(cat "$M_HOME/.local/state/agmsg/db/keep")" = "db store" ]
  [ "$(sentinel_snapshot "$M_HOME" | grep -E 'config.toml|settings.json')" = "$(grep -E 'config.toml|settings.json' <<<"$sentinels")" ]
  # The moved-aside roots are the originals, and the record lists them.
  [ "$(roots_snapshot "$M_HOME" ".bak-$stamp")" = "$original" ]
  [ "$(grep -c '^moved' "$M_HOME/.apm/native-migrate-$stamp.txt")" -eq 4 ]

  real_native "$M_HOME" migrate-rollback --real-home --stamp "$stamp"
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  [ "$(sentinel_snapshot "$M_HOME")" = "$sentinels" ]
  [ -f "$M_HOME/.claude/skills.native-$stamp/ship/SKILL.md" ]
  [ -z "$(compgen -G "$M_HOME/.claude/skills.bak-*" || true)" ]
  [ "$(readlink "$M_HOME/.agents/skills/agmsg/db")" = "$M_HOME/.local/state/agmsg/db" ]

  # A second rollback finds every root already restored and changes nothing.
  listing_bak="$(find "$M_HOME" | LC_ALL=C sort)"
  run real_native "$M_HOME" migrate-rollback --real-home --stamp "$stamp"
  [ "$status" -eq 0 ]
  [ "$(find "$M_HOME" | LC_ALL=C sort)" = "$listing_bak" ]
}

@test "migrate rolls the roots back when a step fails, and fails when config.toml or settings.json would change" {
  local stub="$FX/stub-apm-deploy" fail_compile="$FX/stub-apm-fail-compile" touch_config="$FX/stub-apm-touch-config"
  local original
  write_deploy_stub "$stub"
  printf '#!/bin/sh\n[ "$1" = install ] || exit 1\nmkdir -p "$HOME/.claude/skills/foo"\necho "deployed by apm" >"$HOME/.claude/skills/foo/SKILL.md"\n' >"$fail_compile"
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nmkdir -p "$HOME/.claude/skills/foo"\necho "deployed by apm" >"$HOME/.claude/skills/foo/SKILL.md"\necho changed >>"$HOME/.claude/settings.json"\n' >"$touch_config"
  chmod +x "$fail_compile" "$touch_config"

  prepare_migrate migrate-fail-compile "$stub"
  original="$(roots_snapshot "$M_HOME")"
  run real_native_with_stub "$M_HOME" "$fail_compile" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"rolling the roots back"* ]]
  [[ "$output" == *"~/.apm.checkout-<UTC>"* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  [ -z "$(compgen -G "$M_HOME/.claude/skills.bak-*" || true)" ]
  [ "$(cat "$M_HOME"/.claude/skills.native-*/foo/SKILL.md)" = "deployed by apm" ]
  [ "$(readlink "$M_HOME/.agents/skills/agmsg/db")" = "$M_HOME/.local/state/agmsg/db" ]

  prepare_migrate migrate-touch-config "$stub"
  original="$(roots_snapshot "$M_HOME")"
  chmod 600 "$M_HOME/.claude/settings.json"
  run real_native_with_stub "$M_HOME" "$touch_config" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"migrate changed these files"* ]]
  [[ "$output" == *".claude/settings.json"* ]]
  [[ "$output" != *'"fixture"'* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  # The file is back to what it was, with its permissions; what migrate left is kept beside it.
  [ "$(cat "$M_HOME/.claude/settings.json")" = '{"fixture": true}' ]
  [ "$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$M_HOME/.claude/settings.json")" = 0o600 ]
  [ "$(tail -n 1 "$M_HOME"/.claude/settings.json.changed-*)" = "changed" ]
  [ "$(cat "$M_HOME/.codex/config.toml")" = 'model = "fixture"' ]
  [ -z "$(compgen -G "$M_HOME/.apm/native-migrate-*.untouched" || true)" ]
}
