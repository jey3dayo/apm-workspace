#!/usr/bin/env bats
#
# Behavioral unit tests for scripts/apm-workspace.sh: the pure,
# side-effect-free helpers, the public command dispatch surface (invoked as a
# subprocess), and fixture-backed guards such as assert_catalog_stage_safety
# that protect the tracked catalog from destructive resets. Sourcing the
# script from bats leaves ${BASH_SOURCE[0]} != $0, so the bottom-of-file
# dispatch guard keeps the command dispatch from running on load.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Sourcing the script re-derives its own REPO_ROOT from $0 (the bats
  # runner), clobbering the value above. Subprocess-invocation tests need the
  # real repo root, so keep a copy that survives sourcing.
  TEST_REPO_ROOT="$REPO_ROOT"
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/apm-workspace.sh"
  source "$REPO_ROOT/scripts/apm-workspace.sh"
  mise_fixture=""
  mise_external_source=""
}

teardown() {
  if [[ -n "${mise_fixture:-}" ]]; then
    rm -rf "$mise_fixture"
  fi
  if [[ -n "${mise_external_source:-}" ]]; then
    rm -rf "$mise_external_source"
  fi
}

mise_tasks_json() {
  local directory="$1"
  shift
  # Keep only tasks whose source file is under the directory under test. This
  # excludes host overlays and tasks included from outside the fixture.
  env -u MISE_ENV -u MISE_CONFIG_FILE MISE_TRUSTED_CONFIG_PATHS="$directory" \
    mise -C "$directory" tasks --json "$@" \
    | node -e '
const fs = require("node:fs");
const path = require("node:path");
const directory = fs.realpathSync(path.resolve(process.argv[1]));
const tasks = JSON.parse(fs.readFileSync(0, "utf8"));
const isUnderDirectory = (source) => {
  if (typeof source !== "string" || source.length === 0) {
    return false;
  }
  let sourcePath;
  try {
    sourcePath = fs.realpathSync(path.resolve(source));
  }
  catch {
    return false;
  }
  const relative = path.relative(directory, sourcePath);
  return relative !== "" && !relative.startsWith("..") && !path.isAbsolute(relative);
};
process.stdout.write(JSON.stringify(tasks.filter((task) => isUnderDirectory(task.source))));
' "$directory"
}

node_json_assert() {
  local script="$1"
  shift
  node -e "$script" "$@"
}

rewrite_mise_fixture() {
  local path="$1"
  local pattern="$2"
  local replacement="$3"
  local flags="$4"
  node - "$path" "$pattern" "$replacement" "$flags" <<'NODE'
const fs = require("node:fs");
const [path, pattern, replacement, flags] = process.argv.slice(2);
const content = fs.readFileSync(path, "utf8");
const updated = content.replace(new RegExp(pattern, flags), replacement);
if (updated === content) {
  process.exit(1);
}
fs.writeFileSync(path, updated);
NODE
}

assert_public_mise_tasks() {
  local tasks_json="$1"
  shift
  node_json_assert '
const fs = require("node:fs");
const tasks = JSON.parse(fs.readFileSync(0, "utf8"));
const names = process.argv.slice(1);
if (!names.every((name) => tasks.some((task) => task.name === name))) {
  process.exit(1);
}
' "$@" <<<"$tasks_json"
}

assert_mise_tasks_absent() {
  local tasks_json="$1"
  shift
  node_json_assert '
const fs = require("node:fs");
const tasks = JSON.parse(fs.readFileSync(0, "utf8"));
const names = process.argv.slice(1);
if (names.some((name) => tasks.some((task) => task.name === name))) {
  process.exit(1);
}
' "$@" <<<"$tasks_json"
}

assert_mise_task_visibility() {
  local public_json="$1"
  local hidden_json="$2"
  local task_name
  for task_name in bootstrap setup:mcp:host; do
    node_json_assert '
const fs = require("node:fs");
const tasks = JSON.parse(fs.readFileSync(0, "utf8"));
const name = process.argv[1];
if (!tasks.some((task) => task.name === name && task.hide === true)) {
  process.exit(1);
}
' "$task_name" <<<"$hidden_json" || return 1
    node_json_assert '
const fs = require("node:fs");
const tasks = JSON.parse(fs.readFileSync(0, "utf8"));
const name = process.argv[1];
if (tasks.some((task) => task.name === name)) {
  process.exit(1);
}
' "$task_name" <<<"$public_json" || return 1
  done
}

assert_mise_check_depends() {
  local tasks_json="$1"
  local required
  for required in format:check lint:yaml lint:frontmatter lint:catalog-leaks validate; do
    node_json_assert '
const fs = require("node:fs");
const tasks = JSON.parse(fs.readFileSync(0, "utf8"));
const [taskName, required] = process.argv.slice(1);
const task = tasks.find(({ name }) => name === taskName);
if (!task || !Array.isArray(task.depends) || !task.depends.includes(required)) {
  process.exit(1);
}
' check "$required" <<<"$tasks_json" || return 1
  done
}

assert_mise_run_sequence() {
  local tasks_json="$1"
  local task_name="$2"
  local expected_json="$3"
  node_json_assert '
const fs = require("node:fs");
const { isDeepStrictEqual } = require("node:util");
const tasks = JSON.parse(fs.readFileSync(0, "utf8"));
const [name, expectedJson] = process.argv.slice(1);
const task = tasks.find(({ name: taskName }) => taskName === name);
const expected = JSON.parse(expectedJson);
if (!task || !isDeepStrictEqual(task.run, expected)) {
  process.exit(1);
}
' "$task_name" "$expected_json" <<<"$tasks_json"
}

assert_mise_command_connections() {
  local tasks_json="$1"
  node_json_assert '
const fs = require("node:fs");
const tasks = JSON.parse(fs.readFileSync(0, "utf8"));
const expected = [
  ["setup:mcp:host", "scripts/apm-workspace.sh", "setup:mcp:host"],
  ["doctor:workspace", "scripts/apm-workspace.sh", "doctor"],
  ["doctor:intake", "scripts/apm-workspace.sh", "doctor-intake"],
  ["validate:catalog", "scripts/apm-workspace.sh", "validate:catalog"],
  ["smoke:catalog", "scripts/apm-workspace.sh", "smoke:catalog"],
  ["format:markdown:bold-headings", "scripts/format-bold-headings.sh", "write"],
  ["format:markdown:bold-headings:check", "scripts/format-bold-headings.sh", "check"],
];
for (const [name, scriptPath, subcommand] of expected) {
  const task = tasks.find(({ name: taskName }) => taskName === name);
  const run = task?.run;
  const tokens = typeof run?.[0] === "string" ? run[0].trim().split(/\s+/) : [];
  if (
    !Array.isArray(run) ||
    run.length !== 1 ||
    !tokens.some((token) => token.endsWith(scriptPath)) ||
    !tokens.includes(subcommand)
  ) {
    process.exit(1);
  }
}
' <<<"$tasks_json"
}

new_mise_fixture() {
  mise_fixture="$(mktemp -d)"
  cp "$TEST_REPO_ROOT/mise.toml" "$mise_fixture/mise.toml"
  cp -R "$TEST_REPO_ROOT/mise" "$mise_fixture/mise"
  printf '%s\n' "$mise_fixture"
}

add_external_mise_task_fixture() {
  mise_external_source="$(mktemp -d)"
  printf '%s\n' '["outside-source"]' 'run = "echo outside"' >"$mise_external_source/tasks.toml"
  local includes
  printf -v includes '  "mise/format.toml",\n  "%s/tasks.toml",\n' "$mise_external_source"
  rewrite_mise_fixture "$mise_fixture/mise.toml" \
    '  "mise/format.toml",\r?\n' "$includes" ''
}

# --- validate_skill_id -------------------------------------------------------

@test "validate_skill_id accepts a plain, hyphenated, namespaced, or dotted/underscored id" {
  for id in "foo" "foo-bar" "a:b:c" "a.b_c"; do
    run validate_skill_id "$id"
    if [ "$status" -ne 0 ]; then
      echo "unexpected: $id"
      false
    fi
  done
}

@test "validate_skill_id rejects empty, dot segments, slashes, colon misuse, spaces, and a leading hyphen" {
  for id in "" "." ".." "a/b" 'a\b' ":lead" "trail:" "a::b" "bad space" "-leading"; do
    run validate_skill_id "$id"
    if [ "$status" -eq 0 ]; then
      echo "unexpected: $id"
      false
    fi
  done
}

# --- validate_skill_path_segments -------------------------------------------

@test "validate_skill_path_segments accepts a run of valid segments" {
  run validate_skill_path_segments "a:b:c" a b c
  [ "$status" -eq 0 ]
}

@test "validate_skill_path_segments rejects a run containing .." {
  run validate_skill_path_segments "a:..:c" a .. c
  [ "$status" -ne 0 ]
}

@test "validate_skill_path_segments rejects a run containing an empty segment" {
  run validate_skill_path_segments "a::c" a "" c
  [ "$status" -ne 0 ]
}

# --- skill_id_to_manifest_path ----------------------------------------------

@test "skill_id_to_manifest_path converts a:b:c to a/b/c" {
  run skill_id_to_manifest_path "a:b:c"
  [ "$status" -eq 0 ]
  [ "$output" = "a/b/c" ]
}

@test "skill_id_to_manifest_path leaves a single segment unchanged" {
  run skill_id_to_manifest_path "a"
  [ "$status" -eq 0 ]
  [ "$output" = "a" ]
}

# --- format_skill_name ------------------------------------------------------

@test "format_skill_name uses the logical leaf of a namespaced id" {
  run format_skill_name "sample:spec-init"
  [ "$status" -eq 0 ]
  [ "$output" = "spec-init" ]
}

@test "format_skill_name uses the final segment of a nested namespaced id" {
  run format_skill_name "mattpocock:engineering:wayfinder"
  [ "$status" -eq 0 ]
  [ "$output" = "wayfinder" ]
}

# --- host-local MCP bootstrap ----------------------------------------------

@test "resolve_1password_mcp_command prefers a native command" {
  fake_bin="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/1password-mcp"
  chmod +x "$fake_bin/1password-mcp"

  PATH="$fake_bin:$PATH" run resolve_1password_mcp_command

  [ "$status" -eq 0 ]
  [ "$output" = "$fake_bin/1password-mcp" ]
  rm -rf "$fake_bin"
}

@test "resolve_1password_mcp_command converts the Windows app alias under WSL" {
  fake_bin="$(mktemp -d)"
  cat >"$fake_bin/cmd.exe" <<'EOF'
#!/usr/bin/env bash
printf 'C:\\Users\\sample\\AppData\\Local\\Microsoft\\WindowsApps\\1password-mcp.exe\r\n'
EOF
  cat >"$fake_bin/wslpath" <<'EOF'
#!/usr/bin/env bash
printf '/mnt/c/Users/sample/AppData/Local/Microsoft/WindowsApps/1password-mcp.exe\n'
EOF
  chmod +x "$fake_bin/cmd.exe" "$fake_bin/wslpath"

  APM_1PASSWORD_MCP_APP_PATHS="" PATH="$fake_bin:/usr/bin:/bin" run resolve_1password_mcp_command

  [ "$status" -eq 0 ]
  [ "$output" = "/mnt/c/Users/sample/AppData/Local/Microsoft/WindowsApps/1password-mcp.exe" ]
  rm -rf "$fake_bin"
}

@test "mise bootstrap keeps host MCP setup tasks hidden" {
  public_json="$(mise_tasks_json "$TEST_REPO_ROOT")"
  hidden_json="$(mise_tasks_json "$TEST_REPO_ROOT" --hidden)"
  run assert_mise_task_visibility "$public_json" "$hidden_json"
  [ "$status" -eq 0 ]
}

@test "mise exposes the expected public task set" {
  tasks_json="$(mise_tasks_json "$TEST_REPO_ROOT")"
  run assert_public_mise_tasks "$tasks_json" \
    check doctor doctor:intake doctor:workspace format format:check test test:sh validate verify
  [ "$status" -eq 0 ]
}

@test "mise no longer exposes the retired legacy writer tasks" {
  tasks_json="$(mise_tasks_json "$TEST_REPO_ROOT" --hidden)"
  run assert_mise_tasks_absent "$tasks_json" \
    apply apply:skills:local check:roots deploy deploy:fresh deploy:pins install:catalog install:pins \
    migrate:roots prepare:catalog prune:cache refresh refresh:deploy repair:local-package-cache upgrade
  [ "$status" -eq 0 ]
}

@test "mise check contains the complete inspection dependency set" {
  tasks_json="$(mise_tasks_json "$TEST_REPO_ROOT" --hidden)"
  run assert_mise_check_depends "$tasks_json"
  [ "$status" -eq 0 ]
}

@test "mise keeps the doctor and verify run order" {
  tasks_json="$(mise_tasks_json "$TEST_REPO_ROOT" --hidden)"
  run assert_mise_run_sequence "$tasks_json" doctor '[{"task":"doctor:workspace"},{"task":"doctor:intake"}]'
  [ "$status" -eq 0 ]
  run assert_mise_run_sequence "$tasks_json" verify '[{"task":"check"},{"task":"test"},{"task":"smoke:catalog"}]'
  [ "$status" -eq 0 ]
}

@test "mise tasks connect to the expected workspace commands" {
  tasks_json="$(mise_tasks_json "$TEST_REPO_ROOT" --hidden)"
  run assert_mise_command_connections "$tasks_json"
  [ "$status" -eq 0 ]
}

@test "negative fixture excludes a task whose source is outside the target directory" {
  new_mise_fixture >/dev/null
  add_external_mise_task_fixture
  raw_json="$(env -u MISE_ENV -u MISE_CONFIG_FILE MISE_TRUSTED_CONFIG_PATHS="$mise_fixture" \
    mise -C "$mise_fixture" tasks --json --hidden)"
  run assert_public_mise_tasks "$raw_json" outside-source
  [ "$status" -eq 0 ]

  tasks_json="$(mise_tasks_json "$mise_fixture" --hidden)"
  run assert_public_mise_tasks "$tasks_json" outside-source
  [ "$status" -ne 0 ]
}

@test "negative fixture detects a mise task connected to another script" {
  new_mise_fixture >/dev/null
  rewrite_mise_fixture "$mise_fixture/mise.toml" \
    'bash \./scripts/apm-workspace\.sh doctor"' \
    'bash ./scripts/other.sh doctor"' ''
  tasks_json="$(mise_tasks_json "$mise_fixture" --hidden)"
  run assert_mise_command_connections "$tasks_json"
  [ "$status" -ne 0 ]
}

@test "command connection contract accepts a path without a leading ./" {
  new_mise_fixture >/dev/null
  rewrite_mise_fixture "$mise_fixture/mise.toml" \
    'bash \./scripts/apm-workspace\.sh doctor"' \
    'bash scripts/apm-workspace.sh doctor"' ''
  tasks_json="$(mise_tasks_json "$mise_fixture" --hidden)"
  run assert_mise_command_connections "$tasks_json"
  [ "$status" -eq 0 ]
}

@test "negative fixture detects a visible bootstrap task" {
  new_mise_fixture >/dev/null
  rewrite_mise_fixture "$mise_fixture/mise.toml" \
    '(\[tasks\.bootstrap\][^[]*)^[ \t]*hide = true\r?\n' '$1' 'm'
  public_json="$(mise_tasks_json "$mise_fixture")"
  hidden_json="$(mise_tasks_json "$mise_fixture" --hidden)"
  run assert_mise_task_visibility "$public_json" "$hidden_json"
  [ "$status" -ne 0 ]
}

@test "negative fixture detects a missing check inspection dependency" {
  new_mise_fixture >/dev/null
  rewrite_mise_fixture "$mise_fixture/mise.toml" \
    '^[ \t]*"lint:frontmatter",\r?\n' '' 'm'
  tasks_json="$(mise_tasks_json "$mise_fixture" --hidden)"
  run assert_mise_check_depends "$tasks_json"
  [ "$status" -ne 0 ]
}

# --- workspace_remote_to_repo_reference -------------------------------------

@test "workspace_remote_to_repo_reference parses an https remote" {
  run workspace_remote_to_repo_reference "https://github.com/owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

@test "workspace_remote_to_repo_reference parses a git@ remote" {
  run workspace_remote_to_repo_reference "git@github.com:owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

# --- public command dispatch surface ----------------------------------------

@test "unknown command exits non-zero with a diagnosable message" {
  run bash "$SCRIPT_UNDER_TEST" definitely-not-a-command
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
}

@test "the retired legacy writer commands are unknown, write nothing and are absent from help" {
  scratch_home="$(mktemp -d)"
  for retired in apply apply:skills:local refresh install-pins repair:local-package-cache pin-external \
    prune:cache prepare:catalog install:catalog check:roots migrate:roots; do
    run env HOME="$scratch_home" APM_WORKSPACE_DIR="$TEST_REPO_ROOT" bash "$SCRIPT_UNDER_TEST" "$retired"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown command: $retired"* ]]
  done
  [ -z "$(ls -A "$scratch_home")" ]

  run env HOME="$scratch_home" APM_WORKSPACE_DIR="$TEST_REPO_ROOT" bash "$SCRIPT_UNDER_TEST" help
  [ "$status" -eq 0 ]
  for retired in apply refresh install-pins repair:local-package-cache pin-external prune:cache \
    prepare:catalog install:catalog check:roots migrate:roots; do
    [[ "$output" != *"$retired"* ]]
  done
  rm -rf "$scratch_home"
}

# --- doctor target outputs --------------------------------------------------

make_doctor_fixture() {
  doctor_workspace_dir="$(mktemp -d)"
  doctor_home="$(mktemp -d)"
  doctor_bin="$(mktemp -d)"

  git -C "$doctor_workspace_dir" init -q
  mkdir -p \
    "$doctor_workspace_dir/catalog/.apm/skills" \
    "$doctor_workspace_dir/catalog/.apm/agents" \
    "$doctor_workspace_dir/catalog/commands" \
    "$doctor_workspace_dir/catalog/rules"
  printf 'dependencies: []\n' >"$doctor_workspace_dir/apm.yml"
  mkdir -p "$doctor_workspace_dir/catalog/.apm/instructions"
  printf -- '---\ndescription: fixture guide\n---\n\n# instructions\n' >"$doctor_workspace_dir/catalog/.apm/instructions/ai-collaboration.instructions.md"

  cat >"$doctor_bin/apm" <<'EOF'
#!/bin/sh
case "$1" in
  --version) printf '%s\n' 'apm test fixture' ;;
  deps|compile) ;;
esac
EOF
  chmod +x "$doctor_bin/apm"

  for target_dir in .claude .codex .cursor .config/opencode; do
    mkdir -p "$doctor_home/$target_dir/agents" "$doctor_home/$target_dir/commands" "$doctor_home/$target_dir/rules"
  done
  mkdir -p \
    "$doctor_home/.claude/skills" \
    "$doctor_home/.agents/skills" \
    "$doctor_home/.cursor/skills" \
    "$doctor_home/.config/opencode/skills"
  printf '# config\n' >"$doctor_home/.claude/CLAUDE.md"
  printf '# config\n' >"$doctor_home/.codex/AGENTS.md"
  printf '# config\n' >"$doctor_home/.cursor/AGENTS.md"
}

doctor_fixture_env() {
  # Pin XDG_STATE_HOME into the fixture explicitly: agmsg-state.sh (and the
  # doctor check mirroring it) fall back to "$HOME/.local/state" only when
  # XDG_STATE_HOME is unset, but this session's real XDG_STATE_HOME is set
  # and would otherwise leak in here, making the agmsg roster link check
  # compare against the live machine's state root instead of the fixture's.
  env HOME="$doctor_home" XDG_STATE_HOME="$doctor_home/.local/state" PATH="$doctor_bin:$PATH" APM_WORKSPACE_DIR="$doctor_workspace_dir" "$@"
}

@test "validate ignores nested deployed Codex skills" {
  make_doctor_fixture
  nested_skill_path="$doctor_home/.agents/skills/legacy/skills/nested/SKILL.md"
  mkdir -p "$(dirname "$nested_skill_path")"
  printf '# nested\n' >"$nested_skill_path"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -eq 0 ]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

write_pin_fixture() {
  make_doctor_fixture
  printf 'name: ws\ndependencies:\n  apm:\n%s\n' "$1" >"$doctor_workspace_dir/apm.yml"
  cat >"$doctor_workspace_dir/apm.lock.yaml" <<'EOF'
lockfile_version: '2'
dependencies:
- repo_url: owner/str
  resolved_commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  virtual_path: skills/str
- repo_url: k16/obj
  resolved_commit: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
- repo_url: owner/multi
  resolved_commit: 9999999999999999999999999999999999999999
EOF
}

pin_hint="apm.yml SHA pins differ from apm.lock.yaml; update the pinned entries of apm.lock.yaml to the same commits (no task re-resolves the root lock on a native HOME)."

@test "validate passes when every SHA pin, string or object form, is in the lock" {
  write_pin_fixture "    - owner/str/skills/str#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v1.0.0
    - git: https://gist.github.com/k16/obj.git
      ref: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb # v1.2.3"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -eq 0 ]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "validate fails naming a bumped string SHA pin and prints the pin update hint" {
  write_pin_fixture "    - owner/str/skills/str#cccccccccccccccccccccccccccccccccccccccc"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"owner/str/skills/str#cccccccccccccccccccccccccccccccccccccccc"* ]]
  [[ "$output" == *"$pin_hint"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "validate fails for a bumped object ref with a trailing version comment" {
  write_pin_fixture "    - git: https://gist.github.com/k16/obj.git
      ref: dddddddddddddddddddddddddddddddddddddddd # v1.2.3"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"https://gist.github.com/k16/obj.git#dddddddddddddddddddddddddddddddddddddddd"* ]]
  [[ "$output" == *"$pin_hint"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "validate passes an object pin with a skills subset against its own lock record" {
  write_pin_fixture "    - git: owner/multi
      ref: 9999999999999999999999999999999999999999 # v2
      skills:
        - a
        - b"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -eq 0 ]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "validate fails a string pin whose SHA exists only on an unrelated lock record" {
  write_pin_fixture "    - owner/str/skills/str#bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"owner/str/skills/str#bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"* ]]
  [[ "$output" == *"$pin_hint"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "validate fails an object pin whose SHA exists only on an unrelated lock record" {
  write_pin_fixture "    - git: owner/multi
      ref: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"owner/multi#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"* ]]
  [[ "$output" == *"$pin_hint"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "validate fails a pinned new dependency that has no lock record" {
  write_pin_fixture "    - owner/new/skills/x#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    - git: owner/new2
      ref: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"owner/new/skills/x#aaaa"*"(no lock record)"* ]]
  [[ "$output" == *"owner/new2#bbbb"*"(no lock record)"* ]]
  [[ "$output" == *"$pin_hint"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "validate ignores tag and branch refs" {
  write_pin_fixture "    - owner/other#main
    - owner/other2#v1.2.3
    - git: owner/other3
      ref: release"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -eq 0 ]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "validate accepts a short SHA pin that prefixes a locked commit" {
  write_pin_fixture "    - owner/str/skills/str#aaaaaaa"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -eq 0 ]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "validate ignores a SHA ref that appears only under mcp" {
  make_doctor_fixture
  cat >"$doctor_workspace_dir/apm.yml" <<'EOF'
name: ws
dependencies:
  apm: []
  mcp:
    - name: x
      ref: eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
    - owner/x#eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
EOF

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -eq 0 ]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "validate fails when apm.lock.yaml is missing while SHA pins are declared" {
  write_pin_fixture "    - owner/str/skills/str#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  rm "$doctor_workspace_dir/apm.lock.yaml"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"$pin_hint"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor reports nested deployed Codex skills and exits non-zero" {
  make_doctor_fixture
  nested_skill_path="$doctor_home/.agents/skills/legacy/skills/nested/SKILL.md"
  mkdir -p "$(dirname "$nested_skill_path")"
  printf '# nested\n' >"$nested_skill_path"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"$nested_skill_path"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor succeeds when all managed catalog outputs are present with the right type" {
  make_doctor_fixture

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -eq 0 ]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor succeeds when deployed agents match the catalog and extra agent files are present" {
  make_doctor_fixture
  printf 'agent body\n' >"$doctor_workspace_dir/catalog/.apm/agents/reviewer.agent.md"
  for target_dir in .claude .cursor; do
    printf 'agent body\n' >"$doctor_home/$target_dir/agents/reviewer.md"
    printf 'mine\n' >"$doctor_home/$target_dir/agents/mine.md"
  done

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -eq 0 ]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor fails on a deployed agent whose content differs from the catalog" {
  make_doctor_fixture
  printf 'agent body\n' >"$doctor_workspace_dir/catalog/.apm/agents/reviewer.agent.md"
  printf 'agent body\n' >"$doctor_home/.claude/agents/reviewer.md"
  printf 'locally edited\n' >"$doctor_home/.cursor/agents/reviewer.md"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"$doctor_home/.cursor/agents/reviewer.md"* ]]
  [[ "$output" != *"$doctor_home/.claude/agents/reviewer.md"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor fails on a catalog agent missing from an apm-owned target" {
  make_doctor_fixture
  printf 'agent body\n' >"$doctor_workspace_dir/catalog/.apm/agents/reviewer.agent.md"
  printf 'agent body\n' >"$doctor_home/.claude/agents/reviewer.md"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"$doctor_home/.cursor/agents/reviewer.md"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor reports missing and wrong-typed managed catalog outputs" {
  make_doctor_fixture
  rm -f "$doctor_home/.claude/CLAUDE.md"
  mkdir "$doctor_home/.claude/CLAUDE.md"
  rm -rf "$doctor_home/.claude/agents"
  printf 'wrong type\n' >"$doctor_home/.claude/agents"
  rm -rf "$doctor_home/.codex/commands"
  rm -rf "$doctor_home/.cursor/rules"
  printf 'wrong type\n' >"$doctor_home/.cursor/rules"
  rm -rf "$doctor_home/.claude/skills"
  printf 'wrong type\n' >"$doctor_home/.claude/skills"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"$doctor_home/.claude/CLAUDE.md"* ]]
  [[ "$output" == *"$doctor_home/.claude/agents"* ]]
  [[ "$output" == *"$doctor_home/.codex/commands"* ]]
  [[ "$output" == *"$doctor_home/.cursor/rules"* ]]
  [[ "$output" == *"$doctor_home/.claude/skills"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor reports skills=n/a and agents=n/a for the opencode sentinels and does not fail on them" {
  make_doctor_fixture
  rm -rf "$doctor_home/.config/opencode/skills" "$doctor_home/.config/opencode/agents"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -eq 0 ]
  [[ "$output" == *"opencode: config=n/a agents=n/a commands=present rules=present skills=n/a"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor reports agents=n/a for the codex sentinel and does not fail on it" {
  make_doctor_fixture
  rm -rf "$doctor_home/.codex/agents"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -eq 0 ]
  [[ "$output" == *"codex: config=hand-written agents=n/a commands=present rules=present skills=present"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor leaves the learning-intake inbox to doctor-intake" {
  make_doctor_fixture
  mkdir -p "$doctor_workspace_dir/tmp/learning-intake"
  printf 'status: 未処理\n' >"$doctor_workspace_dir/tmp/learning-intake/20260101-0000-one.md"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -eq 0 ]
  [[ "$output" != *"learning-intake"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

# --- doctor-intake -----------------------------------------------------------

make_intake_fixture() {
  intake_workspace_dir="$(mktemp -d)"
  intake_dir="$intake_workspace_dir/tmp/learning-intake"
  mkdir -p "$intake_dir"
}

write_pending_reports() {
  local count="$1"
  local index
  for ((index = 1; index <= count; index++)); do
    printf 'status: 未処理\n' >"$intake_dir/$(printf '20261101-%04d-report.md' "$index")"
  done
}

run_doctor_intake() {
  run env APM_WORKSPACE_DIR="$intake_workspace_dir" bash "$SCRIPT_UNDER_TEST" doctor-intake
}

@test "doctor-intake reports the inbox split into 未処理 and 保留" {
  make_intake_fixture
  mkdir -p "$intake_dir/sub"
  printf 'status: 未処理\n# report one\n' >"$intake_dir/20260101-0000-one.md"
  printf '# report two, no status line\n' >"$intake_dir/20260101-0001-two.md"
  printf 'status: 保留\n不足: owner\n' >"$intake_dir/20260101-0002-three.md"
  printf -- '- status: 保留\n' >"$intake_dir/20260101-0003-four.md"
  printf 'status: 保留（注記）\n' >"$intake_dir/20260101-0004-five.md"
  printf 'status: 未処理\nstatus: 保留\n' >"$intake_dir/20260101-0005-six.md"
  printf 'not a report\n' >"$intake_dir/note.txt"
  printf 'status: 未処理\n' >"$intake_dir/UPPER.MD"
  printf 'status: 未処理\n' >"$intake_dir/.hidden.md"
  printf 'status: 未処理\n# nested report\n' >"$intake_dir/sub/nested.md"

  run_doctor_intake

  [ "$status" -eq 0 ]
  [[ "$output" == *"learning-intake inbox: 未処理 4 / 保留 2"* ]]
  rm -rf "$intake_workspace_dir"
}

@test "doctor-intake stays quiet at 9 pending reports" {
  make_intake_fixture
  write_pending_reports 9

  run_doctor_intake

  [ "$status" -eq 0 ]
  [[ "$output" == *"learning-intake inbox: 未処理 9 / 保留 0"* ]]
  [[ "$output" != *"溜まっています"* ]]
  rm -rf "$intake_workspace_dir"
}

@test "doctor-intake warns at 10 pending reports and still succeeds" {
  make_intake_fixture
  write_pending_reports 10

  run_doctor_intake

  [ "$status" -eq 0 ]
  [[ "$output" == *"learning-intake inbox: 未処理 10 / 保留 0"* ]]
  [[ "$output" == *"learning-intake: 未処理 10 件が溜まっています（閾値 10）"* ]]
  rm -rf "$intake_workspace_dir"
}

@test "doctor-intake leaves deferred reports out of the threshold and the oldest date" {
  make_intake_fixture
  write_pending_reports 9
  printf 'status: 保留\n' >"$intake_dir/20200101-0001-deferred.md"
  printf 'status: 保留\n' >"$intake_dir/20200102-0001-deferred.md"

  run_doctor_intake

  [ "$status" -eq 0 ]
  [[ "$output" == *"learning-intake inbox: 未処理 9 / 保留 2"* ]]
  [[ "$output" == *"最古の未処理: 2026-11-01"* ]]
  [[ "$output" != *"2020-01-01"* ]]
  [[ "$output" != *"溜まっています"* ]]
  rm -rf "$intake_workspace_dir"
}

@test "doctor-intake reports the oldest pending date across YYYYMMDD- and YYYY-MM-DD- names" {
  make_intake_fixture
  printf 'x\n' >"$intake_dir/20261105-0042-newer.md"
  printf 'x\n' >"$intake_dir/2026-09-30-cursor-middle.md"
  printf 'x\n' >"$intake_dir/20260815-0001-oldest.md"

  run_doctor_intake

  [ "$status" -eq 0 ]
  [[ "$output" == *"最古の未処理: 2026-08-15"* ]]
  [[ "$output" != *"日付不明"* ]]

  rm "$intake_dir/20260815-0001-oldest.md"
  printf 'x\n' >"$intake_dir/2026-07-04-cursor-oldest.md"

  run_doctor_intake

  [ "$status" -eq 0 ]
  [[ "$output" == *"最古の未処理: 2026-07-04"* ]]
  rm -rf "$intake_workspace_dir"
}

@test "doctor-intake counts pending reports whose name carries no date" {
  make_intake_fixture
  printf 'x\n' >"$intake_dir/20261105-0042-dated.md"
  printf 'x\n' >"$intake_dir/native-undated.md"
  printf 'x\n' >"$intake_dir/20261399-bad-month-day.md"

  run_doctor_intake

  [ "$status" -eq 0 ]
  [[ "$output" == *"最古の未処理: 2026-11-05"* ]]
  [[ "$output" == *"日付不明: 2 件"* ]]
  rm -rf "$intake_workspace_dir"
}

@test "doctor-intake prints no oldest date when every pending report is undated" {
  make_intake_fixture
  printf 'x\n' >"$intake_dir/native-undated.md"

  run_doctor_intake

  [ "$status" -eq 0 ]
  [[ "$output" == *"learning-intake inbox: 未処理 1 / 保留 0"* ]]
  [[ "$output" == *"日付不明: 1 件"* ]]
  [[ "$output" != *"最古の未処理"* ]]
  rm -rf "$intake_workspace_dir"
}

@test "doctor-intake reports an empty inbox without a warning" {
  make_intake_fixture

  run_doctor_intake

  [ "$status" -eq 0 ]
  [[ "$output" == "learning-intake inbox: 未処理 0 / 保留 0" ]]
  rm -rf "$intake_workspace_dir"
}

@test "doctor-intake reports a missing inbox directory without a warning" {
  make_intake_fixture
  rmdir "$intake_dir"

  run_doctor_intake

  [ "$status" -eq 0 ]
  [[ "$output" == "learning-intake inbox: 未処理 0 / 保留 0" ]]
  rm -rf "$intake_workspace_dir"
}

@test "doctor-intake does not count an unreadable report as pending (needs a non-root user: chmod 000 is ignored for root)" {
  make_intake_fixture
  printf 'status: 未処理\n' >"$intake_dir/20261101-0001-readable.md"
  printf 'status: 未処理\n' >"$intake_dir/20261101-0002-locked.md"
  chmod 000 "$intake_dir/20261101-0002-locked.md"

  run_doctor_intake

  [ "$status" -eq 0 ]
  [[ "$output" == *"learning-intake inbox: 未処理 1 / 保留 0"* ]]
  [[ "$output" == *"読み取り不能な報告 1 件"* ]]
  rm -rf "$intake_workspace_dir"
}

@test "doctor-intake warns instead of reporting an empty inbox when the directory cannot be listed (needs a non-root user: chmod 000 is ignored for root)" {
  make_intake_fixture
  printf 'status: 未処理\n' >"$intake_dir/20261101-0001-report.md"
  chmod 000 "$intake_dir"

  run_doctor_intake
  chmod 755 "$intake_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"一覧できません"* ]]
  [[ "$output" != *"未処理 0"* ]]
  rm -rf "$intake_workspace_dir"
}

# --- doctor agmsg roster link reachability -----------------------------------
#
# agmsg resolves db/ and teams/ relative to $HOME/.agents/skills/agmsg, which
# must stay symlinked into $XDG_STATE_HOME/agmsg (see
# scripts/agmsg-state.sh:16). If that link is absorbed into a plain dir or
# dropped by anything outside the deploy flow, agmsg's own errors ("Team not found",
# empty identities) give no hint the link is the actual cause. These tests
# never touch the real $HOME roster — everything runs inside the fake
# $doctor_home fixture.

@test "doctor skips the agmsg roster link check when the agmsg skill face is not deployed" {
  make_doctor_fixture

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -eq 0 ]
  [[ "$output" != *"agmsg roster link"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor passes when the agmsg roster link correctly points into the state root" {
  make_doctor_fixture
  agmsg_skill_dir="$doctor_home/.agents/skills/agmsg"
  agmsg_state_root="$doctor_home/.local/state/agmsg"
  mkdir -p "$agmsg_state_root/db" "$agmsg_state_root/teams" "$agmsg_skill_dir"
  ln -s "$agmsg_state_root/db" "$agmsg_skill_dir/db"
  ln -s "$agmsg_state_root/teams" "$agmsg_skill_dir/teams"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -eq 0 ]
  [[ "$output" != *"agmsg roster link"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor fails on a plain-dir agmsg db link without naming agmsg:state:restore" {
  make_doctor_fixture
  agmsg_skill_dir="$doctor_home/.agents/skills/agmsg"
  agmsg_state_root="$doctor_home/.local/state/agmsg"
  mkdir -p "$agmsg_state_root/db" "$agmsg_state_root/teams" "$agmsg_skill_dir/db"
  ln -s "$agmsg_state_root/teams" "$agmsg_skill_dir/teams"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"agmsg roster link is a plain path"* ]]
  [[ "$output" == *"$agmsg_skill_dir/db"* ]]
  # A plain dir can hold roster updates written while the link was severed;
  # naming agmsg:state:restore here would steer straight at the absorb-and-
  # discard path that can lose them (indicator 2 in the review), so this
  # case must not suggest it.
  [[ "$output" != *"mise run agmsg:state:restore"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor fails and names agmsg:state:restore when the agmsg db link is dangling" {
  make_doctor_fixture
  agmsg_skill_dir="$doctor_home/.agents/skills/agmsg"
  agmsg_state_root="$doctor_home/.local/state/agmsg"
  mkdir -p "$agmsg_state_root/teams" "$agmsg_skill_dir"
  ln -s "$agmsg_state_root/db" "$agmsg_skill_dir/db"
  ln -s "$agmsg_state_root/teams" "$agmsg_skill_dir/teams"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"agmsg roster link is dangling"* ]]
  [[ "$output" == *"$agmsg_skill_dir/db"* ]]
  [[ "$output" == *"mise run agmsg:state:restore"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor fails and names agmsg:state:restore when the agmsg teams link is missing" {
  make_doctor_fixture
  agmsg_skill_dir="$doctor_home/.agents/skills/agmsg"
  agmsg_state_root="$doctor_home/.local/state/agmsg"
  mkdir -p "$agmsg_state_root/db" "$agmsg_state_root/teams" "$agmsg_skill_dir"
  ln -s "$agmsg_state_root/db" "$agmsg_skill_dir/db"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"agmsg roster link is missing"* ]]
  [[ "$output" == *"$agmsg_skill_dir/teams"* ]]
  [[ "$output" == *"mise run agmsg:state:restore"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

# The next three tests cover the mixed db/teams cases the aggregate
# recommendation exists for: `mise run agmsg:state:restore` relinks db and
# teams together, so a per-item recommendation is wrong whenever the *other*
# item is a plain path holding roster writes made while the link was
# severed -- following it would run the restore anyway and let its
# absorb-and-discard path clobber the plain path's contents.

@test "doctor names agmsg:state:restore for neither item when db is a plain path and teams is missing" {
  make_doctor_fixture
  agmsg_skill_dir="$doctor_home/.agents/skills/agmsg"
  agmsg_state_root="$doctor_home/.local/state/agmsg"
  mkdir -p "$agmsg_state_root/db" "$agmsg_state_root/teams" "$agmsg_skill_dir/db"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"agmsg roster link is a plain path"* ]]
  [[ "$output" == *"agmsg roster link is missing"* ]]
  [[ "$output" != *"mise run agmsg:state:restore"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor names agmsg:state:restore for neither item when db is missing and teams is a plain path" {
  make_doctor_fixture
  agmsg_skill_dir="$doctor_home/.agents/skills/agmsg"
  agmsg_state_root="$doctor_home/.local/state/agmsg"
  mkdir -p "$agmsg_state_root/db" "$agmsg_state_root/teams" "$agmsg_skill_dir/teams"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"agmsg roster link is missing"* ]]
  [[ "$output" == *"agmsg roster link is a plain path"* ]]
  [[ "$output" != *"mise run agmsg:state:restore"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor names agmsg:state:restore when db and teams are both missing (no plain path)" {
  make_doctor_fixture
  agmsg_skill_dir="$doctor_home/.agents/skills/agmsg"
  agmsg_state_root="$doctor_home/.local/state/agmsg"
  mkdir -p "$agmsg_state_root/db" "$agmsg_state_root/teams" "$agmsg_skill_dir"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"agmsg roster link is missing: $agmsg_skill_dir/db"* ]]
  [[ "$output" == *"agmsg roster link is missing: $agmsg_skill_dir/teams"* ]]
  [[ "$output" == *"mise run agmsg:state:restore"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

# --- catalog_apm_dir_claim_message and catalog fixtures ---------------------

# Builds a temp workspace with a tracked catalog and a matching
# .catalog-build/catalog tree, both containing $1 skills (and one file each
# under .apm/agents and commands/rules unless suppressed by the caller after the
# fact). Sets WORKSPACE_DIR and CATALOG_BUILD_ROOT to point at it, along with
# FIXTURE_WORKSPACE_DIR for teardown. Must be called directly (not inside a
# command substitution) so those global assignments are not lost to a
# subshell.
make_catalog_fixture() {
  tracked_skill_count="$1"
  build_skill_count="$2"
  workspace_dir="$(mktemp -d)"

  tracked_dir="$workspace_dir/catalog"
  build_dir="$workspace_dir/.catalog-build/catalog"

  mkdir -p "$tracked_dir/.apm/skills" "$tracked_dir/.apm/agents" "$tracked_dir/commands" "$tracked_dir/rules"
  mkdir -p "$build_dir/.apm/skills" "$build_dir/.apm/agents" "$build_dir/commands" "$build_dir/rules"

  printf 'dependencies: []\n' >"$tracked_dir/apm.yml"
  printf '# catalog\n' >"$tracked_dir/README.md"
  mkdir -p "$tracked_dir/.apm/instructions"
  printf -- '---\ndescription: fixture guide\n---\n\n# instructions\n' >"$tracked_dir/.apm/instructions/ai-collaboration.instructions.md"
  printf 'agent\n' >"$tracked_dir/.apm/agents/sample.agent.md"
  printf 'command\n' >"$tracked_dir/commands/sample.md"
  printf 'rule\n' >"$tracked_dir/rules/sample.md"

  printf 'dependencies: []\n' >"$build_dir/apm.yml"
  printf '# catalog\n' >"$build_dir/README.md"
  mkdir -p "$build_dir/.apm/instructions"
  printf -- '---\ndescription: fixture guide\n---\n\n# instructions\n' >"$build_dir/.apm/instructions/ai-collaboration.instructions.md"
  printf 'agent\n' >"$build_dir/.apm/agents/sample.agent.md"
  printf 'command\n' >"$build_dir/commands/sample.md"
  printf 'rule\n' >"$build_dir/rules/sample.md"

  index=0
  while [ "$index" -lt "$tracked_skill_count" ]; do
    mkdir -p "$tracked_dir/.apm/skills/skill-$index"
    touch "$tracked_dir/.apm/skills/skill-$index/SKILL.md"
    index=$((index + 1))
  done

  index=0
  while [ "$index" -lt "$build_skill_count" ]; do
    mkdir -p "$build_dir/.apm/skills/skill-$index"
    touch "$build_dir/.apm/skills/skill-$index/SKILL.md"
    index=$((index + 1))
  done

  WORKSPACE_DIR="$workspace_dir"
  CATALOG_BUILD_ROOT="$workspace_dir/.catalog-build"
  FIXTURE_WORKSPACE_DIR="$workspace_dir"
}

@test "catalog_apm_dir_claim_message names a file directly under .apm/skills" {
  make_catalog_fixture 2 2
  printf 'readme\n' >"$workspace_dir/catalog/.apm/skills/README.md"

  run catalog_apm_dir_claim_message

  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm holds skills/README.md"* ]]
  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message names a file in a namespace directory that is not itself a skill" {
  make_catalog_fixture 2 2
  mkdir -p "$workspace_dir/catalog/.apm/skills/ns/inner"
  : >"$workspace_dir/catalog/.apm/skills/ns/inner/SKILL.md"
  printf 'loose\n' >"$workspace_dir/catalog/.apm/skills/ns/notes.md"

  run catalog_apm_dir_claim_message

  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm holds skills/ns/notes.md"* ]]
  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message names a symlink inside a skill directory" {
  make_catalog_fixture 2 2
  printf 'outside\n' >"$workspace_dir/outside-reference.md"
  ln -s "$workspace_dir/outside-reference.md" "$workspace_dir/catalog/.apm/skills/skill-0/link.md"

  run catalog_apm_dir_claim_message

  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm holds skills/skill-0/link.md, but the catalog package carries only"* ]]
  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message refuses a name with a newline that would pose as SKILL.md" {
  make_catalog_fixture 2 2
  mkdir -p "$workspace_dir/catalog/.apm/skills/draft"
  : >"$workspace_dir/catalog/.apm/skills/draft/SKILL.md"$'\n'"decoy" || skip "this filesystem rejects a newline in a file name"
  printf 'draft notes\n' >"$workspace_dir/catalog/.apm/skills/draft/notes.md"

  run catalog_apm_dir_claim_message

  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm holds an entry whose name contains a newline"* ]]
  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message names an agent file that is not <name>.agent.md" {
  make_catalog_fixture 2 2
  printf 'legacy\n' >"$workspace_dir/catalog/.apm/agents/legacy-name.md"

  run catalog_apm_dir_claim_message

  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm holds agents/legacy-name.md"* ]]
  [[ "$output" == *"<name>.agent.md"* ]]
  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message names an agent nested below .apm/agents" {
  make_catalog_fixture 2 2
  mkdir -p "$workspace_dir/catalog/.apm/agents/team"
  printf 'nested\n' >"$workspace_dir/catalog/.apm/agents/team/helper.agent.md"

  run catalog_apm_dir_claim_message

  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm holds agents/team/helper.agent.md"* ]]
  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message is silent when .apm is absent or holds only skills and agents" {
  make_catalog_fixture 2 2

  run catalog_apm_dir_claim_message
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  rm -rf "$workspace_dir/catalog/.apm"
  run catalog_apm_dir_claim_message
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message names the first primitive other than skills and agents found under .apm" {
  make_catalog_fixture 2 2
  mkdir -p "$workspace_dir/catalog/.apm/instructions"
  printf 'instruction\n' >"$workspace_dir/catalog/.apm/instructions/sample.instructions.md"

  run catalog_apm_dir_claim_message
  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm holds instructions/sample.instructions.md"* ]]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

make_stageable_catalog_fixture() {
  make_catalog_fixture 2 0
  mkdir -p "$workspace_dir/.git"
  printf 'dependencies: []\n' >"$workspace_dir/apm.yml"
  : >"$workspace_dir/mise.toml"
  MISE_DESTINATION="$workspace_dir/mise.toml"
  tracked_catalog_reference() { printf 'owner/repo/catalog#main\n'; }
}

@test "cmd_seed_catalog_build writes skills and agents under .apm and no top-level skills or agents directory" {
  make_stageable_catalog_fixture

  run cmd_seed_catalog_build
  [ "$status" -eq 0 ]
  [ -f "$workspace_dir/.catalog-build/catalog/.apm/skills/skill-0/SKILL.md" ]
  [ -f "$workspace_dir/.catalog-build/catalog/.apm/skills/skill-1/SKILL.md" ]
  [ -f "$workspace_dir/.catalog-build/catalog/.apm/agents/sample.agent.md" ]
  [ ! -e "$workspace_dir/.catalog-build/catalog/skills" ]
  [ ! -e "$workspace_dir/.catalog-build/catalog/agents" ]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message names a symlink under .apm" {
  make_catalog_fixture 2 2
  mkdir -p "$workspace_dir/catalog/.apm/agents"
  printf 'agent\n' >"$workspace_dir/outside.md"
  ln -s "$workspace_dir/outside.md" "$workspace_dir/catalog/.apm/agents/demo.agent.md"

  run catalog_apm_dir_claim_message
  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm holds agents/demo.agent.md"* ]]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message claims a .apm that is a symlink to an empty directory" {
  make_catalog_fixture 2 2
  rm -rf "$workspace_dir/catalog/.apm"
  mkdir -p "$workspace_dir/outside-apm"
  ln -s "$workspace_dir/outside-apm" "$workspace_dir/catalog/.apm"

  run catalog_apm_dir_claim_message
  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm is a symlink"* ]]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message claims a .apm that is a dangling symlink" {
  make_catalog_fixture 2 2
  rm -rf "$workspace_dir/catalog/.apm"
  ln -s "$workspace_dir/missing-apm" "$workspace_dir/catalog/.apm"

  run catalog_apm_dir_claim_message
  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm is a symlink"* ]]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message claims a .apm holding a directory it cannot read" {
  [ "$(id -u)" -ne 0 ] || skip "root reads a directory without read permission"
  make_catalog_fixture 2 2
  mkdir -p "$workspace_dir/catalog/.apm/instructions"
  printf 'hidden\n' >"$workspace_dir/catalog/.apm/instructions/a.instructions.md"
  chmod 000 "$workspace_dir/catalog/.apm/instructions"

  run catalog_apm_dir_claim_message

  chmod 755 "$workspace_dir/catalog/.apm/instructions"
  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm could not be fully read"* ]]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

@test "catalog_apm_dir_claim_message claims a FIFO under .apm/agents" {
  command -v mkfifo >/dev/null || skip "mkfifo is unavailable"
  make_catalog_fixture 2 2
  mkdir -p "$workspace_dir/catalog/.apm/agents"
  mkfifo "$workspace_dir/catalog/.apm/agents/queue"

  run catalog_apm_dir_claim_message
  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog/.apm holds agents/queue"* ]]

  rm -rf "$FIXTURE_WORKSPACE_DIR"
}

# --- ensure_workspace_scaffold -----------------------------------------------

@test "ensure_workspace_scaffold fails when apm.yml is missing" {
  workspace_dir="$(mktemp -d)"
  WORKSPACE_DIR="$workspace_dir"
  ensure_workspace_repo() { :; }

  run ensure_workspace_scaffold
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing workspace apm.yml"* ]]

  rm -rf "$workspace_dir"
}

@test "ensure_workspace_scaffold succeeds when apm.yml is present" {
  workspace_dir="$(mktemp -d)"
  printf 'dependencies: []\n' >"$workspace_dir/apm.yml"
  WORKSPACE_DIR="$workspace_dir"
  ensure_workspace_repo() { :; }

  run ensure_workspace_scaffold
  [ "$status" -eq 0 ]

  rm -rf "$workspace_dir"
}

# --- unpinned_external_references -------------------------------------------

@test "unpinned_external_references includes a structured git dependency path but not nested skills" {
  # Regression for the doctor "unpinned" count being inflated: the old awk
  # matched every "- " line at or below the apm bullet indent, so it also
  # counted the literal "git:" token and the nested "- ui-ux-pro-max" item
  # under skills: as separate unpinned refs.
  workspace_dir="$(mktemp -d)"
  cat >"$workspace_dir/apm.yml" <<'EOF'
dependencies:
  apm:
    - git: nextlevelbuilder/ui-ux-pro-max-skill
      path: plugins/ui-ux-pro-max
      skills:
        - ui-ux-pro-max
EOF

  WORKSPACE_DIR="$workspace_dir"

  run unpinned_external_references
  [ "$status" -eq 0 ]
  [ "$output" = "nextlevelbuilder/ui-ux-pro-max-skill/plugins/ui-ux-pro-max" ]

  rm -rf "$workspace_dir"
}

@test "unpinned_external_references treats a structured entry with a ref: sibling as pinned" {
  workspace_dir="$(mktemp -d)"
  cat >"$workspace_dir/apm.yml" <<'EOF'
dependencies:
  apm:
    - git: nextlevelbuilder/ui-ux-pro-max-skill
      skills:
        - ui-ux-pro-max
      ref: 4aad0584d92131626b16d4ff4d77f0455385013c
    - jey3dayo/apm-workspace/catalog#main
EOF

  WORKSPACE_DIR="$workspace_dir"

  run unpinned_external_references
  [ "$status" -eq 0 ]
  [ "$output" = "" ]

  rm -rf "$workspace_dir"
}

# --- catalog instructions and root migration ---------------------------------
#
# The guide lives in catalog/.apm/instructions/ai-collaboration.instructions.md.
# APM writes the roots; the scripts only classify them and copy the body to
# OpenCode.

make_roots_fixture() {
  roots_workspace="$(mktemp -d)"
  roots_home="$(mktemp -d)"
  mkdir -p "$roots_workspace/catalog/.apm/instructions"
  printf -- '---\ndescription: fixture guide\n---\n\n\n# Guide\n\nbody line\n' \
    >"$roots_workspace/catalog/.apm/instructions/ai-collaboration.instructions.md"
  printf '# Guide\n\nbody line\n' >"$roots_home/guide-body.md"
  mkdir -p "$roots_home/.claude" "$roots_home/.codex" "$roots_home/.cursor"
  WORKSPACE_DIR="$roots_workspace"
  HOME="$roots_home"
  OPENCODE_INSTRUCTIONS_OUTPUT="$roots_home/.config/opencode/AGENTS.md"
  PI_OUTPUT="$roots_home/AGENTS.md"
}

# Writes a root the way apm compile does: the Build ID is the sha256 of the other lines joined by "\n".
write_generated_root() {
  build_id=$(printf '%s\n%s' "$APM_GENERATED_ROOT_MARKER" "$2" | file_sha256 - | cut -c1-12)
  printf '%s\n<!-- Build ID: %s -->\n%s\n' "$APM_GENERATED_ROOT_MARKER" "$build_id" "$2" >"$1"
}

@test "catalog_instructions_body drops the frontmatter and leading blank lines, as APM renders a rule" {
  make_roots_fixture

  catalog_instructions_body "$(tracked_catalog_instructions_path)" >"$roots_home/rendered.md"

  cmp "$roots_home/rendered.md" "$roots_home/guide-body.md"
  rm -rf "$roots_workspace" "$roots_home"
}

@test "user_root_state tells absent, generated, edited-generated, legacy, hand-written and non-regular roots apart" {
  make_roots_fixture
  known="$(legacy_catalog_instructions_blobs)"
  cp "$roots_home/guide-body.md" "$roots_home/.claude/CLAUDE.md"
  write_generated_root "$roots_home/.codex/AGENTS.md" '# compiled'
  write_generated_root "$roots_home/edited.md" '# compiled'
  printf 'my own line\n' >>"$roots_home/edited.md"
  printf '%s\n# compiled\n' "$APM_GENERATED_ROOT_MARKER" >"$roots_home/no-build-id.md"
  sed '1s/$/ my note/' "$roots_home/.codex/AGENTS.md" >"$roots_home/marker-note.md"
  sed 's/$/\r/' "$roots_home/.codex/AGENTS.md" >"$roots_home/crlf.md"
  { printf '\357\273\277'; cat "$roots_home/.codex/AGENTS.md"; } >"$roots_home/bom.md"
  printf '# Guide\n\nbody line\nmy own addition\n' >"$roots_home/.cursor/AGENTS.md"
  ln -s "$roots_home/guide-body.md" "$roots_home/linked.md"
  mkdir "$roots_home/dir.md"

  [ "$(user_root_state "$roots_home/missing.md" "$known")" = absent ]
  [ "$(user_root_state "$roots_home/.codex/AGENTS.md" "$known")" = generated ]
  [ "$(user_root_state "$roots_home/edited.md" "$known")" = edited-generated ]
  [ "$(user_root_state "$roots_home/no-build-id.md" "$known")" = edited-generated ]
  # APM's own reading: the marker is a prefix, CRLF is LF, and a BOM hides the marker.
  [ "$(user_root_state "$roots_home/marker-note.md" "$known")" = edited-generated ]
  [ "$(user_root_state "$roots_home/crlf.md" "$known")" = generated ]
  [ "$(user_root_state "$roots_home/bom.md" "$known")" = hand-written ]
  [ "$(user_root_state "$roots_home/.claude/CLAUDE.md" "$known")" = legacy ]
  [ "$(user_root_state "$roots_home/.cursor/AGENTS.md" "$known")" = hand-written ]
  [ "$(user_root_state "$roots_home/linked.md" "$known")" = not-regular ]
  [ "$(user_root_state "$roots_home/dir.md" "$known")" = not-regular ]
  rm -rf "$roots_workspace" "$roots_home"
}

@test "user_root_state reads a root larger than a pipe buffer under pipefail" {
  make_roots_fixture
  large_body="$(printf '# Guide\n'; seq 1 50000)"
  write_generated_root "$roots_home/.codex/AGENTS.md" "$large_body"
  [ "$(user_root_state "$roots_home/.codex/AGENTS.md" "")" = generated ]
  printf 'my own line\n' >>"$roots_home/.codex/AGENTS.md"
  [ "$(user_root_state "$roots_home/.codex/AGENTS.md" "")" = edited-generated ]
  rm -rf "$roots_workspace" "$roots_home"
}

@test "user_root_state skips the same leading whitespace before the marker as APM's Python lstrip" {
  make_roots_fixture
  write_generated_root "$roots_home/compiled.md" '# compiled'
  # form feed, U+001C, U+0085, U+00A0, U+2000, U+200A, U+3000 and U+2028 are Python whitespace; U+200B and a BOM are not.
  for prefix in '\014' '\034' '\302\205' '\302\240' '\342\200\200' '\342\200\212' '\343\200\200' '\342\200\250\n'; do
    { printf "$prefix"; cat "$roots_home/compiled.md"; } >"$roots_home/prefixed.md"
    [ "$(user_root_state "$roots_home/prefixed.md" "")" = edited-generated ]
  done
  { printf '\342\200\213'; cat "$roots_home/compiled.md"; } >"$roots_home/zwsp.md"
  [ "$(user_root_state "$roots_home/zwsp.md" "")" = hand-written ]
  rm -rf "$roots_workspace" "$roots_home"
}

@test "legacy_catalog_instructions_blobs also recognizes an older committed catalog/AGENTS.md" {
  make_roots_fixture
  git -C "$roots_workspace" init -q
  printf '# Old guide\n' >"$roots_workspace/catalog/AGENTS.md"
  git -C "$roots_workspace" add catalog/AGENTS.md
  git -C "$roots_workspace" -c user.name=t -c user.email=t@example.invalid commit -q -m old
  git -C "$roots_workspace" rm -q catalog/AGENTS.md
  git -C "$roots_workspace" -c user.name=t -c user.email=t@example.invalid commit -q -m moved
  printf '# Old guide\n' >"$roots_home/.codex/AGENTS.md"

  [ "$(user_root_state "$roots_home/.codex/AGENTS.md" "$(legacy_catalog_instructions_blobs)")" = legacy ]
  rm -rf "$roots_workspace" "$roots_home"
}

@test "sync_opencode_instructions writes the body when absent or a legacy copy, and leaves a hand-written file" {
  make_roots_fixture

  run sync_opencode_instructions
  [ "$status" -eq 0 ]
  cmp "$OPENCODE_INSTRUCTIONS_OUTPUT" "$roots_home/guide-body.md"

  printf 'my opencode rules\n' >"$OPENCODE_INSTRUCTIONS_OUTPUT"
  run sync_opencode_instructions
  [ "$status" -eq 0 ]
  [ "$(cat "$OPENCODE_INSTRUCTIONS_OUTPUT")" = "my opencode rules" ]
  [[ "$output" == *"Leaving $OPENCODE_INSTRUCTIONS_OUTPUT as is (hand-written)"* ]]
  rm -rf "$roots_workspace" "$roots_home"
}

@test "sync_opencode_instructions does not displace an edited generated ~/.claude/CLAUDE.md that OpenCode falls back to" {
  make_roots_fixture
  write_generated_root "$roots_home/.claude/CLAUDE.md" '# compiled'
  printf 'my own claude line\n' >>"$roots_home/.claude/CLAUDE.md"

  run sync_opencode_instructions

  [ "$status" -eq 0 ]
  [ ! -e "$OPENCODE_INSTRUCTIONS_OUTPUT" ]
  [[ "$output" == *"OpenCode falls back to $roots_home/.claude/CLAUDE.md (edited-generated)"* ]]
  rm -rf "$roots_workspace" "$roots_home"
}

@test "catalog_apm_dir_claim_message allows the catalog instruction and claims any other instruction" {
  workspace="$(mktemp -d)"
  mkdir -p "$workspace/catalog/.apm/instructions"
  WORKSPACE_DIR="$workspace"
  printf -- '---\ndescription: x\n---\n\nbody\n' >"$workspace/catalog/.apm/instructions/ai-collaboration.instructions.md"

  run catalog_apm_dir_claim_message
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  printf 'x\n' >"$workspace/catalog/.apm/instructions/extra.instructions.md"
  run catalog_apm_dir_claim_message
  [[ "$output" == *"catalog/.apm holds instructions/extra.instructions.md, which the catalog build does not carry"* ]]

  rm "$workspace/catalog/.apm/instructions/extra.instructions.md"
  mkdir -p "$workspace/catalog/.apm/instructions/nested"
  printf 'x\n' >"$workspace/catalog/.apm/instructions/nested/ai-collaboration.instructions.md"
  run catalog_apm_dir_claim_message
  [[ "$output" == *"instructions/nested/ai-collaboration.instructions.md"* ]]
  rm -rf "$workspace"
}

@test "validate:catalog rejects instructions without a description, a revived catalog/AGENTS.md and a colliding rule name" {
  make_doctor_fixture
  instructions="$doctor_workspace_dir/catalog/.apm/instructions/ai-collaboration.instructions.md"

  printf '# no frontmatter\n' >"$instructions"
  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate:catalog
  [ "$status" -ne 0 ]
  [[ "$output" == *"Catalog instructions need YAML frontmatter with a description"* ]]

  printf -- '---\ndescription: guide\n---\n\n# guide\n' >"$instructions"
  printf '# old\n' >"$doctor_workspace_dir/catalog/AGENTS.md"
  printf 'rule\n' >"$doctor_workspace_dir/catalog/rules/ai-collaboration.md"
  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" validate:catalog
  [ "$status" -ne 0 ]
  [[ "$output" == *"catalog/AGENTS.md is no longer deployed"* ]]
  [[ "$output" == *"Catalog rule collides with the Claude rule APM writes for the catalog instructions"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor warns about a legacy root without failing and accepts a missing Claude root" {
  make_doctor_fixture
  rm -f "$doctor_home/.claude/CLAUDE.md"
  printf '# instructions\n' >"$doctor_home/.codex/AGENTS.md"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -eq 0 ]
  [[ "$output" == *"claude: config=absent"* ]]
  [[ "$output" == *"Claude has neither $doctor_home/.claude/CLAUDE.md nor the guide rule"* ]]
  [[ "$output" == *"codex: config=legacy"* ]]
  [[ "$output" == *"$doctor_home/.codex/AGENTS.md is still the copy the retired legacy catalog sync wrote"* ]]
  [[ "$output" == *"opencode instructions: "* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

@test "doctor warns when a Claude compile output sits next to the guide rule, and about an edited one" {
  make_doctor_fixture
  write_generated_root "$doctor_home/.claude/CLAUDE.md" '# instructions'
  printf '# instructions\n' >"$doctor_home/.claude/rules/ai-collaboration.md"

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor
  [[ "$output" == *"claude: config=generated"* ]]
  [[ "$output" == *"$doctor_home/.claude/CLAUDE.md is an apm compile output that still sits next to the guide rule"* ]]

  printf 'my own line\n' >>"$doctor_home/.claude/CLAUDE.md"
  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor
  [[ "$output" == *"claude: config=edited-generated"* ]]
  [[ "$output" == *"Claude reads the guide from it as well as from the rule"* ]]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}

write_catalog_lock_fixture() {
  cat >"$1" <<'LOCK'
lockfile_version: '2'
dependencies:
- repo_url: other/repo
  name: catalog-lookalike
  virtual_path: skills/other
  deployed_files:
  - .agents/skills/other/SKILL.md
- repo_url: jey3dayo/apm-workspace
  name: catalog
  virtual_path: catalog
  package_type: apm_package
  deployed_files:
  - .agents/skills/demo
  - .agents/skills/demo/SKILL.md
  - .claude/rules/ai-collaboration.md
  deployed_file_hashes:
    .agents/skills/demo/SKILL.md: sha256:c0ffee
    .claude/rules/ai-collaboration.md: sha256:RULEHASH
- repo_url: jey3dayo/apm-workspace
  name: manual-skills
  virtual_path: manual-skills
  deployed_files:
  - .agents/skills/manual/SKILL.md
LOCK
}

@test "catalog_lock_deployed_entries reads only the catalog package's deployed files and hashes" {
  lock_dir="$(mktemp -d)"
  write_catalog_lock_fixture "$lock_dir/apm.lock.yaml"

  run catalog_lock_deployed_entries "$lock_dir/apm.lock.yaml"

  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'F\t.agents/skills/demo\nF\t.agents/skills/demo/SKILL.md\nF\t.claude/rules/ai-collaboration.md\nH\t.agents/skills/demo/SKILL.md\tc0ffee\nH\t.claude/rules/ai-collaboration.md\tRULEHASH')" ]
  rm -rf "$lock_dir"
}

@test "check_catalog_lock_deployed_files fails for a recorded file that is gone and only counts a changed one" {
  WORKSPACE_DIR="$(mktemp -d)"
  HOME="$(mktemp -d)"
  write_catalog_lock_fixture "$WORKSPACE_DIR/apm.lock.yaml"
  mkdir -p "$HOME/.agents/skills/demo" "$HOME/.claude/rules"
  printf 'edited\n' >"$HOME/.agents/skills/demo/SKILL.md"
  printf 'rule\n' >"$HOME/.claude/rules/ai-collaboration.md"
  rule_hash=$(sha256sum "$HOME/.claude/rules/ai-collaboration.md" | awk '{print $1}')
  sed -i.orig "s/RULEHASH/$rule_hash/" "$WORKSPACE_DIR/apm.lock.yaml"

  run check_catalog_lock_deployed_files
  [ "$status" -eq 0 ]
  [[ "$output" == *"catalog lock files: listed=3 missing=0 stale=0 changed=1"* ]]

  mv "$HOME/.claude/rules/ai-collaboration.md" "$HOME/rule.aside"
  run check_catalog_lock_deployed_files
  [ "$status" -ne 0 ]
  [[ "$output" == *"Catalog file recorded in apm.lock.yaml is missing: ~/.claude/rules/ai-collaboration.md"* ]]
  [[ "$output" == *"listed=3 missing=1 stale=0 changed=1"* ]]
  rm -rf "$WORKSPACE_DIR" "$HOME"
}

@test "check_catalog_lock_deployed_files only warns about a skill deleted from the working catalog before the lock is next updated" {
  WORKSPACE_DIR="$(mktemp -d)"
  HOME="$(mktemp -d)"
  write_catalog_lock_fixture "$WORKSPACE_DIR/apm.lock.yaml"
  mkdir -p "$HOME/.claude/rules"
  printf 'rule\n' >"$HOME/.claude/rules/ai-collaboration.md"
  rule_hash=$(sha256sum "$HOME/.claude/rules/ai-collaboration.md" | awk '{print $1}')
  sed -i.orig "s/RULEHASH/$rule_hash/" "$WORKSPACE_DIR/apm.lock.yaml"

  run check_catalog_lock_deployed_files

  [ "$status" -eq 0 ]
  [[ "$output" == *"listed=3 missing=0 stale=2 changed=0"* ]]
  [[ "$output" == *"2 skill or agent file(s) recorded in apm.lock.yaml are gone"*"they leave the lock when apm.lock.yaml is next updated"* ]]
  [[ "$output" != *"is missing"* ]]
  rm -rf "$WORKSPACE_DIR" "$HOME"
}

commit_instruction_version() {
  printf -- '---\ndescription: fixture guide\n---\n\n%s\n' "$2" \
    >"$1/catalog/.apm/instructions/ai-collaboration.instructions.md"
  git -C "$1" add catalog/.apm/instructions/ai-collaboration.instructions.md
  git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q -m "$2"
}

@test "sync_opencode_instructions keeps updating a copy written from an earlier committed instruction version" {
  make_roots_fixture
  git -C "$roots_workspace" init -q
  commit_instruction_version "$roots_workspace" "# Guide v2"
  commit_instruction_version "$roots_workspace" "# Guide v3"
  mkdir -p "${OPENCODE_INSTRUCTIONS_OUTPUT%/*}"
  printf '# Guide v2\n' >"$OPENCODE_INSTRUCTIONS_OUTPUT"

  [ "$(user_root_state "$OPENCODE_INSTRUCTIONS_OUTPUT" "$(legacy_catalog_instructions_blobs)")" = legacy ]
  run sync_opencode_instructions

  [ "$status" -eq 0 ]
  [ "$(cat "$OPENCODE_INSTRUCTIONS_OUTPUT")" = "# Guide v3" ]
  rm -rf "$roots_workspace" "$roots_home"
}

@test "sync_opencode_instructions does not displace a hand-written ~/.claude/CLAUDE.md that OpenCode falls back to" {
  make_roots_fixture
  printf 'my own claude rules\n' >"$roots_home/.claude/CLAUDE.md"

  run sync_opencode_instructions

  [ "$status" -eq 0 ]
  [ ! -e "$OPENCODE_INSTRUCTIONS_OUTPUT" ]
  [[ "$output" == *"Not writing $OPENCODE_INSTRUCTIONS_OUTPUT: OpenCode falls back to $roots_home/.claude/CLAUDE.md (hand-written)"* ]]
  rm -rf "$roots_workspace" "$roots_home"
}

@test "catalog_lock_deployed_entries also reads a catalog installed from a local path" {
  lock_dir="$(mktemp -d)"
  printf "lockfile_version: '1'\ndependencies:\n- repo_url: _local/catalog\n  name: catalog\n  package_type: apm_package\n  deployed_files:\n  - .claude/rules/ai-collaboration.md\n  source: local\ndeployments:\n- kind: project-relative\n  value: .claude/agents/x.md\n" >"$lock_dir/apm.lock.yaml"

  run catalog_lock_deployed_entries "$lock_dir/apm.lock.yaml"

  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'F\t.claude/rules/ai-collaboration.md')" ]
  rm -rf "$lock_dir"
}
