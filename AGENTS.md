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

Use this table as the Source of Truth Table (SoTT) when deciding where to read or update durable workspace knowledge.

| 対象                                                              | 正本                                                          | 用途                                                                                           |
| ----------------------------------------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Personal skills / shared guidance                                 | `catalog/**`                                                  | skills、AGENTS.md、agents、commands、rules の authoring surface                                |
| Optional repository-scoped skills                                 | `optional-skills/<id>/**`                                     | 保存するがグローバル配布せず、利用リポジトリの `apm.yml` から個別参照するスキル                |
| External skills / global MCP                                      | `apm.yml` + `apm.lock.yaml`                                   | 外部依存の宣言と accepted resolved state。global MCP は `apm.yml` の `mcp:`                    |
| Host-local MCP                                                    | `mise.toml` + `scripts/apm-workspace.*`                       | OS / desktop app に依存する user-scope MCP の検出・同期                                        |
| SaaS 連携（コネクタ / プラグイン）                                | `docs/saas-connectors.md`                                     | claude.ai / ChatGPT アプリ側コネクタの接続状況と配置優先度（plugin > apm.yml > catalog skill） |
| Repo-local MCP                                                    | 各リポジトリの `apm.yml`（一覧は `ghq list -p`）              | リポジトリ固有の MCP セット                                                                    |
| パッケージ採用・撤去の意思決定                                    | `docs/package-decisions.md`                                   | なぜ入れた / 消したかのログ                                                                    |
| APM タスクの使い分け                                              | `docs/apm-task-coverage.md`                                   | rollout / verify などのタスク責務                                                              |
| Manual-lane skills                                                | `manual-skills/.apm/skills/**` + `manual-skills/upstreams/**` | managed lane で壊れる外部スキルの手動管理と provenance                                         |
| APM workspace-only skills                                         | `.apm/skills/**`                                              | この APM リポジトリだけで使うスキルの正本。root `apm.yml` には登録しない                       |
| APM workspace skill bridges                                       | `.claude/skills/**`, `.agents/skills/**`                      | 正本のスキルディレクトリを runtime ごとに参照する symlink。直接編集しない                      |
| Deployed targets（`~/.claude/`, `~/.codex/`, `~/.agents/skills`） | 生成物（SSoT ではない）                                       | 検証・配布面。直接編集しない                                                                   |

- `./catalog` is the tracked source of truth for managed content in this repository
  - `catalog/skills/**` for skills that belong in the global automatic rollout
  - `catalog/AGENTS.md`, `catalog/agents/**`, `catalog/commands/**`, and `catalog/rules/**` for shared guidance
- `./optional-skills` is the tracked source of truth for repository-scoped skills
  - `optional-skills/<id>/**` contains individually installable skills that are not part of the global rollout
  - the collection root is not an APM package and has no package manifest
  - do not add `optional-skills` to the root `apm.yml`; install `jey3dayo/apm-workspace/optional-skills/<id>#main` from the target repository
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
- if the skill should be available only to selected repositories, edit `./optional-skills/<id>/**` and reference that skill directly from the consuming repository
- if the change is to external dependency selection or accepted upstream state, edit or review `apm.yml` and `apm.lock.yaml`
- if an upstream skill does not install or deploy cleanly through the normal managed lane, copy it under `./manual-skills/.apm/skills/<id>/`, record provenance under `./manual-skills/upstreams/**`, and distribute it through the `jey3dayo/apm-workspace/manual-skills` package ref in root `apm.yml`
- exception: a skill that exists only to carry runtime assets for `catalog/commands/**` stays under `catalog/skills/<id>/` with provenance recorded in its own `SKILL.md`; do not move it onto the `manual-skills` lane, because deployed wiring may point at its catalog-deployed path
- if a skill should stay machine-local and untracked, place it under `./private-skills/.apm/skills/<id>/`; this gitignored lane is only used by the local Codex skill sync flow
- if both `catalog/skills/<id>/` and `private-skills/.apm/skills/<id>/` exist, the private copy overrides the tracked copy for `mise run apply:skills:local`
- if a skill is intentionally scoped only to this APM workspace, keep its source under `./.apm/skills/<id>/`; do not add it to root `apm.yml` or `apm.lock.yaml`
- if an external bundle contains a skill that should be opt-in, keep the upstream dependency external and install the selected skill in the target repository with `apm install <package-ref> --skill <id>`; do not copy it into `catalog/**` or `optional-skills/**`
- expose an APM workspace-only skill to both runtimes through `./.claude/skills/<id>` and `./.agents/skills/<id>` symlinks to the source directory
- keep `./.claude/skills/` and `./.agents/skills/` as real directories; symlink the child skill directories, not the roots or `SKILL.md` files
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
- Treat the current `apm` source as a pinned runtime dependency managed by `mise` (see `mise.toml`)
  - if both the workspace and global `mise` config define `apm`, keep them aligned to the same source to avoid command-resolution collisions

## MCP Placement

Placement policy (global vs repo-local vs on-demand, browser-tool selection, ownership gate) is owned by `catalog/AGENTS.md` の「MCP 配置方針」. Do not restate it here; this section covers only workspace mechanics.

- The global MCP set is defined by root `apm.yml` `mcp:`; keep it limited to cross-repo foundations per the catalog policy
- When moving MCP servers, edit the tracked APM source first and regenerate deployed targets
  - do not hand-edit deployed Codex MCP config such as `~/.codex/config.toml`
- Keep desktop-app-dependent MCP servers out of the portable global manifest
  - `mise bootstrap` runs the hidden host-local setup task and reconciles the Codex / Claude user-scope entries
  - treat `~/.codex/config.toml` and `~/.claude.json` as generated targets, not source files
- If the APM workspace has no repo-local MCP deployment lane for a target, keep the global manifest lightweight and treat repo-local MCP distribution as a separate workspace-mechanics task

## Task Selection

Choose the command based on intent:

- Before running a rollout command, classify the work as `stable rollout`, `upstream refresh`, or `local-only skill sync`
  - `stable rollout`: preserve the current manifest and lock, then use `mise run deploy`
  - `upstream refresh`: intentionally accept newer dependency content, then use `mise run upgrade` and review `apm.lock.yaml`
  - `local-only skill sync`: refresh local Codex skills only, then use `mise run apply:skills:local`

- `mise run upgrade`
  - Accept newer upstream package content with `apm install -g --update`
  - Avoid for routine rollout; reserve it for intentional upstream refresh of workspace dependencies
  - Use for weekly refreshes, dependency drift acceptance, and content-hash mismatch resolution
- `mise run refresh:deploy`
  - Preserve the current manifest and lock
  - Runs `refresh -> deploy`
  - Use cautiously; it is broader than the normal day-to-day rollout path
  - Use when you want a stable rollout without taking new upstream refs
- `mise run check`
  - Verification only
  - Runs formatting checks and validation only
  - Does not deploy
- `mise run verify`
  - Deep verification
  - Runs `check` plus catalog smoke verification
  - Use when you want stronger confidence before or apart from deployment
- `mise run audit:ci:smoke`
  - Temp-install the current manifest and lock into an isolated project, then run `apm audit --ci`
  - Use when you want APM's lockfile/deployed-file integrity checks without depending on the current user-scope targets
- `mise run deploy`
  - End-to-end local rollout
  - Runs checks, deploys the current manifest and lock, then inspects targets
  - Prefer when you want `mise run deploy` to finish the whole local workflow
- `mise run apply`
  - Deploy the current manifest and lock to user targets
  - Also sync Codex-targeted skills into `~/.agents/skills`
  - Use when deployment is needed without the bundled `check -> doctor` flow
- `mise run prepare:catalog`
  - Normalize tracked shared guidance under `catalog/`
- `mise run install:catalog`
  - Install the tracked catalog ref after commit and push
- `mise run doctor`
  - Inspect rollout state and target coverage after deployment or refresh

## Common Flows

### Upstream Refresh

Use when you want newer external content.

```bash
cd ~/.apm
mise install
mise run upgrade
```

Review `apm.lock.yaml` carefully before commit.

### Stable Rollout

Use when you want to deploy the current manifest and lock as-is.

```bash
cd ~/.apm
mise install
mise run deploy
```

### Shared Guidance Update

Use when changing `catalog/AGENTS.md`, `catalog/agents/**`, `catalog/commands/**`, or `catalog/rules/**`.

```bash
cd ~/.apm
mise run prepare:catalog
mise run install:catalog
mise run doctor
```

### Personal Skill Update

Use when changing `catalog/skills/**`.

```bash
cd ~/.apm
mise run format:markdown:bold-headings
mise run deploy
```

Then review and commit the skill changes.

### External Skill Add/Remove

Use when adding or removing an external skill dependency in `apm.yml` (global
via `apm install -g <package-ref>` or manual `dependencies.apm` edit).

```bash
cd ~/.apm
apm install -g <package-ref>   # or edit apm.yml directly for removal
mise run deploy
```

Every add/remove of an `apm.yml` external skill dependency MUST update
`docs/package-decisions.md` in the same change: record what was added/removed,
why, what was passed over, and what to re-check if reconsidering. Treat a
dependency diff without a corresponding `docs/package-decisions.md` diff as
incomplete work, not as optional follow-up.

## Editing Rules

- Do not edit `apm_modules/`
- Do not treat deployed targets such as `~/.claude/` or `~/.codex/` as source of truth
- For APM workspace-only skills, edit `.apm/skills/**`; do not edit the symlinked bridge entries under `.claude/skills/**` or `.agents/skills/**`
- Do not reintroduce local `./packages/*` refs into the global manifest
- Do not hand-edit runtime outputs when the tracked workspace can regenerate them
- Do not commit `private-skills/`; it is a gitignored local-only overlay for `mise run apply:skills:local`
- When changing the active `apm` source, update both tracked `mise` config locations that define `apm`
  - `~/.apm/mise.toml`
  - `~/.config/mise/config.windows.toml`
- When verifying Codex skill rollout, check `~/.agents/skills`
- Codex skill verification is complete only when the deployed `~/.agents/skills/<id>/SKILL.md` contains the expected content
- When verifying APM workspace-only skills, check that both bridge entries are symlinks and resolve to `.apm/skills/<id>/SKILL.md`
- if an external skill is still missing there after deployment, treat it as a temporary Codex-specific delivery gap and resolve it separately from the tracked workspace state
- if a skill repeatedly fails the normal upstream-managed lane because of packaging or rollout issues, move it onto the `manual-skills` package flow rather than patching deployed targets by hand
- When updating user-global tools through `mise`, verify the actual install tree and resolved binary path before declaring success
  - `mise latest` can be affected by release-age policy; compare with the upstream registry when the exact latest version matters

## Cache Integrity Recovery

If a deployed skill exists but its `SKILL.md` is clearly wrong, tiny, or a placeholder while the tracked source is complete, suspect a stale or corrupted `apm_modules/` cache before changing source files.

- Prefer `mise run deploy:fresh` when normal `mise run deploy` succeeds but deployed output still looks stale or corrupted
- Compare the tracked source, cache, and deployed target first
  - source example: `manual-skills/.apm/skills/<id>/SKILL.md`
  - cache example: `apm_modules/<owner>/<repo>/<virtual-path>/.apm/skills/<id>/SKILL.md`
  - Codex target example: `~/.agents/skills/<id>/SKILL.md`
- Do not fix this by editing `apm_modules/` contents or deployed targets in place
- `deploy:fresh` runs `apm prune --dry-run`, `apm prune`, rebuilds workspace-owned `catalog` and `manual-skills` cache entries from tracked sources, runs `deploy`, then `check`
- If a targeted manual repair is still needed, delete only the bad package cache directory after resolving and verifying the absolute path stays under `./apm_modules/`
- Recreate the cache with `mise run deploy:fresh` or the smallest equivalent dependency-refresh command
- If refresh times out, check whether the target cache was restored; stop only leftover refresh/update processes before retrying deploy
- Verify the repaired skill in deployed targets by checking the real `SKILL.md` size/content, then run `mise run check`

## Review Focus

When changing workspace mechanics, verify:

- task semantics still match documentation
- `upgrade` and `refresh:deploy` remain clearly differentiated
- `check` stays verification-only
- `deploy` remains the one-command local rollout entrypoint
- catalog normalization and registration flows remain reproducible
- lockfile changes are intentional and scoped
