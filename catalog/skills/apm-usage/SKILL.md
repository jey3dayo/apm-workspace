---
name: apm-usage
description: Use when editing the `~/.apm` global APM workspace, deciding whether a change belongs in `~/.apm/catalog/` or workspace-owned files, or rolling out managed catalog updates.
---

# APM Usage

## Overview

In this repository, APM is used primarily for **global skill management**.

- `~/.apm/apm.yml` is the global manifest
- `~/.apm/apm_modules/` stores downloaded dependency sources
- `~/.apm/catalog/` is the repo-tracked package for shared runtime guidance
- `~/.apm/catalog/skills/` is the authoring source for personal skills
- `apm install -g` is the normal deployment path

There is no `~/.apm/skills/` directory in the current global model.
Do not treat `packages/`, `~/.apm/skills/`, or workspace-root `.apm/` as the source of truth for global skills.
The current day-to-day model is `catalog/skills/` authoring for personal skills, `catalog/` authoring for shared guidance, and external refs in `apm.yml`.

## Use This Skill When

- Editing or reviewing `~/.apm/apm.yml`
- Installing or updating global skills with `apm install -g`
- Refreshing the tracked managed-skill catalog in `~/.apm/catalog/`
- Explaining the difference between upstream refs, `apm_modules/`, and deployed targets

## Quick Routing

Start by routing the request into one of these lanes:

- managed catalog content:
  - edit `~/.apm/catalog/skills/**` for personal skills
  - edit `~/.apm/catalog/AGENTS.md`, `agents/**`, `commands/**`, or `rules/**` for shared runtime guidance
  - when the task is "create or migrate a managed skill", use `skill-creator`
  - then run `mise run stage-catalog`
- workspace-owned files:
  - edit `~/.apm/README.md`, `llms.md`, `apm.yml`, `apm.lock.yaml`, or `docs/**` directly
  - do not restage the catalog unless managed content changed too

## Rule Of Thumb

Prefer `~/.apm` when:

- The skill should be globally available across machines
- You want the managed catalog to preserve the tracked rollout path

When a user says "fix what is in `~/.apm`", first decide which layer actually owns the change:

- edit `~/.apm/catalog/skills/**` for personal skills
- edit `~/.apm/catalog/**` for shared runtime guidance
- edit `~/.apm/README.md`, `llms.md`, `apm.yml`, or `apm.lock.yaml` for workspace-owned files that live only in the `~/.apm` repo

Treat `~/.apm/catalog/skills/` as the authoring source of truth for personal skills, and `~/.apm/catalog/` as the source of truth for shared runtime guidance.
Do not reference removed legacy agent directories; the active managed workflow no longer depends on them.
For new managed skill authoring, prefer `skill-creator`; use `apm-usage` for broader catalog and manifest routing.
For installed sources, the on-disk cache is `~/.apm/apm_modules/`; it remains read-only cache state.

For managed skills, the tracked package is:

```text
~/.apm/catalog/skills/<id>/SKILL.md
```

That tracked package is then referenced from `~/.apm/apm.yml` as:

```text
jey3dayo/apm-workspace/catalog#main
```

The shared guidance package carries:

```text
~/.apm/catalog/AGENTS.md
~/.apm/catalog/agents/**
~/.apm/catalog/commands/**
~/.apm/catalog/rules/**
```

## Managed Skill Model

Managed assets now follow a split model:

- source of truth:
  - `~/.apm/catalog/skills/<id>/`
  - `~/.apm/catalog/AGENTS.md`
  - `~/.apm/catalog/agents/**`
  - `~/.apm/catalog/commands/**`
  - `~/.apm/catalog/rules/**`

Runtime targets are a third layer, not an editing surface:

- deployed user targets:
  - `~/.claude/`
  - `~/.codex/`
  - other detected runtime targets
- refresh path:
  - `stage-catalog` updates the tracked package in `~/.apm/catalog/`
  - `register-catalog`, `apply`, or `update` installs that tracked package and syncs runtime guidance files, including `commands/`

In short:

- authoring change: `~/.apm/catalog/skills/**` or `~/.apm/catalog/**`
- runtime change: produced by install/sync, not hand-edited

## Fast Paths

Use these short flows for the common request shapes:

1. Managed skill or guidance changed
   - edit `~/.apm/catalog/skills/**` for personal skills or `~/.apm/catalog/**` for shared guidance
   - run `mise run format:markdown:bold-headings` when you want heading normalization for personal skills
   - run `mise run stage-catalog` for shared guidance
   - review the `src/**` or normalized `catalog/**` diff
   - commit/push `~/.apm`
   - run `mise run register-catalog`
   - run `mise run doctor`

2. Only `~/.apm` docs or manifest files changed
   - edit the workspace-owned files directly
   - commit/push `~/.apm`
   - run `mise run register-catalog` only if `catalog/` changed too

Not allowed:

- treating `~/.apm/skills/` as the global source of truth
- reintroducing many local-path skill entries into `~/.apm/apm.yml`
- describing `apm_modules/` as the place where managed skills should be edited

## Core Commands

```bash
# Day-to-day global flow from ~/.apm
cd ~/.apm
mise install
mise run format
mise run ci:check
mise run apply
mise run doctor
```

## Managed Catalog Workflow

Use the workspace script when you need to normalize the tracked catalog package before commit/push.

```bash
# Refresh the tracked catalog artifact
cd ~/.apm
powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.config\scripts\apm-workspace.ps1 stage-catalog

# Or on POSIX shells
sh "$HOME/.config/scripts/apm-workspace.sh" stage-catalog
```

That flow:

- rebuilds `~/.apm/.catalog-build/catalog/` as a temporary package artifact
- copies the normalized result back into `~/.apm/catalog/`
- lets `~/.apm/apm.yml` keep a single upstream ref: `jey3dayo/apm-workspace/catalog#main`

For a full managed-content rollout, the normal sequence is:

1. edit `~/.apm/catalog/`
2. run `mise run stage-catalog` from `~/.apm`
3. review the normalized `catalog/` diff
4. commit and push `~/.apm`
5. run `mise run register-catalog`
6. run `mise run doctor`

## Important Global Model

APM global skill management in this setup is centered on:

```text
~/.apm/
  apm.yml
  apm.lock.yaml
  apm_modules/
  catalog/
  src/
  mise.toml
```

- `apm.yml` tracks dependencies by upstream ref
- `apm_modules/` holds downloaded sources
- `src/` holds personal skill sources
- `catalog/` holds the tracked shared guidance package
- `catalog/AGENTS.md`, `catalog/agents/`, `catalog/commands/`, and `catalog/rules/` hold tracked shared guidance assets
- `apm install -g` deploys the current global dependency set to user targets

If you see `./packages/...` in `apm.yml`, that is legacy migration residue and should be removed from the global model.

When shared guidance content changes:

- run `mise run stage-catalog`
- review, commit, and push the updated `catalog/`
- run `mise run register-catalog`
- run `mise run doctor` and confirm target `config/agents/commands/rules` are present

When personal skill content changes:

- edit `~/.apm/catalog/skills/**`
- run `mise run format:markdown:bold-headings`
- review, commit, and push the updated `src/`

When the change is only for workspace-owned docs such as `~/.apm/README.md` or `llms.md`:

- edit those files directly in `~/.apm`
- do not run `stage-catalog` unless managed catalog content also changed
- push `~/.apm`, then use `register-catalog` only if the tracked package changed

## Workspace Notes

- `validate:catalog` now validates the tracked `catalog/` package itself and its required assets
- `validate:catalog` is available both as `mise run validate:catalog` and as a workspace script command
- `format` formats Markdown / TOML / YAML inside `~/.apm`
- `ci:check` runs format checks plus validation and smoke checks
- `ci` formats, validates, applies, and verifies the local workspace rollout
- `catalog:tidy` restages the tracked catalog, validates it, and prints workspace health
- public maintenance commands should use `bundle-catalog`, `stage-catalog`, `register-catalog`, and `smoke-catalog`
- `doctor` shows catalog coverage plus target `config/agents/commands/rules/skills` presence
- `apply` / `update` validate the tracked catalog before global install
- `apply` / `update` sync tracked `AGENTS.md`, `agents/`, `commands/`, and `rules/` into user runtime targets after install
- `apply` / `update` should fail fast if `./packages/*` entries still remain in the global manifest
- install helpers also fail when APM prints diagnostics such as `packages failed` or `error(s)` even if exit code is 0
- install the APM CLI through `mise` in this repository unless you are doing manual recovery
