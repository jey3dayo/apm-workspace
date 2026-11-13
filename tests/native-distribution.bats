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

# The lock a previous native deployment left: it records the hash apm wrote for .claude/skills/foo/SKILL.md.
seed_previous_lock() {
  local home="$1" recorded_content="$2" digest
  digest="$(printf '%s\n' "$recorded_content" | shasum -a 256 | awk '{print $1}')"
  mkdir -p "$home/.apm"
  cat >"$home/.apm/apm.lock.yaml" <<EOF
lockfile_version: '1'
dependencies:
- repo_url: fixture/foo
  name: foo
  deployed_files:
  - .claude/skills/foo
  - .claude/skills/foo/SKILL.md
  deployed_file_hashes:
    .claude/skills/foo/SKILL.md: sha256:$digest
EOF
}

# Deploys foo (with a link.md, so a link of that name in the old entry loses nothing) and, like apm install, replaces the
# lock, so the old hashes are only usable if they were read before install.
write_deploy_and_relock_stub() {
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nmkdir -p "$HOME/.claude/skills/foo" "$HOME/.apm"\necho "deployed by apm" >"$HOME/.claude/skills/foo/SKILL.md"\ncp "$HOME/.claude/skills/foo/SKILL.md" "$HOME/.claude/skills/foo/link.md"\nprintf "lockfile_version: 1\\n" >"$HOME/.apm/apm.lock.yaml"\n' >"$1"
  chmod +x "$1"
}

add_quoted_lock_record_of_missing_file() {
  printf "    '.claude/skills/foo/gone file.md': sha256:%064d\n" 0 >>"$1/.apm/apm.lock.yaml"
}

add_explicit_key_lock_record_of_missing_file() {
  printf '    ? .claude/skills/foo/gone-file-with-a-very-long-name.md\n    : sha256:%064d\n' 0 >>"$1/.apm/apm.lock.yaml"
}

add_comment_between_lock_record_of_missing_file() {
  printf '# a comment at column 0\n    .claude/skills/foo/gone.md: sha256:%064d\n' 0 >>"$1/.apm/apm.lock.yaml"
}

add_lock_record_of_missing_file_at() {
  printf '    %s: sha256:%064d\n' "$2" 0 >>"$1/.apm/apm.lock.yaml"
}

add_dot_segment_lock_record_of_missing_file() {
  add_lock_record_of_missing_file_at "$1" .claude/skills/./foo/gone.md
}

add_double_slash_lock_record_of_missing_file() {
  add_lock_record_of_missing_file_at "$1" .claude/skills//foo/gone.md
}

add_pycache_dotdot_lock_record_of_missing_file() {
  add_lock_record_of_missing_file_at "$1" .claude/skills/foo/__pycache__/../gone.md
}

# The lock's only record is for a path with a NUL in it, which a shell would read as the old entry's SKILL.md.
add_nul_path_lock_record_of_missing_file() {
  local digest
  digest="$(printf 'old foo\n' | shasum -a 256 | awk '{print $1}')"
  printf "lockfile_version: '1'\ndependencies:\n- deployed_file_hashes:\n    \"%s\": sha256:%s\n" '.claude/skills/foo/\0SKILL.md' "$digest" >"$1/.apm/apm.lock.yaml"
}

# The only deployed_file_hashes: in this lock is text of a block scalar; the dependencies hold no record of foo.
use_lock_with_hashes_only_in_a_block_scalar() {
  local digest
  digest="$(printf 'old foo\n' | shasum -a 256 | awk '{print $1}')"
  printf "lockfile_version: '1'\ndependencies: []\nnotes: |\n  deployed_file_hashes:\n    .claude/skills/foo/SKILL.md: sha256:%s\n" "$digest" >"$1/.apm/apm.lock.yaml"
}

add_link_to_home_file() {
  ln -s "$1/private-skills/private-link/SKILL.md" "$1/.claude/skills/foo/link.md"
  printf '    .claude/skills/foo/link.md: sha256:%s\n' "$(shasum -a 256 <"$1/private-skills/private-link/SKILL.md" | awk '{print $1}')" >>"$1/.apm/apm.lock.yaml"
}

add_duplicate_key_lock_record_of_missing_file() {
  printf '    .claude/skills/foo/SKILL.md: sha256:%064d\n' 0 >>"$1/.apm/apm.lock.yaml"
}

add_bad_hash_lock_record_of_missing_file() {
  printf '    .claude/skills/foo/gone.md: sha256:not-a-hash\n' >>"$1/.apm/apm.lock.yaml"
}

# foo and f\oo are different entries; an awk -v would read the second as the first.
write_deploy_foo_and_backslash_entry_stub() {
  cat >"$1" <<'EOF'
#!/bin/sh
[ "$1" = install ] || exit 0
newline="$(printf '\n.')"
newline="${newline%.}"
mkdir -p "$HOME/.claude/skills/foo" "$HOME/.claude/skills/f\\oo" "$HOME/.claude/skills/foo$newline" "$HOME/.apm"
echo "deployed by apm" >"$HOME/.claude/skills/foo/SKILL.md"
cp "$HOME/.claude/skills/foo/SKILL.md" "$HOME/.claude/skills/foo/link.md"
cp "$HOME/.claude/skills/foo/SKILL.md" "$HOME/.claude/skills/f\\oo/SKILL.md"
cp "$HOME/.claude/skills/foo/SKILL.md" "$HOME/.claude/skills/foo$newline/SKILL.md"
printf "lockfile_version: 1\n" >"$HOME/.apm/apm.lock.yaml"
EOF
  chmod +x "$1"
}

add_hand_edited_newline_entry() {
  mkdir -p "$1/.claude/skills/foo"$'\n'
  echo "hand edited" >"$1/.claude/skills/foo"$'\n'/SKILL.md
}

add_hand_edited_backslash_entry() {
  mkdir -p "$1/.claude/skills/f\\oo"
  echo "hand edited" >"$1/.claude/skills/f\\oo/SKILL.md"
}

add_unlisted_file_to_foo() {
  echo "not in the lock" >"$1/.claude/skills/foo/link.md"
}

make_skills_root_an_absolute_link() {
  mv "$1/.claude/skills" "$1/real-skills"
  ln -s "$1/real-skills" "$1/.claude/skills"
}

# Its target is outside what backup copies, so the link is broken in the rehearsal's clone.
make_skills_root_a_relative_link() {
  mv "$1/.claude/skills" "$1/real-skills"
  ln -s ../real-skills "$1/.claude/skills"
}

make_claude_directory_a_link() {
  mv "$1/.claude" "$1/real-claude"
  ln -s real-claude "$1/.claude"
}

# A third argument seeds a previous lock that records that content for .claude/skills/foo/SKILL.md; a fourth is a
# function that then changes the seeded HOME (called with the HOME) before the backup.
prepare_migrate() {
  local name="$1" stub="$2" lock_content="${3:-}" seed_more="${4:-}"
  M_HOME="$(new_home "$name")"
  M_BACKUP="$FX/backups/$name"
  seed_migrate_home "$M_HOME"
  [ -z "$lock_content" ] || seed_previous_lock "$M_HOME" "$lock_content"
  [ -z "$seed_more" ] || "$seed_more" "$M_HOME"
  real_native "$M_HOME" backup --real-home --backup-dir "$M_BACKUP"
  if [ "$stub" = real ]; then
    real_native "$M_HOME" rehearse --real-home --backup-dir "$M_BACKUP" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  else
    real_native_with_stub "$M_HOME" "$stub" rehearse --real-home --backup-dir "$M_BACKUP" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  fi
  M_REHEARSAL="$(dirname "$(compgen -G "$M_BACKUP/rehearsal-*/result.txt")")"
}

prepare_scoped_runtime() {
  cp -R "$SOURCE_REPO" "$FX/runtime"
  # shellcheck source=tests/native-test-helpers.bash
  . "$REPO_ROOT/tests/native-test-helpers.bash"
  copy_native_runtime "${NATIVE_SCOPED_SOURCE:-$REPO_ROOT}" "$FX/runtime"
  cp "$REPO_ROOT/apm.yml" "$FX/runtime/apm.yml"
}

scoped_native() {
  local home="$1"
  shift
  fixture_exec "$home" /usr/bin/env APM_NATIVE_ACCOUNT_HOME="$home" /bin/bash "$FX/runtime/scripts/native.sh" "$@"
}

seed_design_rule() {
  mkdir -p "$1/.claude/rules"
  printf -- '---\npaths:\n  - "**/catalog/.apm/instructions/*.instructions.md"\n---\n\n' >"$1/.claude/rules/claude-md-design.md"
  awk 'BEGIN { frontmatter = 1 } NR == 1 { next } frontmatter && $0 == "---" { frontmatter = 0; next } !frontmatter { if (!started && $0 == "") next; started = 1; print }' \
    "$SOURCE_REPO/catalog/.apm/instructions/claude-md-design.instructions.md" >>"$1/.claude/rules/claude-md-design.md"
}

@test "native updates a previous generated design body from the lock baseline and refuses edits or an invalid lock" {
  local home backup rehearsal old_hash digest
  prepare_scoped_runtime
  home="$(new_home previous-design)"
  seed_sentinels "$home"
  seed_design_rule "$home"
  printf 'PREVIOUS_GENERATED_BODY\n' >>"$home/.claude/rules/claude-md-design.md"
  cp "$home/.claude/rules/claude-md-design.md" "$FX/previous-design.md"
  old_hash="$(git hash-object "$FX/previous-design.md")"
  digest="$(shasum -a 256 "$FX/previous-design.md" | awk '{ print $1 }')"
  mkdir -p "$home/.apm"
  cat >"$FX/previous-lock.yaml" <<EOF
lockfile_version: '1'
dependencies:
- repo_url: fixture-owner/apm-workspace
  name: catalog
  virtual_path: catalog
  resolved_commit: $SOURCE_SHA
  deployed_files:
  - .claude/rules/claude-md-design.md
  deployed_file_hashes:
    .claude/rules/claude-md-design.md: sha256:$digest
EOF
  cp "$FX/previous-lock.yaml" "$home/.apm/apm.lock.yaml"
  printf 'USER_EDIT_MARKER\n' >>"$home/.claude/rules/claude-md-design.md"
  backup="$FX/edited-backup"
  scoped_native "$home" backup --real-home --backup-dir "$backup"
  run scoped_native "$home" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *"$home/.claude/rules/claude-md-design.md differs"* ]]
  grep -q USER_EDIT_MARKER "$home/.claude/rules/claude-md-design.md"
  cp "$FX/previous-design.md" "$home/.claude/rules/claude-md-design.md"
  printf 'dependencies: invalid\n' >"$home/.apm/apm.lock.yaml"
  backup="$FX/invalid-lock-backup"
  scoped_native "$home" backup --real-home --backup-dir "$backup"
  run scoped_native "$home" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *"$home/.claude/rules/claude-md-design.md differs"* ]]
  [ "$(git hash-object "$home/.claude/rules/claude-md-design.md")" = "$old_hash" ]
  cp "$FX/previous-lock.yaml" "$home/.apm/apm.lock.yaml"
  backup="$FX/pristine-backup"
  scoped_native "$home" backup --real-home --backup-dir "$backup"
  scoped_native "$home" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  rehearsal="$(dirname "$(compgen -G "$backup/rehearsal-*/result.txt")")"
  scoped_native "$home" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$rehearsal"
  [ "$(git hash-object "$home/.claude/rules/claude-md-design.md")" != "$old_hash" ]
  grep -q 'CLAUDE.md Design Principles' "$home/.claude/rules/claude-md-design.md"
  ! grep -q PREVIOUS_GENERATED_BODY "$home/.claude/rules/claude-md-design.md"
}

@test "native scoped design instruction preserves its paths and manual policy without entering global roots" {
  local home backup="$FX/backup" rehearsal expected
  prepare_scoped_runtime
  home="$(new_home scoped-design)"
  seed_sentinels "$home"
  seed_design_rule "$home"
  expected="$(git hash-object "$home/.claude/rules/claude-md-design.md")"
  printf 'PRIVATE_MODEL_POLICY_MARKER\n' >"$home/.claude/rules/model-policy.md"
  scoped_native "$home" backup --real-home --backup-dir "$backup"
  scoped_native "$home" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  rehearsal="$(dirname "$(compgen -G "$backup/rehearsal-*/result.txt")")"
  scoped_native "$home" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$rehearsal"
  [ "$(git hash-object "$home/.claude/rules/claude-md-design.md")" = "$expected" ]
  [ "$(cat "$home/.claude/rules/model-policy.md")" = PRIVATE_MODEL_POLICY_MARKER ]
  grep -q '^paths:' "$home/.claude/rules/claude-md-design.md"
  for root in .codex/AGENTS.md .cursor/AGENTS.md; do
    grep -q 'AI 開発協働ガイド' "$home/$root"
    ! grep -q 'CLAUDE.md Design Principles\|PRIVATE_MODEL_POLICY_MARKER\|Claude Code のモデル運用' "$home/$root"
  done
  [ ! -e "$home/.cursor/rules/claude-md-design.mdc" ]
}

@test "native refuses an edited design rule before rehearsal and rechecks after a clean rehearsal" {
  local home backup="$FX/backup" rehearsal edited
  prepare_scoped_runtime
  home="$(new_home edited-design)"
  seed_sentinels "$home"
  seed_design_rule "$home"
  printf 'USER_EDIT_MARKER\n' >>"$home/.claude/rules/claude-md-design.md"
  edited="$(git hash-object "$home/.claude/rules/claude-md-design.md")"
  scoped_native "$home" backup --real-home --backup-dir "$backup"
  run scoped_native "$home" rehearse --real-home --backup-dir "$backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *"$home/.claude/rules/claude-md-design.md differs"* ]]
  [ "$(git hash-object "$home/.claude/rules/claude-md-design.md")" = "$edited" ]
  [ ! -e "$home/.apm/apm.yml" ]
  seed_design_rule "$home"
  scoped_native "$home" backup --real-home --backup-dir "$FX/clean-backup"
  scoped_native "$home" rehearse --real-home --backup-dir "$FX/clean-backup" --source-ref "$SOURCE_SHA" --workspace-only --migrate
  rehearsal="$(dirname "$(compgen -G "$FX/clean-backup/rehearsal-*/result.txt")")"
  printf 'USER_EDIT_MARKER\n' >>"$home/.claude/rules/claude-md-design.md"
  run scoped_native "$home" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$rehearsal"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$home/.claude/rules/claude-md-design.md differs"* ]]
  [ "$(git hash-object "$home/.claude/rules/claude-md-design.md")" = "$edited" ]
  [ ! -e "$home/.apm/apm.yml" ]
}

@test "backup copies the backed-up paths, refuses to overwrite, and a clean rehearse loses nothing" {
  local home before backup="$FX/backups/real-clean" result
  home="$(new_home real-clean)"
  seed_sentinels "$home"
  before="$(backed_up_snapshot "$home")"

  real_native "$home" backup --real-home --backup-dir "$backup"
  [ -f "$backup/complete" ]
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
  [ "$(sentinel_snapshot "$M_HOME" | grep -E 'config.toml|settings.json')" = "$(grep -E 'config.toml|settings.json' <<<"$sentinels")" ]
  # The moved-aside roots are the originals, and the record lists them.
  [ "$(roots_snapshot "$M_HOME" ".bak-$stamp")" = "$original" ]
  [ "$(grep -c '^moved' "$M_HOME/.apm/native-migrate-$stamp.txt")" -eq 4 ]

  real_native "$M_HOME" migrate-rollback --real-home --stamp "$stamp"
  [ "$(roots_snapshot "$M_HOME")" = "$original" ]
  [ "$(sentinel_snapshot "$M_HOME")" = "$sentinels" ]
  [ -f "$M_HOME/.claude/skills.native-$stamp/ship/SKILL.md" ]
  [ -z "$(compgen -G "$M_HOME/.claude/skills.bak-*" || true)" ]

  # A second rollback finds every root already restored and changes nothing.
  listing_bak="$(find "$M_HOME" | LC_ALL=C sort)"
  run real_native "$M_HOME" migrate-rollback --real-home --stamp "$stamp"
  [ "$status" -eq 0 ]
  [ "$(find "$M_HOME" | LC_ALL=C sort)" = "$listing_bak" ]
}

@test "apm install runs with APM_NON_INTERACTIVE=1 so the Trust prompt cannot hold the lock on a terminal" {
  local stub="$FX/stub-apm-record-env" seen="$FX/apm-env-seen"
  printf '#!/bin/sh\n[ "$1" = install ] || exit 0\nprintf "%%s\\n" "${APM_NON_INTERACTIVE-unset}" >>"%s"\nmkdir -p "$HOME/.claude/skills/foo"\necho "deployed by apm" >"$HOME/.claude/skills/foo/SKILL.md"\n' "$seen" >"$stub"
  chmod +x "$stub"

  prepare_migrate non-interactive "$stub"
  [ -s "$seen" ]
  [ "$(sort -u "$seen")" = 1 ]
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

@test "an old entry that still matches the previous lock's hashes is replaced without an --allow-skip approval" {
  local stub="$FX/stub-apm-relock" stamp
  write_deploy_and_relock_stub "$stub"
  prepare_migrate skip-lock-match "$stub" "old foo"
  [ ! -s "$M_REHEARSAL/skipped.txt" ]
  [ "$(cat "$M_REHEARSAL/auto-approved-skips.txt")" = ".claude/skills/foo" ]
  [ "$(cut -f1 "$M_REHEARSAL/pristine-entries.txt")" = ".claude/skills/foo" ]

  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -eq 0 ]
  stamp="$(printf '%s\n' "$output" | tail -n 1)"
  [ ! -s "$M_HOME/.apm/native-migrate-$stamp.skipped.txt" ]
  [ "$(cat "$M_HOME/.apm/native-migrate-$stamp.auto-approved-skips.txt")" = ".claude/skills/foo" ]
  [ "$(cat "$M_HOME/.claude/skills/foo/SKILL.md")" = "deployed by apm" ]
  [ "$(cat "$M_HOME/.claude/skills.bak-$stamp/foo/SKILL.md")" = "old foo" ]
}

@test "an old entry edited after the previous lock recorded it is still reported for --allow-skip" {
  local stub="$FX/stub-apm-relock"
  write_deploy_and_relock_stub "$stub"
  prepare_migrate skip-lock-edited "$stub" "what apm deployed before the hand edit"
  [ "$(cat "$M_REHEARSAL/skipped.txt")" = ".claude/skills/foo" ]
  [ ! -s "$M_REHEARSAL/auto-approved-skips.txt" ]
}

@test "the lock is read as YAML: a record of a file the old entry no longer has blocks the approval however it is spelled" {
  local stub="$FX/stub-apm-relock" form
  write_deploy_and_relock_stub "$stub"
  for form in quoted explicit-key comment-between nul-path dot-segment double-slash pycache-dotdot duplicate-key bad-hash; do
    prepare_migrate "skip-lock-$form" "$stub" "old foo" "add_${form//-/_}_lock_record_of_missing_file"
    [ "$(cat "$M_REHEARSAL/skipped.txt")" = ".claude/skills/foo" ]
    [ ! -s "$M_REHEARSAL/auto-approved-skips.txt" ]
  done
}

@test "a file the lock does not list, or no lock at all, leaves the entry reported for --allow-skip" {
  local stub="$FX/stub-apm-relock"
  write_deploy_and_relock_stub "$stub"
  prepare_migrate skip-unlisted-file "$stub" "old foo" add_unlisted_file_to_foo
  [ "$(cat "$M_REHEARSAL/skipped.txt")" = ".claude/skills/foo" ]
  [ ! -s "$M_REHEARSAL/auto-approved-skips.txt" ]
  prepare_migrate skip-no-lock "$stub"
  [ "$(cat "$M_REHEARSAL/skipped.txt")" = ".claude/skills/foo" ]
  [ ! -s "$M_REHEARSAL/auto-approved-skips.txt" ]
}

@test "text of a block scalar that looks like a deployed_file_hashes section is not a record of the entry" {
  local stub="$FX/stub-apm-relock"
  write_deploy_and_relock_stub "$stub"
  prepare_migrate skip-lock-block-scalar "$stub" "old foo" use_lock_with_hashes_only_in_a_block_scalar
  [ "$(cat "$M_REHEARSAL/skipped.txt")" = ".claude/skills/foo" ]
  [ ! -s "$M_REHEARSAL/auto-approved-skips.txt" ]
}

@test "a link inside the entry, a root that is a link (absolute or relative) or a link above the root approves nothing, and the migrate lists agree with the rehearsal" {
  local stub="$FX/stub-apm-relock" seed
  write_deploy_and_relock_stub "$stub"
  for seed in add_link_to_home_file make_skills_root_an_absolute_link make_skills_root_a_relative_link make_claude_directory_a_link; do
    prepare_migrate "skip-link-$seed" "$stub" "old foo" "$seed"
    [ "$(cat "$M_REHEARSAL/skipped.txt")" = ".claude/skills/foo" ]
    [ ! -s "$M_REHEARSAL/auto-approved-skips.txt" ]
    run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
    [ "$status" -eq 0 ]
  done
}

@test "a pristine entry changed between the rehearsal and the migrate (edited, or edited with the lock rewritten to match) stops the migrate before it moves anything" {
  local stub="$FX/stub-apm-relock" before
  write_deploy_and_relock_stub "$stub"
  prepare_migrate skip-edited-after-rehearsal "$stub" "old foo"
  [ "$(cat "$M_REHEARSAL/auto-approved-skips.txt")" = ".claude/skills/foo" ]
  echo "edited after the rehearsal" >>"$M_HOME/.claude/skills/foo/SKILL.md"
  before="$(roots_snapshot "$M_HOME")"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"changed since the rehearsal"* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$before" ]
  [ -z "$(compgen -G "$M_HOME/.claude/skills.bak-*" || true)" ]

  prepare_migrate skip-relocked-after-rehearsal "$stub" "old foo"
  echo "new content" >"$M_HOME/.claude/skills/foo/SKILL.md"
  seed_previous_lock "$M_HOME" "new content"
  before="$(roots_snapshot "$M_HOME")"
  run real_native_with_stub "$M_HOME" "$stub" migrate --real-home --source-ref "$SOURCE_SHA" --workspace-only --rehearsal "$M_REHEARSAL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"changed since the rehearsal"* ]]
  [ "$(roots_snapshot "$M_HOME")" = "$before" ]
}

@test "an entry whose name holds a backslash is not taken for the pristine entry it would read as" {
  local stub="$FX/stub-apm-backslash"
  write_deploy_foo_and_backslash_entry_stub "$stub"
  prepare_migrate skip-backslash-name "$stub" "old foo" add_hand_edited_backslash_entry
  [ "$(cat "$M_REHEARSAL/skipped.txt")" = '.claude/skills/f\oo' ]
  [ "$(cat "$M_REHEARSAL/auto-approved-skips.txt")" = ".claude/skills/foo" ]
}

@test "an entry whose name ends in a newline is not taken for the pristine entry it would read as" {
  local stub="$FX/stub-apm-newline"
  write_deploy_foo_and_backslash_entry_stub "$stub"
  prepare_migrate skip-newline-name "$stub" "old foo" add_hand_edited_newline_entry
  [ "$(cat "$M_REHEARSAL/auto-approved-skips.txt")" = ".claude/skills/foo" ]
  [ "$(wc -l <"$M_REHEARSAL/auto-approved-skips.txt" | tr -d ' ')" -eq 1 ]
}

@test "lock-hashes pristine lists the entries that hold exactly what the lock records, ignoring __pycache__ and .apm-pin" {
  local home python lock out
  home="$(new_home pristine-mode)"
  python="$(APM_BIN="$APM_BIN" /bin/bash -c '. "$1/scripts/native.sh"; lock_python' _ "$REPO_ROOT")"
  hash_of() { shasum -a 256 <"$1" | awk '{print $1}'; }
  entry_digest() { printf '%s\n' "$@" | LC_ALL=C sort | shasum -a 256 | awk '{print $1}'; }

  mkdir -p "$home/.claude/skills/dir/sub/__pycache__" "$home/.claude/skills/extra" "$home/.claude/skills/linked" "$home/.claude/agents"
  printf 'skill\n' >"$home/.claude/skills/dir/SKILL.md"
  printf 'nested\n' >"$home/.claude/skills/dir/sub/a.txt"
  printf 'cache\n' >"$home/.claude/skills/dir/sub/__pycache__/a.pyc"
  printf 'pin\n' >"$home/.claude/skills/dir/.apm-pin"
  printf 'one\n' >"$home/.claude/skills/extra/SKILL.md"
  printf 'unrecorded\n' >"$home/.claude/skills/extra/more.md"
  printf 'two\n' >"$home/.claude/skills/linked/SKILL.md"
  ln -s SKILL.md "$home/.claude/skills/linked/alias.md"
  printf 'agent\n' >"$home/.claude/agents/single.md"
  printf 'unrecorded\n' >"$home/.claude/agents/unlocked.md"

  lock="$home/lock.yaml"
  {
    printf "lockfile_version: '1'\ndependencies:\n- deployed_file_hashes:\n"
    printf '    %s: sha256:%s\n' \
      .claude/skills/dir/SKILL.md "$(hash_of "$home/.claude/skills/dir/SKILL.md")" \
      .claude/skills/dir/sub/a.txt "$(hash_of "$home/.claude/skills/dir/sub/a.txt")" \
      .claude/skills/extra/SKILL.md "$(hash_of "$home/.claude/skills/extra/SKILL.md")" \
      .claude/skills/linked/SKILL.md "$(hash_of "$home/.claude/skills/linked/SKILL.md")" \
      .claude/skills/linked/alias.md "$(hash_of "$home/.claude/skills/linked/SKILL.md")" \
      .claude/agents/single.md "$(hash_of "$home/.claude/agents/single.md")"
  } >"$lock"

  out="$(env -i "$python" -I "$REPO_ROOT/scripts/lock-hashes.py" pristine "$lock" "$home" .claude/skills .claude/agents .cursor/agents)"
  [ "$out" = "$(
    printf '.claude/agents/single.md\t%s\n' "$(entry_digest "$(hash_of "$home/.claude/agents/single.md")  single.md")"
    printf '.claude/skills/dir\t%s\n' "$(entry_digest \
      "$(hash_of "$home/.claude/skills/dir/SKILL.md")  dir/SKILL.md" \
      "$(hash_of "$home/.claude/skills/dir/sub/a.txt")  dir/sub/a.txt")"
  )" ]
}

@test "a lock record whose path is not valid UTF-8 makes the whole lock unreadable, even outside the roots" {
  local home python digest
  home="$(new_home pristine-surrogate)"
  python="$(APM_BIN="$APM_BIN" /bin/bash -c '. "$1/scripts/native.sh"; lock_python' _ "$REPO_ROOT")"
  mkdir -p "$home/.claude/skills/foo" "$home/.apm"
  printf 'skill\n' >"$home/.claude/skills/foo/SKILL.md"
  digest="$(shasum -a 256 <"$home/.claude/skills/foo/SKILL.md" | awk '{print $1}')"
  printf "lockfile_version: '1'\ndependencies:\n- deployed_file_hashes:\n    .claude/skills/foo/SKILL.md: sha256:%s\n    \"unrelated/\\\\uD800\": sha256:%064d\n" \
    "$digest" 0 >"$home/.apm/apm.lock.yaml"
  grep -qF 'unrelated/\uD800' "$home/.apm/apm.lock.yaml"

  run -1 env -i "$python" -I "$REPO_ROOT/scripts/lock-hashes.py" pristine "$home/.apm/apm.lock.yaml" "$home" .claude/skills
  [ -z "$(env -i "$python" -I "$REPO_ROOT/scripts/lock-hashes.py" pristine "$home/.apm/apm.lock.yaml" "$home" .claude/skills 2>/dev/null)" ]

  run --separate-stderr /bin/bash -c '. "$1/scripts/native.sh"; APM_BIN="$2"; pristine_entries "$3"' _ "$REPO_ROOT" "$APM_BIN" "$home"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"could not be read as expected"* ]]
}
