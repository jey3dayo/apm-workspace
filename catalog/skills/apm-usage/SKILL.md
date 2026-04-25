---
name: apm-usage
description: Use when working in the `~/.apm` global APM workspace and you need to decide what owns a change, which path is the source of truth, or which `mise` task to run. Trigger for tasks involving `~/.apm/catalog/skills/**` vs `~/.apm/catalog/**`, `apm.yml` / `apm.lock.yaml`, managed catalog rollout, or choosing between `mise run check`, `verify`, `deploy`, `refresh`, `upgrade`, `refresh:deploy`, `prepare:catalog`, `install:catalog`, `smoke:catalog`, and `apply:skills:local`.
---

# APM Usage

Route `~/.apm` work by ownership first, then choose the smallest task that matches the intent.

## Ownership

- Edit `~/.apm/catalog/skills/**` for personal skills.
- Edit `~/.apm/catalog/{AGENTS.md,agents/**,commands/**,rules/**}` for shared guidance.
- Edit `~/.apm/apm.yml` and `~/.apm/apm.lock.yaml` for dependency selection and accepted upstream state.
- Edit `~/.apm/README.md`, `llms.txt`, and `docs/**` only for workspace-owned prose.
- Treat `~/.apm/apm_modules/` and deployed targets as generated state, not editing surfaces.

There is no active `~/.apm/skills/` editing surface in this model.

Use `catalog/skills/<id>/` for skills that are personally optimized, curated, or expected to keep evolving in this workspace.

Use `manual-skills/.apm/skills/<id>/` only for upstream skills that do not install or deploy cleanly through the normal managed lane because of symlinks, packaging quirks, missing bundled files, or incompatible upstream layout. Record the reason and provenance under `manual-skills/upstreams/**`.

If a manual skill becomes a workspace-owned skill that will be tuned over time, migrate it into `catalog/skills/<id>/`.

## Task Selection

- Run `mise run check` for a lightweight pre-deploy gate.
- Run `mise run verify` for `check` plus catalog smoke verification.
- Run `mise run deploy` for the normal local rollout from the current manifest and lock.
- Run `mise run apply` only when deployment is needed without the bundled `check -> doctor` flow.
- Run `mise run refresh` to refresh the checkout and dependency state without deploying.
- Run `mise run upgrade` to accept newer upstream package content with `apm install -g --update`.
- Run `mise run refresh:deploy` when you explicitly want `refresh -> deploy`.
- Run `mise run prepare:catalog` before commit/push when tracked catalog content changed.
- Run `mise run install:catalog` after commit/push when you want to install the tracked catalog ref.
- Run `mise run smoke:catalog` to smoke-test the generated catalog package.
- Run `mise run apply:skills:local` for a fast local Codex skill refresh only.

## Routing

- If the request is "change a personal skill", edit `catalog/skills/**`; use `skill-creator` for new or migrated managed skills.
- If the request is "optimize" or "customize" a skill for this workspace, treat it as personal skill work and prefer `catalog/skills/<id>/`.
- If the skill currently lives in `manual-skills/.apm/skills/<id>/`, first decide whether it is still an upstream packaging workaround. If it is becoming workspace-owned, plan a catalog migration instead of continuing to tune it in the manual lane.
- If the request is "change shared guidance", edit `catalog/**`; use `prepare:catalog` before publish/install.
- If the request is "change dependency selection", edit or review `apm.yml` / `apm.lock.yaml`.
- If the request is "change only workspace docs or notes", edit the workspace files directly and do not restage the catalog unless `catalog/**` changed too.

## Guardrails

- Do not treat `~/.apm/apm_modules/` as the place to edit managed skills.
- Do not manage the same skill in both `catalog/skills/**` and `manual-skills/.apm/skills/**`.
- Do not keep accumulating workspace-specific optimizations in `manual-skills`; migrate to `catalog/skills/**` once the skill is no longer just an upstream delivery workaround.
- Do not reintroduce many local `./packages/*` refs into `~/.apm/apm.yml`.
- Do not hand-edit deployed targets such as `~/.claude/`, `~/.codex/`, or `~/.agents/skills`.
- Prefer `mise` tasks over ad hoc script entrypoints for normal operation.

## Fast Paths

1. Personal skill changed:
   - edit `~/.apm/catalog/skills/**`
   - optionally run `mise run format:markdown:bold-headings`
   - run `mise run deploy` or `mise run apply:skills:local`

2. Shared guidance changed:
   - edit `~/.apm/catalog/**`
   - run `mise run prepare:catalog`
   - review the diff, commit/push, then run `mise run install:catalog`

3. Upstream refresh:
   - run `mise run upgrade`
   - review `apm.lock.yaml` before commit

4. Manual skill promoted to workspace-owned:
   - move the skill from `manual-skills/.apm/skills/<id>/` to `catalog/skills/<id>/`
   - update `manual-skills/upstreams/**` to note the migration
   - run `mise run check`, then `mise run deploy` or `mise run apply:skills:local`
   - verify the deployed target contains one copy of the skill
