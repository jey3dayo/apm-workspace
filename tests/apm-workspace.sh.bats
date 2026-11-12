#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/apm-workspace.sh"
}

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

@test "doctor succeeds when all managed catalog outputs are present with the right type" {
  make_doctor_fixture

  run doctor_fixture_env bash "$SCRIPT_UNDER_TEST" doctor

  [ "$status" -eq 0 ]
  rm -rf "$doctor_workspace_dir" "$doctor_home" "$doctor_bin"
}
