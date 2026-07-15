---
name: apm-usage
description: >-
  Route work in the `~/.apm` global APM workspace: decide what owns a change,
  which path is the source of truth, and which APM rollout / `mise` task to
  run. Use for skill update and redistribution requests
  (`skillアップデートして再配布して`, `再配布`), `apm.yml` / `apm.lock.yaml` and managed catalog
  rollout, manual-skills package state, orphaned APM packages, checked-out
  external dependency repositories, optional repository-scoped skill packages,
  and `apmのバージョンあげて` / pinned `apm`
  source checks. For skill body, description, script, reference, or asset
  design itself, coordinate with `skill-creator`; for general mise usage
  outside the APM workspace (including `mise upgrade TOOL` and
  `minimum_release_age`), use `mise`.
---

# APM Usage

Route `~/.apm` work by ownership first, then choose the smallest task that matches the intent.

## Ownership

- Edit `~/.apm/catalog/skills/**` for personal skills.
- Edit `~/.apm/catalog/{AGENTS.md,agents/**,commands/**,rules/**}` for shared guidance.
- Edit `~/.apm/optional-skills/.apm/skills/**` for skills that should be tracked
  here but installed only by selected repositories.
- Edit `~/.apm/optional-skills/apm.yml` for the standalone optional package
  manifest.
- Edit `~/.apm/apm.yml` and `~/.apm/apm.lock.yaml` for dependency selection and accepted upstream state.
- Edit `~/.apm/README.md`, `llms.txt`, and `docs/**` only for workspace-owned prose.
- Treat `~/.apm/apm_modules/` and deployed targets as generated state, not editing surfaces.
- For an external dependency listed in `apm.yml` / `apm.lock.yaml`, edit the upstream repository checkout when that checkout is the user-specified source of truth. Commit and push there first, then accept the new resolved commit through `~/.apm`.

There is no active `~/.apm/skills/` editing surface in this model.

Use `catalog/skills/<id>/` for skills that are personally optimized, curated, or expected to keep evolving in this workspace.

Use `optional-skills/.apm/skills/<id>/` for workspace-owned skills that should
not be included in the global automatic rollout. The package is consumed from a
repository-local `apm.yml` with `--skill <id>`.

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

## Routing

- If the request is "change a personal skill", edit `catalog/skills/**`; use `skill-creator` for new or migrated managed skills.
- If the request is "make a skill repository-specific", edit
  `optional-skills/.apm/skills/**` and keep `optional-skills` out of the root
  `apm.yml`.
- If the request is "optimize" or "customize" a skill for this workspace, treat it as personal skill work and prefer `catalog/skills/<id>/`.
- If the request is to preserve a reusable implementation judgment from real work, such as "Valibot belongs in schemas", "Result conversion belongs at a boundary", or "DB access belongs in repositories", encode it as a concern -> owner candidates -> caller rule table in the relevant personal skill under `catalog/skills/<id>/`.
- If the user does not specify the target skill id for that reusable judgment, inspect named skills, catalog triggers, and existing examples first; update the closest existing personal skill instead of creating a new skill by default.
- If the request is "change shared guidance", edit `catalog/**`; use `prepare:catalog` before publish/install.
- If the request is "change dependency selection", edit or review `apm.yml` / `apm.lock.yaml`.
- If the request is about `mise upgrade <tool>`, `minimum_release_age`, latest eligible release selection, or why a non-APM tool version did not update, use the `mise` skill unless the pinned `apm` source, APM manifest, lockfile, or rollout task selection is the actual subject.
- If the request is to add an individual APM package, decide scope before running `apm install`: use `apm install -g <package-ref>` only for user-global dependencies that belong in `~/.apm`; use `apm install <package-ref>` from the target repository for repo-local dependencies.
- For an optional skill from this workspace, add
  `jey3dayo/apm-workspace/optional-skills#main` to the consuming repository and
  select it with `apm install --skill <id>`.
- For an optional skill embedded in an external bundle, keep the external
  package as the source of truth and select it in the consuming repository with
  `apm install <package-ref> --skill <id>`.
- If the request is to scan an arbitrary repository and create, update, or clean up its repo-local `apm.yml`, use `apm-repo-bootstrap`; keep this skill focused on global APM ownership and rollout decisions.
- If the request is to add an MCP server through APM, apply the same scope rule: use `apm install -g --mcp <name> ...` only for cross-repo foundation MCPs; use repo-local `apm install --mcp <name> ...` for project, framework, UI, database, browser, or app-runtime-specific MCPs.
- If MCP placement, server selection, credentials, transport, or startup behavior is the main question, coordinate with `mcp-tools`; keep this skill focused on APM ownership, source of truth, and rollout commands.
- If the APM workspace has no repo-local MCP distribution lane for a target repository, record the intended placement as guidance and keep the global manifest lightweight. Treat implementing repo-local MCP distribution as a separate workspace-mechanics task.
- If the request is "enable Headroom MCP" or "compare Headroom with RTK", treat the Headroom MCP server as a global foundation managed through the `mcp:` section of `~/.apm/apm.yml`. Keep the Headroom binary itself managed by user-global `~/.config/mise`, and use the `headroom` skill for usage guidance; do not add Headroom to repo-local `mise.toml`.
- If the request is "change only workspace docs or notes", edit the workspace files directly and do not restage the catalog unless `catalog/**` changed too.

## Repo-Local MCP Recommendations

When moving tools out of global APM, prefer project-local APM installs for MCPs that depend on a specific app runtime, browser session, UI workflow, or repository credential context.

Good repo-local candidates:

- `chrome-devtools`: treat as a browser MCP, not as a lightweight web skill. Prefer `claude-in-chrome`/Codex Chrome addon for ordinary browser operation when sufficient; add `chrome-devtools` repo-local or on-demand only for DevTools-specific depth (Lighthouse, performance trace, heap snapshot), project login/session state, local runtime coupling, or repeatable browser verification beyond that.
  - When a repository keeps `chrome-devtools` as an exception to the global default, record the concrete reason in that repository's own `apm.yml`/`AGENTS.md` (e.g. "uses Lighthouse audits for perf regression checks"), not just "this is a web app". Central `~/.apm` guidance states the default; repo-local docs state the exception and why it does not fit the default.
- `tauri-mcp-server`: install only in repositories that own a Tauri runtime such as `src-tauri`.
- `agentation-mcp`: install only in projects that use the Agentation toolbar and need annotation sync with agents.
- `peekaboo` or other screen automation MCPs: keep repo-local or on-demand for visual inspection; avoid global startup fan-out.
- database, SaaS observability, or project API MCPs: keep repo-local so credentials and environment loading stay scoped to the project.

Use global APM only for cross-repo foundations such as lightweight notifications, current docs lookup, public research/readers, or core agent bridges.

When deciding repo-local MCP placement by repository type, runtime, or workflow, read `references/repo-local-mcp.md`.

## Guardrails

- Do not treat `~/.apm/apm_modules/` as the place to edit managed skills.
- Do not manage the same skill in both `catalog/skills/**` and `manual-skills/.apm/skills/**`.
- Do not manage the same skill in both `catalog/skills/**` and `optional-skills/.apm/skills/**`.
- Do not add `optional-skills` to the root `apm.yml`; its purpose is explicit repository-scoped installation.
- Do not duplicate an external dependency into `catalog/skills/**` just because a local checkout exists. Keep one source of truth: upstream checkout, managed catalog, manual copy, or private overlay.
- Do not reintroduce many local `./packages/*` refs into `~/.apm/apm.yml`.
- Do not hand-edit deployed targets such as `~/.claude/`, `~/.codex/`, or `~/.agents/skills`.
- Headroom MCP server registration lives in the `mcp:` section of `~/.apm/apm.yml` like other global foundation MCPs. Do not persist Headroom proxy/wrap configuration through APM package manifests; treat proxy/wrap setup as a local machine setup step unless the user explicitly asks to manage that runtime state.
- Prefer `mise` tasks over ad hoc script entrypoints for normal operation.
- Before changing user-global `mise` tools, verify the resolved binary path and install tree. `mise latest` can lag or differ because of release-age policy, so compare with the upstream registry when exact latest-version behavior matters.
- Before committing `apm.lock.yaml` after `mise run upgrade`, separate the intended dependency update from unrelated unpinned dependency drift. Report unrelated drift instead of hiding it inside the target dependency change.
- When `apm.yml` includes a `gist.github.com/...#<sha>` dependency, verify the refreshed `apm.lock.yaml` record after `mise run upgrade` or any lock refresh. The workspace validator accepts APM's shortened `owner/<gist-id>` lock form as the same gist dependency, but the deployed target should still be checked before declaring the rollout complete.
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

2. Optional repository skill changed:
   - edit `optional-skills/.apm/skills/**`
   - run the optional package smoke check or a temporary `apm install --skill <id>` from a fixture repository
   - do not run the global deployment as the delivery mechanism
   - verify the consuming repository's selected skill is present after installation

3. Shared guidance changed:
   - edit `~/.apm/catalog/**`
   - run `mise run prepare:catalog`
   - review the diff, commit/push, then run `mise run install:catalog`

4. Upstream refresh:
   - run `mise run upgrade`
   - if the manifest contains `gist.github.com/...#<sha>`, verify the regenerated `apm.lock.yaml` kept the same `repo_url` spelling before deploy
   - review `apm.lock.yaml` before commit

5. Individual package or MCP added:
   - choose global vs repo-local before installing
   - for global dependencies, work in `~/.apm` and use `apm install -g <package-ref>` or `apm install -g --mcp <name> ...`
   - for repo-local dependencies, work in the target repository and use `apm install <package-ref>` or `apm install --mcp <name> ...`
   - for global changes, run `mise run check`, then `mise run deploy`; for repo-local changes, run that repository's defined APM or project checks
   - verify the intended `apm.yml`, `apm.lock.yaml`, and deployed target changed, and no unrelated workspace dependencies drifted

6. Checked-out external dependency changed:
   - edit the external repository checkout that is the source of truth
   - run that repository's relevant checks
   - commit and push the external repository
   - in `~/.apm`, run `mise run upgrade`
   - verify `apm.lock.yaml` points the target dependency at the pushed commit
   - check whether `apm.lock.yaml` also changed unrelated unpinned dependencies
   - verify the deployed target such as `~/.agents/skills/<id>` contains the updated content
   - keep unrelated dirty files in `~/.apm` unstaged unless the user explicitly includes them

7. Manual skill promoted to workspace-owned:
   - move the skill from `manual-skills/.apm/skills/<id>/` to `catalog/skills/<id>/`
   - update `manual-skills/upstreams/**` to note the migration
   - run `mise run check`, then `mise run deploy`
   - verify the deployed target contains one copy of the skill
