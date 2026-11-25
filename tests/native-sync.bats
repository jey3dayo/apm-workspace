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
  git -C "$FX/repo" add scripts/native.sh scripts/native-sync.sh scripts/native-home.py scripts/lock-hashes.py scripts/lib .gitignore
  git -C "$FX/repo" -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m fixture
  env GIT_CONFIG_GLOBAL="$FX/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_TEMPLATE_DIR="$FX/template" git init --bare -q "$FX/remote.git"
  git -C "$FX/repo" push -q "$FX/remote.git" HEAD:refs/heads/main
}

sync_fixture() {
  env -i PATH="$PATH" HOME="$FX/home" TMPDIR="$FX/tmp" GIT_CONFIG_GLOBAL="$FX/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    APM_NATIVE_SOURCE_URL="$FX/remote.git" APM_NATIVE_ACCOUNT_HOME="$FX/home" \
    "${@}"
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
  [[ "$output" == *".agents/skills: 1 -> 1 (+0)"* ]]
  [[ "$output" == *"Rollback of the migrated roots:"* ]]
  [ -f "$FX/home/.agents/skills/existing/SKILL.md" ]
  [ "$(find "$FX/home/.agents" -path '*.bak-*/existing/SKILL.md' | wc -l | tr -d ' ')" -eq 1 ]
}

failing_ssh_fixture() {
  local root
  root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  cp "$root/apm.yml" "$FX/repo/apm.yml"
  cat >"$FX/apm-stub" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = install ]; then
  printf 'ssh: connect to host github.com port 22: Connection refused\n' >&2
  printf 'fatal: Could not read from remote repository.\n' >&2
  exit 1
fi
EOF
  chmod +x "$FX/apm-stub"
  git -C "$FX/repo" add apm.yml
  git -C "$FX/repo" -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m ssh-failure
  git -C "$FX/repo" push -q "$FX/remote.git" HEAD:refs/heads/main
}

@test "sync suggests --https when a stage log shows an SSH transport failure" {
  failing_ssh_fixture
  run sync_fixture APM_BIN="$FX/apm-stub" bash "$FX/repo/scripts/native.sh" sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"native:sync stopped"* ]]
  [[ "$output" == *"retry over HTTPS: mise run native:sync -- --https"* ]]
}

@test "sync does not suggest --https when --https was already passed" {
  failing_ssh_fixture
  run sync_fixture APM_BIN="$FX/apm-stub" bash "$FX/repo/scripts/native.sh" sync --https
  [ "$status" -ne 0 ]
  [[ "$output" == *"native:sync stopped"* ]]
  [[ "$output" == *"ssh: connect to host github.com port 22"* ]]
  [[ "$output" != *"retry over HTTPS"* ]]
}

@test "retire_orphaned_receipts removes only receipts whose recorded root is gone" {
  local receipts="$FX/home/.apm/deployment-receipts" record="$FX/retired.txt"
  mkdir -p "$receipts/mcp" "$FX/parent" "$FX/alive-root"
  printf '{"root": "%s/gone", "scope": "user"}' "$FX/parent" >"$receipts/orphan.json"
  cp "$receipts/orphan.json" "$receipts/mcp/orphan.json"
  printf '{"root": "%s/alive-root", "scope": "user"}' "$FX" >"$receipts/alive.json"
  printf '{"root": "/missing-parent-%s/gone", "scope": "user"}' "$$" >"$receipts/unmounted.json"
  printf '{"root": "relative/path", "scope": "user"}' >"$receipts/relative.json"
  printf 'not json\n' >"$receipts/broken.json"
  run bash -c '. "$1/scripts/lib/native-roots.sh"; retire_orphaned_receipts "$2" "$3"' _ "$FX/repo" "$FX/home" "$record"
  [ "$status" -eq 0 ]
  [ ! -e "$receipts/orphan.json" ]
  [ ! -e "$receipts/mcp/orphan.json" ]
  [ -f "$receipts/alive.json" ]
  [ -f "$receipts/unmounted.json" ]
  [ -f "$receipts/relative.json" ]
  [ -f "$receipts/broken.json" ]
  [ "$(cat "$record")" = "orphan.json"$'\t'"$FX/parent/gone" ]
}

@test "the link guards flag a symlinked intermediate directory above a migrated root" {
  mkdir -p "$FX/outside/skills" "$FX/home/.gemini"
  ln -s "$FX/outside" "$FX/home/.gemini/antigravity-cli"
  run bash -c '
    MIGRATE_ROOTS=".agents/skills .claude/skills .claude/agents .cursor/agents .gemini/antigravity-cli/skills"
    REAL_HOME_TOOL_DIRS=".agents .claude .codex .cursor .gemini .cache Library Library/Caches"
    REAL_HOME_WRITE_PATHS=".gemini/antigravity-cli/skills"
    . "$1/scripts/lib/native-core.sh"
    . "$1/scripts/lib/native-roots.sh"
    root_escaping_links "$2"
    real_home_shared_entries "$2"
    reinstate_escaping_links "$2" 20260101T000000Z
  ' _ "$FX/repo" "$FX/home"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c "antigravity-cli -> ")" -eq 3 ]
}
