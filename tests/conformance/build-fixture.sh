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

# Writes the apm/git/codex recording stubs to $1. Every stub resolves its
# log path at runtime as `${FIXTURE_CALL_LOG:-$2}` so a caller sharing one
# stub set across fixtures (Gatekeeper only assesses a new executable file
# once) can still route each run's call log to that run's own fixture by
# exporting FIXTURE_CALL_LOG before invoking apply.
build_apply_stubs() {
  bin_dir="$1"
  default_call_log="$2"
  mkdir -p "$bin_dir"

  git_bin="$bin_dir/git"
  cat >"$git_bin" <<STUB
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >>"\${FIXTURE_CALL_LOG:-$default_call_log}"
exit 0
STUB
  chmod +x "$git_bin"

  codex_bin="$bin_dir/codex"
  cat >"$codex_bin" <<STUB
#!/usr/bin/env bash
printf 'codex %s\n' "\$*" >>"\${FIXTURE_CALL_LOG:-$default_call_log}"
exit 0
STUB
  chmod +x "$codex_bin"

  # apm needs subcommand-aware behavior: `compile --target codex --output
  # <path>` has to actually create the output file (apply's compile_codex
  # only mkdir -p's the parent dir; it never writes the file itself),
  # `install` has to exit 0 without printing the diagnostics-failure patterns
  # apm_install_has_diagnostics_failure() scans for, and `deps update -g` has
  # to reproduce the observed real-world behavior (2026-09-23) of wiping the
  # deployed agmsg skill dir wholesale, so tests/update-agmsg-roster.bats and
  # its Pester parity can exercise cmd_update's roster save/restore without a
  # live apm CLI.
  apm_bin="$bin_dir/apm"
  cat >"$apm_bin" <<STUB
#!/usr/bin/env bash
printf 'apm %s\n' "\$*" >>"\${FIXTURE_CALL_LOG:-$default_call_log}"

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

if [ "\$*" = "deps update -g" ] && [ -n "\${HOME:-}" ] && [ -d "\$HOME/.agents/skills/agmsg" ]; then
  rm -rf "\$HOME/.agents/skills/agmsg"
  mkdir -p "\$HOME/.agents/skills/agmsg"
fi

exit 0
STUB
  chmod +x "$apm_bin"
}

# $2 (optional): an already-built stub bin dir (from build_apply_stubs) to
# reuse instead of writing a fresh one. Every other part of the fixture
# (home/, workspace/, calls.log) is still built fresh under $1.
build_apply_fixture() {
  base_dir="$1"
  shared_bin_dir="${2:-}"
  mkdir -p "$base_dir"

  home_dir="$base_dir/home"
  mkdir -p "$home_dir/.agents/skills" "$home_dir/.claude/skills" "$home_dir/.codex"

  call_log="$base_dir/calls.log"
  : >"$call_log"

  if [ -n "$shared_bin_dir" ]; then
    bin_dir="$shared_bin_dir"
  else
    bin_dir="$base_dir/bin"
    build_apply_stubs "$bin_dir" "$call_log"
  fi

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
