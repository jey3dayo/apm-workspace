#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  local root source
  root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source="${NATIVE_SAFETY_SOURCE:-$root}"
  FX="$(cd "$BATS_TEST_TMPDIR" && pwd -P)/native-safety"
  mkdir -p "$FX/repo/catalog/.apm/instructions" "$FX/home/.agents/skills/existing" "$FX/tmp" "$FX/template" "$FX/outside"
  # shellcheck source=scripts/lib/git-test-env.sh
  . "$root/scripts/lib/git-test-env.sh"
  apm_isolate_git_env
  export GIT_TEMPLATE_DIR="$FX/template"
  cp -R "$source/scripts" "$FX/repo/scripts"
  cp "$source/apm.yml" "$FX/repo/apm.yml"
  cp "$source/catalog/.apm/instructions/ai-collaboration.instructions.md" "$FX/repo/catalog/.apm/instructions/"
  printf 'tmp/\n' >"$FX/repo/.gitignore"
  printf 'fixture shipped\n' >"$FX/home/.agents/skills/existing/SKILL.md"
  git init -q -b main "$FX/repo"
  git -C "$FX/repo" add scripts apm.yml catalog .gitignore
  git -C "$FX/repo" -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m source
  git init --bare -q "$FX/remote.git"
  git -C "$FX/repo" push -q "$FX/remote.git" HEAD:refs/heads/main
  SHA="$(git -C "$FX/repo" rev-parse HEAD)"
  cat >"$FX/apm-stub" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\$1" = install ]; then
  if [ -f "$FX/block" ] && [[ "\$HOME" = */rehearsal-*/home ]] && mkdir "$FX/block-claimed" 2>/dev/null; then
    printf 'ready\n' >"$FX/ready"
    while [ ! -f "$FX/release" ]; do sleep 0.05; done
  fi
  mkdir -p "\$HOME/.agents/skills/existing" "\$HOME/.apm"
  printf 'fixture shipped\n' >"\$HOME/.agents/skills/existing/SKILL.md"
  printf 'lockfile_version: 1\n' >"\$HOME/.apm/apm.lock.yaml"
fi
EOF
  chmod +x "$FX/apm-stub"
  cat >"$FX/opencode-harness" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$1/scripts/native.sh"
. "$1/scripts/native-sync.sh"
SYNC_HOME="$2"
sync_workspace sync:opencode
EOF
  cat >"$FX/guide-harness" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$1/scripts/apm-workspace.sh"
catalog_instructions_body "$(tracked_catalog_instructions_path)"
EOF
  fixture bash "$FX/guide-harness" "$FX/repo" >"$FX/old-guide"
  printf '\nfixture guide update\n' >>"$FX/repo/catalog/.apm/instructions/ai-collaboration.instructions.md"
  git -C "$FX/repo" add catalog/.apm/instructions/ai-collaboration.instructions.md
  git -C "$FX/repo" -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m guide-update
  git -C "$FX/repo" push -q "$FX/remote.git" HEAD:refs/heads/main
  SHA="$(git -C "$FX/repo" rev-parse HEAD)"
}

fixture() {
  env -i PATH="$PATH" HOME="$FX/home" TMPDIR="$FX/tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_CEILING_DIRECTORIES="$FX" APM_NATIVE_ACCOUNT_HOME="$FX/home" APM_BIN="$FX/apm-stub" \
    APM_NATIVE_SOURCE_URL="$FX/remote.git" APM_WORKSPACE_DIR="$FX/repo" "$@"
}

native() {
  fixture bash "$FX/repo/scripts/native.sh" "$@"
}

prepare_rehearsal() {
  native backup --real-home --backup-dir "$FX/backup"
  native rehearse --real-home --backup-dir "$FX/backup" --source-ref "$SHA" --migrate
  for REHEARSAL in "$FX/backup"/rehearsal-*; do [ -d "$REHEARSAL" ] && break; done
}

wait_ready() {
  local attempts=0
  while [ ! -f "$FX/ready" ] && [ "$attempts" -lt 200 ]; do
    sleep 0.05
    attempts=$((attempts + 1))
  done
  [ -f "$FX/ready" ]
}

@test "native HOME lock excludes manual migrate rollback backup rehearsal and reinstate during sync" {
  local writer migrate_status rollback_status backup_status rehearse_status reinstate_status opencode_status inherited_status
  prepare_rehearsal
  printf 'block\n' >"$FX/block"
  native sync >"$FX/writer.log" 2>&1 &
  writer=$!
  wait_ready
  run native migrate --real-home --source-ref "$SHA" --rehearsal "$REHEARSAL"
  migrate_status="$status"
  printf '%s\n' "$output" >"$FX/second-migrate.log"
  run native migrate-rollback --real-home --stamp 20000101T000000Z
  rollback_status="$status"
  printf '%s\n' "$output" >"$FX/second-rollback.log"
  run native backup --real-home --backup-dir "$FX/second-backup"
  backup_status="$status"
  printf '%s\n' "$output" >"$FX/second-backup.log"
  run native rehearse --real-home --backup-dir "$FX/backup" --source-ref "$SHA" --migrate
  rehearse_status="$status"
  printf '%s\n' "$output" >"$FX/second-rehearse.log"
  run native reinstate --real-home --stamp 20000101T000000Z
  reinstate_status="$status"
  printf '%s\n' "$output" >"$FX/second-reinstate.log"
  run native opencode --real-home
  opencode_status="$status"
  printf '%s\n' "$output" >"$FX/second-opencode.log"
  cat >"$FX/forged-lock-harness" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec 8<>"$1/.cache/apm-native-operation.lock"
APM_NATIVE_LOCK_FD=8 bash "$2/scripts/native.sh" backup --real-home --backup-dir "$3"
EOF
  run fixture bash "$FX/forged-lock-harness" "$FX/home" "$FX/repo" "$FX/forged-backup"
  inherited_status="$status"
  printf '%s\n' "$output" >"$FX/second-inherited.log"
  printf 'release\n' >"$FX/release"
  wait "$writer" || :
  [ "$migrate_status" -ne 0 ]
  [ "$rollback_status" -ne 0 ]
  [ "$backup_status" -ne 0 ]
  [ "$rehearse_status" -ne 0 ]
  [ "$reinstate_status" -ne 0 ]
  [ "$opencode_status" -ne 0 ]
  [ "$inherited_status" -ne 0 ]
  local operation
  for operation in migrate rollback backup rehearse reinstate opencode inherited; do
    [[ "$(cat "$FX/second-$operation.log")" == *"another native operation is active"* ]]
  done
  [ ! -e "$FX/second-backup" ]
  [ ! -e "$FX/forged-backup" ]
}

@test "native OpenCode write ignores inherited output outside the target HOME" {
  cp "$FX/old-guide" "$FX/outside/AGENTS.md"
  local before
  before="$(git hash-object "$FX/outside/AGENTS.md")"
  run fixture APM_OPENCODE_OUTPUT="$FX/outside/AGENTS.md" bash "$FX/opencode-harness" "$FX/repo" "$FX/home"
  [ "$status" -eq 0 ]
  [ "$(git hash-object "$FX/outside/AGENTS.md")" = "$before" ]
  [ -f "$FX/home/.config/opencode/AGENTS.md" ]
}

@test "native OpenCode write rejects a parent symlink out of HOME without changing the linked guide" {
  mkdir -p "$FX/home/.config" "$FX/outside/opencode"
  cp "$FX/old-guide" "$FX/outside/opencode/AGENTS.md"
  local before
  before="$(git hash-object "$FX/outside/opencode/AGENTS.md")"
  ln -s "$FX/outside/opencode" "$FX/home/.config/opencode"
  run fixture bash "$FX/opencode-harness" "$FX/repo" "$FX/home"
  [ "$status" -ne 0 ]
  [ "$(git hash-object "$FX/outside/opencode/AGENTS.md")" = "$before" ]
}

@test "native OpenCode write rejects a hardlinked guide without changing either copy" {
  mkdir -p "$FX/home/.config/opencode"
  cp "$FX/old-guide" "$FX/outside/AGENTS.md"
  ln "$FX/outside/AGENTS.md" "$FX/home/.config/opencode/AGENTS.md"
  local before
  before="$(git hash-object "$FX/outside/AGENTS.md")"
  run fixture bash "$FX/opencode-harness" "$FX/repo" "$FX/home"
  [ "$status" -ne 0 ]
  [ "$(git hash-object "$FX/outside/AGENTS.md")" = "$before" ]
}

@test "migrate automatically restores a skill edited after rehearsal when it was an unapproved skip" {
  prepare_rehearsal
  [ ! -s "$REHEARSAL/skipped.txt" ]
  printf 'user edit after rehearsal\n' >"$FX/home/.agents/skills/existing/SKILL.md"
  run native migrate --real-home --source-ref "$SHA" --rehearsal "$REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"migrate replaced different entries than the rehearsal did"* ]]
  [[ "$output" == *"rolling the roots back"* ]]
  [ "$(cat "$FX/home/.agents/skills/existing/SKILL.md")" = 'user edit after rehearsal' ]
  local kept
  for kept in "$FX/home/.agents"/skills.native-*/existing/SKILL.md; do
    [ "$(cat "$kept")" = 'fixture shipped' ]
  done
}

@test "native lock metadata rejects a symlinked cache parent and a hardlinked lock file" {
  ln -s "$FX/outside" "$FX/home/.cache"
  run native backup --real-home --backup-dir "$FX/backup"
  [ "$status" -ne 0 ]
  [ ! -e "$FX/outside/apm-native-operation.lock" ]
  [ ! -e "$FX/backup" ]
  mv "$FX/home/.cache" "$FX/cache-link-kept"
  mkdir "$FX/home/.cache"
  printf 'owner metadata\n' >"$FX/outside/lock"
  chmod 600 "$FX/outside/lock"
  ln "$FX/outside/lock" "$FX/home/.cache/apm-native-operation.lock"
  run native backup --real-home --backup-dir "$FX/backup"
  [ "$status" -ne 0 ]
  [[ "$output" == *"one link"* ]]
  [ "$(cat "$FX/outside/lock")" = 'owner metadata' ]
  [ ! -e "$FX/backup" ]
}

@test "native lock metadata survives a holder crash and permits the next operation without deletion" {
  cat >"$FX/crash-child.py" <<'EOF'
import os
import signal

os.fstat(int(os.environ["APM_NATIVE_LOCK_FD"]))
os.kill(os.getppid(), signal.SIGKILL)
EOF
  run fixture python3 "$FX/repo/scripts/native-home.py" run "$FX/home" python3 "$FX/crash-child.py"
  [ "$status" -ne 0 ]
  local before
  before="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$FX/home/.cache/apm-native-operation.lock")"
  run native backup --real-home --backup-dir "$FX/after-crash"
  [ "$status" -eq 0 ]
  [ -f "$FX/after-crash/complete" ]
  [ "$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$FX/home/.cache/apm-native-operation.lock")" = "$before" ]
}
