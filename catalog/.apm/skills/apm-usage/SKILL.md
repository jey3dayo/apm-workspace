---
name: apm-usage
description: Use when working with APM manifests, `~/.apm` global skill management, or migrating enabled external skills into `apm-workspace`.
---

# APM Usage

## Overview

In this repository, APM is used primarily for **global skill management**.

- `~/.apm/apm.yml` is the global manifest
- `~/.apm/apm_modules/` stores downloaded dependency sources
- `~/.apm/catalog/` is the repo-tracked package for managed skills
- `apm install -g` is the normal deployment path

There is no `~/.apm/skills/` directory in the current global model.
Do not treat `packages/`, `~/.apm/skills/`, or workspace-root `.apm/` as the source of truth for global skills.

## Use This Skill When

- Editing or reviewing `~/.apm/apm.yml`
- Installing or updating global skills with `apm install -g`
- Refreshing the tracked managed-skill catalog in `~/.apm/catalog/`
- Explaining the difference between upstream refs, `apm_modules/`, and deployed targets
- Checking whether a skill should stay source-only instead of entering the global manifest

## Rule Of Thumb

Prefer `~/.apm` when:

- The skill should be globally available across machines
- You want the manifest to preserve the upstream repository reference
- The skill already comes from `nix/agent-skills-sources.nix`

When a user says "fix what is in `~/.apm`", first decide which layer actually owns the change:

- edit `~/.config/agents/src/**` for managed catalog content that is redistributed into `catalog/`
- edit `~/.apm/README.md`, `llms.txt`, `llms.md`, `apm.yml`, or `apm.lock.yaml` for workspace-owned files that live only in the `~/.apm` repo
- do not edit `~/.apm/catalog/**` first unless you are doing emergency repair and will immediately restage from the authoring source

Treat `~/.config/agents/src/skills/<name>/` as the **authoring source of truth** for managed skills.
Treat `~/.apm/catalog/` as the **tracked APM package artifact** that is generated from that source tree.
Treat `~/.config/agents/src/AGENTS.md`, `agents/`, and `rules/` as additional managed authoring sources that are staged into the same catalog.

For external skills, the source of truth is the upstream ref in `~/.apm/apm.yml`.  
For installed sources, the on-disk cache is `~/.apm/apm_modules/`.

For managed skills, the tracked package is:

```text
~/.apm/catalog/.apm/skills/<id>/SKILL.md
```

That tracked package is then referenced from `~/.apm/apm.yml` as:

```text
jey3dayo/apm-workspace/catalog#main
```

The same tracked catalog also carries:

```text
~/.apm/catalog/AGENTS.md
~/.apm/catalog/agents/**
~/.apm/catalog/rules/**
```

## Managed Skill Model

Managed skills now follow a simple two-layer model:

- authoring source:
  - `~/.config/agents/src/skills/<id>/`
- tracked deployment package:
  - `~/.apm/catalog/.apm/skills/<id>/`

Managed shared guidance follows the same pattern:

- authoring source:
  - `~/.config/agents/src/AGENTS.md`
  - `~/.config/agents/src/agents/**`
  - `~/.config/agents/src/rules/**`
- tracked deployment package:
  - `~/.apm/catalog/AGENTS.md`
  - `~/.apm/catalog/agents/**`
  - `~/.apm/catalog/rules/**`

The tracked package exists so APM can install one flat, repo-tracked catalog instead of many local-path entries.

Runtime targets are a third layer, not an editing surface:

- deployed user targets:
  - `~/.claude/`
  - `~/.codex/`
  - other detected runtime targets
- refresh path:
  - `stage-catalog` updates the tracked package in `~/.apm/catalog/`
  - `register-catalog`, `apply`, or `update` installs that tracked package and syncs runtime guidance files

In short:

- authoring change: `~/.config/agents/src/**`
- tracked package change: `~/.apm/catalog/**` via staging
- runtime change: produced by install/sync, not hand-edited

Not allowed:

- treating `~/.apm/skills/` as the global source of truth
- reintroducing many local-path skill entries into `~/.apm/apm.yml`
- describing `apm_modules/` as the place where managed skills should be edited

## Core Commands

```bash
# Bootstrap once from ~/.config
cd ~/.config
mise run apm:bootstrap

# Day-to-day global flow from ~/.apm
cd ~/.apm
mise install
mise run migrate-external
mise run apply
mise run doctor
```

## Managed Catalog Workflow

Use the workspace script when you need to refresh the tracked catalog package from `~/.config/agents/src/skills/`.

```bash
# Refresh the tracked catalog artifact
cd ~/.apm
powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.config\scripts\apm-workspace.ps1 stage-catalog

# Or on POSIX shells
sh "$HOME/.config/scripts/apm-workspace.sh" stage-catalog
```

That flow:

- rebuilds `~/.apm/.catalog-build/catalog/` as a temporary package artifact
- copies the result into `~/.apm/catalog/`
- keeps `~/.config/agents/src/skills/`, `AGENTS.md`, `agents/`, and `rules/` as the authoring source
- lets `~/.apm/apm.yml` keep a single upstream ref: `jey3dayo/apm-workspace/catalog#main`

For a full managed-content rollout, the normal sequence is:

1. edit the authoring source under `~/.config/agents/src/`
2. run `mise run stage-catalog` from `~/.apm`
3. review the generated diff in `~/.apm/catalog/`
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
  mise.toml
```

- `apm.yml` tracks dependencies by upstream ref
- `apm_modules/` holds downloaded sources
- `catalog/` holds the tracked managed-skill package
- `catalog/AGENTS.md`, `catalog/agents/`, and `catalog/rules/` hold tracked shared guidance assets
- `apm install -g` deploys the current global dependency set to user targets

If you see `./packages/...` in `apm.yml`, that is legacy migration residue and should be removed from the global model.

## External Migration Workflow

1. Bootstrap with `cd ~/.config && mise run apm:bootstrap`
2. Move to `~/.apm` and run `mise install`
3. Run `mise run migrate-external`
4. Run `mise run apply`
5. Validate with `mise run doctor`

`migrate-external` does this:

- reads `nix/agent-skills-sources.nix`
- derives canonical upstream refs for enabled skills
- skips IDs already owned by the managed catalog
- updates `~/.apm/apm.yml` through `apm install -g <upstream-ref>`
- lets APM place downloaded sources in `~/.apm/apm_modules/`
- auto-runs `pin-external` at the end, rewriting those external refs to `#resolved_commit` based on `apm.lock.yaml`

When a skill is moved into the managed catalog:

- remove the overlapping selection from `nix/agent-skills-sources.nix`
- run `mise run doctor` and confirm `external selection overlap: count=0`
- run `apm prune` once if old package ownership is still hanging around from a previous install state

When shared guidance changes under `agents/src`:

- run `mise run stage-catalog`
- review, commit, and push the updated `catalog/`
- run `mise run register-catalog`
- run `mise run doctor` and confirm target `config/agents/rules` are present

When the change is only for workspace-owned docs such as `~/.apm/README.md` or `llms.md`:

- edit those files directly in `~/.apm`
- do not run `stage-catalog` unless managed catalog content also changed
- push `~/.apm`, then use `register-catalog` only if the tracked package changed

## Legacy Notes

- `validate-catalog` now validates the tracked `catalog/` package against `~/.config/agents/src/skills/`
- `validate-catalog` also validates `agents/src/AGENTS.md`, `agents/`, and `rules/`
- public maintenance commands should use `bundle-catalog`, `stage-catalog`, `register-catalog`, and `smoke-catalog`
- `doctor` shows both catalog coverage and managed-vs-external selection overlap, plus target `config/agents/rules/skills` presence
- `apply` / `update` validate the tracked catalog before global install
- `apply` / `update` sync tracked `AGENTS.md`, `agents/`, and `rules/` into user runtime targets after install
- `apply` / `update` should fail fast if `./packages/*` entries still remain in the global manifest
- install helpers also fail when APM prints diagnostics such as `packages failed` or `error(s)` even if exit code is 0
- install the APM CLI through `mise` in this repository unless you are doing manual recovery
- top-level managed `commands/` are not in scope yet because `agents/src/` has no authoritative `commands/` tree today
