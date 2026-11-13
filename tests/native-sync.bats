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
  [[ "$output" == *"Rollback of the four roots:"* ]]
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
