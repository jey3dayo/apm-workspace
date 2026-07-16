---
name: agent-curation
description: "Curate external agent collections into this APM workspace. Use when evaluating whether an outside agent repository can be installed through APM, importing selected agents into catalog/agents, recording provenance, or refreshing curated agents from upstream."
---

# Agent Curation

Use this workspace-only skill to turn external agent collections into workspace-managed agents without hand-editing deployed runtime targets.

## Core Rule

First test whether the upstream is an APM-valid package. If it is not, curate selected agents into `catalog/agents/` and record provenance. Do not add invalid upstream repositories directly to `apm.yml`, and do not run upstream installers that write directly to `~/.codex/agents`, `~/.claude/agents`, or other runtime targets.

## Workflow

1. Inspect the upstream source.
   - Record repository URL, resolved commit, license, candidate file paths, and upstream install instructions.
   - Check for APM-compatible entries: root `apm.yml`, root `SKILL.md`, `.apm/`, `plugin.json`, `.apm/agents/*.agent.md`, or root `*.agent.md`.
   - If the upstream has only plain categorized Markdown or runtime-specific installers, treat it as not directly installable through APM.

2. Prove direct APM installability before editing.
   - Use an isolated temporary APM project for tests.
   - Test the root and the narrowest plausible subpath.
   - Record the exact command and failure reason when APM rejects the package.

3. Select agents deliberately.
   - Prefer the smallest useful set for the user's current objective.
   - Include adjacent candidates in `references/hired-agents-registry.md` when they may be useful later.
   - Do not bulk-import a whole collection unless the user explicitly asks for broad adoption.

4. Curate into `catalog/agents/`.
   - Adapt the agent to this workspace's agent format and existing communication style.
   - Preserve the useful behavior, but remove upstream-specific installer assumptions, unsupported tool lists, and verbose persona boilerplate.
   - Add provenance near the top of the agent body: upstream repository, commit, source path, license, curation date, and relationship to the original.

5. Update the hiring registry.
   - Read `references/hired-agents-registry.md` before adding or refreshing curated agents.
   - Add the hired agent, source repository, commit, source path, local target path, license, selection reason, verification status, and related candidates.
   - Keep this registry as the exploration index; do not put non-agent notes in `catalog/agents/`.

6. Validate the affected delivery surface.
   - If `catalog/agents` changed, run `mise run prepare:catalog`, `mise run check`, and `mise run deploy`; verify the curated agent in its runtime targets.
   - If only this workspace-only skill or its registry changed, run `mise run check`; verify both local bridge entries resolve to `.apm/skills/agent-curation/`.

## Refresh Rules

- Re-check the upstream commit before refreshing.
- Compare upstream source, local curated agent, and registry entry before editing.
- Keep local curation intentional; do not blindly overwrite local agent instructions with upstream text.
- If upstream becomes APM-compatible later, prefer switching to a direct APM dependency only after reviewing package contents and deployment targets.

## Required Evidence In Final Reports

- APM installability decision and the command or observation behind it.
- Changed files.
- Upstream repository, commit, source path, and license for each hired agent.
- Validation commands with exit status.
- Curated-agent deployment target checks when agents changed; otherwise, local bridge checks for this workspace-only skill.

## References

- Read `references/hired-agents-registry.md` before importing, refreshing, or looking up curated external agents.
