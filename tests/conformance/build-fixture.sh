#!/usr/bin/env bash
# Shared conformance fixture for `apm-workspace.sh apply` / `apm-workspace.ps1
# apply`. Builds, under $1 (a caller-owned temp dir):
#   home/       fake $HOME with empty .agents/skills, .claude/skills, .codex
#   bin/        recording stubs for apm/git/codex, meant to sit at the front
#               of $PATH so real network/host state is never touched
#   workspace/  minimal ~/.apm-equivalent: apm.yml + one catalog skill/agent/
#               command/rule + one private skill
#   calls.log   one line per stub invocation, in call order
#
# Both bats (source this file, call build_apply_fixture) and Pester (invoke
# this file as `bash build-fixture.sh <dir>`, parse the KEY=VALUE stdout)
# drive the same fixture so the two adapters are held to identical fixtures.
#
# Usage as a script: build-fixture.sh <base_dir>
# Usage sourced:      build_apply_fixture <base_dir>  (sets the vars below)
set -euo pipefail

build_apply_fixture() {
  base_dir="$1"
  mkdir -p "$base_dir"

  home_dir="$base_dir/home"
  mkdir -p "$home_dir/.agents/skills" "$home_dir/.claude/skills" "$home_dir/.codex"

  bin_dir="$base_dir/bin"
  mkdir -p "$bin_dir"

  call_log="$base_dir/calls.log"
  : >"$call_log"

  git_bin="$bin_dir/git"
  cat >"$git_bin" <<STUB
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >>"$call_log"
exit 0
STUB
  chmod +x "$git_bin"

  codex_bin="$bin_dir/codex"
  cat >"$codex_bin" <<STUB
#!/usr/bin/env bash
printf 'codex %s\n' "\$*" >>"$call_log"
exit 0
STUB
  chmod +x "$codex_bin"

  # apm needs subcommand-aware behavior: `compile --target codex --output
  # <path>` has to actually create the output file (apply's compile_codex
  # only mkdir -p's the parent dir; it never writes the file itself), and
  # `install` has to exit 0 without printing the diagnostics-failure patterns
  # apm_install_has_diagnostics_failure() scans for.
  apm_bin="$bin_dir/apm"
  cat >"$apm_bin" <<STUB
#!/usr/bin/env bash
printf 'apm %s\n' "\$*" >>"$call_log"

output_path=""
prev_arg=""
for arg in "\$@"; do
  if [ "\$prev_arg" = "--output" ]; then
    output_path="\$arg"
  fi
  prev_arg="\$arg"
done

if [ -n "\$output_path" ]; then
  mkdir -p "\$(dirname "\$output_path")"
  printf '# fixture: apm compile output\n' >"\$output_path"
fi

exit 0
STUB
  chmod +x "$apm_bin"

  workspace_dir="$base_dir/workspace"
  mkdir -p "$workspace_dir/.git"
  mkdir -p "$workspace_dir/catalog/skills/sample-skill" \
    "$workspace_dir/catalog/agents" \
    "$workspace_dir/catalog/commands" \
    "$workspace_dir/catalog/rules"

  printf '# sample skill\n' >"$workspace_dir/catalog/skills/sample-skill/SKILL.md"
  printf 'agent\n' >"$workspace_dir/catalog/agents/sample.md"
  printf 'command\n' >"$workspace_dir/catalog/commands/sample.md"
  printf 'rule\n' >"$workspace_dir/catalog/rules/sample.md"
  printf '# catalog\n' >"$workspace_dir/catalog/README.md"
  printf '# instructions\n' >"$workspace_dir/catalog/AGENTS.md"
  printf 'dependencies: []\n' >"$workspace_dir/catalog/apm.yml"

  cat >"$workspace_dir/apm.yml" <<'EOF'
dependencies:
  apm:
    - git: jey3dayo/apm-workspace/catalog#main
EOF
  : >"$workspace_dir/apm.lock.yaml"

  cat >"$workspace_dir/mise.toml" <<'EOF'
[tasks.apply]
run = "bash ./scripts/apm-workspace.sh apply"
EOF

  private_skill_dir="$workspace_dir/private-skills/.apm/skills/sample-private-skill"
  mkdir -p "$private_skill_dir"
  printf '# private skill\n' >"$private_skill_dir/SKILL.md"

  FIXTURE_HOME="$home_dir"
  FIXTURE_WORKSPACE_DIR="$workspace_dir"
  FIXTURE_BIN_DIR="$bin_dir"
  FIXTURE_CALL_LOG="$call_log"
  FIXTURE_PRIVATE_SKILL_DIR="$private_skill_dir"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  build_apply_fixture "$1"
  printf 'HOME=%s\n' "$FIXTURE_HOME"
  printf 'WORKSPACE_DIR=%s\n' "$FIXTURE_WORKSPACE_DIR"
  printf 'BIN_DIR=%s\n' "$FIXTURE_BIN_DIR"
  printf 'CALL_LOG=%s\n' "$FIXTURE_CALL_LOG"
  printf 'PRIVATE_SKILL_DIR=%s\n' "$FIXTURE_PRIVATE_SKILL_DIR"
fi
