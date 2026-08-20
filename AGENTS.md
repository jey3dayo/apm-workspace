# APM Workspace Guide

`~/.apm` is the operational source of truth. Keep authoring inputs, generated
targets, and caches separate; never infer ownership from whichever copy is
currently deployed.

## Ownership

| Asset                                      | Source of truth                                               | Rule                                                                                          |
| ------------------------------------------ | ------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Global personal skills and shared guidance | `catalog/**`                                                  | Edit here; shared guidance includes `AGENTS.md`, agents, commands, and rules.                 |
| Repository-scoped skills                   | `optional-skills/<id>/**`                                     | The consuming repository installs its direct ref; never add the collection to root `apm.yml`. |
| Workspace-only skills                      | `.apm/skills/**`                                              | Maintain child symlinks in `.claude/skills/` and `.agents/skills/`; edit neither bridge.      |
| Private local overrides                    | `private-skills/.apm/skills/**`                               | Gitignored; local Codex sync only, and it overrides an identically named catalog skill.       |
| Managed external skills and global MCP     | `apm.yml` + `apm.lock.yaml`                                   | The manifest declares dependencies; the lock records the accepted resolution.                 |
| Manual upstream copies                     | `manual-skills/.apm/skills/**` + `manual-skills/upstreams/**` | Use only when the normal managed lane cannot package or deploy the upstream skill.            |
| Host-local MCP                             | `mise.toml` + `scripts/apm-workspace.*`                       | Reconcile through `mise bootstrap`; do not edit runtime config.                               |
| Cursor user-scope MCP                      | `~/.cursor/mcp.json`                                          | Hand-maintained and outside global APM.                                                       |
| Decision records and task ownership        | `docs/package-decisions.md`, `docs/apm-task-coverage.md`      | Record external dependency adds/removals in the former.                                       |

`apm_modules/`, `~/.claude/`, `~/.codex/`, and `~/.agents/skills/` are cache or
delivery surfaces. Regenerate them instead of editing them. Codex compiles
guidance to `~/.codex/AGENTS.md` and deploys skills to `~/.agents/skills`.

For the detailed lane inventory, use [`docs/skill-inventory.md`](docs/skill-inventory.md).
Choose a lane by scope: global personal work goes to `catalog`, selected-repo
work to `optional-skills`, machine-local work to `private-skills`, and
workspace-only work to `.apm/skills`. Keep opt-in skills in their upstream
bundle and install only the required sub-skill from the consuming repository.

## Rollout and Verification

Classify work before running a rollout:

| Intent                 | Command                       | Constraint                                                       |
| ---------------------- | ----------------------------- | ---------------------------------------------------------------- |
| Stable rollout         | `mise run deploy`             | Preserves manifest and lock.                                     |
| Upstream refresh       | `mise run upgrade`            | Intentionally accepts newer content; review `apm.lock.yaml`.     |
| Local Codex skill sync | `mise run apply:skills:local` | Does not replace a normal rollout.                               |
| Validation only        | `mise run check`              | Does not deploy.                                                 |
| Deep verification      | `mise run verify`             | Runs checks, both script suites, and catalog smoke verification. |

`mise run deploy` is the normal end-to-end entry point (`check`, `apply`, and
`doctor`). `mise run refresh:deploy` is broader and should not be substituted
for normal rollout. Use `mise run prepare:catalog`, then `mise run
install:catalog`, and `mise run doctor` for pushed shared-guidance changes.

`mise.toml` manages required tools except `pwsh` plus Pester, which `test:ps`
(and therefore `test`/`verify`) requires. The bold-heading formatter helper is
vendored at `scripts/replace-bold-headings.ts`; a missing helper is a broken
checkout, not an optional dependency.

Before external sharing, run the repository's full gate. For smaller edits run
touched-file formatting and the relevant focused check; always run `git diff
--check` before committing. Confirm a Codex skill rollout from the deployed
`~/.agents/skills/<id>/SKILL.md`, and confirm workspace-only bridges are
symlinks resolving to `.apm/skills/<id>/SKILL.md`.

## Editing Rules

- Do not hand-edit deployed targets or `apm_modules/`; regenerate from tracked
  workspace state.
- Do not add local `./packages/*` refs to the global manifest.
- Keep skills carrying runtime assets for `catalog/commands/**` in
  `catalog/skills/<id>/` with provenance in their `SKILL.md`, even if they are
  otherwise unusual.
- If a managed upstream skill repeatedly fails packaging or rollout, move it to
  the manual lane rather than patching cache or runtime output.
- When changing the active `apm` source, update both `~/.apm/mise.toml` and
  `~/.config/mise/config.windows.toml`.
- Follow `catalog/AGENTS.md` for MCP placement. Root `apm.yml` contains only
  cross-repository global MCP; use the tracked source and regenerate, never
  edit `~/.codex/config.toml`. Desktop MCP setup belongs to bootstrap.
- Runtime assets that a skill places at launch have no `targets:` distribution
  route. For `~/.codex/agmsg-review.config.toml`, use the placement contract in
  `catalog/skills/agmsg-delegation/SKILL.md`.

## agmsg State

`~/.agents/skills/agmsg/db` and `teams` must remain symlinks to
`${XDG_STATE_HOME:-~/.local/state}/agmsg/`; `apm apply` would otherwise erase
the roster and history. `mise run apply` (both `apm-workspace.sh` and
`apm-workspace.ps1`) saves and restores them automatically on every exit
path, success or failure — the `agmsg:state:save`/`agmsg:state:restore` mise
tasks are recovery adapters only, for a roster left unlinked by some other
process. Run `mise run agmsg:state:restore` by hand to recover from that.
Remove this workaround only after upstream `AGMSG_HOME` supports both
locations.

## Cache Recovery

When a deployed `SKILL.md` is tiny, placeholder, or differs from a complete
tracked source, compare source, cache, and target first. Prefer `mise run
deploy:fresh`; it prunes, repairs workspace package caches, then deploys.

`apm prune` can miss orphaned owner directories and removed nested skills.
Compare `apm_modules/` with both manifest and lock; delete only an unreferenced
path after proving its resolved absolute path remains under `apm_modules/`.
The orphan list printed from a temporary deployment compile is not evidence
about the real workspace. Verify repaired deployed content, then run `mise run
check`.

## Review Focus

For workspace-mechanics changes, verify command semantics, the separation of
`upgrade` from `refresh:deploy`, verification-only `check`, reproducible catalog
registration, and intentional lockfile changes.
