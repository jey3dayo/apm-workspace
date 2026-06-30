# APM Task Coverage

## Operational Contract

- `~/.apm` is the day-to-day source of truth for APM catalog content, task wiring, and supporting docs.
- `~/.config` is reference-only for this workflow. It is not the operational source of truth.
- The only allowed operational exception under `~/.config` is `~/.config/scripts/replace-bold-headings.ts`, which exists as a formatter helper for heading normalization.
- Codex guidance is handled as a compile target via `apm compile --target codex --output ~/.codex/AGENTS.md`.
- Codex skills deploy separately to `~/.agents/skills`; skill rollout verification must inspect the deployed `SKILL.md` there.

## Source Of Truth

- `~/.apm/catalog/skills/**`: personal skills
- `~/.apm/catalog/{AGENTS.md,agents/**,commands/**,rules/**}`: shared guidance
- `~/.apm/apm.yml`, `~/.apm/apm.lock.yaml`: dependency selection and accepted upstream state
- `~/.apm/apm_modules/`: cache only

## Task Contract

| task / command                | skills   | agents   | rules    | `AGENTS.md` | commands | Coverage summary                                                                                                             |
| ----------------------------- | -------- | -------- | -------- | ----------- | -------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `mise run apply`              | ○        | ○        | ○        | ○           | ○        | Installs and syncs the managed catalog from `~/.apm`                                                                         |
| `mise run refresh`            | ○        | ○        | ○        | ○           | ○        | Refreshes the checkout and dependency state without deploying                                                                |
| `mise run upgrade`            | ○        | ○        | ○        | ○           | ○        | Accepts newer upstream package content with `apm install -g --update`, then runs the local rollout                           |
| `mise run refresh:deploy`     | ○        | ○        | ○        | ○           | ○        | Refreshes first, then runs the full local rollout without forcing upstream refresh                                           |
| `mise run doctor`             | 状態確認 | 状態確認 | 状態確認 | 状態確認    | 状態確認 | Verifies target presence, overlap, and catalog health                                                                        |
| `mise run format`             | 間接     | 間接     | 間接     | 間接        | 間接     | Formats workspace Markdown / TOML / YAML and may use the documented heading helper                                           |
| `mise run check`              | ○        | ○        | ○        | ○           | ○        | Runs format check and validation for lightweight pre-deploy verification                                                     |
| `mise run verify`             | ○        | ○        | ○        | ○           | ○        | Runs `check` plus catalog smoke verification                                                                                 |
| `mise run audit:ci:smoke`     | ○        | ○        | ○        | ○           | ○        | Temp-installs the manifest/lock into an isolated project and runs `apm audit --ci`                                           |
| `mise run validate`           | ○        | ○        | ○        | ○           | ○        | Bundles `validate:workspace` and `validate:catalog`                                                                          |
| `mise run validate:workspace` | ○        | ○        | ○        | ○           | ○        | Respects `APM_WORKSPACE_DIR` for workspace validation                                                                        |
| `mise run deploy`             | ○        | ○        | ○        | ○           | ○        | Runs `check -> apply -> doctor` for local delivery                                                                           |
| `mise run prepare:catalog`    | ○        | ○        | ○        | ○           | ○        | Normalizes `catalog/` into the managed catalog package                                                                       |
| `mise run install:catalog`    | ○        | ○        | ○        | ○           | ○        | Installs a pushed `catalog` ref                                                                                              |
| `mise run smoke:catalog`      | ○        | ○        | ○        | ○           | ○        | Performs a temporary-install smoke test                                                                                      |
| `mise run validate:catalog`   | ○        | ○        | ○        | ○           | ○        | Public task for drift checks                                                                                                 |
| `mise run apply` for Codex    | ○        | ○        | ○        | ○           | n/a      | Compiles `~/.codex/AGENTS.md` and syncs Codex-targeted skills into `~/.agents/skills`; `~/.codex/skills` is not the contract |
