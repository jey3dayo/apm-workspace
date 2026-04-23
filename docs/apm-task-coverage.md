# APM Task Coverage

## Operational Contract

- `~/.apm` is the day-to-day source of truth for APM catalog content, task wiring, and supporting docs.
- `~/.config` is bootstrap-only. It may be used to start or maintain the local APM environment, but it is not the operational source of truth.
- The only allowed operational exception under `~/.config` is `~/.config/scripts/replace-bold-headings.ts`, which exists as a formatter helper for heading normalization.
- `~/.config/nix/agent-skills-sources.nix` is retired and intentionally empty because external skill sources were removed.
- Codex is currently handled as a compile target via `apm compile --target codex --output ~/.codex/AGENTS.md`, not as a user-scope skill install target.

## Where Content Lives

| Content area           | Current source of truth                      | Notes                                    |
| ---------------------- | -------------------------------------------- | ---------------------------------------- |
| `skills`               | `~/.apm/catalog/skills/**`                   | Personal skill authoring source          |
| `agents`               | `~/.apm/catalog/agents/**`                   | Runtime sync target                      |
| top-level `commands/`  | `~/.apm/catalog/commands/**`                 | Runtime sync target                      |
| `rules`                | `~/.apm/catalog/rules/**`                    | Runtime sync target                      |
| `AGENTS.md`            | `~/.apm/catalog/AGENTS.md`                   | Managed catalog instructions             |
| formatter helper       | `~/.config/scripts/replace-bold-headings.ts` | Allowed bootstrap/helper exception       |
| retired skills sources | `~/.config/nix/agent-skills-sources.nix`     | Intentionally empty; do not repopulate   |
| Codex compiled output  | `~/.codex/AGENTS.md`                         | Produced by `apm compile --target codex` |

## Task Coverage

| task / command                | skills   | agents   | rules    | `AGENTS.md` | commands | Coverage summary                                                                                                            |
| ----------------------------- | -------- | -------- | -------- | ----------- | -------- | --------------------------------------------------------------------------------------------------------------------------- |
| `mise run apply`              | ○        | ○        | ○        | ○           | ○        | Installs and syncs the managed catalog from `~/.apm`                                                                        |
| `mise run refresh`            | ○        | ○        | ○        | ○           | ○        | Refreshes the checkout and dependency state without deploying                                                               |
| `mise run upgrade`            | ○        | ○        | ○        | ○           | ○        | Accepts newer upstream package content with `apm install -g --update`, then runs the local rollout                          |
| `mise run refresh:deploy`     | ○        | ○        | ○        | ○           | ○        | Refreshes first, then runs the full local rollout without forcing upstream refresh                                          |
| `mise run doctor`             | 状態確認 | 状態確認 | 状態確認 | 状態確認    | 状態確認 | Verifies target presence, overlap, and catalog health                                                                       |
| `mise run format`             | 間接     | 間接     | 間接     | 間接        | 間接     | Formats workspace Markdown / TOML / YAML and may use the documented heading helper                                          |
| `mise run check`              | ○        | ○        | ○        | ○           | ○        | Runs format check and validation for lightweight pre-deploy verification                                                    |
| `mise run verify`             | ○        | ○        | ○        | ○           | ○        | Runs `check` plus catalog smoke verification                                                                                |
| `mise run validate`           | ○        | ○        | ○        | ○           | ○        | Bundles `validate:workspace` and `validate:catalog`                                                                         |
| `mise run validate:workspace` | ○        | ○        | ○        | ○           | ○        | Respects `APM_WORKSPACE_DIR` for workspace validation                                                                       |
| `mise run deploy`             | ○        | ○        | ○        | ○           | ○        | Runs `check -> apply -> doctor` for local delivery                                                                          |
| `mise run prepare:catalog`    | ○        | ○        | ○        | ○           | ○        | Normalizes `catalog/` into the managed catalog package                                                                      |
| `mise run verify:catalog`     | ○        | ○        | ○        | ○           | ○        | Runs `prepare:catalog`, `validate:catalog`, and `doctor`                                                                    |
| `mise run install:catalog`    | ○        | ○        | ○        | ○           | ○        | Installs a pushed `catalog` ref                                                                                             |
| `mise run smoke:catalog`      | ○        | ○        | ○        | ○           | ○        | Performs a temporary-install smoke test                                                                                     |
| `mise run validate:catalog`   | ○        | ○        | ○        | ○           | ○        | Public task for drift checks                                                                                                |
| `mise run apply` for Codex    | n/a      | ○        | ○        | ○           | n/a      | Runs `apm compile --target codex --output ~/.codex/AGENTS.md` instead of treating `~/.codex/skills` as the rollout contract |

## Acceptance Criteria

This migration slice is complete only when all of the following are true:

1. `mise.toml` task entries do not call `~/.config/scripts/apm-workspace` or any equivalent bootstrap script path.
2. `README.md`, `llms.md`, and `docs/apm-task-coverage.md` do not reference the retired bootstrap docs subtree.
3. The only allowed operational exception under `~/.config` is `~/.config/scripts/replace-bold-headings.ts`, and this document names it explicitly.
4. `~/.config/nix/agent-skills-sources.nix` remains retired and intentionally empty, with no external skill source definitions restored there.
5. The task coverage above continues to map operational work to `~/.apm` as the source of truth.
6. Codex verification is based on compile success and `~/.codex/AGENTS.md`, not on the contents of `~/.codex/skills`.

## Notes

- This document is a current operating contract, not a migration log.
- Existing coverage remains useful only insofar as it explains how the `mise` tasks operate from `~/.apm`.
