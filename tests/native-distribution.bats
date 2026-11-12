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

load 'native-test-helpers'

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

# The guide as the script writes it into a root, taken from the script's own function.
catalog_guide_body() {
  APM_WORKSPACE_DIR="$REPO_ROOT" /bin/bash -c '. "$1" && catalog_instructions_body "$(tracked_catalog_instructions_path)"' _ "$REPO_ROOT/scripts/apm-workspace.sh"
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

@test "removed apply, opencode and reinstate commands are unknown" {
  local home command
  home="$(new_home removed-commands)"
  for command in apply opencode reinstate; do
    run native "$home" "$command"
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown native command: $command"* ]]
  done
}

@test "render pins catalog and manual-skills by SHA, converts yomiyasu to the structured form, and keeps every other external dependency and MCP server" {
  local home rendered yomiyasu_sha
  home="$(new_home render)"
  rendered="$(native "$home" render --source-ref "$SOURCE_SHA")"
  [ "$(grep -c "^      ref: $SOURCE_SHA\$" <<<"$rendered")" -eq 2 ]
  [ "$(grep -c 'apm-workspace/.*#main' <<<"$rendered")" -eq 0 ]

  # The SHA comes from the line of the root manifest.
  yomiyasu_sha="$(sed -n 's|^    - nanaism/yomiyasu/skills/yomiyasu#\([0-9a-f]\{40\}\).*|\1|p' "$REPO_ROOT/apm.yml")"
  [ -n "$yomiyasu_sha" ]
  [ "$(grep -c 'nanaism/yomiyasu/skills/yomiyasu' <<<"$rendered")" -eq 0 ]

  # browser-harness is pinned in the virtual-subdirectory form, which apm deploys as the one skill (the repo-root form
  # deploys the whole upstream repository as a Codex plugin skill); render passes the line through unchanged.
  [ "$(grep -c 'browser-use/browser-harness' "$REPO_ROOT/apm.yml")" -eq 1 ]
  [ "$(grep -E '^    - browser-use/browser-harness/skills/browser-harness#[0-9a-f]{40}( |$)' "$REPO_ROOT/apm.yml")" = "$(grep 'browser-use/browser-harness' <<<"$rendered")" ]
  [ "$(grep -A3 '^    - git: nanaism/yomiyasu$' <<<"$rendered")" = "$(printf '    - git: nanaism/yomiyasu\n      ref: %s\n      skills:\n        - yomiyasu' "$yomiyasu_sha")" ]

  # APM 0.35 user-scope install reads the legacy key; approvals come from root executables.allow.
  [ "$(sed -n '/^allowExecutables:/,$p' <<<"$rendered")" = "$(printf 'allowExecutables:\n  github.com/fujibee/agmsg:\n    bin: true\n  github.com/ibelick/ui-skills:\n    bin: true\n  github.com/tt-a1i/archify/archify:\n    bin: true')" ]
  [ "$(grep -c '^executables:' <<<"$rendered")" -eq 0 ]

  [ "$(sed -n 2p <<<"$rendered")" = "# native-render: workspace_only=0" ]

  # Everything else in apm.yml passes through line for line.
  diff <(sed '/^executables:/,$d' "$REPO_ROOT/apm.yml" | grep -vE 'jey3dayo/apm-workspace/(catalog|manual-skills)#main|nanaism/yomiyasu/skills/yomiyasu#') \
    <(sed 1,2d <<<"$rendered" | sed '/^allowExecutables:/,$d' | sed '/^    - git: nanaism\/yomiyasu$/,+3d' |
      grep -vE "^    - git: $FIXTURE_URL\$|^      path: (catalog|manual-skills)\$|^      ref: $SOURCE_SHA\$")

  rendered="$(native "$home" render --source-ref "$SOURCE_SHA" --workspace-only)"
  [ "$(grep -c '^    - ' <<<"$rendered")" -eq 2 ]
  [ "$(grep -c 'xecutables' <<<"$rendered")" -eq 0 ]
}

@test "render fails when a listed external or executable package is missing from apm.yml, and --workspace-only does not need it" {
  local home repo="$FX/render-repo"
  home="$(new_home render-missing)"
  copy_native_runtime "$REPO_ROOT" "$repo"
  grep -v 'nanaism/yomiyasu' "$REPO_ROOT/apm.yml" >"$repo/apm.yml"
  run fixture_exec "$home" /bin/bash "$repo/scripts/native.sh" render --source-ref "$SOURCE_SHA"
  [ "$status" -ne 0 ]
  [[ "$output" == *"valid bin-only executable approvals"* ]]
  run fixture_exec "$home" /bin/bash "$repo/scripts/native.sh" render --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -eq 0 ]

  grep -v '^    - fujibee/agmsg#' "$REPO_ROOT/apm.yml" >"$repo/apm.yml"
  run fixture_exec "$home" /bin/bash "$repo/scripts/native.sh" render --source-ref "$SOURCE_SHA"
  [ "$status" -ne 0 ]
  [[ "$output" == *"valid bin-only executable approvals"* ]]
  run fixture_exec "$home" /bin/bash "$repo/scripts/native.sh" render --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -eq 0 ]
}

@test "render refuses unsupported executable grants and duplicate approvals" {
  local home repo="$FX/render-exec-invalid"
  home="$(new_home render-exec-invalid)"
  copy_native_runtime "$REPO_ROOT" "$repo"
  sed 's/bin: true/hooks: true/' "$REPO_ROOT/apm.yml" >"$repo/apm.yml"
  run fixture_exec "$home" /bin/bash "$repo/scripts/native.sh" render --source-ref "$SOURCE_SHA"
  [ "$status" -ne 0 ]
  [[ "$output" == *"valid bin-only executable approvals"* ]]
  cp "$REPO_ROOT/apm.yml" "$repo/apm.yml"
  printf '    github.com/fujibee/agmsg:\n      bin: true\n' >>"$repo/apm.yml"
  run fixture_exec "$home" /bin/bash "$repo/scripts/native.sh" render --source-ref "$SOURCE_SHA"
  [ "$status" -ne 0 ]
  [[ "$output" == *"valid bin-only executable approvals"* ]]
}

@test "render rejects removal of a required bin approval while its dependency remains" {
  local home repo="$FX/render-exec-missing"
  home="$(new_home render-exec-missing)"
  copy_native_runtime "$REPO_ROOT" "$repo"
  awk '/^    github[.]com\/ibelick\/ui-skills:$/ { skip=1; next } skip { skip=0; next } { print }' "$REPO_ROOT/apm.yml" >"$repo/apm.yml"
  grep -q '^    - git: ibelick/ui-skills$' "$repo/apm.yml"
  run fixture_exec "$home" /bin/bash "$repo/scripts/native.sh" render --source-ref "$SOURCE_SHA"
  [ "$status" -ne 0 ]
  [[ "$output" == *"valid bin-only executable approvals"* ]]
}

@test "render rejects quoted legacy approval keys for normal and workspace-only installs" {
  local home repo="$FX/render-exec-quoted" mode
  home="$(new_home render-exec-quoted)"
  copy_native_runtime "$REPO_ROOT" "$repo"
  cp "$REPO_ROOT/apm.yml" "$repo/apm.yml"
  printf '"allowExecutables": {github.com/fujibee/agmsg: {bin: true}}\n' >>"$repo/apm.yml"
  for mode in normal workspace-only; do
    if [ "$mode" = workspace-only ]; then
      run fixture_exec "$home" /bin/bash "$repo/scripts/native.sh" render --source-ref "$SOURCE_SHA" --workspace-only
    else
      run fixture_exec "$home" /bin/bash "$repo/scripts/native.sh" render --source-ref "$SOURCE_SHA"
    fi
    [ "$status" -ne 0 ]
    [[ "$output" == *"valid bin-only executable approvals"* ]]
  done
}

@test "render rejects duplicate flow and anchored executable approvals in both modes" {
  local home repo="$FX/render-exec-flow" mode form
  home="$(new_home render-exec-flow)"
  copy_native_runtime "$REPO_ROOT" "$repo"
  for form in flow anchor; do
    cp "$REPO_ROOT/apm.yml" "$repo/apm.yml"
    if [ "$form" = flow ]; then
      printf 'executables: {allow: {github.com/fujibee/agmsg: {hooks: true}}}\n' >>"$repo/apm.yml"
    else
      printf 'executables: &extra {allow: {github.com/fujibee/agmsg: {hooks: true}}}\n' >>"$repo/apm.yml"
    fi
    for mode in normal workspace-only; do
      if [ "$mode" = workspace-only ]; then
        run fixture_exec "$home" /bin/bash "$repo/scripts/native.sh" render --source-ref "$SOURCE_SHA" --workspace-only
      else
        run fixture_exec "$home" /bin/bash "$repo/scripts/native.sh" render --source-ref "$SOURCE_SHA"
      fi
      [ "$status" -ne 0 ]
      [[ "$output" == *"valid bin-only executable approvals"* ]]
    done
  done
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

@test "backup records the state of the HOME, and rehearse copies it into result.txt as the expected state" {
  local home backup="$FX/backups/state-recorded" result
  home="$(new_home state-recorded)"
  seed_sentinels "$home"
  mkdir -p "$home/.apm"
  : >"$home/.apm/apm.lock.yaml"
  real_native "$home" backup --real-home --backup-dir "$backup"
  [ "$(cat "$backup/home-state.txt")" = "$(printf 'previous_lock=present\nhome_apm=consumer')" ]

  printf '#!/bin/sh\nexit 0\n' >"$FX/stub-apm-noop-state"
  chmod +x "$FX/stub-apm-noop-state"
  real_native_with_stub "$home" "$FX/stub-apm-noop-state" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  result="$(compgen -G "$backup/rehearsal-*/result.txt")"
  grep -qxF "previous_lock=present" "$result"
  grep -qxF "home_apm=consumer" "$result"
}

@test "rehearse fails when the HOME changed state after the backup, and when the backup records no state" {
  local home backup="$FX/backups/state-differs"
  home="$(new_home state-differs)"
  seed_sentinels "$home"
  mkdir -p "$home/.apm/catalog"
  real_native "$home" backup --real-home --backup-dir "$backup"
  grep -qxF "home_apm=checkout" "$backup/home-state.txt"

  rm -rf "$home/.apm/catalog"
  run real_native "$home" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"another state"* ]]
  [[ "$output" == *"home_apm=checkout"* ]]
  [ -z "$(compgen -G "$backup/rehearsal-*" || true)" ]

  mkdir -p "$home/.apm/catalog"
  : >"$home/.apm/apm.lock.yaml"
  run real_native "$home" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"previous_lock=absent"* ]]

  rm -f "$backup/home-state.txt"
  run real_native "$home" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"older format"* ]]
  [[ "$output" == *"take a new backup"* ]]
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

# The four roots migrate moves aside, as path and content (or link target) per file, so a round trip is compared byte for byte.
# A second argument names a moved-aside copy, such as .bak-<stamp>; its files are listed under the original names.
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

# Stands in for apm: install deploys foo (without its .apm-pin), everything else succeeds and does nothing.
write_deploy_stub() {
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nmkdir -p "$HOME/.claude/skills/foo"\necho "deployed by apm" >"$HOME/.claude/skills/foo/SKILL.md"\n' >"$1"
  chmod +x "$1"
}

# Sets M_HOME, M_BACKUP, M_REHEARSAL and M_BEFORE (the HOME's backed-up files before the rehearsal): a seeded HOME, its
# backup, and a clean rehearse --migrate of it.
prepare_migrate() {
  local name="$1" stub="$2"
  M_HOME="$(new_home "$name")"
  M_BACKUP="$FX/backups/$name"
  seed_migrate_home "$M_HOME"
  M_BEFORE="$(backed_up_snapshot "$M_HOME")"
  real_native "$M_HOME" backup --real-home --backup-dir "$M_BACKUP"
  if [ "$stub" = real ]; then
    real_native "$M_HOME" rehearse --real-home --backup-dir "$M_BACKUP" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  else
    real_native_with_stub "$M_HOME" "$stub" rehearse --real-home --backup-dir "$M_BACKUP" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  fi
  M_REHEARSAL="$(dirname "$(compgen -G "$M_BACKUP/rehearsal-*/result.txt")")"
}

@test "a failure to restore the untouched files does not skip the rollback of the roots or the agmsg restore" {
  local stub="$FX/stub-apm-deploy" sabotage="$FX/stub-apm-sabotage" original
  write_deploy_stub "$stub"
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nmkdir -p "$HOME/.claude/skills/foo"\necho "deployed by apm" >"$HOME/.claude/skills/foo/SKILL.md"\nrm -f "$HOME"/.agents/skills.bak-*/agmsg/db "$HOME"/.agents/skills.bak-*/agmsg/teams\necho changed >>"$HOME/.codex/config.toml"\nchmod 555 "$HOME/.codex"\n' >"$sabotage"
  chmod +x "$sabotage"

  prepare_migrate migrate-restore-fails "$stub"
  original="$(roots_snapshot "$M_HOME")"
  run real_native_with_stub "$M_HOME" "$sabotage" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  chmod 755 "$M_HOME/.codex"
  [ "$status" -ne 0 ]
  [[ "$output" == *"rolling the roots back"* ]]
  [[ "$output" == *"were not restored; the copies are in"* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  [ "$(readlink "$M_HOME/.agents/skills/agmsg/db")" = "$M_HOME/.local/state/agmsg/db" ]
  [ "$(readlink "$M_HOME/.agents/skills/agmsg/teams")" = "$M_HOME/.local/state/agmsg/teams" ]
}

@test "a failure while saving the untouched files leaves the files not yet saved where they are" {
  local stub="$FX/stub-apm-deploy" before
  write_deploy_stub "$stub"
  prepare_migrate migrate-save-fails "$stub"
  before="$(roots_snapshot "$M_HOME")"
  # .codex/config.toml is saved first; the second copy (.claude/settings.json) cannot be read.
  chmod 000 "$M_HOME/.claude/settings.json"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  chmod 600 "$M_HOME/.claude/settings.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot copy"* ]]
  [ "$(cat "$M_HOME/.claude/settings.json")" = '{"fixture": true}' ]
  [ "$(cat "$M_HOME/.codex/config.toml")" = 'model = "fixture"' ]
  [ -z "$(compgen -G "$M_HOME/.claude/settings.json.changed-*" || true)" ]
  [ -z "$(compgen -G "$M_HOME/.codex/config.toml.changed-*" || true)" ]
  [ "$(roots_snapshot "$M_HOME")" = "$before" ]
}

@test "a config file that is a link keeps its link when a failed migrate restores it, and the target gets the old content" {
  local stub="$FX/stub-apm-deploy" touch_config="$FX/stub-apm-touch-link"
  write_deploy_stub "$stub"
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nmkdir -p "$HOME/.claude/skills/foo"\necho "deployed by apm" >"$HOME/.claude/skills/foo/SKILL.md"\necho changed >>"$HOME/.claude/settings.json"\n' >"$touch_config"
  chmod +x "$touch_config"
  M_HOME="$(new_home migrate-config-link)"
  M_BACKUP="$FX/backups/migrate-config-link"
  seed_migrate_home "$M_HOME"
  mkdir -p "$M_HOME/dotfiles"
  mv "$M_HOME/.claude/settings.json" "$M_HOME/dotfiles/settings.json"
  ln -s "$M_HOME/dotfiles/settings.json" "$M_HOME/.claude/settings.json"
  real_native "$M_HOME" backup --real-home --backup-dir "$M_BACKUP"
  real_native_with_stub "$M_HOME" "$stub" rehearse --real-home --backup-dir "$M_BACKUP" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  M_REHEARSAL="$(dirname "$(compgen -G "$M_BACKUP/rehearsal-*/result.txt")")"

  run real_native_with_stub "$M_HOME" "$touch_config" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [ -L "$M_HOME/.claude/settings.json" ]
  [ "$(readlink "$M_HOME/.claude/settings.json")" = "$M_HOME/dotfiles/settings.json" ]
  [ "$(cat "$M_HOME/dotfiles/settings.json")" = '{"fixture": true}' ]
  [ "$(tail -n 1 "$M_HOME"/.claude/settings.json.changed-*)" = "changed" ]
}

@test "a later migrate does not put back an entry the previous native lock listed and the catalog dropped; rehearse lists what it reinstates and what it skips" {
  local stub="$FX/stub-apm-deploy" rehearsal
  write_deploy_stub "$stub"
  M_HOME="$(new_home migrate-dropped)"
  M_BACKUP="$FX/backups/migrate-dropped"
  seed_migrate_home "$M_HOME"
  mkdir -p "$M_HOME/.claude/skills/removed-upstream" "$M_HOME/.claude/skills/same" "$M_HOME/.apm"
  echo "old" >"$M_HOME/.claude/skills/removed-upstream/SKILL.md"
  echo "same" >"$M_HOME/.claude/skills/same/SKILL.md"
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nmkdir -p "$HOME/.claude/skills/foo" "$HOME/.claude/skills/same"\necho "deployed by apm" >"$HOME/.claude/skills/foo/SKILL.md"\necho same >"$HOME/.claude/skills/same/SKILL.md"\n' >"$stub"
  printf "lockfile_version: '2'\ndependencies:\n- repo_url: https://github.com/fixture-owner/apm-workspace\n  deployed_files:\n  - .claude/skills/removed-upstream\n  - .claude/skills/removed-upstream/SKILL.md\n  - .claude/skills/foo\n  - .claude/skills/foo/SKILL.md\n  deployed_file_hashes:\n    .claude/skills/removed-upstream/SKILL.md: sha256:00\n" >"$M_HOME/.apm/apm.lock.yaml"
  real_native "$M_HOME" backup --real-home --backup-dir "$M_BACKUP"
  real_native_with_stub "$M_HOME" "$stub" rehearse --real-home --backup-dir "$M_BACKUP" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  rehearsal="$(dirname "$(compgen -G "$M_BACKUP/rehearsal-*/result.txt")")"

  grep -q $'^\.claude/skills/removed-upstream/SKILL.md\t.*not deployed this time' "$rehearsal/allowed-lost.txt"
  grep -qx '\.claude/skills/removed-upstream' "$rehearsal/dropped.txt"
  grep -qx 'dropped=1' "$rehearsal/result.txt"
  grep -q $'^\.claude/skills/private-copy\t' "$rehearsal/reinstated.txt"
  ! grep -q 'removed-upstream' "$rehearsal/reinstated.txt"
  grep -qx '\.claude/skills/foo' "$rehearsal/skipped.txt"
  ! grep -q 'same' "$rehearsal/skipped.txt"

  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$rehearsal"
  [ "$status" -eq 0 ]
  [[ "$output" == *"share a name with what apm deployed"* ]]
  [ ! -e "$M_HOME/.claude/skills/removed-upstream" ]
  [ -f "$M_HOME"/.claude/skills.bak-*/removed-upstream/SKILL.md ]
  [ -f "$M_HOME/.claude/skills/private-copy/SKILL.md" ]
  grep -qx '\.claude/skills/foo' "$M_HOME"/.apm/native-migrate-*.skipped.txt
}

@test "migrate treats agmsg run/ and a synced-skill cache that a running Claude Code session recreates as runtime state, not as skipped entries" {
  local stub="$FX/stub-apm-runtime" marker="$FX/live-writer" rehearsal
  M_HOME="$(new_home migrate-runtime)"
  M_BACKUP="$FX/backups/migrate-runtime"
  seed_migrate_home "$M_HOME"
  mkdir -p "$M_HOME/.agents/skills/agmsg/run" "$M_HOME/.claude/skills/synced/bucket" "$M_HOME/.apm"
  echo "lastcheck" >"$M_HOME/.agents/skills/agmsg/run/.lastcheck-worker"
  echo "old sync state" >"$M_HOME/.claude/skills/synced/bucket/manifest.json"
  echo "old only" >"$M_HOME/.claude/skills/synced/bucket/old-only.json"
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nmkdir -p "$HOME/.claude/skills/foo" "$HOME/.agents/skills/agmsg"\necho "old foo" >"$HOME/.claude/skills/foo/SKILL.md"\necho "agmsg skill" >"$HOME/.agents/skills/agmsg/SKILL.md"\nif [ -e "%s" ]; then mkdir -p "$HOME/.claude/skills/synced/bucket"; echo "live sync state" >"$HOME/.claude/skills/synced/bucket/manifest.json"; fi\n' "$marker" >"$stub"
  chmod +x "$stub"
  real_native "$M_HOME" backup --real-home --backup-dir "$M_BACKUP"
  real_native_with_stub "$M_HOME" "$stub" rehearse --real-home --backup-dir "$M_BACKUP" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  rehearsal="$(dirname "$(compgen -G "$M_BACKUP/rehearsal-*/result.txt")")"
  [ ! -s "$rehearsal/skipped.txt" ]

  : >"$marker"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$rehearsal"
  [ "$status" -eq 0 ]
  [ ! -s "$M_HOME"/.apm/native-migrate-*.skipped.txt ]
  [ "$(cat "$M_HOME/.claude/skills/synced/bucket/manifest.json")" = "live sync state" ]
  [ "$(cat "$M_HOME"/.claude/skills.bak-*/synced/bucket/old-only.json)" = "old only" ]
  [ -L "$M_HOME/.agents/skills/agmsg/db" ]
}

@test "migrate-rollback accepts a record whose root has no done line and no backup" {
  local home stamp=20261109T000000Z
  home="$(new_home rollback-unmoved)"
  mkdir -p "$home/.apm" "$home/.agents/skills.bak-$stamp/a" "$home/.agents/skills/new" "$home/.claude/skills/keep"
  printf 'moved\t.agents/skills\nmoved\t.claude/skills\nabsent\t.claude/agents\nabsent\t.cursor/agents\n' >"$home/.apm/native-migrate-$stamp.txt"
  run real_native "$home" migrate-rollback --real-home --stamp "$stamp"
  [ "$status" -eq 0 ]
  [ -d "$home/.agents/skills/a" ]
  [ -d "$home/.agents/skills.native-$stamp/new" ]
  [ -d "$home/.claude/skills/keep" ]
  [ ! -e "$home/.claude/skills.native-$stamp" ]
  [[ "$output" == *"was never moved aside"* ]]
}

@test "an automatic rollback accepts the root whose move never started, after migrate_roots failed part way" {
  local stub="$FX/stub-apm-deploy" original
  write_deploy_stub "$stub"
  prepare_migrate migrate-mid-move "$stub"
  original="$(roots_snapshot "$M_HOME")"
  # .agents/skills moves; .claude/skills cannot (its parent is read-only).
  chmod 555 "$M_HOME/.claude"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  chmod 755 "$M_HOME/.claude"
  [ "$status" -ne 0 ]
  [[ "$output" == *"was never moved aside"* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  [ -z "$(compgen -G "$M_HOME/.agents/skills.bak-*" || true)" ]
}

@test "migrate-rollback that stopped at its second root is finished by running it again, and stops when a backup was deleted" {
  local stub="$FX/stub-apm-deploy" original stamp
  write_deploy_stub "$stub"
  prepare_migrate migrate-rollback-resume "$stub"
  original="$(roots_snapshot "$M_HOME")"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -eq 0 ]
  stamp="$(printf '%s\n' "$output" | tail -n 1)"

  chmod 555 "$M_HOME/.claude"
  run real_native "$M_HOME" migrate-rollback --real-home --stamp "$stamp"
  chmod 755 "$M_HOME/.claude"
  [ "$status" -ne 0 ]
  [ -d "$M_HOME/.agents/skills.native-$stamp" ]
  grep -qx $'restored\t.agents/skills' "$M_HOME/.apm/native-migrate-$stamp.txt"
  run real_native "$M_HOME" migrate-rollback --real-home --stamp "$stamp"
  [ "$status" -eq 0 ]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]

  # A backup deleted by hand after a finished move stops a rollback before it moves anything.
  prepare_migrate migrate-rollback-deleted "$stub"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -eq 0 ]
  stamp="$(printf '%s\n' "$output" | tail -n 1)"
  rm -rf "$M_HOME/.claude/skills.bak-$stamp"
  run real_native "$M_HOME" migrate-rollback --real-home --stamp "$stamp"
  [ "$status" -ne 0 ]
  [[ "$output" == *"skills.bak-$stamp is missing"* ]]
  [ -z "$(compgen -G "$M_HOME/.agents/skills.native-*" || true)" ]
  [ -d "$M_HOME/.agents/skills.bak-$stamp" ]
}

@test "migrate-rollback finishes a rollback that stopped after moving a root back and before writing restored" {
  local stub="$FX/stub-apm-deploy" original stamp
  write_deploy_stub "$stub"
  prepare_migrate migrate-rollback-unrecorded "$stub"
  original="$(roots_snapshot "$M_HOME")"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -eq 0 ]
  stamp="$(printf '%s\n' "$output" | tail -n 1)"

  mv "$M_HOME/.agents/skills" "$M_HOME/.agents/skills.native-$stamp"
  mv "$M_HOME/.agents/skills.bak-$stamp" "$M_HOME/.agents/skills"
  run real_native "$M_HOME" migrate-rollback --real-home --stamp "$stamp"
  [ "$status" -eq 0 ]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  grep -qx $'restored\t.agents/skills' "$M_HOME/.apm/native-migrate-$stamp.txt"
  grep -qx $'restored\t.claude/skills' "$M_HOME/.apm/native-migrate-$stamp.txt"
}

@test "migrate stops when the HOME is in another state than at the rehearsal (previous lock, ~/.apm), and moves nothing" {
  local stub="$FX/stub-apm-deploy" original
  write_deploy_stub "$stub"
  prepare_migrate migrate-stale-state "$stub"
  grep -qx 'previous_lock=absent' "$M_REHEARSAL/result.txt"
  grep -qx 'home_apm=absent' "$M_REHEARSAL/result.txt"
  original="$(roots_snapshot "$M_HOME")"

  mkdir -p "$M_HOME/.apm"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"home_apm=consumer"* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]

  : >"$M_HOME/.apm/apm.lock.yaml"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"previous_lock=present"* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  [ -z "$(compgen -G "$M_HOME/.claude/skills.bak-*" || true)" ]
}

@test "migrate fails and rolls back when it drops other entries than the rehearsal did" {
  local stub="$FX/stub-apm-deploy" original
  write_deploy_stub "$stub"
  prepare_migrate migrate-dropped-differs "$stub"
  original="$(roots_snapshot "$M_HOME")"
  printf '.claude/skills/ghost\n' >>"$M_REHEARSAL/dropped.txt"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dropped other entries than the rehearsal did"* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  [ -z "$(compgen -G "$M_HOME/.claude/skills.bak-*" || true)" ]
  [ -f "$(compgen -G "$M_HOME/.apm/native-migrate-*.dropped.txt")" ]
}

@test "a migrate that draws the stamp of another migrate stops before it moves or rolls back anything of that one" {
  local stub="$FX/stub-apm-deploy" bin="$FX/date-bin" stamp=20261109T111111Z original record
  write_deploy_stub "$stub"
  mkdir -p "$bin"
  printf '#!/bin/bash\ncase "$*" in "-u +%%Y%%m%%dT%%H%%M%%SZ") echo %s ;; *) exec /bin/date "$@" ;; esac\n' "$stamp" >"$bin/date"
  chmod +x "$bin/date"
  M_HOME="$(new_home migrate-same-stamp)"
  seed_migrate_home "$M_HOME"
  record="$M_HOME/.apm/native-migrate-$stamp.txt"
  mkdir -p "$M_HOME/.apm" "$M_HOME/.claude/skills.bak-$stamp"
  printf 'earlier\n' >"$M_HOME/.claude/skills.bak-$stamp/SKILL.md"
  printf 'moved\t.claude/skills\ndone\t.claude/skills\n' >"$record"
  real_native "$M_HOME" backup --real-home --backup-dir "$FX/backups/migrate-same-stamp"
  real_native_with_stub "$M_HOME" "$stub" rehearse --real-home --backup-dir "$FX/backups/migrate-same-stamp" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  M_REHEARSAL="$(dirname "$(compgen -G "$FX/backups/migrate-same-stamp/rehearsal-*/result.txt")")"
  original="$(roots_snapshot "$M_HOME")"

  run fixture_exec "$M_HOME" /usr/bin/env PATH="$bin:$FIXTURE_PATH" APM_NATIVE_ACCOUNT_HOME="$M_HOME" APM_BIN="$stub" /bin/bash "$REPO_ROOT/scripts/native.sh" \
    migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"another migrate drew the same stamp"* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  [ "$(cat "$record")" = "$(printf 'moved\t.claude/skills\ndone\t.claude/skills')" ]
  [ "$(cat "$M_HOME/.claude/skills.bak-$stamp/SKILL.md")" = "earlier" ]
  [ ! -e "$M_HOME/.claude/skills.native-$stamp" ]
}

@test "migrate and rehearse stop before writing when agmsg db or teams links to a store other than the default" {
  local stub="$FX/stub-apm-deploy" original
  write_deploy_stub "$stub"
  prepare_migrate migrate-store "$stub"
  mkdir -p "$M_HOME/.state/agmsg/db"
  echo "other store" >"$M_HOME/.state/agmsg/db/keep"
  rm "$M_HOME/.agents/skills/agmsg/db"
  ln -s "$M_HOME/.state/agmsg/db" "$M_HOME/.agents/skills/agmsg/db"
  original="$(roots_snapshot "$M_HOME")"

  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"the only store agmsg-state.sh relinks to"* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  [ ! -e "$M_HOME/.apm/apm.yml" ]
  [ "$(readlink "$M_HOME/.agents/skills/agmsg/db")" = "$M_HOME/.state/agmsg/db" ]

  real_native "$M_HOME" backup --real-home --backup-dir "$FX/backups/migrate-store-2"
  run real_native_with_stub "$M_HOME" "$stub" rehearse --real-home --backup-dir "$FX/backups/migrate-store-2" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *"the only store agmsg-state.sh relinks to"* ]]
  [ -z "$(compgen -G "$FX/backups/migrate-store-2/rehearsal-*" || true)" ]
}

@test "a rehearsal or migrate with another --workspace-only than the previous manifest stops" {
  local stub="$FX/stub-apm-deploy"
  write_deploy_stub "$stub"
  prepare_migrate migrate-mode "$stub"
  mkdir -p "$M_HOME/.apm"
  printf '# Rendered by scripts/native.sh from apm.yml with this repository pinned at x. Do not edit; re-render.\n# native-render: workspace_only=0\n' >"$M_HOME/.apm/apm.yml"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"rendered with workspace_only=0"* ]]
  [ -z "$(compgen -G "$M_HOME/.claude/skills.bak-*" || true)" ]
  real_native "$M_HOME" backup --real-home --backup-dir "$FX/backups/migrate-mode-2"
  run real_native_with_stub "$M_HOME" "$stub" rehearse --real-home --backup-dir "$FX/backups/migrate-mode-2" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *"rendered with workspace_only=0"* ]]
}

# A HOME whose ~/.apm is a native consumer: apm.yml rendered by native.sh, no checkout.
seed_native_consumer_home() {
  mkdir -p "$1/.apm"
  printf '# Rendered by scripts/native.sh from apm.yml with this repository pinned at %s. Do not edit; re-render.\n' "$SOURCE_SHA" >"$1/.apm/apm.yml"
}

@test "sync:opencode writes the OpenCode guide on a native HOME and leaves a hand-written one alone" {
  local home
  home="$(new_home opencode-sync)"
  seed_native_consumer_home "$home"

  run fixture_exec "$home" /bin/bash "$REPO_ROOT/scripts/apm-workspace.sh" sync:opencode
  [ "$status" -eq 0 ]
  [ "$(cat "$home/.config/opencode/AGENTS.md")" = "$(catalog_guide_body)" ]
  [ "$(cd "$home" && find . -type f | LC_ALL=C sort)" = "$(printf './.apm/apm.yml\n./.cache/apm/last_version_check\n./.config/opencode/AGENTS.md')" ]

  echo "my own opencode guide" >"$home/.config/opencode/AGENTS.md"
  run fixture_exec "$home" /bin/bash "$REPO_ROOT/scripts/apm-workspace.sh" sync:opencode
  [ "$status" -eq 0 ]
  [ "$(cat "$home/.config/opencode/AGENTS.md")" = "my own opencode guide" ]
}

@test "migrate --real-home stops before writing when .cache/apm, Library/Caches/apm or .claude/commands holds a broken link" {
  local stub="$FX/stub-apm-deploy" original link
  write_deploy_stub "$stub"
  prepare_migrate migrate-cache-links "$stub"
  original="$(roots_snapshot "$M_HOME")"
  mkdir -p "$M_HOME/Library/Caches/apm" "$M_HOME/.claude/commands" "$M_HOME/.cache/apm/git"
  for link in .cache/apm/git/broken Library/Caches/apm/broken .claude/commands/broken; do
    ln -s ./gone "$M_HOME/$link"
    run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
    [ "$status" -ne 0 ]
    [[ "$output" == *"$M_HOME/$link (broken)"* ]]
    [ "$(roots_snapshot "$M_HOME")" = "$original" ]
    [ -z "$(compgen -G "$M_HOME/.claude/skills.bak-*" || true)" ]
    [ ! -e "$M_HOME/.apm/apm.yml" ]
    rm "$M_HOME/$link"
  done
}

@test "rehearse fails on a broken link or a link that leaves the HOME inside the migrated roots, and names each one" {
  local home backup="$FX/backups/rehearse-links" stub="$FX/rehearse-links-stub" migrate
  home="$(new_home rehearse-links)"
  seed_migrate_home "$home"
  ln -s "$home/does-not-exist" "$home/.claude/skills/dangling"
  ln -s /usr/bin "$home/.cursor/agents/leaves-home"
  write_deploy_stub "$stub"
  real_native "$home" backup --real-home --backup-dir "$backup"
  for migrate in --migrate ""; do
    run real_native_with_stub "$home" "$stub" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only ${migrate:+"$migrate"}
    [ "$status" -ne 0 ]
    [[ "$output" == *"$home/.claude/skills/dangling (broken)"* ]]
    [[ "$output" == *"$home/.cursor/agents/leaves-home -> "* ]]
    [[ "$output" != *"removed the broken link"* ]]
  done
  [ -z "$(compgen -G "$backup/rehearsal-*")" ]
}

@test "rehearse --migrate is clean when only a .apm-pin disappears, and reports it apart from the lost files" {
  write_deploy_stub "$FX/stub-apm-deploy"
  prepare_migrate rehearse-migrate-clean "$FX/stub-apm-deploy"
  grep -qxF "mode=migrate" "$M_REHEARSAL/result.txt"
  grep -qxF "lost=0" "$M_REHEARSAL/result.txt"
  grep -qxF "allowed_lost=1" "$M_REHEARSAL/result.txt"
  grep -qxF "reinstate_status=0" "$M_REHEARSAL/result.txt"
  grep -qxF "baseline_skips=0" "$M_REHEARSAL/result.txt"
  grep -qxF ".claude/skills/foo/.apm-pin"$'\t'"pin marker inside a root that migrate moved aside" "$M_REHEARSAL/allowed-lost.txt"
  [ ! -s "$M_REHEARSAL/lost.txt" ]
  [ "$(backed_up_snapshot "$M_HOME")" = "$M_BEFORE" ]
}

@test "rehearse --migrate fails on a lost file other than a .apm-pin, and on a skipped baseline" {
  local home backup="$FX/backups/rehearse-migrate-lost"
  home="$(new_home rehearse-migrate-lost)"
  seed_migrate_home "$home"
  echo "extra" >"$home/.claude/skills/foo/extra.txt"
  real_native "$home" backup --real-home --backup-dir "$backup"
  write_deploy_stub "$FX/stub-apm-deploy"
  run real_native_with_stub "$home" "$FX/stub-apm-deploy" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  [ "$status" -eq 1 ]
  [[ "$output" == *".claude/skills/foo/extra.txt"* ]]
  grep -qxF "lost=1" "$(compgen -G "$backup/rehearsal-*/result.txt")"
  grep -qxF "allowed_lost=1" "$(compgen -G "$backup/rehearsal-*/result.txt")"

  home="$(new_home rehearse-migrate-baseline)"
  backup="$FX/backups/rehearse-migrate-baseline"
  seed_migrate_home "$home"
  real_native "$home" backup --real-home --backup-dir "$backup"
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\necho "no trustworthy local deployment baseline for foo" >&2\n' >"$FX/stub-apm-baseline"
  chmod +x "$FX/stub-apm-baseline"
  run real_native_with_stub "$home" "$FX/stub-apm-baseline" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  [ "$status" -eq 1 ]
  grep -qxF "lost=0" "$(compgen -G "$backup/rehearsal-*/result.txt")"
  grep -qxF "baseline_skips=1" "$(compgen -G "$backup/rehearsal-*/result.txt")"
}

@test "rehearse --migrate allows the agmsg metadata and run state it lists, and fails on any other agmsg file" {
  local home backup="$FX/backups/rehearse-migrate-agmsg-table" stub="$FX/stub-apm-replace-agmsg" result
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nrm -rf "$HOME/.agents/skills/agmsg" "$HOME/.claude/skills/agmsg"\nmkdir -p "$HOME/.agents/skills/agmsg" "$HOME/.claude/skills/agmsg"\necho deployed >"$HOME/.agents/skills/agmsg/SKILL.md"\necho deployed >"$HOME/.claude/skills/agmsg/SKILL.md"\n' >"$stub"
  chmod +x "$stub"
  home="$(new_home rehearse-migrate-agmsg-table)"
  seed_migrate_home "$home"
  mkdir -p "$home/.agents/skills/agmsg/.apm" "$home/.agents/skills/agmsg/run" "$home/.claude/skills/agmsg/.apm"
  for f in apm.yml .apm/.plugin-skill-sources.json run/role-session; do echo x >"$home/.agents/skills/agmsg/$f"; done
  for f in apm.yml .apm/.plugin-skill-sources.json; do echo x >"$home/.claude/skills/agmsg/$f"; done
  echo skill >"$home/.claude/skills/agmsg/SKILL.md"
  real_native "$home" backup --real-home --backup-dir "$backup"
  real_native_with_stub "$home" "$stub" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  result="$(compgen -G "$backup/rehearsal-*/result.txt")"
  grep -qxF "lost=0" "$result"
  # The agmsg run directory and its file, and per root apm.yml, .apm and its metadata file.
  grep -qxF "allowed_lost=8" "$result"
  grep -qF ".agents/skills/agmsg/run/role-session"$'\t' "$(dirname "$result")/allowed-lost.txt"
  [ "$(cut -f2 "$(dirname "$result")/allowed-lost.txt" | grep -c 'agmsg runtime state')" -eq 2 ]

  # The same skill's other files are not in the table.
  home="$(new_home rehearse-migrate-agmsg-other)"
  backup="$FX/backups/rehearse-migrate-agmsg-other"
  seed_migrate_home "$home"
  mkdir -p "$home/.agents/skills/agmsg/bin"
  echo x >"$home/.agents/skills/agmsg/bin/agmsg.js"
  echo x >"$home/.agents/skills/agmsg/apm.yml"
  real_native "$home" backup --real-home --backup-dir "$backup"
  run real_native_with_stub "$home" "$stub" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  [ "$status" -eq 1 ]
  [[ "$output" == *".agents/skills/agmsg/bin/agmsg.js"* ]]
  result="$(compgen -G "$backup/rehearsal-*/result.txt")"
  grep -qxF "lost=2" "$result"
  [ "$(cat "$(dirname "$result")/lost.txt")" = "$(printf '.agents/skills/agmsg/bin\n.agents/skills/agmsg/bin/agmsg.js')" ]
}

@test "rehearse and migrate stop when <HOME>/apm.yml exists, because apm would read its executable approvals instead, before apm runs" {
  local home backup="$FX/backups/home-manifest" stub="$FX/stub-apm-home-manifest"
  printf '#!/bin/sh\ntouch "$HOME/apm-ran"\n' >"$stub"
  chmod +x "$stub"
  home="$(new_home home-manifest)"
  seed_migrate_home "$home"
  real_native "$home" backup --real-home --backup-dir "$backup"
  echo "name: stray" >"$home/apm.yml"

  run real_native_with_stub "$home" "$stub" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *"$home/apm.yml exists"* ]]
  [ -z "$(compgen -G "$backup/rehearsal-*" || true)" ]

  rm "$home/apm.yml"
  write_deploy_stub "$FX/stub-apm-deploy"
  real_native_with_stub "$home" "$FX/stub-apm-deploy" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  echo "name: stray" >"$home/apm.yml"
  run real_native_with_stub "$home" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$(dirname "$(compgen -G "$backup/rehearsal-*/result.txt")")"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$home/apm.yml exists"* ]]
  [ -z "$(compgen -G "$home/.claude/skills.bak-*" || true)" ]
  [ ! -e "$home/apm-ran" ]
}

@test "rehearse and migrate pass --trust-bin to install only" {
  local home stub="$FX/stub-apm-args"
  printf '#!/bin/sh\necho "$*" >>"$HOME/apm-args.log"\n' >"$stub"
  chmod +x "$stub"
  home="$(new_home trust-bin-args-migrate)"
  seed_migrate_home "$home"
  real_native "$home" backup --real-home --backup-dir "$FX/backups/trust-bin-args"
  real_native_with_stub "$home" "$stub" rehearse --real-home --backup-dir "$FX/backups/trust-bin-args" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  real_native_with_stub "$home" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only \
    --rehearsal "$(dirname "$(compgen -G "$FX/backups/trust-bin-args/rehearsal-*/result.txt")")"
  [ "$(grep -c '^install -g --only apm --trust-bin$' "$home/apm-args.log")" -eq 1 ]
  [ "$(grep -c '^compile -g --clean$' "$home/apm-args.log")" -eq 1 ]
  [ "$(grep -c -- '--trust-bin' "$home/apm-args.log")" -eq 1 ]
  [ "$(find "$FX/backups/trust-bin-args"/rehearsal-*/home -name apm-args.log | xargs cat | grep -c -- '--trust-bin')" -eq 1 ]
}

@test "migrate refuses a HOME whose .apm is a checkout, and a repository inside .apm, before anything is written" {
  local home before
  home="$(new_home migrate-checkout)"
  seed_migrate_home "$home"
  before="$(find "$home" | LC_ALL=C sort)"
  mkdir -p "$home/.apm/.git"
  run real_native "$home" migrate --real-home --source-ref "$SOURCE_SHA" --rehearsal "$FX/none"
  [ "$status" -ne 0 ]
  [[ "$output" == *"authoring checkout"* ]]
  rmdir "$home/.apm/.git"
  mkdir -p "$home/.apm/catalog"
  run real_native "$home" migrate --real-home --source-ref "$SOURCE_SHA" --rehearsal "$FX/none"
  [ "$status" -ne 0 ]
  [[ "$output" == *"authoring checkout"* ]]
  rmdir "$home/.apm/catalog"

  copy_native_runtime "$REPO_ROOT" "$home/.apm"
  run fixture_exec "$home" /usr/bin/env APM_NATIVE_ACCOUNT_HOME="$home" /bin/bash "$home/.apm/scripts/native.sh" \
    migrate --real-home --source-ref "$SOURCE_SHA" --rehearsal "$FX/none"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is inside"* ]]
  rm -rf "$home/.apm/scripts"
  rmdir "$home/.apm"
  [ "$(find "$home" | LC_ALL=C sort)" = "$before" ]
}

@test "migrate refuses a missing, plain, failed or mismatched rehearsal, and moves nothing" {
  local home backup before bad stub="$FX/stub-apm-deploy"
  write_deploy_stub "$stub"
  prepare_migrate migrate-refuse "$stub"
  home="$M_HOME"
  before="$(find "$home" | LC_ALL=C sort)"

  run real_native_with_stub "$home" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs --rehearsal"* ]]
  run real_native_with_stub "$home" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$FX/none"
  [ "$status" -ne 0 ]
  [[ "$output" == *"has no result.txt"* ]]
  # Another ref, and a rehearsal made without --workspace-only.
  run real_native_with_stub "$home" "$stub" migrate --real-home --source-ref 0000000000000000000000000000000000000001 --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not show source_ref=0000000000000000000000000000000000000001"* ]]
  run real_native_with_stub "$home" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not show workspace_only=0"* ]]

  # A plain rehearsal, a failed step and a lost file each leave the result without a line migrate needs.
  for bad in mode=plain lost=1 install_status=1 reinstate_status=1 baseline_skips=2; do
    cp -R "$M_REHEARSAL" "$M_REHEARSAL.$bad"
    sed -i.orig "s/^${bad%%=*}=.*/$bad/" "$M_REHEARSAL.$bad/result.txt"
    run real_native_with_stub "$home" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL.$bad"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not show ${bad%%=*}="* ]]
  done

  # Another HOME's rehearsal.
  home="$(new_home migrate-refuse-other)"
  seed_migrate_home "$home"
  run real_native_with_stub "$home" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not show home=$home"* ]]
  [ -z "$(compgen -G "$home/.claude/skills.bak-*" || true)" ]
  [ -z "$(compgen -G "$M_HOME/.claude/skills.bak-*" || true)" ]
  [ "$(find "$M_HOME" | LC_ALL=C sort)" = "$before" ]
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

@test "migrate links agmsg db and teams again when apm replaces the agmsg skill directory" {
  local stub="$FX/stub-apm-replace-agmsg"
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nrm -rf "$HOME/.agents/skills/agmsg"\nmkdir -p "$HOME/.agents/skills/agmsg"\necho "deployed agmsg" >"$HOME/.agents/skills/agmsg/SKILL.md"\n' >"$stub"
  chmod +x "$stub"
  prepare_migrate migrate-agmsg "$stub"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -eq 0 ]
  [ "$(cat "$M_HOME/.agents/skills/agmsg/SKILL.md")" = "deployed agmsg" ]
  [ "$(readlink "$M_HOME/.agents/skills/agmsg/db")" = "$M_HOME/.local/state/agmsg/db" ]
  [ "$(readlink "$M_HOME/.agents/skills/agmsg/teams")" = "$M_HOME/.local/state/agmsg/teams" ]
  [ "$(cat "$M_HOME/.local/state/agmsg/db/keep")" = "db store" ]
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

@test "migrate fails and rolls back when a file of a root that apm redeploys was added after the rehearsal" {
  local stub="$FX/stub-apm-deploy" original
  write_deploy_stub "$stub"
  prepare_migrate migrate-late-file "$stub"
  echo "added after the rehearsal" >"$M_HOME/.claude/skills/foo/extra.txt"
  original="$(roots_snapshot "$M_HOME")"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *".claude/skills/foo/extra.txt"* ]]
  [[ "$output" == *"rolling the roots back"* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  [ "$(cat "$M_HOME/.claude/skills/foo/extra.txt")" = "added after the rehearsal" ]
  grep -qxF ".claude/skills/foo/extra.txt" "$M_HOME"/.apm/native-migrate-*.lost.txt
  # The .apm-pin of the same skill is in the allowlist and is not listed.
  ! grep -q 'apm-pin' "$M_HOME"/.apm/native-migrate-*.lost.txt
}

@test "migrate and migrate-rollback take a disposable --home as well" {
  local home stub="$FX/stub-apm-deploy" original stamp backup="$FX/backups/migrate-home"
  write_deploy_stub "$stub"
  home="$(new_home migrate-home)"
  seed_migrate_home "$home"
  original="$(roots_snapshot "$home")"
  native "$home" backup --home "$home" --backup-dir "$backup"
  fixture_exec "$home" /usr/bin/env APM_BIN="$stub" /bin/bash "$REPO_ROOT/scripts/native.sh" rehearse --home "$home" --backup-dir "$backup"     --source-ref "$SOURCE_SHA" --workspace-only --migrate
  run fixture_exec "$home" /usr/bin/env APM_BIN="$stub" /bin/bash "$REPO_ROOT/scripts/native.sh" migrate --home "$home"     --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$(dirname "$(compgen -G "$backup/rehearsal-*/result.txt")")"
  [ "$status" -eq 0 ]
  stamp="$(printf '%s\n' "$output" | tail -n 1)"
  [ "$(cat "$home/.claude/skills/foo/SKILL.md")" = "deployed by apm" ]
  native "$home" migrate-rollback --home "$home" --stamp "$stamp"
  [ "$(roots_snapshot "$home")" = "$original" ]
}

# After the cutover the checkout lives outside HOME (a linked worktree has a .git file) and HOME/.apm is the consumer.
setup_authoring_checkout() {
  local authoring="$1" log="$2" bin="$3"
  mkdir -p "$authoring" "$bin"
  cp -R "$REPO_ROOT/scripts" "$authoring/scripts"
  cp "$REPO_ROOT/apm.yml" "$REPO_ROOT/apm.lock.yaml" "$REPO_ROOT/mise.toml" "$authoring/"
  ln -s "$REPO_ROOT/catalog" "$authoring/catalog"
  printf 'gitdir: %s/.git/worktrees/authoring\n' "$authoring" >"$authoring/.git"
  printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$PWD" "$*" >>"%s"\nprintf "%%s|%%s\\n" "$HOME" "$*" >>"%s.home"\n[ "$1" != install ] || mkdir -p "$HOME/.apm/deployment-receipts"\n' "$log" "$log" >"$bin/apm"
  chmod +x "$bin/apm"
}

apm_tree_snapshot() {
  local home="$1"
  (
    cd "$home/.apm"
    find . -print | LC_ALL=C sort
    find . -type f -exec cksum {} + | LC_ALL=C sort
  )
}

@test "validate checks authoring pins without APM or changing the consumer HOME" {
  local home authoring="$FX/authoring" bin="$FX/authoring-bin" log="$FX/authoring-apm.log" consumer_before
  home="$(new_home authoring-consumer)"
  mkdir -p "$home/.apm"
  native "$home" render --source-ref "$SOURCE_SHA" --workspace-only >"$home/.apm/apm.yml"
  setup_authoring_checkout "$authoring" "$log" "$bin"
  printf 'name: consumer\ndependencies:\n  apm:\n    - owner/consumer/skills/x#dddddddddddddddddddddddddddddddddddddddd\n' >"$home/.apm/apm.yml"
  consumer_before="$(apm_tree_snapshot "$home")"

  run fixture_exec "$home" /usr/bin/env PATH="/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$authoring/scripts/apm-workspace.sh" validate
  [ "$status" -eq 0 ]
  [ ! -e "$log" ]
  [ ! -e "$log.home" ]

  printf 'name: source-checkout\ndependencies:\n  apm:\n    - owner/source/skills/x#cccccccccccccccccccccccccccccccccccccccc\n' >"$authoring/apm.yml"
  run fixture_exec "$home" /usr/bin/env PATH="/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$authoring/scripts/apm-workspace.sh" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"owner/source/skills/x#cccccccccccccccccccccccccccccccccccccccc"* ]]
  [[ "$output" != *"owner/consumer/skills/x"* ]]
  [ ! -e "$log" ]
  [ ! -e "$log.home" ]
  [ "$(apm_tree_snapshot "$home")" = "$consumer_before" ]

  run fixture_exec "$home" /usr/bin/env PATH="/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$authoring/scripts/apm-workspace.sh" apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
  [ "$(apm_tree_snapshot "$home")" = "$consumer_before" ]
}

@test "validate uses HOME/.apm only when it is a checkout and rejects a catalog without .git" {
  local home authoring="$FX/authoring-old" bin="$FX/authoring-old-bin" log="$FX/authoring-old-apm.log" consumer_before
  setup_authoring_checkout "$authoring" "$log" "$bin"

  home="$(new_home old-checkout)"
  mkdir -p "$home/.apm/.git"
  printf 'name: old-checkout\ndependencies:\n  apm:\n    - owner/home-checkout/skills/x#eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\n' >"$home/.apm/apm.yml"
  printf "lockfile_version: '2'\ndependencies: []\n" >"$home/.apm/apm.lock.yaml"
  consumer_before="$(apm_tree_snapshot "$home")"
  run fixture_exec "$home" /usr/bin/env PATH="/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$authoring/scripts/apm-workspace.sh" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"owner/home-checkout/skills/x#eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"* ]]
  [ ! -e "$log" ]
  [ ! -e "$log.home" ]
  [ "$(apm_tree_snapshot "$home")" = "$consumer_before" ]

  home="$(new_home old-catalog-only)"
  mkdir -p "$home/.apm/catalog"
  run fixture_exec "$home" /usr/bin/env PATH="$bin:$FIXTURE_PATH" /bin/bash "$authoring/scripts/apm-workspace.sh" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"$home/.apm exists but is not an empty directory or git checkout"* ]]
}
