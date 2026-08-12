# APM Task Coverage

## Operational Contract

- `~/.apm` is the day-to-day source of truth for APM catalog content, task wiring, and supporting docs.
- `~/.config` is reference-only for this workflow. It is not the operational source of truth.
- The only allowed operational exception under `~/.config` is `~/.config/scripts/replace-bold-headings.ts`, which exists as a formatter helper for heading normalization.
- Codex guidance is handled as a compile target via `apm compile --target codex --output ~/.codex/AGENTS.md`.
- Codex skills deploy separately to `~/.agents/skills`; skill rollout verification must inspect the deployed `SKILL.md` there.

## Source Of Truth

Path-by-path ownership (catalog, optional-skills, workspace-only skills, lockfiles, caches) is owned by the Source of Truth Table in the root `AGENTS.md`. This file covers only task responsibilities.

## Task Contract

| task / command                        | skills   | agents   | rules    | `AGENTS.md` | commands | Coverage summary                                                                                                                   |
| ------------------------------------- | -------- | -------- | -------- | ----------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `mise run apply`                      | ○        | ○        | ○        | ○           | ○        | Installs and syncs the managed catalog from `~/.apm`                                                                               |
| `mise bootstrap`                      | n/a      | n/a      | n/a      | n/a         | n/a      | Runs the hidden final hook that reconciles host-local MCP entries for Codex and Claude                                             |
| `mise run refresh`                    | ○        | ○        | ○        | ○           | ○        | Refreshes the checkout and dependency state without deploying                                                                      |
| `mise run upgrade`                    | ○        | ○        | ○        | ○           | ○        | Accepts newer upstream package content with `apm update -g`, then runs the local rollout                                           |
| `mise run refresh:deploy`             | ○        | ○        | ○        | ○           | ○        | Refreshes first, then runs the full local rollout without forcing upstream refresh                                                 |
| `mise run doctor`                     | 状態確認 | 状態確認 | 状態確認 | 状態確認    | 状態確認 | Verifies target presence, overlap, and catalog health                                                                              |
| `mise run format`                     | 間接     | 間接     | 間接     | 間接        | 間接     | Formats workspace Markdown / TOML / YAML and may use the documented heading helper                                                 |
| `mise run check`                      | ○        | ○        | ○        | ○           | ○        | Runs format check and validation for lightweight pre-deploy verification                                                           |
| `mise run verify`                     | ○        | ○        | ○        | ○           | ○        | Runs `check`, both workspace-script test suites, then catalog smoke verification                                                   |
| `mise run test`                       | n/a      | n/a      | n/a      | n/a         | n/a      | Runs the Pester and bats suites for `scripts/apm-workspace.*` serially; both are also wired as pre-push jobs                       |
| `mise run test:ps`                    | n/a      | n/a      | n/a      | n/a         | n/a      | Runs the Pester behavioral suite for `apm-workspace.ps1`; needs a host-installed `pwsh` with Pester                                |
| `mise run test:sh`                    | n/a      | n/a      | n/a      | n/a         | n/a      | Runs bats unit tests for `scripts/apm-workspace.sh`                                                                                |
| `mise run format:check`               | 間接     | 間接     | 間接     | 間接        | 間接     | Checks workspace Markdown / TOML / YAML formatting without rewriting files; this is what CI and the pre-push hook run              |
| `mise run lint:yaml`                  | n/a      | n/a      | n/a      | n/a         | n/a      | Lints YAML files in the workspace                                                                                                  |
| `mise run audit:ci:smoke`             | ○        | ○        | ○        | ○           | ○        | Temp-installs the manifest/lock into an isolated project and runs `apm audit --ci`                                                 |
| `mise run validate`                   | ○        | ○        | ○        | ○           | ○        | Bundles `validate:workspace` and `validate:catalog`                                                                                |
| `mise run validate:workspace`         | ○        | ○        | ○        | ○           | ○        | Respects `APM_WORKSPACE_DIR` for workspace validation                                                                              |
| `mise run deploy`                     | ○        | ○        | ○        | ○           | ○        | Runs `check -> apply -> doctor` for local delivery                                                                                 |
| `mise run repair:local-package-cache` | n/a      | n/a      | n/a      | n/a         | n/a      | Rebuilds workspace-owned APM package cache entries from tracked sources; run this before `deploy` when deployed output looks stale |
| `mise run deploy:fresh`               | ○        | ○        | ○        | ○           | ○        | Recovery path for stale deployed output: `apm prune`, `repair:local-package-cache`, then `deploy` (which already runs `check`)     |
| `mise run apply:skills:local`         | ○        | n/a      | n/a      | n/a         | n/a      | Quick-applies managed catalog skills into the local Codex target only, without the full `apply` rollout                            |
| `mise run prepare:catalog`            | ○        | ○        | ○        | ○           | ○        | Normalizes `catalog/` into the managed catalog package                                                                             |
| `mise run install:catalog`            | ○        | ○        | ○        | ○           | ○        | Installs a pushed `catalog` ref                                                                                                    |
| `mise run smoke:catalog`              | ○        | ○        | ○        | ○           | ○        | Performs a temporary-install smoke test                                                                                            |
| `mise run validate:catalog`           | ○        | ○        | ○        | ○           | ○        | Public task for drift checks                                                                                                       |
| `mise run apply` for Codex            | ○        | ○        | ○        | ○           | n/a      | Compiles `~/.codex/AGENTS.md` and syncs Codex-targeted skills into `~/.agents/skills`; deployed skill tree is authoritative.       |
| `mise run agmsg:state:restore`        | n/a      | n/a      | n/a      | n/a         | n/a      | Relinks the agmsg roster into the deployed skill directory                                                                         |

## Task Visibility

`mise tasks` lists only the entry points. Parts that exist to be composed by an aggregate, or to be reached only during recovery, carry `hide = true` and stay directly runnable by name:

- check parts of `check` / `format:check`: `format:markdown:check`, `format:markdown:bold-headings:check`, `format:toml`, `format:toml:check`, `format:yaml`, `format:yaml:check`, `lint:yaml`, `validate:workspace`, `validate:catalog`, `smoke:catalog`
- recovery-only: `repair:local-package-cache`, `deploy:fresh`, `refresh:deploy`, `agmsg:state:restore`
- bootstrap hooks: `bootstrap`, `setup:mcp:host`, `agmsg:state:save`

## Script-Only Commands

`scripts/apm-workspace.sh` and `scripts/apm-workspace.ps1` dispatch two commands that have no `mise`
task wrapper and no documentation elsewhere. Invoke them directly:

| Command          | Invocation                                                      | What it does                                                                                                                              |
| ---------------- | --------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `pin-external`   | `bash ./scripts/apm-workspace.sh pin-external`                  | Pins external manifest refs to lockfile commits                                                                                           |
| `bundle-catalog` | `bash ./scripts/apm-workspace.sh bundle-catalog [skill-id ...]` | Builds `~/.apm/.catalog-build/catalog` as the catalog package artifact. Also called internally by `prepare:catalog` and `install:catalog` |
