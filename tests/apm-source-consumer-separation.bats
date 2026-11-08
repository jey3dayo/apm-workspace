#!/usr/bin/env bats
#
# Runs the real APM CLI to show that the authoring source (a git repository of APM packages) and a consumer's
# global state ($HOME/.apm with apm.yml, apm.lock.yaml and apm_modules, plus the runtime roots under $HOME) can
# live apart: the consumer pins the source by commit SHA and nothing flows back. docs/source-consumer-separation.md
# records the findings and the limits.
#
# Every apm call gets `env -i`, a disposable HOME inside the fixture root, and a dependency host that cannot
# resolve (fixture.invalid), which the fixture's own git config redirects to a local repository. Where
# sandbox-exec exists (macOS) a profile also denies network access and writes outside the fixture root; elsewhere
# the HOME guard in fixture_exec is the only protection.
#
# The fixture root is BATS_FILE_TMPDIR, or a fresh directory under APM_SEPARATION_FIXTURE_ROOT when that is set
# (to keep these fixtures somewhere other than the suite-wide TMPDIR).

bats_require_minimum_version 1.5.0

# The APM release the docs' claims were measured on; bump it only after re-checking them.
EXPECTED_APM_VERSION=0.35.0

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
  # shellcheck source=../scripts/lib/git-test-env.sh
  . "$REPO_ROOT/scripts/lib/git-test-env.sh"
  apm_isolate_git_env

  REAL_HOME="$(cd "$HOME" && pwd -P)"
  export REAL_HOME
  if [ -n "${APM_SEPARATION_FIXTURE_ROOT:-}" ]; then
    assert_fixture_root_allowed "$APM_SEPARATION_FIXTURE_ROOT" || return 1
    mkdir -p "$APM_SEPARATION_FIXTURE_ROOT"
    FX="$(cd "$(mktemp -d "$APM_SEPARATION_FIXTURE_ROOT/run.XXXXXX")" && pwd -P)"
  else
    FX="$(cd "$BATS_FILE_TMPDIR" && pwd -P)"
  fi
  export FX
  assert_fixture_root_allowed "$FX" || return 1
  FIXTURE_PATH="$(dirname "$(command -v git)"):/usr/bin:/bin:/usr/sbin:/sbin"
  export FIXTURE_PATH
  mkdir -p "$FX/tmp" "$FX/homes"

  SANDBOX_EXEC=""
  if command -v sandbox-exec >/dev/null 2>&1; then
    SANDBOX_EXEC="$(command -v sandbox-exec)"
    write_sandbox_profile "$FX/sandbox.sb"
    assert_sandbox_confines_writes || return 1
  fi
  export SANDBOX_EXEC

  APM_BIN="$(resolve_apm_bin)" || return 1
  export APM_BIN
  assert_apm_version || return 1

  build_authoring_repo "$FX/src/authoring"
  write_fixture_gitconfig "$FX/gitconfig" "$FX/src/authoring"
}

# Physical path of $1, resolved through its nearest existing ancestor so a root that does not exist yet is checked
# before anything is created.
physical_path() {
  local path="$1" rest=""
  while [ ! -d "$path" ]; do
    rest="/$(basename "$path")$rest"
    path="$(dirname "$path")"
  done
  printf '%s%s\n' "$(cd "$path" && pwd -P)" "$rest"
}

# A root inside the invoking HOME is allowed (a scratch directory there is fine), but never the HOME itself, one of
# its ancestors, or a directory where APM or the three tools keep real state.
assert_fixture_root_allowed() {
  local root surface
  case "/$1/" in
    */../*) echo "the fixture root $1 must not contain '..'" >&2 && return 1 ;;
  esac
  root="$(physical_path "$1")"
  local prefix="${root%/}/"
  case "$REAL_HOME/" in
    "$prefix"*) echo "the fixture root $root must not be the invoking HOME or contain it" >&2 && return 1 ;;
  esac
  # Each surface is compared both as written and resolved, so a symlinked ~/.apm still protects its target.
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

# Runs under the same isolation as every other apm call, so even the version probe never sees the real HOME.
assert_apm_version() {
  local version
  version="$(apm_in "$(new_home version)" "$FX/tmp" --version 2>&1)" || {
    echo "apm at $APM_BIN does not run under the fixture isolation: $version" >&2
    return 1
  }
  # `apm --version` prints "Agent Package Manager (APM) CLI version <version>".
  [ "${version##* }" = "$EXPECTED_APM_VERSION" ] || {
    echo "expected APM $EXPECTED_APM_VERSION, got: $version" >&2
    return 1
  }
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

# The authoring repo is built under the same isolation as apm, with an empty template so no caller hook gets in.
fixture_git() {
  mkdir -p "$FX/empty-git-template"
  fixture_exec "$(new_home author)" "$FX" /usr/bin/env GIT_TEMPLATE_DIR="$FX/empty-git-template" \
    GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' \
    git -C "$AUTHORING" -c user.name=fixture -c user.email=fixture@example.invalid "$@"
}

write_skill() {
  mkdir -p "$(dirname "$1")"
  printf -- '---\nname: %s\ndescription: Synthetic fixture skill.\n---\n\n%s\n' "$(basename "$(dirname "$1")")" "$2" >"$1"
}

write_reader_agent() {
  mkdir -p "$(dirname "$1")"
  printf -- '---\nname: fixture-reader\ndescription: Synthetic read-only agent.\ntools: Read, Grep\ndisallowedTools: Write, Edit\n---\n\nRead-only fixture agent.\n' >"$1"
}

write_guide() {
  mkdir -p "$(dirname "$1")"
  printf -- '---\ndescription: Synthetic global guidance\n---\n\n# Fixture guidance\n\n%s\n' "$2" >"$1"
}

# catalog mirrors the real catalog package (targets without codex), manual-skills a second package in the same
# repository, unguarded the same agent without targets. The root .apm/ only exists to show that a consumer never
# reads it. v1 and v2 are commits; the v3 edit stays uncommitted in the working tree.
build_authoring_repo() {
  AUTHORING="$1"
  mkdir -p "$AUTHORING"
  fixture_git init -q -b main
  printf 'name: authoring-root\nversion: 0.0.1\n' >"$AUTHORING/apm.yml"
  write_skill "$AUTHORING/.apm/skills/authoring-only/SKILL.md" "authoring root only"
  mkdir -p "$AUTHORING/catalog" "$AUTHORING/manual-skills" "$AUTHORING/unguarded"
  printf 'name: catalog\nversion: 1.0.0\ndescription: Synthetic catalog\ntargets: [claude, cursor, agent-skills]\n' >"$AUTHORING/catalog/apm.yml"
  write_skill "$AUTHORING/catalog/.apm/skills/fixture-alpha/SKILL.md" "alpha v1"
  write_reader_agent "$AUTHORING/catalog/.apm/agents/fixture-reader.agent.md"
  write_guide "$AUTHORING/catalog/.apm/instructions/fixture-guide.instructions.md" "guide v1"
  printf 'name: manual-skills\nversion: 1.0.0\ndescription: Synthetic manual lane\n' >"$AUTHORING/manual-skills/apm.yml"
  write_skill "$AUTHORING/manual-skills/.apm/skills/fixture-manual/SKILL.md" "manual v1"
  printf 'name: unguarded\nversion: 1.0.0\ndescription: Same agent without targets\n' >"$AUTHORING/unguarded/apm.yml"
  write_reader_agent "$AUTHORING/unguarded/.apm/agents/fixture-reader.agent.md"
  fixture_git add apm.yml .apm catalog manual-skills unguarded
  fixture_git commit -q -m v1
  SHA1="$(fixture_git rev-parse HEAD)"

  write_skill "$AUTHORING/catalog/.apm/skills/fixture-alpha/SKILL.md" "alpha v2"
  write_guide "$AUTHORING/catalog/.apm/instructions/fixture-guide.instructions.md" "guide v2"
  fixture_git add catalog
  fixture_git commit -q -m v2
  SHA2="$(fixture_git rev-parse HEAD)"

  write_skill "$AUTHORING/catalog/.apm/skills/fixture-alpha/SKILL.md" "alpha v3 uncommitted"
  AUTHORING_STATUS="$(fixture_git status --porcelain --ignored)"
  export AUTHORING SHA1 SHA2 AUTHORING_STATUS
}

write_fixture_gitconfig() {
  cat >"$1" <<EOF
[url "file://$2"]
	insteadOf = https://fixture.invalid/fixture-owner/fixture-authoring.git
[protocol "file"]
	allow = always
EOF
}

# A fresh consumer HOME. The version-check stamp keeps apm from asking GitHub for a newer release.
new_home() {
  local home="$FX/homes/$1"
  mkdir -p "$home/.apm" "$home/.cache/apm"
  touch "$home/.cache/apm/last_version_check"
  printf '%s\n' "$home"
}

# $1 home, $2 pinned commit, rest: package paths inside the authoring repository.
write_consumer_manifest() {
  local home="$1" ref="$2" pkg
  shift 2
  {
    printf 'name: fixture-consumer\nversion: 0.0.1\ntargets:\n  - claude\n  - codex\n  - cursor\n  - agent-skills\n'
    printf 'dependencies:\n  apm:\n'
    for pkg in "$@"; do
      printf '    - git: https://fixture.invalid/fixture-owner/fixture-authoring.git\n      path: %s\n      ref: %s\n' "$pkg" "$ref"
    done
  } >"$home/.apm/apm.yml"
}

# Runs a command the way apm runs: no inherited environment (tokens, proxies, askpass, SSH agent), git reading only
# the fixture's global config, and the sandbox when there is one.
fixture_exec() {
  local home cwd="$2"
  # Compare the physical path, so `..` segments or a symlink cannot point HOME out of the fixture.
  home="$(cd "$1" 2>/dev/null && pwd -P)" || {
    echo "refusing to run with HOME=$1: not an existing directory" >&2
    return 97
  }
  shift 2
  case "$home" in
    "$FX"/homes/*/*) echo "refusing to run with HOME=$home: not a direct child of $FX/homes" >&2 && return 97 ;;
    "$FX"/homes/?*) ;;
    *) echo "refusing to run with HOME=$home outside the fixture" >&2 && return 97 ;;
  esac
  [ "$home" != "$REAL_HOME" ] || return 97
  local cmd=(env -i HOME="$home" TMPDIR="$FX/tmp" PATH="$FIXTURE_PATH" LANG="${LANG:-C.UTF-8}" PYTHONUTF8=1
    GIT_CONFIG_GLOBAL="$FX/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$FX")
  if [ -n "$SANDBOX_EXEC" ]; then
    cmd+=("$SANDBOX_EXEC" -f "$FX/sandbox.sb")
  fi
  (cd "$cwd" && "${cmd[@]}" "$@")
}

apm_in() {
  local home="$1" cwd="$2"
  shift 2
  fixture_exec "$home" "$cwd" "$APM_BIN" "$@"
}

install_and_compile() {
  apm_in "$1" "${2:-$1}" install -g || return 1
  apm_in "$1" "${2:-$1}" compile -g --clean
}

# Files and links under the runtime roots, relative to HOME.
deployed_set() {
  (cd "$1" && find .agents .claude .codex .cursor \( -type f -o -type l \) 2>/dev/null | LC_ALL=C sort)
}

# Everything apm can touch except caches and receipts (receipt names derive from the HOME path).
home_snapshot() {
  (cd "$1" && find . \( -path ./.apm/apm_modules -o -path ./.apm/deployment-receipts -o -path ./.cache -o -path ./Library \) -prune -o \
    \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"; else printf '%s %s\n' "$f" "$(git hash-object "$f")"; fi
  done)
}

locked_commits() {
  grep -E '^ *resolved_commit:' "$1/.apm/apm.lock.yaml" | awk '{print $2}'
}

assert_authoring_untouched() {
  [ "$(fixture_git rev-parse HEAD)" = "$SHA2" ]
  [ "$(fixture_git --no-optional-locks status --porcelain --ignored)" = "$AUTHORING_STATUS" ]
}

seed_sentinels() {
  local home="$1"
  mkdir -p "$home/.claude/skills/private-copy" "$home/.agents/skills/herdr-automations" "$home/.codex" \
    "$FX/private/$(basename "$home")/private-link"
  echo "private copy" >"$home/.claude/skills/private-copy/SKILL.md"
  echo "private link target" >"$FX/private/$(basename "$home")/private-link/SKILL.md"
  ln -s "$FX/private/$(basename "$home")/private-link" "$home/.claude/skills/private-link"
  echo "tool-owned" >"$home/.agents/skills/herdr-automations/SKILL.md"
  echo 'model = "fixture"' >"$home/.codex/config.toml"
  echo '{"fixture": true}' >"$home/.claude/settings.json"
  echo "hand-written root" >"$home/.claude/CLAUDE.md"
}

sentinel_snapshot() {
  (cd "$1" && for f in .claude/skills/private-copy/SKILL.md .claude/skills/private-link .claude/skills/private-link/SKILL.md \
    .agents/skills/herdr-automations/SKILL.md .codex/config.toml .claude/settings.json .claude/CLAUDE.md; do
    if [ -L "$f" ]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"; else printf '%s %s\n' "$f" "$(git hash-object "$f")"; fi
  done)
}

@test "apm starts without inherited credentials, proxies or askpass, whatever the caller exports" {
  home="$(new_home env)"
  export GITHUB_TOKEN=fixture-secret GH_TOKEN=fixture-secret GITHUB_APM_PAT=fixture-secret \
    HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9 \
    GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false SSH_AUTH_SOCK="$FX/tmp/agent.sock" XDG_CONFIG_HOME="$FX/tmp/xdg"

  run fixture_exec "$home" "$home" /usr/bin/env
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | cut -d= -f1 | LC_ALL=C sort | paste -sd' ' -)" = \
    "GIT_CEILING_DIRECTORIES GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM HOME LANG PATH PYTHONUTF8 TMPDIR" ]
  [[ "$output" != *fixture-secret* ]]
}

@test "git inside the wrapper reads only the fixture's global config and the authoring repo's own config" {
  home="$(new_home gitconfig)"

  run fixture_exec "$home" "$AUTHORING" git config --list --show-scope --show-origin
  [ "$status" -eq 0 ]
  while IFS=$'\t' read -r scope origin entry; do
    case "$scope $origin" in
      "global file:$FX/gitconfig" | "local file:.git/config") ;;
      *) echo "unexpected git config source: $scope $origin $entry" >&2 && return 1 ;;
    esac
    case "$entry" in
      credential.* | include.* | includeif.* | http.* | https.* | core.askpass=* | core.sshcommand=*)
        echo "unexpected git config entry: $entry" >&2 && return 1 ;;
    esac
  done <<<"$output"
  [[ "$output" == *"url.file://$AUTHORING.insteadof=https://fixture.invalid/fixture-owner/fixture-authoring.git"* ]]
}

@test "git inside the wrapper never discovers a checkout that encloses the fixture root" {
  home="$(new_home ceiling)"
  # The fixture root may sit under a real checkout; stand one up at the root itself, with config that must not leak.
  git init -q --template="$FX/empty-git-template" "$FX"
  git config -f "$FX/.git/config" credential.helper '!echo enclosing-leak'
  git config -f "$FX/.git/config" http.proxy http://127.0.0.1:9

  run fixture_exec "$home" "$FX/tmp" /usr/bin/env -u GIT_CEILING_DIRECTORIES git config --list --show-scope
  [ "$status" -eq 0 ]
  [[ "$output" == *enclosing-leak* ]]

  run fixture_exec "$home" "$FX/tmp" git config --list --show-scope
  [ "$status" -eq 0 ]
  [[ "$output" != *enclosing-leak* ]]
  [[ "$output" != *127.0.0.1:9* ]]
  run fixture_exec "$home" "$FX/tmp" git rev-parse --git-dir
  [ "$status" -ne 0 ]

  rm -rf "$FX/.git"
}

@test "a fixture root may sit in a scratch directory of HOME but never on HOME, its ancestors or tool state" {
  REAL_HOME="$FX/fake-home"
  mkdir -p "$REAL_HOME/.claude" "$REAL_HOME/scratch" "$FX/apm-elsewhere"
  ln -s "$REAL_HOME/.claude" "$REAL_HOME/scratch/claude-link"
  ln -s "$FX/apm-elsewhere" "$REAL_HOME/.apm"

  for root in "$REAL_HOME" "$FX" / "$REAL_HOME/.claude/fixtures" "$REAL_HOME/.codex/new/fixtures" \
    "$REAL_HOME/scratch/claude-link/fixtures" "$REAL_HOME/scratch/../.codex" \
    "$REAL_HOME/.apm" "$REAL_HOME/.apm/new" "$FX/apm-elsewhere/new"; do
    run assert_fixture_root_allowed "$root"
    [ "$status" -ne 0 ]
  done
  assert_fixture_root_allowed "$REAL_HOME/scratch/separation/new"
  [ ! -e "$REAL_HOME/scratch/separation" ]
  [ ! -e "$REAL_HOME/.codex" ]
  [ -z "$(ls -A "$FX/apm-elsewhere")" ]
}

@test "the HOME guard refuses paths that resolve outside the fixture, without running anything" {
  outside="$FX/outside"
  mkdir -p "$outside"
  ln -s "$outside" "$FX/homes/escape-link"

  for home in "$FX/homes/../outside" "$FX/homes/escape-link" "$FX/homes" "$FX/homes/missing" "$REAL_HOME"; do
    run fixture_exec "$home" "$FX/tmp" /usr/bin/touch "$outside/ran"
    [ "$status" -eq 97 ]
    [ ! -e "$outside/ran" ]
  done
}

# Loopback stands in for the network: an external host would make the test itself call out. The same request
# succeeding outside the sandbox shows the refusal comes from the profile, not from a dead listener.
@test "the sandbox refuses network connections that succeed without it" {
  [ -n "$SANDBOX_EXEC" ] || skip "no sandbox-exec on this host: network access is not blocked, only unused (see docs/source-consumer-separation.md)"
  [ -x /usr/bin/curl ] || skip "no /usr/bin/curl to probe with"
  command -v python3 >/dev/null 2>&1 || skip "no python3 for the loopback listener"
  home="$(new_home network)"
  python3 -c '
import socket, sys
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(4); s.settimeout(60)
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
while True:
    try:
        c, _ = s.accept()
    except OSError:
        break
    c.recv(1024); c.sendall(b"HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok"); c.close()
' "$FX/tmp/port" 3>&- &
  listener=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$FX/tmp/port" ] && break; sleep 0.2; done
  url="http://127.0.0.1:$(cat "$FX/tmp/port")/"

  run /usr/bin/curl -sS -m 5 "$url"
  control_status="$status" control_output="$output"
  run fixture_exec "$home" "$home" /usr/bin/curl -sS -m 5 -o /dev/null "$url"
  kill "$listener" 2>/dev/null || true

  [ "$control_status" -eq 0 ]
  [ "$control_output" = ok ]
  # 7: could not connect.
  [ "$status" -eq 7 ]
}

@test "a consumer HOME installs the authoring packages by SHA pin and deploys the three tools' surfaces" {
  home="$(new_home pinned)"
  write_consumer_manifest "$home" "$SHA1" catalog manual-skills

  run install_and_compile "$home"
  [ "$status" -eq 0 ]

  expected=".agents/skills/fixture-alpha/SKILL.md
.agents/skills/fixture-manual/SKILL.md
.claude/agents/fixture-reader.md
.claude/rules/fixture-guide.md
.claude/skills/fixture-alpha/SKILL.md
.claude/skills/fixture-manual/SKILL.md
.codex/AGENTS.md
.cursor/AGENTS.md
.cursor/agents/fixture-reader.md"
  [ "$(deployed_set "$home")" = "$expected" ]
  grep -qx 'alpha v1' "$home/.claude/skills/fixture-alpha/SKILL.md"
  grep -qx 'alpha v1' "$home/.agents/skills/fixture-alpha/SKILL.md"
  [ "$(locked_commits "$home")" = "$SHA1
$SHA1" ]
  [ ! -e "$AUTHORING/apm.lock.yaml" ]
  [ ! -e "$AUTHORING/apm_modules" ]
  assert_authoring_untouched
}

@test "compile -g writes the Codex and Cursor roots from the pinned instructions and leaves a hand-written Claude root" {
  home="$(new_home roots)"
  write_consumer_manifest "$home" "$SHA1" catalog
  mkdir -p "$home/.claude"
  echo "hand-written root" >"$home/.claude/CLAUDE.md"

  apm_in "$home" "$home" install -g
  [ "$(cat "$home/.claude/CLAUDE.md")" = "hand-written root" ]
  [ ! -e "$home/.codex/AGENTS.md" ]
  [ ! -e "$home/.cursor/AGENTS.md" ]
  run apm_in "$home" "$home" compile -g --clean
  [ "$status" -eq 0 ]

  for root in .codex/AGENTS.md .cursor/AGENTS.md; do
    [ "$(head -n 1 "$home/$root")" = "<!-- Generated by APM CLI from .apm/ primitives -->" ]
    grep -qx 'guide v1' "$home/$root"
  done
  [ "$(cat "$home/.claude/CLAUDE.md")" = "hand-written root" ]
  grep -qx 'guide v1' "$home/.claude/rules/fixture-guide.md"
}

@test "rerunning install and compile changes nothing, and a second fresh HOME resolves the same lock" {
  first="$(new_home rerun-a)"
  second="$(new_home rerun-b)"
  write_consumer_manifest "$first" "$SHA1" catalog manual-skills
  write_consumer_manifest "$second" "$SHA1" catalog manual-skills

  install_and_compile "$first"
  before="$(home_snapshot "$first")"
  install_and_compile "$first"
  [ "$(home_snapshot "$first")" = "$before" ]

  install_and_compile "$second"
  cmp "$first/.apm/apm.lock.yaml" "$second/.apm/apm.lock.yaml"
  [ "$(deployed_set "$first")" = "$(deployed_set "$second")" ]
  cmp "$first/.codex/AGENTS.md" "$second/.codex/AGENTS.md"
}

@test "authoring commits and uncommitted edits reach the consumer only when the pin moves" {
  home="$(new_home bump)"
  write_consumer_manifest "$home" "$SHA1" catalog manual-skills
  install_and_compile "$home"
  pinned="$(home_snapshot "$home")"

  # v2 is committed and v3 is a dirty edit in the authoring tree; the v1 pin keeps both out.
  install_and_compile "$home"
  [ "$(home_snapshot "$home")" = "$pinned" ]

  write_consumer_manifest "$home" "$SHA2" catalog manual-skills
  run install_and_compile "$home"
  [ "$status" -eq 0 ]
  grep -qx 'alpha v2' "$home/.claude/skills/fixture-alpha/SKILL.md"
  grep -qx 'alpha v2' "$home/.agents/skills/fixture-alpha/SKILL.md"
  grep -qx 'guide v2' "$home/.codex/AGENTS.md"
  [ "$(locked_commits "$home")" = "$SHA2
$SHA2" ]
  assert_authoring_untouched
}

@test "install, rerun and a pin bump keep private, tool-owned and runtime files apm does not own" {
  home="$(new_home sentinels)"
  seed_sentinels "$home"
  sentinels="$(sentinel_snapshot "$home")"
  write_consumer_manifest "$home" "$SHA1" catalog manual-skills

  install_and_compile "$home"
  [ "$(sentinel_snapshot "$home")" = "$sentinels" ]
  install_and_compile "$home"
  [ "$(sentinel_snapshot "$home")" = "$sentinels" ]
  write_consumer_manifest "$home" "$SHA2" catalog manual-skills
  install_and_compile "$home"
  [ "$(sentinel_snapshot "$home")" = "$sentinels" ]
}

@test "package targets keep the restricted agent out of Codex; without them APM writes a Codex agent without its tool limits" {
  guarded="$(new_home agents-guarded)"
  unguarded="$(new_home agents-unguarded)"
  write_consumer_manifest "$guarded" "$SHA1" catalog
  write_consumer_manifest "$unguarded" "$SHA1" unguarded

  apm_in "$guarded" "$guarded" install -g
  [ -f "$guarded/.claude/agents/fixture-reader.md" ]
  [ -f "$guarded/.cursor/agents/fixture-reader.md" ]
  [ ! -e "$guarded/.codex/agents" ]

  # Why catalog/apm.yml drops codex from targets: docs/package-decisions.md, the rejected Codex conversion.
  apm_in "$unguarded" "$unguarded" install -g
  [ -f "$unguarded/.codex/agents/fixture-reader.toml" ]
  run ! grep -qiE 'disallowed|^tools' "$unguarded/.codex/agents/fixture-reader.toml"
}

@test "the consumer ~/.apm deploys any primitive directory inside it, while the authoring root's .apm is never read" {
  home="$(new_home stray)"
  write_consumer_manifest "$home" "$SHA1" catalog
  write_skill "$home/.apm/skills/stray/SKILL.md" "stray"

  apm_in "$home" "$AUTHORING" install -g
  [ -f "$home/.claude/skills/stray/SKILL.md" ]
  [ -f "$home/.agents/skills/stray/SKILL.md" ]
  [ ! -e "$home/.claude/skills/authoring-only" ]
  [ ! -e "$home/.agents/skills/authoring-only" ]
  assert_authoring_untouched
}

@test "this checkout, which serves as the consumer ~/.apm, has no top-level primitive directory" {
  # The directory names APM 0.35.0 scans under a user-scope source root (install/phases/local_content.py).
  for name in skills instructions chatmodes agents prompts hooks commands extensions; do
    [ ! -d "$REPO_ROOT/$name" ] || {
      echo "$REPO_ROOT/$name would deploy as user-scope local content" >&2
      return 1
    }
  done
}
