---
name: apm-usage
description: Use when editing the `~/.apm` global APM workspace, deciding whether a change belongs in `~/.apm/catalog/` or workspace-owned files, choosing between `mise run check`, `mise run verify`, `mise run deploy`, `mise run upgrade`, `mise run refresh:deploy`, `apply`, and `install:catalog`, or rolling out managed catalog updates.
---

# APM Usage

## Overview

In this repository, APM is used primarily for **global skill management**.

- `~/.apm/apm.yml` is the global manifest
- `~/.apm/apm_modules/` stores downloaded dependency sources
- `~/.apm/catalog/` is the repo-tracked package for shared runtime guidance
- `~/.apm/catalog/skills/` is the authoring source for personal skills
- `mise run check` is the lightweight verification path for the current workspace state
- `mise run verify` is the deep-verification path for the current workspace state
- `mise run deploy` is the routine local rollout path for the current manifest and lock
- `mise run upgrade` is the upstream-refresh path
- `mise run refresh:deploy` is the stable rollout path for the current manifest and lock

There is no `~/.apm/skills/` directory in the current global model.
Do not treat `packages/`, `~/.apm/skills/`, or workspace-root `.apm/` as the source of truth for global skills.
The current day-to-day model is `catalog/skills/` authoring for personal skills, `catalog/` authoring for shared guidance, and external refs in `apm.yml`.

## Use This Skill When

- Editing or reviewing `~/.apm/apm.yml`
- Installing or updating global skills with `apm install -g`
- Choosing between `mise run check`, `mise run verify`, `mise run deploy`, `mise run upgrade`, `mise run refresh:deploy`, `apply`, and `install:catalog`
- Refreshing the tracked managed-skill catalog in `~/.apm/catalog/`
- Explaining the difference between upstream refs, `apm_modules/`, and deployed targets

## Quick Routing

Start by routing the request into one of these lanes:

- managed catalog content:
  - edit `~/.apm/catalog/skills/**` for personal skills
  - edit `~/.apm/catalog/AGENTS.md`, `agents/**`, `commands/**`, or `rules/**` for shared runtime guidance
  - when the task is "create or migrate a managed skill", use `skill-creator`
- local rollout from the current manifest and lock:
  - use `mise run check` when you want a lightweight pre-deploy gate
  - use `mise run verify` when you want smoke verification without deploying
  - use `mise run deploy` when you want checks plus deployment from the current tracked state without taking new upstream refs
  - use `mise run apply` only when you need deployment without the bundled check flow
- managed catalog registration:
  - run `mise run prepare:catalog` before commit/push when shared guidance changed
  - run `mise run install:catalog` after commit/push when you want to install the tracked catalog package by upstream ref
- upstream dependency refresh:
  - use `mise run upgrade` to accept newer upstream package content with `apm install -g --update`
  - review `apm.lock.yaml` carefully before commit
- stable local rollout:
  - use `mise run refresh:deploy` to keep the current manifest and lock while still running `refresh -> deploy`
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
  - `prepare:catalog` updates the tracked package in `~/.apm/catalog/`
  - `install:catalog`, `deploy`, `apply`, and `refresh:deploy` install tracked runtime guidance into user targets

In short:

- authoring change: `~/.apm/catalog/skills/**` or `~/.apm/catalog/**`
- runtime change: produced by install/upgrade flows, not hand-edited

## Fast Paths

Use these short flows for the common request shapes:

1. Personal skill changed and you want a local rollout
   - edit `~/.apm/catalog/skills/**`
   - run `mise run format:markdown:bold-headings` when you want heading normalization for Markdown in `catalog/`
   - run `mise run deploy`

2. Shared guidance changed and you want to publish the tracked catalog update
   - edit `~/.apm/catalog/**`
   - run `mise run prepare:catalog`
   - review the normalized `catalog/**` diff
   - commit/push `~/.apm`
   - run `mise run install:catalog`
   - run `mise run doctor`

3. Only `~/.apm` docs or manifest files changed
   - edit the workspace-owned files directly
   - commit/push `~/.apm`
   - run `mise run install:catalog` only if `catalog/` changed too

4. Upstream dependency refresh
   - run `mise run upgrade` when you want to accept new upstream package content with `apm install -g --update`
   - run `mise run refresh:deploy` when you want to update first and then run the full local rollout without taking new upstream refs

Not allowed:

- treating `~/.apm/skills/` as the global source of truth
- reintroducing many local-path skill entries into `~/.apm/apm.yml`
- describing `apm_modules/` as the place where managed skills should be edited

## Core Commands

```bash
# Day-to-day global flow from ~/.apm
cd ~/.apm
mise install
mise run deploy

# when you intentionally want newer upstream content
mise run upgrade
# or
mise run refresh:deploy
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
2. run `mise run prepare:catalog` from `~/.apm`
3. review the normalized `catalog/` diff
4. commit and push `~/.apm`
5. run `mise run install:catalog`
6. run `mise run doctor`

## Important Global Model

APM global skill management in this setup is centered on:

```text
~/.apm/
  apm.yml
  apm.lock.yaml
  apm_modules/
  catalog/
  mise.toml
```

- `apm.yml` tracks dependencies by upstream ref
- `apm_modules/` holds downloaded sources
- `catalog/` holds the tracked shared guidance package
- `catalog/skills/` holds the authoring source for personal skills
- `catalog/AGENTS.md`, `catalog/agents/`, `catalog/commands/`, and `catalog/rules/` hold tracked shared guidance assets
- `apm install -g` deploys the current global dependency set to user targets

If you see `./packages/...` in `apm.yml`, that is legacy migration residue and should be removed from the global model.

When shared guidance content changes:

- run `mise run prepare:catalog`
- review, commit, and push the updated `catalog/`
- run `mise run install:catalog`
- run `mise run doctor` and confirm target `config/agents/commands/rules` are present

When personal skill content changes:

- edit `~/.apm/catalog/skills/**`
- run `mise run format:markdown:bold-headings`
- run `mise run deploy` when you want the current tracked state checked and deployed locally

When the change is only for workspace-owned docs such as `~/.apm/README.md` or `llms.md`:

- edit those files directly in `~/.apm`
- do not run `prepare:catalog` unless managed catalog content also changed
- push `~/.apm`, then use `install:catalog` only if the tracked package changed

## Workspace Notes

- `validate:catalog` now validates the tracked `catalog/` package itself and its required assets
- `validate:catalog` is available both as `mise run validate:catalog` and as a workspace script command
- `format` formats Markdown / TOML / YAML inside `~/.apm`
- `check` runs format checks plus validation
- `verify` runs `check` plus catalog smoke verification
- `deploy` runs `check -> apply -> doctor`
- `verify:catalog` restages the tracked catalog, validates it, and prints workspace health
- public maintenance commands should use `bundle-catalog`, `prepare:catalog`, `install:catalog`, and `smoke:catalog`
- `doctor` shows catalog coverage plus target `config/agents/commands/rules/skills` presence
- `apply` / `refresh` validate the tracked catalog before global install
- `apply` / `refresh` sync tracked `AGENTS.md`, `agents/`, `commands/`, and `rules/` into user runtime targets after install
- `upgrade` is the upstream-acceptance flow centered on `apm install -g --update`
- `refresh:deploy` preserves the older `refresh -> deploy` flow for current manifest plus lock rollout
- `apply` / `update` should fail fast if `./packages/*` entries still remain in the global manifest
- install helpers also fail when APM prints diagnostics such as `packages failed` or `error(s)` even if exit code is 0
- install the APM CLI through `mise` in this repository unless you are doing manual recovery
