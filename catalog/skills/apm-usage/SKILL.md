---
name: apm-usage
description: >-
  Route work in the `~/.apm` global APM workspace: decide what owns a change,
  which path is the source of truth, and which APM rollout / `mise` task to
  run. Use for skill update and redistribution requests
  (`skillアップデートして再配布して`, `再配布`), `apm.yml` / `apm.lock.yaml` and managed catalog
  rollout, manual-skills package state, orphaned APM packages, checked-out
  external dependency repositories, optional repository-scoped skill packages,
  `~/.codex/config.toml` の MCP block 編集、`codex mcp add` / `codex mcp remove`,
  global MCP の追加・変更・削除、および所有元が不明な runtime MCP 設定,
  and `apmのバージョンあげて` / pinned `apm`
  source checks. For skill body, description, script, reference, or asset
  design itself, coordinate with `skill-creator`; for general mise usage
  outside the APM workspace (including `mise upgrade TOOL` and
  `minimum_release_age`), use `mise`. Re-invoke this skill even mid-session
  when the conversation shifts to these topics — e.g. during a `/doctor` run
  the user asks to remove an MCP and redistribute, or muses about deleting a
  `catalog/skills/**` skill (`これいるかな`) and needs the correct rollout task.
---

# APM Usage

Route `~/.apm` work by ownership first, then choose the smallest task that matches the intent.

## Ownership

- Edit `~/.apm/.apm/skills/**` for skills that operate only on this APM workspace.
- Edit `~/.apm/catalog/skills/**` for personal skills that should be available
  in the global automatic rollout.
- Edit `~/.apm/catalog/{AGENTS.md,agents/**,commands/**,rules/**}` for shared guidance.
- Edit `~/.apm/optional-skills/<id>/**` for skills that should be tracked
  here but installed only by selected repositories.
- Treat each optional skill directory as an individually installable package;
  the `optional-skills` collection root has no package manifest.
- Edit `~/.apm/apm.yml` and `~/.apm/apm.lock.yaml` for dependency selection and accepted upstream state.
- Edit `~/.apm/README.md`, `llms.txt`, and `docs/**` only for workspace-owned prose.
- Treat `~/.apm/.claude/skills/**` and `~/.apm/.agents/skills/**` as runtime
  bridges for workspace-only skills: create or repoint the per-skill symlinks
  there, but never edit skill content through them.
- Treat `~/.apm/apm_modules/` and deployed targets as generated state, not editing surfaces.
- For an external dependency listed in `apm.yml` / `apm.lock.yaml`, edit the upstream repository checkout when that checkout is the user-specified source of truth. Commit and push there first, then accept the new resolved commit through `~/.apm`.

## MCP Ownership Gate

Before any persistent MCP configuration write:

1. If `~/.apm` exists, inspect its root `apm.yml`, ownership guidance, and rollout script first.
2. Classify the requested path as a source of truth or deployed output before writing.
3. If the MCP is declared in APM, edit the tracked APM source and redeploy; do not run `codex mcp add` / `codex mcp remove` or hand-edit `~/.codex/config.toml` as the durable change.
4. For diagnostics, prefer a one-run `codex -c` override and state that it is temporary.
5. Verify the resolved server with `codex mcp list` and one real tool call before reporting completion.

`jina-reader` is a cross-repository foundation MCP. Its transport, URL, authentication, and tool filter belong in the root `apm.yml`; `apm.lock.yaml` records the accepted state and runtime MCP blocks are deployed outputs.

## Skill Placement

Choose the narrowest lane that matches who needs the skill. Name the lane
before installing or creating a skill.

| Lane                | Scope                                                         | Source of truth                    | Delivery                                                              |
| ------------------- | ------------------------------------------------------------- | ---------------------------------- | --------------------------------------------------------------------- |
| `workspace-only`    | APM workspace operations only                                 | `.apm/skills/<id>/`                | Local `.claude/skills/<id>` and `.agents/skills/<id>` bridges         |
| `repository-local`  | One repository's runtime, credentials, framework, or workflow | Target repository's `apm.yml`      | `apm install <package-ref>` in that repository                        |
| `optional`          | Workspace-owned skill used by selected repositories           | `optional-skills/<id>/`            | Direct `apm install jey3dayo/apm-workspace/optional-skills/<id>#main` |
| `global-catalog`    | Personal cross-repository workflow                            | `catalog/skills/<id>/`             | Global automatic rollout                                              |
| `global-dependency` | External cross-repository foundation                          | Root `apm.yml` and `apm.lock.yaml` | `apm install -g <package-ref>`                                        |
| `private`           | Machine-local, untracked overlay                              | `private-skills/.apm/skills/<id>/` | Local Codex skill sync only                                           |
| `manual`            | Upstream package that cannot use the managed lane             | `manual-skills/.apm/skills/<id>/`  | Manual-skills package rollout                                         |

## Install Gate

Before an install, assign exactly one lane name.

1. Use `workspace-only` when the skill operates `~/.apm` itself.
2. Use `repository-local` when it depends on one repository's runtime,
   credentials, framework, browser session, or service.
3. Use `optional` when this workspace owns the skill but only selected
   repositories need it.
4. Use `global-catalog` or `global-dependency` only when it is useful across
   unrelated repositories, has no repository-specific credential or runtime
   dependency, and is expected to be used repeatedly. Between the two, use
   `global-catalog` when this workspace owns and evolves the skill, and
   `global-dependency` when an external upstream package is the source of
   truth.
5. Use `private` for untracked machine-local work and `manual` only for an
   upstream packaging failure.

If the lane is unclear, start with `repository-local` in a known consumer
repository and promote it to a global lane only after real use proves the need.
If no consumer repository can be named yet, do not install anywhere; record the
candidate and revisit when a concrete repository needs it.

Before installing into or reviewing a `repository-local` manifest, check its
`targets:` list against which agent runtimes are actually used in that
repository. A `targets: [codex]`-only manifest never deploys to
`.claude/skills/`; add `claude` (and `agent-skills` when applicable) whenever
Claude Code is one of the repository's runtimes, otherwise every
repository-local skill or MCP silently misses Claude Code. `apm-repo-bootstrap`
preserves the repository's existing target style by design and does not check
this — this gate is this skill's responsibility, not that one's.

Use `docs/apm-task-coverage.md` for the workspace-only bridge contract and
verification details.

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

- If the request is "change a workspace-only skill", edit `.apm/skills/**`.
  Keep its bridge entries as symlinks to that source; do not add it to the
  global catalog or root manifest.
- If the request is "change a personal skill", edit `catalog/skills/**`; use `skill-creator` for new or migrated managed skills.
- If the request is "make a skill repository-specific", edit
  `optional-skills/<id>/**` and keep the skill out of the root `apm.yml`.
- If the request is "optimize" or "customize" a cross-repository skill for this workspace, treat it as personal skill work and prefer `catalog/skills/<id>/`.
- If the request is to preserve a reusable implementation judgment from real work, such as "Valibot belongs in schemas", "Result conversion belongs at a boundary", or "DB access belongs in repositories", encode it as a concern -> owner candidates -> caller rule table in the relevant personal skill under `catalog/skills/<id>/`.
- If the user does not specify the target skill id for that reusable judgment, inspect named skills, catalog triggers, and existing examples first; update the closest existing personal skill instead of creating a new skill by default.
- If the request is "change shared guidance", edit `catalog/**`; use `prepare:catalog` before publish/install.
- If the request is "change dependency selection", edit or review `apm.yml` / `apm.lock.yaml`.
- If the request is about `mise upgrade <tool>`, `minimum_release_age`, latest eligible release selection, or why a non-APM tool version did not update, use the `mise` skill unless the pinned `apm` source, APM manifest, lockfile, or rollout task selection is the actual subject.
- If the request is to add an individual APM package, assign its lane before
  running `apm install`. Use `apm install -g <package-ref>` only for the
  `global-dependency` lane; use `apm install <package-ref>` from the target
  repository for the `repository-local` lane.
- If the request touches a `repository-local` manifest for any reason
  (new dependency, audit, cleanup), also check that `targets:` covers every
  agent runtime actually used in that repository before finishing. Fix a
  `codex`-only manifest that should also deploy to Claude Code by adding
  `claude`, then re-run `apm install` and verify `.claude/skills/<id>` exists
  for the affected skills.
- For an optional skill from this workspace, add only
  `jey3dayo/apm-workspace/optional-skills/<id>#main` to the consuming repository.
- For an optional skill embedded in an external bundle, keep the external
  package as the source of truth and select it in the consuming repository with
  `apm install <package-ref> --skill <id>`.
- If the request is to scan an arbitrary repository and create, update, or clean up its repo-local `apm.yml`, use `apm-repo-bootstrap`; keep this skill focused on global APM ownership and rollout decisions.
- If the request is to add an MCP server through APM, apply the same scope rule: use `apm install -g --mcp <name> ...` only for cross-repo foundation MCPs; use repo-local `apm install --mcp <name> ...` for project, framework, UI, database, browser, or app-runtime-specific MCPs.
- If MCP placement, server selection, credentials, transport, or startup behavior is the main question, coordinate with `mcp-tools`; keep this skill focused on APM ownership, source of truth, and rollout commands.
- If the APM workspace has no repo-local MCP distribution lane for a target repository, record the intended placement as guidance and keep the global manifest lightweight. Treat implementing repo-local MCP distribution as a separate workspace-mechanics task.
- If the request is "enable Headroom MCP", treat the Headroom MCP server as a global foundation managed through the `mcp:` section of `~/.apm/apm.yml`. Keep the Headroom binary itself managed by user-global `~/.config/mise`, and use the `headroom` skill for usage guidance; do not add Headroom to repo-local `mise.toml`.
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
- Do not manage the same skill in both `catalog/skills/**` and `optional-skills/<id>/**`.
- Do not manage the same skill in `.apm/skills/**` and any global or optional
  skill lane.
- Do not add the `optional-skills` collection root to the root `apm.yml`; install individual skill refs only in consuming repositories.
- Do not duplicate an external dependency into `catalog/skills/**` just because a local checkout exists. Keep one source of truth: upstream checkout, managed catalog, manual copy, or private overlay.
- Do not reintroduce many local `./packages/*` refs into `~/.apm/apm.yml`.
- Do not hand-edit deployed targets such as `~/.claude/`, `~/.codex/`, or `~/.agents/skills`.
- Do not assume a repository-local `apm.yml` with `targets: [codex]` is correct just because it predates this check. Verify against the repository's actual runtimes; a stale `codex`-only manifest silently starves Claude Code of every repo-local skill and MCP declared there.
- Headroom MCP server registration lives in the `mcp:` section of `~/.apm/apm.yml` like other global foundation MCPs. Do not persist Headroom proxy/wrap configuration through APM package manifests; treat proxy/wrap setup as a local machine setup step unless the user explicitly asks to manage that runtime state.
- Prefer `mise` tasks over ad hoc script entrypoints for normal operation.
- Before changing user-global `mise` tools, verify the resolved binary path and install tree. `mise latest` can lag or differ because of release-age policy, so compare with the upstream registry when exact latest-version behavior matters.
- Before committing `apm.lock.yaml` after `mise run upgrade`, separate the intended dependency update from unrelated unpinned dependency drift. Report unrelated drift instead of hiding it inside the target dependency change.
- When `apm.yml` includes a `gist.github.com/...#<sha>` dependency, verify the refreshed `apm.lock.yaml` record after `mise run upgrade` or any lock refresh. The workspace validator accepts APM's shortened `owner/<gist-id>` lock form as the same gist dependency, but the deployed target should still be checked before declaring the rollout complete.
- If an upstream skill path is wrong, correct it to the real upstream path and treat the corrected successful install as the main result.
- Treat known orphaned guidance or unrelated `manual-skills` deploy warnings as residual noise. Do not mention them in the final report when the command exits zero and the target skill source path, manifest or lock entry, and deployed target are correct.
- Report deploy warnings only when they directly affect the skill changed in this task, its manifest entry, its `manual-skills` provenance, or the deploy exit code.

## Fast Paths

1. Workspace-only skill changed:
   - edit `.apm/skills/**`
   - verify `.claude/skills/<id>` and `.agents/skills/<id>` are symlinks to
     the source
   - run `mise run check`

2. Personal skill changed:
   - edit `~/.apm/catalog/skills/**`
   - optionally run `mise run format:markdown:bold-headings`
   - run `mise run deploy`
   - verify `~/.agents/skills/<id>/` contains the deployed skill
   - use `mise run apply:skills:local` only when the user explicitly wants a fast local Codex skill refresh

3. Optional repository skill changed:
   - edit `optional-skills/<id>/**`
   - run a temporary `apm install jey3dayo/apm-workspace/optional-skills/<id>#main` from a fixture repository
   - do not run the global deployment as the delivery mechanism
   - verify the consuming repository's directly referenced skill is present after installation

4. Shared guidance changed:
   - edit `~/.apm/catalog/**`
   - run `mise run prepare:catalog`
   - review the diff, commit/push, then run `mise run install:catalog`

5. Upstream refresh:
   - run `mise run upgrade`
   - if the manifest contains `gist.github.com/...#<sha>`, verify the regenerated `apm.lock.yaml` kept the same `repo_url` spelling before deploy
   - review `apm.lock.yaml` before commit

6. Individual package or MCP added:
   - assign `workspace-only`, `repository-local`, `optional`,
     `global-dependency`, `private`, or `manual` before installing;
     `global-catalog` is not an install lane — create the skill via
     Fast Path 2 instead
   - for global dependencies, work in `~/.apm` and use `apm install -g <package-ref>` or `apm install -g --mcp <name> ...`
   - for repo-local dependencies, work in the target repository and use `apm install <package-ref>` or `apm install --mcp <name> ...`
   - for global changes, run `mise run check`, then `mise run deploy`; for repo-local changes, run that repository's defined APM or project checks
   - for repo-local changes, also confirm `targets:` includes every runtime the
     repository actually uses (add `claude` if it only lists `codex` but the
     repository uses Claude Code) before running `apm install`
   - verify the intended `apm.yml`, `apm.lock.yaml`, and deployed target changed, and no unrelated workspace dependencies drifted

7. Checked-out external dependency changed:
   - edit the external repository checkout that is the source of truth
   - run that repository's relevant checks
   - commit and push the external repository
   - in `~/.apm`, run `mise run upgrade`
   - verify `apm.lock.yaml` points the target dependency at the pushed commit
   - check whether `apm.lock.yaml` also changed unrelated unpinned dependencies
   - verify the deployed target such as `~/.agents/skills/<id>` contains the updated content
   - keep unrelated dirty files in `~/.apm` unstaged unless the user explicitly includes them

8. Manual skill promoted to workspace-owned:
   - move the skill from `manual-skills/.apm/skills/<id>/` to `catalog/skills/<id>/`
   - update `manual-skills/upstreams/**` to note the migration
   - run `mise run check`, then `mise run deploy`
   - verify the deployed target contains one copy of the skill
