---
name: rtk
description: Use only when the user explicitly asks about RTK, when maintaining existing `.rtk/filters.toml`, or when evaluating RTK in manual mode. Do not use this skill to make RTK the default command wrapper.
---

# RTK

## Overview

RTK compresses noisy CLI output before it reaches the model context window. In this workspace, treat it as an opt-in/manual tool rather than the default command wrapper.

Rule of thumb: use raw commands by default; use `rtk` only when the user explicitly asks for it, when maintaining existing RTK configuration, or when a specific A/B test requires RTK.

Read `references/command-reference.md` when you need the detailed command families, install options, or repository-specific override patterns.

## Quick Workflow

1. Confirm whether the repository already uses RTK.
   - Look for `.rtk/filters.toml`, `rtk` in tool configs, or existing RTK-specific rules.
2. Confirm the user wants RTK involved for this task before prefixing commands with `rtk`.
3. Keep shell builtins and session-state changes raw.
   - Examples: `cd`, `export`, `alias`, shell option changes, and other operations whose effect must stay in the current shell.
4. Do not install hooks or startup guidance unless the user explicitly asks to enable RTK.
5. Run `rtk gain` or `rtk gain --history` to verify the benefit and identify the noisiest commands.
6. If RTK filtering hides information you need for debugging, switch that command to `rtk proxy <command>`.

## Opt-In RTK Candidates

When the user explicitly selects RTK for a task, these command families are reasonable candidates:

- Very noisy test, build, and check commands
- Large Git, GitHub, package-manager, container, and orchestration logs
- Long-running remote log inspection where compact output is more useful than raw output

## Use Raw Commands Carefully

Use raw commands when:

- The command is a shell builtin or mutates shell session state
- The command output is already tiny and wrapping adds no value
- You need raw, unfiltered output to debug formatter or filter behavior

Do not assume every shell builtin behaves correctly through a subprocess wrapper.

## Setup

### Install RTK

Choose the install path that matches the repository or machine:

- Run `mise install` when the active mise config already declares `rtk`
- Run `brew install rtk` on macOS or Linux when Homebrew is the standard tool path
- Use the official install script or release binaries when `mise` or Homebrew are not the right fit

### Automatic Rewriting

```bash
rtk init --global
```

This installs the PreToolUse hook so supported Bash commands are automatically rewritten to RTK equivalents. Do not run it unless the user explicitly asks to re-enable RTK auto rewriting.

For Codex, use the Codex-specific global setup:

```bash
rtk init -g --codex
```

Codex integration upstream writes RTK guidance into `~/.codex/AGENTS.md` and `~/.codex/RTK.md`. In this APM workspace, do not adopt that generated `RTK.md` layout as the source of truth:

- Keep detailed operational guidance in this skill and its references
- Use `rtk init -g --codex --dry-run` only as a diagnostic/reference command
- Do not create `RTK.md` under `~/.config`, `~/.apm/catalog`, or `~/.codex` unless the catalog deployment model is intentionally changed
- Do not hand-edit deployed targets such as `~/.codex/AGENTS.md`, `~/.codex/RTK.md`, or `~/.agents/skills/**`

### Verify Savings

```bash
rtk gain
rtk gain --history
```

Use the savings output as operational evidence, not just as a vanity metric.

## Filters

Project-local filters live in `.rtk/filters.toml`. Update filters when:

- A frequently used command still emits too much boilerplate
- A project-specific tool has stable noise that can be stripped safely
- You want a compact success path without hiding actionable failures

Keep filters conservative. Remove repeated noise, not real errors.

## Repository Overrides

When the current repository already documents RTK usage, treat current user preference and local guidance as authoritative for rollout and maintenance details.

- Check `.rtk/filters.toml` before adding new filter behavior
- If the repository already declares RTK in its toolchain, install or update it through that existing path instead of inventing a new one
- If the repository has task docs or rollout commands for RTK-related changes, follow those local instructions rather than hardcoding one workspace's maintenance flow here
- Do not add a new task runner command unless the existing repository workflow cannot pick the change up
- In Codex, do not add always-on RTK rules to `catalog/AGENTS.md`; keep RTK opt-in/manual unless the user changes the policy.

## Example

```bash
rtk git status
rtk git diff
rtk vitest run
rtk tsc
rtk gain
```

## Common Mistakes

- Wrapping every shell builtin blindly and assuming shell state will persist
- Using RTK out of habit when the current policy is raw commands by default
- Forgetting `rtk proxy <command>` when filtered output is too compact to debug
- Editing `.rtk/filters.toml` aggressively enough to remove real failures
- Treating `rtk gain` as marketing only instead of validating actual workflow benefit
