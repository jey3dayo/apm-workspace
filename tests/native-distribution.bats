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
# The fixture root is BATS_FILE_TMPDIR, or a fresh directory under APM_NATIVE_FIXTURE_ROOT when that is set.

bats_require_minimum_version 1.5.0

# docs/native-distribution.md was written against this release; bump it only after re-checking the docs.
EXPECTED_APM_VERSION=0.35.0
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

native() {
  local home="$1"
  shift
  fixture_exec "$home" /bin/bash "$REPO_ROOT/scripts/native.sh" "$@"
}

assert_apm_version() {
  local version
  version="$(fixture_exec "$(new_home version)" "$APM_BIN" --version 2>&1)" || {
    echo "apm at $APM_BIN does not run under the fixture isolation: $version" >&2
    return 1
  }
  [ "${version##* }" = "$EXPECTED_APM_VERSION" ] || {
    echo "expected APM $EXPECTED_APM_VERSION, got: $version" >&2
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

apply_workspace() {
  native "$1" apply --home "$1" --source-ref "$SOURCE_SHA" --workspace-only
}

# Everything apm can touch except caches and receipts (receipt names derive from the HOME path).
home_snapshot() {
  (cd "$1" && find . \( -path ./.apm/apm_modules -o -path ./.apm/deployment-receipts -o -path ./.cache -o -path ./Library \) -prune -o \
    \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"; else printf '%s %s\n' "$f" "$(git hash-object "$f")"; fi
  done)
}

skill_ids() {
  local dir
  for dir in "$REPO_ROOT"/catalog/.apm/skills/*/ "$REPO_ROOT"/manual-skills/.apm/skills/*/; do
    basename "$dir"
  done
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

@test "plan prints the SHA-pinned manifest and the steps, and writes nothing" {
  local home before
  home="$(new_home plan)"
  # Only this test's HOME and the source repository: other tests write their own HOMEs in parallel.
  before="$(find "$home" "$SOURCE_REPO" | LC_ALL=C sort)"
  run native "$home" plan --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"ref: $SOURCE_SHA"* ]]
  [[ "$output" == *"This plan wrote nothing."* ]]
  [ "$(find "$home" "$SOURCE_REPO" | LC_ALL=C sort)" = "$before" ]
}

@test "render pins catalog and manual-skills by SHA and keeps every external dependency and MCP server" {
  local home rendered
  home="$(new_home render)"
  rendered="$(native "$home" render --source-ref "$SOURCE_SHA")"
  [ "$(grep -c "^      ref: $SOURCE_SHA\$" <<<"$rendered")" -eq 2 ]
  [ "$(grep -c 'apm-workspace/.*#main' <<<"$rendered")" -eq 0 ]
  # Everything else in apm.yml passes through line for line.
  diff <(grep -vE 'jey3dayo/apm-workspace/(catalog|manual-skills)#main' "$REPO_ROOT/apm.yml") \
    <(sed 1d <<<"$rendered" | grep -vE "^    - git: $FIXTURE_URL\$|^      path: (catalog|manual-skills)\$|^      ref: $SOURCE_SHA\$")

  rendered="$(native "$home" render --source-ref "$SOURCE_SHA" --workspace-only)"
  [ "$(grep -c '^    - ' <<<"$rendered")" -eq 2 ]
  [ "$(grep -c '^  mcp:' <<<"$rendered")" -eq 0 ]
}

@test "apply refuses a missing HOME or ref, the account HOME, its ancestors and its tool state, before writing" {
  local home account
  home="$(new_home refuse)"
  account="$(cd "$(eval "printf '%s' ~$(id -un)")" && pwd -P)"
  run native "$home" apply --source-ref "$SOURCE_SHA"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs --home"* ]]
  run native "$home" apply --home "$home"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs --source-ref"* ]]
  run native "$home" apply --home "$account" --source-ref "$SOURCE_SHA"
  [ "$status" -ne 0 ]
  [[ "$output" == *"account's HOME"* ]]
  run native "$home" apply --home / --source-ref "$SOURCE_SHA"
  [ "$status" -ne 0 ]
  [[ "$output" == *"account's HOME"* ]]
  if [ -d "$account/.claude" ]; then
    run native "$home" apply --home "$account/.claude" --source-ref "$SOURCE_SHA"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is inside"* ]]
  fi
  [ ! -e "$home/.apm" ]
}

@test "apply deploys every workspace skill to Claude and agent-skills, agents to Claude and Cursor only, and both compiled roots" {
  local home id agent name
  home="$(new_home deploy)"
  run apply_workspace "$home"
  [ "$status" -eq 0 ]
  while IFS= read -r id; do
    for dir in "$REPO_ROOT"/catalog/.apm/skills "$REPO_ROOT"/manual-skills/.apm/skills; do
      [ -f "$dir/$id/SKILL.md" ] || continue
      cmp "$dir/$id/SKILL.md" "$home/.claude/skills/$id/SKILL.md"
      cmp "$dir/$id/SKILL.md" "$home/.agents/skills/$id/SKILL.md"
    done
  done < <(skill_ids)
  for agent in "$REPO_ROOT"/catalog/.apm/agents/*.agent.md; do
    name="$(basename "$agent" .agent.md)"
    [ -f "$home/.claude/agents/$name.md" ]
    [ -f "$home/.cursor/agents/$name.md" ]
  done
  [ ! -e "$home/.codex/agents" ]
  head -n 1 "$home/.codex/AGENTS.md" | grep -qF '<!-- Generated by APM CLI from .apm/ primitives -->'
  head -n 1 "$home/.cursor/AGENTS.md" | grep -qF '<!-- Generated by APM CLI from .apm/ primitives -->'
  grep -qF '# AI 開発協働ガイド' "$home/.codex/AGENTS.md"
  grep -q "resolved_commit: $SOURCE_SHA" "$home/.apm/apm.lock.yaml"
}

@test "rerunning apply changes nothing, and files apm does not own survive both runs" {
  local home first
  home="$(new_home rerun)"
  seed_sentinels "$home"
  local sentinels
  sentinels="$(sentinel_snapshot "$home")"
  apply_workspace "$home"
  first="$(home_snapshot "$home")"
  apply_workspace "$home"
  [ "$(home_snapshot "$home")" = "$first" ]
  [ "$(sentinel_snapshot "$home")" = "$sentinels" ]
  [ -z "$(compgen -G "$home/.apm/apm.yml.*.bak" || true)" ]
}

@test "apply stops before writing when a compiled root was edited after compile" {
  local home before
  home="$(new_home edited)"
  apply_workspace "$home"
  echo "local edit" >>"$home/.codex/AGENTS.md"
  before="$(home_snapshot "$home")"
  run apply_workspace "$home"
  [ "$status" -ne 0 ]
  [[ "$output" == *".codex/AGENTS.md"* ]]
  [ "$(home_snapshot "$home")" = "$before" ]
}

@test "apply keeps a differing manifest as a .bak before replacing it" {
  local home
  home="$(new_home backup)"
  mkdir -p "$home/.apm"
  printf 'name: earlier\nversion: 0.0.1\n' >"$home/.apm/apm.yml"
  apply_workspace "$home"
  run cat "$home"/.apm/apm.yml.*.bak
  [ "$output" = $'name: earlier\nversion: 0.0.1' ]
  grep -q "ref: $SOURCE_SHA" "$home/.apm/apm.yml"

  # Compared byte for byte: a manifest that differs only in trailing newlines is kept too.
  home="$(new_home backup-newline)"
  mkdir -p "$home/.apm"
  native "$home" render --source-ref "$SOURCE_SHA" --workspace-only >"$home/.apm/apm.yml"
  printf '\n' >>"$home/.apm/apm.yml"
  apply_workspace "$home"
  [ "$(compgen -G "$home/.apm/apm.yml.*.bak" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "every catalog file APM does not deploy is listed in the manual distribution table" {
  local f missing=""
  while IFS= read -r f; do
    grep -qF "\`$f\`" "$REPO_ROOT/docs/native-distribution.md" || missing+=" $f"
  done < <(cd "$REPO_ROOT" && git ls-files catalog | grep -vE '^catalog/(\.apm/|apm\.yml$|README\.md$)|/\.gitkeep$')
  [ -z "$missing" ] || {
    echo "not listed in docs/native-distribution.md:$missing" >&2
    return 1
  }
}

@test "apply refuses a HOME whose write targets link outside it, before writing through them" {
  local home outside="$FX/outside"
  mkdir -p "$outside/apm-dir" "$outside/ship"
  home="$(new_home link-apm)"
  ln -s "$outside/apm-dir" "$home/.apm"
  run apply_workspace "$home"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$home/.apm -> $outside/apm-dir"* ]]
  [ -z "$(ls -A "$outside/apm-dir")" ]

  home="$(new_home link-root)"
  mkdir -p "$home/.codex"
  ln -s "$outside/root.md" "$home/.codex/AGENTS.md"
  run apply_workspace "$home"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$home/.codex/AGENTS.md (broken)"* ]]
  [ ! -e "$outside/root.md" ]

  # Any depth counts: apm resolves cache paths such as Library/Caches/apm, not only the deploy roots.
  home="$(new_home link-deep)"
  mkdir -p "$home/Library/Caches" "$home/.claude/skills"
  ln -s "$outside/ship" "$home/Library/Caches/apm"
  ln -s "$outside/ship" "$home/.claude/skills/ship"
  run apply_workspace "$home"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$home/Library/Caches/apm -> $outside/ship"* ]]
  [[ "$output" == *"$home/.claude/skills/ship -> $outside/ship"* ]]
  [ -z "$(ls -A "$outside/ship")" ]
  [ ! -e "$home/.apm" ]
}

@test "apply hides APM_CACHE_DIR and XDG locations from apm, which would otherwise write there" {
  local home var
  # Positive controls, one variable each: apm itself follows them out of HOME.
  for var in APM_CACHE_DIR XDG_CACHE_HOME; do
    home="$(new_home "control-$var")"
    mkdir -p "$home/.apm"
    native "$home" render --source-ref "$SOURCE_SHA" --workspace-only >"$home/.apm/apm.yml"
    fixture_exec "$home" /usr/bin/env "$var=$FX/leak/control-$var" "$APM_BIN" install -g >/dev/null 2>&1 || true
    [ -n "$(ls -A "$FX/leak/control-$var" 2>/dev/null)" ]
  done

  home="$(new_home env-apply)"
  fixture_exec "$home" /usr/bin/env APM_CACHE_DIR="$FX/leak/apply-apm" XDG_CACHE_HOME="$FX/leak/apply-xdg" \
    XDG_CONFIG_HOME="$FX/leak/apply-config" /bin/bash "$REPO_ROOT/scripts/native.sh" \
    apply --home "$home" --source-ref "$SOURCE_SHA" --workspace-only
  [ ! -e "$FX/leak/apply-apm" ]
  [ ! -e "$FX/leak/apply-xdg" ]
  [ ! -e "$FX/leak/apply-config" ]
  [ -f "$home/.claude/skills/ship/SKILL.md" ]
}

@test "apply refuses hard-linked write targets and a temp_dir override, and leaves the linked file alone" {
  local home outside="$FX/outside-hardlink"
  mkdir -p "$outside"
  printf 'real manifest\n' >"$outside/apm.yml"
  home="$(new_home hardlink)"
  mkdir -p "$home/.apm"
  ln "$outside/apm.yml" "$home/.apm/apm.yml"
  run apply_workspace "$home"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$home/.apm/apm.yml (hard link)"* ]]
  [ "$(cat "$outside/apm.yml")" = "real manifest" ]

  # Escaped the way JSON allows, so only a decoder sees the key apm reads.
  home="$(new_home temp-dir-config)"
  mkdir -p "$home/.apm"
  printf '{"default_client": "vscode", "temp\\u005fdir": "%s"}\n' "$outside" >"$home/.apm/config.json"
  run apply_workspace "$home"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sets temp_dir"* ]]
  [ ! -e "$home/.apm/apm.yml" ]
}

@test "apm sees only the allowlisted environment, with TMPDIR inside the HOME" {
  local home stub="$FX/stub-apm"
  home="$(new_home env-stub)"
  printf '#!/bin/sh\nenv >>"$HOME/apm-env.log"\n' >"$stub"
  chmod +x "$stub"
  fixture_exec "$home" /usr/bin/env APM_BIN="$stub" TMPDIR="$FX/caller-tmp" APM_CACHE_DIR="$FX/caller-cache" \
    XDG_STATE_HOME="$FX/caller-state" GITHUB_TOKEN=fixture-token /bin/bash "$REPO_ROOT/scripts/native.sh" \
    apply --home "$home" --source-ref "$SOURCE_SHA" --workspace-only
  # One block per apm call (install, compile).
  [ "$(grep -c '^HOME=' "$home/apm-env.log")" -eq 2 ]
  [ "$(grep -c "^TMPDIR=$home/.cache/apm-native-tmp\$" "$home/apm-env.log")" -eq 2 ]
  [ "$(grep -cE '^(APM_CACHE_DIR|XDG_STATE_HOME|GITHUB_TOKEN)=' "$home/apm-env.log")" -eq 0 ]
  # ssh would otherwise read its config from, and add host keys to, the account HOME.
  [ "$(grep -c "^GIT_SSH_COMMAND=ssh -F /dev/null -o UserKnownHostsFile=$home/.ssh/known_hosts" "$home/apm-env.log")" -eq 2 ]
}

@test "a lone carriage return inserted into a compiled root counts as an edit, as it does for APM" {
  local home
  home="$(new_home edited-cr)"
  apply_workspace "$home"
  python3 - "$home/.codex/AGENTS.md" <<'PY'
import sys
p = sys.argv[1]
data = open(p, "rb").read()
i = data.index(b"# AI")
open(p, "wb").write(data[: i + 4] + b"\r" + data[i + 4 :])
PY
  run apply_workspace "$home"
  [ "$status" -ne 0 ]
  [[ "$output" == *".codex/AGENTS.md"* ]]
}


# backup and rehearse accept the account's own HOME; the fixture HOME stands in for it through APM_NATIVE_ACCOUNT_HOME.
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

@test "apply --real-home is blocked with or without a backup, as is --home inside the account HOME under the test override, and writes nothing" {
  local home before listing backup="$FX/backups/blocked" surface=""
  for surface in .cache .config .local; do
    surface="$(eval "printf '%s' ~$(id -un)")/$surface"
    [ -d "$surface" ] && break
  done
  home="$(new_home real-blocked)"
  seed_sentinels "$home"
  before="$(backed_up_snapshot "$home")"
  listing="$(find "$home" | LC_ALL=C sort)"

  run real_native "$home" apply --real-home --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocked"* ]]
  [[ "$output" == *"docs/native-distribution.md"* ]]

  real_native "$home" backup --real-home --backup-dir "$backup"
  run real_native "$home" apply --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocked"* ]]
  [[ "$output" == *"docs/native-distribution.md"* ]]

  run real_native "$home" apply --home "$surface" --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"is inside"* ]]

  [ "$(backed_up_snapshot "$home")" = "$before" ]
  [ "$(find "$home" | LC_ALL=C sort)" = "$listing" ]
  [ ! -e "$home/.apm/apm.yml" ]
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
  grep -qxF "lost=0" "$result"
  grep -qxF "install_status=0" "$result"
  grep -qxF "compile_status=0" "$result"
  [ "$(backed_up_snapshot "$home")" = "$before" ]
  [ "$(readlink "$home/.agents/skills/agmsg/db")" = "$home/.local/state/agmsg/db" ]
}

@test "a rehearsal that loses a deployed file fails, lists it and leaves the HOME alone" {
  local home before backup="$FX/backups/real-lost" lost
  home="$(new_home real-lost)"
  seed_sentinels "$home"
  mkdir -p "$home/.claude/skills/victim"
  echo "deployed by an earlier apply" >"$home/.claude/skills/victim/SKILL.md"
  before="$(backed_up_snapshot "$home")"
  real_native "$home" backup --real-home --backup-dir "$backup"
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nrm -f "$HOME/.claude/skills/victim/SKILL.md"\n' >"$FX/stub-apm-deletes"
  chmod +x "$FX/stub-apm-deletes"

  run real_native_with_stub "$home" "$FX/stub-apm-deletes" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -eq 1 ]
  [[ "$output" == *"lost.txt"* ]]
  [[ "$output" == *".claude/skills/victim/SKILL.md"* ]]
  lost="$(grep -lxF ".claude/skills/victim/SKILL.md" "$backup"/rehearsal-*/lost.txt)"
  [ "$(wc -l <<<"$lost" | tr -d ' ')" -eq 1 ]
  grep -qxF "lost=1" "$(dirname "$lost")/result.txt"
  [ "$(backed_up_snapshot "$home")" = "$before" ]
  [ -f "$home/.claude/skills/victim/SKILL.md" ]
}

@test "rehearse copies the target of a relative link that leaves the backed-up paths, so losing it would count" {
  local home backup="$FX/backups/real-rehearse-rel" scratch
  home="$(new_home real-rehearse-rel)"
  mkdir -p "$home/src/local-skill" "$home/.claude/skills"
  echo "local skill" >"$home/src/local-skill/SKILL.md"
  ln -s ../../src/local-skill "$home/.claude/skills/local"
  real_native "$home" backup --real-home --backup-dir "$backup"
  printf '#!/bin/sh\nexit 0\n' >"$FX/stub-apm-noop-rel"
  chmod +x "$FX/stub-apm-noop-rel"

  real_native_with_stub "$home" "$FX/stub-apm-noop-rel" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  scratch="$(compgen -G "$backup/rehearsal-*/home")"
  [ ! -L "$scratch/.claude/skills/local" ]
  [ "$(cat "$scratch/.claude/skills/local/SKILL.md")" = "local skill" ]
  grep -qxF ".claude/skills/local/SKILL.md" "$(dirname "$scratch")/before.txt"
  [ "$(readlink "$home/.claude/skills/local")" = "../../src/local-skill" ]
}

@test "rehearse points the agmsg links into the scratch HOME and leaves the real store alone" {
  local home backup="$FX/backups/real-rehearse-agmsg" scratch store_before
  home="$(new_home real-rehearse-agmsg)"
  seed_agmsg "$home"
  real_native "$home" backup --real-home --backup-dir "$backup"
  store_before="$(cd "$home/.local/state/agmsg" && find . | LC_ALL=C sort)"
  printf '#!/bin/sh\nexit 0\n' >"$FX/stub-apm-noop-agmsg"
  chmod +x "$FX/stub-apm-noop-agmsg"

  real_native_with_stub "$home" "$FX/stub-apm-noop-agmsg" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  scratch="$(compgen -G "$backup/rehearsal-*/home")"
  [ "$(readlink "$scratch/.agents/skills/agmsg/db")" = "$scratch/.local/state/agmsg/db" ]
  [ "$(readlink "$scratch/.agents/skills/agmsg/teams")" = "$scratch/.local/state/agmsg/teams" ]
  [ "$(cat "$scratch/.local/state/agmsg/db/keep")" = "db store" ]
  [ "$(readlink "$home/.agents/skills/agmsg/db")" = "$home/.local/state/agmsg/db" ]
  [ "$(cd "$home/.local/state/agmsg" && find . | LC_ALL=C sort)" = "$store_before" ]
}

@test "rehearse accepts a config.json holding only default_client and prefer_ssh and reproduces it" {
  local home backup="$FX/backups/real-config-ok" stub="$FX/stub-apm-config-ok" scratch
  home="$(new_home real-config-ok)"
  mkdir -p "$home/.apm"
  printf '{"default_client": "vscode", "prefer_ssh": true}\n' >"$home/.apm/config.json"
  printf '#!/bin/sh\nexit 0\n' >"$stub"
  chmod +x "$stub"
  real_native "$home" backup --real-home --backup-dir "$backup"
  cmp "$home/.apm/config.json" "$backup/home/.apm/config.json"
  real_native_with_stub "$home" "$stub" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  scratch="$(compgen -G "$backup/rehearsal-*/home")"
  cmp "$home/.apm/config.json" "$scratch/.apm/config.json"
}

@test "a config.json with temp_dir, in the HOME or in the backup copy, refuses rehearse before install runs" {
  local home backup called="$FX/stub-apm-config-called" stub="$FX/stub-apm-config-bad"
  printf '#!/bin/sh\nif [ "$1" = install ]; then echo called >>"%s"; fi\nexit 0\n' "$called" >"$stub"
  chmod +x "$stub"
  local bad='{"default_client": "vscode", "temp_dir": "/elsewhere"}'
  local good='{"default_client": "vscode"}'

  # The HOME gained temp_dir after the backup: rehearse refuses on the HOME itself.
  home="$(new_home real-config-home)"
  backup="$FX/backups/real-config-home"
  mkdir -p "$home/.apm"
  printf '%s\n' "$good" >"$home/.apm/config.json"
  real_native "$home" backup --real-home --backup-dir "$backup"
  printf '%s\n' "$bad" >"$home/.apm/config.json"
  run real_native_with_stub "$home" "$stub" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"sets temp_dir"* ]]
  [ -z "$(compgen -G "$backup/rehearsal-*" || true)" ]

  # The backup holds temp_dir while the HOME does not: rehearse refuses on the scratch copy.
  home="$(new_home real-config-backup)"
  backup="$FX/backups/real-config-backup"
  mkdir -p "$home/.apm"
  printf '%s\n' "$good" >"$home/.apm/config.json"
  real_native "$home" backup --real-home --backup-dir "$backup"
  printf '%s\n' "$bad" >"$backup/home/.apm/config.json"
  run real_native_with_stub "$home" "$stub" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"sets temp_dir"* ]]
  [ ! -e "$called" ]
}
