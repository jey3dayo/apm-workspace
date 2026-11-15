# APM Task Coverage

## Operational Contract

- The authoring checkout owns task wiring and catalog sources; the root [`AGENTS.md`](../AGENTS.md) describes path ownership and the consumer state in `~/.apm`.
- `mise run native:sync` is the sole rollout task. [`native-distribution.md`](native-distribution.md) owns its stages, delivery targets, and rollback. `setup:mcp:host` also writes to HOME.
- The bold-heading formatter helper is vendored at `scripts/replace-bold-headings.ts`; it is not loaded from `~/.config`.

## Source Of Truth

Path-by-path ownership (catalog, optional-skills, workspace-only skills, lockfiles, caches) is owned by the Ownership table in the root `AGENTS.md`. This file covers only task responsibilities.

## Task Contract

| task / command                            | skills   | agents   | rules    | `AGENTS.md` | commands | Coverage summary                                                                                                                                                                 |
| ----------------------------------------- | -------- | -------- | -------- | ----------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mise bootstrap`                          | n/a      | n/a      | n/a      | n/a         | n/a      | Runs the hidden final hook that reconciles host-local MCP entries for Codex and Claude                                                                                           |
| `mise run doctor` (hidden)                | 状態確認 | 状態確認 | 状態確認 | 状態確認    | 状態確認 | Runs workspace and learning-intake diagnostics sequentially; the first failure stops the task                                                                                    |
| `mise run format`                         | 間接     | 間接     | 間接     | 間接        | 間接     | Formats workspace Markdown / TOML / YAML and may use the documented heading helper                                                                                               |
| `mise run upgrade:deps`                   | n/a      | n/a      | n/a      | n/a         | n/a      | Lists dependency holds, then regenerates `apm.lock.yaml` with `apm lock`; `-- --dry-run` previews without regenerating it                                                        |
| `mise run check`                          | ○        | ○        | ○        | ○           | ○        | Sole read-only gate: format checks, all linters, offline action-lock verification, both validation tasks directly, and the full Bats suite                                       |
| `mise run test:sh` (hidden)               | n/a      | n/a      | n/a      | n/a         | n/a      | Runs the full Bats script suite; also a focused subtask of `check`. `APM_TEST_PARALLEL=0` forces serial execution (CI sets this)                                                 |
| `mise run format:check` (hidden)          | 間接     | 間接     | 間接     | 間接        | 間接     | Checks workspace Markdown / TOML / YAML formatting without rewriting files; part of `check`                                                                                      |
| `mise run lint:yaml`                      | n/a      | n/a      | n/a      | n/a         | n/a      | Lints YAML files in the workspace                                                                                                                                                |
| `mise run lint:actions`                   | n/a      | n/a      | n/a      | n/a         | n/a      | Lints GitHub Actions workflows with jactionlint                                                                                                                                  |
| `mise run actions-lock:verify` (hidden)   | n/a      | n/a      | n/a      | n/a         | n/a      | Offline check that every `uses:` has an `.github/workflows/actions.lock` entry and the lockfile parses; part of `check` and the targeted pre-commit hook. Not a provenance check |
| `mise run actions-lock:upstream` (hidden) | n/a      | n/a      | n/a      | n/a         | n/a      | CI-only `gh-actions-lock --verify`: checks provenance online. Needs network and `GH_TOKEN`; the job's `github.token` suffices while every locked action is public                |
| `mise run validate:workspace` (hidden)    | ○        | ○        | ○        | ○           | ○        | Ensures the authoring checkout and scaffold exist and checks SHA pins against `apm.lock.yaml`; no APM compile or cache is needed                                                 |
| `mise run validate:catalog` (hidden)      | ○        | ○        | ○        | ○           | ○        | Checks the managed catalog package tree for normalization and required assets; called directly by `check`                                                                        |
| `mise run agmsg:state:restore` (hidden)   | n/a      | n/a      | n/a      | n/a         | n/a      | Relinks the agmsg roster into the deployed skill directory during recovery                                                                                                       |
| `mise run native:sync`                    | ○        | ○        | ○        | ○           | ○        | Checks the pushed source, then runs backup, rehearsal, migration, OpenCode setup and diagnostics; see `docs/native-distribution.md`                                              |

## Task Visibility

The workspace-local public `mise tasks` list is `check`, `format`, `native:sync`, and `upgrade:deps`. Hidden tasks remain directly runnable by name:

- check parts: `format:check`, `test:sh`, `lint:yaml`, `lint:actions`, `actions-lock:verify`, `lint:frontmatter`, `lint:catalog-leaks`, `validate:workspace`, `validate:catalog`; format subtasks: `format:markdown`, `format:markdown:check`, `format:markdown:bold-headings`, `format:markdown:bold-headings:check`, `format:toml`, `format:toml:check`, `format:yaml`, `format:yaml:check`
- diagnostic: `doctor` runs workspace and learning-intake checks in sequence.
- native operations: `native:sync` is the only native task; its plan, backup, rehearsal, migration, OpenCode, and diagnostic stages are internal.
- recovery-only: `agmsg:state:save`, `agmsg:state:restore` relink a roster unlinked outside the migration path.
- bootstrap hooks: `bootstrap`, `setup:mcp:host`
