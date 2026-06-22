---
name: apm-usage
description: Use when working in the `~/.apm` global APM workspace and you need to decide what owns a change, which path is the source of truth, or which APM rollout / `mise` task to run. Trigger on natural-language requests such as `skillアップデートして再配布して`, `manual-skillsはやらないとダメ`, `orphaned package`, `apm.ymlのパス調整`, `apmのバージョンあげて`, or checking whether the `apm` source/version is recorded in `mise.toml`. Also trigger for `skillアップデート`, `再配布`, `apm.yml`, `apm.lock.yaml`, managed catalog rollout, checked-out external dependency repositories, and choosing between `mise run check`, `verify`, `deploy`, `refresh`, `upgrade`, `refresh:deploy`, `prepare:catalog`, `install:catalog`, `smoke:catalog`, and `apply:skills:local` inside `~/.apm`. For skill body, description, script, reference, or asset design itself, coordinate with `skill-creator`; for general mise usage outside the APM workspace, use `mise`.
---

# APM Usage

Route `~/.apm` work by ownership first, then choose the smallest task that matches the intent.

## Ownership

- Edit `~/.apm/catalog/skills/**` for personal skills.
- Edit `~/.apm/catalog/{AGENTS.md,agents/**,commands/**,rules/**}` for shared guidance.
- Edit `~/.apm/apm.yml` and `~/.apm/apm.lock.yaml` for dependency selection and accepted upstream state.
- Edit `~/.apm/README.md`, `llms.txt`, and `docs/**` only for workspace-owned prose.
- Treat `~/.apm/apm_modules/` and deployed targets as generated state, not editing surfaces.
- For an external dependency listed in `apm.yml` / `apm.lock.yaml`, edit the upstream repository checkout when that checkout is the user-specified source of truth. Commit and push there first, then accept the new resolved commit through `~/.apm`.

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
- For skill creation, updates, installs, or migrations in this workspace, include `mise run deploy` and a deployed target check in the plan unless the user explicitly asks for local-only refresh.
- After pushing a checked-out external dependency repository, run `mise run upgrade` in `~/.apm` to update `apm.lock.yaml`, deploy, and inspect targets. Review lock drift before treating the rollout as complete.

## Routing

- If the request is "change a personal skill", edit `catalog/skills/**`; use `skill-creator` for new or migrated managed skills.
- If the request is "optimize" or "customize" a skill for this workspace, treat it as personal skill work and prefer `catalog/skills/<id>/`.
- If the request is to preserve a reusable implementation judgment from real work, such as "Valibot belongs in schemas", "Result conversion belongs at a boundary", or "DB access belongs in repositories", encode it as a concern -> owner candidates -> caller rule table in the relevant personal skill under `catalog/skills/<id>/`.
- If the user does not specify the target skill id for that reusable judgment, inspect named skills, catalog triggers, and existing examples first; update the closest existing personal skill instead of creating a new skill by default.
- If the skill currently lives in `manual-skills/.apm/skills/<id>/`, first decide whether it is still an upstream packaging workaround. If it is becoming workspace-owned, plan a catalog migration instead of continuing to tune it in the manual lane.
- If the request is "change shared guidance", edit `catalog/**`; use `prepare:catalog` before publish/install.
- If the request is "change dependency selection", edit or review `apm.yml` / `apm.lock.yaml`.
- If the request names an external dependency that is already checked out locally and present in `apm.yml`, treat that checkout as the authoring surface when the user identifies it as the source of truth. Do not copy the change into `catalog/skills/**` unless the user is migrating ownership.
- If the request is "change only workspace docs or notes", edit the workspace files directly and do not restage the catalog unless `catalog/**` changed too.

## Guardrails

- Do not treat `~/.apm/apm_modules/` as the place to edit managed skills.
- Do not manage the same skill in both `catalog/skills/**` and `manual-skills/.apm/skills/**`.
- Do not duplicate an external dependency into `catalog/skills/**` just because a local checkout exists. Keep one source of truth: upstream checkout, managed catalog, manual copy, or private overlay.
- Do not keep accumulating workspace-specific optimizations in `manual-skills`; migrate to `catalog/skills/**` once the skill is no longer just an upstream delivery workaround.
- Do not reintroduce many local `./packages/*` refs into `~/.apm/apm.yml`.
- Do not hand-edit deployed targets such as `~/.claude/`, `~/.codex/`, or `~/.agents/skills`.
- Prefer `mise` tasks over ad hoc script entrypoints for normal operation.
- Before committing `apm.lock.yaml` after `mise run upgrade`, separate the intended dependency update from unrelated unpinned dependency drift. Report unrelated drift instead of hiding it inside the target dependency change.
- If an upstream skill path is wrong, correct it to the real upstream path and treat the corrected successful install as the main result.
- Treat known orphaned guidance or unrelated `manual-skills` deploy warnings as residual noise. Do not mention them in the final report when the command exits zero and the target skill source path, manifest or lock entry, and deployed target are correct.
- Report deploy warnings only when they directly affect the skill changed in this task, its manifest entry, its `manual-skills` provenance, or the deploy exit code.

## Fast Paths

1. Personal skill changed:
   - edit `~/.apm/catalog/skills/**`
   - optionally run `mise run format:markdown:bold-headings`
   - run `mise run deploy`
   - verify `~/.agents/skills/<id>/` contains the deployed skill
   - use `mise run apply:skills:local` only when the user explicitly wants a fast local Codex skill refresh

2. Shared guidance changed:
   - edit `~/.apm/catalog/**`
   - run `mise run prepare:catalog`
   - review the diff, commit/push, then run `mise run install:catalog`

3. Upstream refresh:
   - run `mise run upgrade`
   - review `apm.lock.yaml` before commit

4. Checked-out external dependency changed:
   - edit the external repository checkout that is the source of truth
   - run that repository's relevant checks
   - commit and push the external repository
   - in `~/.apm`, run `mise run upgrade`
   - verify `apm.lock.yaml` points the target dependency at the pushed commit
   - check whether `apm.lock.yaml` also changed unrelated unpinned dependencies
   - verify the deployed target such as `~/.agents/skills/<id>` contains the updated content
   - keep unrelated dirty files in `~/.apm` unstaged unless the user explicitly includes them

5. Manual skill promoted to workspace-owned:
   - move the skill from `manual-skills/.apm/skills/<id>/` to `catalog/skills/<id>/`
   - update `manual-skills/upstreams/**` to note the migration
   - run `mise run check`, then `mise run deploy`
   - verify the deployed target contains one copy of the skill
