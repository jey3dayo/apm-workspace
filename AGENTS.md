# APM Workspace Guide

## Purpose

This repository is the operational source of truth for `~/.apm`.

- `catalog/skills/**` is the authoring surface for personal skills
- `catalog/AGENTS.md`, `catalog/agents/**`, `catalog/commands/**`, and `catalog/rules/**` are shared runtime guidance assets
- `apm.yml` and `apm.lock.yaml` are command-managed dependency state
- `apm_modules/` is cache state, not an editing surface

Keep the split between authoring, tracked package content, and deployed runtime targets explicit.

## Single Source of Truth

Treat source of truth as a split model by asset type, not as "whatever is currently deployed".

- `./catalog` is the tracked source of truth for managed content in this repository
  - `catalog/skills/**` for personal skills
  - `catalog/AGENTS.md`, `catalog/agents/**`, `catalog/commands/**`, and `catalog/rules/**` for shared guidance
- external skills are not authored under `./catalog`
  - their source of truth is the upstream reference recorded in `apm.yml`
  - the accepted resolved state is captured in `apm.lock.yaml`
- deployed targets such as `~/.claude/`, `~/.codex/`, and other runtime roots are generated outputs
  - they are verification and delivery surfaces, not editing surfaces
- Codex skill delivery uses `~/.agents/skills`
  - `~/.codex/skills` is legacy and should not be used as the active deployment root
- `apm_modules/` is cache state only
  - do not treat downloaded contents there as the place to edit or define truth

In practice:

- if the change is to a personal skill or shared guidance asset, edit `./catalog`
- if the change is to external dependency selection or accepted upstream state, edit or review `apm.yml` and `apm.lock.yaml`
- if the change only exists in a deployed target or cache, regenerate from the tracked workspace instead of editing it in place
- if the question is specifically about Codex skills, treat `~/.agents/skills` as the deployed output and `~/.codex/AGENTS.md` as the compiled guidance output

## Operating Philosophy

- Prefer explicit flow separation over one large catch-all command
- Treat upstream refresh and stable rollout as different intents
- Review lockfile changes intentionally; do not normalize unexpected dependency drift into routine edits
- Keep runtime targets reproducible from committed workspace state
- Use tracked catalog workflows for shared guidance, not ad hoc edits under deployed targets
- For Codex, separate compiled guidance from skills
  - `~/.codex/AGENTS.md` is the compiled output
  - `~/.agents/skills` is the deployed skill tree
- Treat the current `apm` source as a pinned runtime dependency managed by `mise`
  - current source: `github:jey3dayo/apm@v0.8.12.post1`
  - keep the previous `github:microsoft/apm` entry commented in tracked config for rollback
  - if both the workspace and global `mise` config define `apm`, keep them aligned to the same source to avoid command-resolution collisions
  - prefer `mise exec github:jey3dayo/apm@v0.8.12.post1 -- apm ...` when you need to force the exact binary explicitly

## Task Selection

Choose the command based on intent:

- `mise run sync`
  - Accept newer upstream package content with `apm install -g --update`
  - Avoid for routine rollout; reserve it for intentional upstream refresh of workspace dependencies
  - Use for weekly refreshes, dependency drift acceptance, and content-hash mismatch resolution
- `mise run sync:stable`
  - Preserve the current manifest and lock
  - Runs `update -> ci -> apply -> doctor`
  - Use cautiously; it is broader than the normal day-to-day rollout path
  - Use when you want a stable rollout without taking new upstream refs
- `mise run ci`
  - Verification only
  - Runs formatting checks, validation, and smoke checks
  - Does not deploy
- `mise run apply`
  - Deploy the current manifest and lock to user targets
  - Also sync Codex-targeted skills into `~/.agents/skills`
  - Prefer for routine local rollout
  - Use when deployment is needed without a broader maintenance flow
- `mise run stage-catalog`
  - Normalize tracked shared guidance under `catalog/`
- `mise run register-catalog`
  - Install the tracked catalog ref after commit and push
- `mise run doctor`
  - Inspect rollout state and target coverage after deployment or refresh

## Common Flows

### Upstream Refresh

Use when you want newer external content.

```bash
cd ~/.apm
mise install
mise run sync
```

Review `apm.lock.yaml` carefully before commit.

### Stable Rollout

Use when you want to deploy the current manifest and lock as-is.

```bash
cd ~/.apm
mise install
mise run apply
mise run doctor
```

### Shared Guidance Update

Use when changing `catalog/AGENTS.md`, `catalog/agents/**`, `catalog/commands/**`, or `catalog/rules/**`.

```bash
cd ~/.apm
mise run stage-catalog
mise run register-catalog
mise run doctor
```

### Personal Skill Update

Use when changing `catalog/skills/**`.

```bash
cd ~/.apm
mise run format:markdown:bold-headings
mise run ci
```

Then review and commit the skill changes.

## Editing Rules

- Do not edit `apm_modules/`
- Do not treat deployed targets such as `~/.claude/` or `~/.codex/` as source of truth
- Do not reintroduce local `./packages/*` refs into the global manifest
- Do not hand-edit runtime outputs when the tracked workspace can regenerate them
- When changing the active `apm` source, update both tracked `mise` config locations that define `apm`
  - `~/.apm/mise.toml`
  - `~/.config/mise/config.default.toml`
- When verifying Codex skill rollout, check `~/.agents/skills`
  - if an external skill is still missing there after deployment, treat it as a temporary Codex-specific delivery gap and resolve it separately from the tracked workspace state

## Review Focus

When changing workspace mechanics, verify:

- task semantics still match documentation
- `sync` and `sync:stable` remain clearly differentiated
- `ci` stays verification-only
- catalog normalization and registration flows remain reproducible
- lockfile changes are intentional and scoped
