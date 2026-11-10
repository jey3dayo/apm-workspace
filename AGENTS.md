# APM Workspace Guide

The authoring checkout (`~/src/github.com/jey3dayo/apm-workspace`; "the checkout"
below) is the operational source of truth. Keep authoring inputs, generated
targets, and caches separate; never infer ownership from whichever copy is
currently deployed. On the native HOME, `~/.apm` is not the checkout: it holds
only the APM consumer state (rendered manifest, lock, `apm_modules`, migrate
records), so never edit it.

## Ownership

| Asset                                      | Source of truth                                               | Rule                                                                                                                                                                                                                                                                                                                |
| ------------------------------------------ | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Global personal skills and shared guidance | `catalog/**`                                                  | Edit here; personal skills live in `catalog/.apm/skills/<id>/`, agents in `catalog/.apm/agents/<name>.agent.md`, and shared guidance includes the guide in `catalog/.apm/instructions/ai-collaboration.instructions.md`, commands, and rules. `catalog/.apm/` holds only `skills/`, `agents/` and that instruction. |
| Repository-scoped skills                   | `optional-skills/<id>/**`                                     | The consuming repository installs its direct ref; never add the collection to root `apm.yml`.                                                                                                                                                                                                                       |
| Workspace-only skills                      | `.apm/skills/**`                                              | Maintain child symlinks in `.claude/skills/` and `.agents/skills/`; edit neither bridge.                                                                                                                                                                                                                            |
| Private local overrides                    | `private-skills/.apm/skills/**`                               | Gitignored here, tracked in the private repo. Native distribution does not deliver it (`docs/native-distribution.md`); whether it overrides an identically named catalog skill is unconfirmed.                                                                                                                      |
| Managed external skills and global MCP     | `apm.yml` + `apm.lock.yaml`                                   | The manifest declares dependencies; the lock records the accepted resolution.                                                                                                                                                                                                                                       |
| Manual upstream copies                     | `manual-skills/.apm/skills/**` + `manual-skills/upstreams/**` | Use only when the normal managed lane cannot package or deploy the upstream skill.                                                                                                                                                                                                                                  |
| Host-local MCP                             | `mise.toml` + `scripts/apm-workspace.*`                       | Reconcile through `mise bootstrap`; do not edit runtime config.                                                                                                                                                                                                                                                     |
| Cursor user-scope MCP                      | `~/.cursor/mcp.json`                                          | Hand-maintained and outside global APM.                                                                                                                                                                                                                                                                             |
| Decision records and task ownership        | `docs/package-decisions.md`, `docs/apm-task-coverage.md`      | Record external dependency adds/removals in the former.                                                                                                                                                                                                                                                             |

`apm_modules/`, `~/.claude/`, `~/.codex/`, and `~/.agents/skills/` are cache or
delivery surfaces. Regenerate them instead of editing them. `apm compile -g`
writes the guide to `~/.codex/AGENTS.md` and `~/.cursor/AGENTS.md`, Claude reads
it as `~/.claude/rules/ai-collaboration.md`, and Codex skills deploy to
`~/.agents/skills`. Legacy root copies from the old path are covered in the known issues of `docs/native-distribution.md`.

## Task Tracking

`todo.txt` is the source of truth for unfinished work and is managed with
`TODO_FILE=todo.txt tuxedo`. Completed internal tasks are archived in the
sibling `done.txt`. Decision history (why a package or lane was adopted,
removed, or deferred) belongs in `docs/package-decisions.md`; code-change
history lives in git log. `plans/` is gitignored and holds local plan output;
only the `plans/*.md` files tracked before that rule remain as history
documents. Do not
introduce `CHANGELOG.md` and do not recreate `TODO.md` for active work — those roles are already covered by
the three surfaces above.

For the detailed lane inventory, use [`docs/skill-inventory.md`](docs/skill-inventory.md).
Choose a lane by scope: global personal work goes to `catalog`, selected-repo
work to `optional-skills`, machine-local work to `private-skills`, and
workspace-only work to `.apm/skills`. Keep opt-in skills in their upstream
bundle and install only the required sub-skill from the consuming repository.

## Rollout and Verification

The real HOME is native (`~/.apm/apm.yml` starts with
`# Rendered by scripts/native.sh`). The legacy writer (`deploy`, `apply`,
`upgrade`, `refresh` and their helper tasks) was removed on 2026-11-10; its last
version is commit `0bcce09`. Roll out a pushed commit with section B of
`docs/native-distribution.md` (`native:plan`, `native:backup`,
`native:rehearse --migrate`, `native:migrate`); `native:migrate-rollback`
undoes it.

| Intent            | Command                                              | Constraint                                                                     |
| ----------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------ |
| Rollout           | `docs/native-distribution.md` section B (`native:*`) | Rehearse on a backup copy first; only `native:migrate` and its undo write HOME |
| Validation only   | `mise run check`                                     | Does not roll out.                                                             |
| Deep verification | `mise run verify`                                    | Runs checks, both script suites, and catalog smoke verification.               |
| Inspection        | `mise run doctor`                                    | Read-only.                                                                     |

Shipping here has no PR: commit directly on `main`, run `apm-deploy-verify`
(it runs format and check, then compares the deployed files with the
checkout), then push `main` and watch the pushed CI run. `ship` reads this as
the repository's end point. After the push, roll the pushed commit out with
section B of `docs/native-distribution.md`.

`mise.toml` manages required tools except `pwsh` plus Pester, which `test:ps`
(and therefore `test`/`verify`) requires. The bold-heading formatter helper is
vendored at `scripts/replace-bold-headings.ts`; a missing helper is a broken
checkout, not an optional dependency.

GNU parallel and a locking implementation (`flock` or `shlock`) are, by
contrast, a real optional dependency for `test:sh`: bats' within-file
parallelization requires both together, and a host missing either falls back
to a serial `bats` run rather than failing. Parallel width is tunable via
`BATS_JOBS` (default: half the detected cores, minimum `4`).

Within-suite parallelization width is otherwise environment-dependent, not a
fixed default: CI runners and local macOS hosts differ by an order of
magnitude in per-process cost (process spawn overhead, and lock polling when
neither `flock` nor `shlock` is available), so the same fan-out that helps on
a developer machine loses to overhead on a CI runner's limited core count.
`APM_TEST_PARALLEL=0` forces both `test:sh` and `test:ps` to their
serial/single-process path regardless of the parallel/flock/shlock guard or
`BATS_JOBS`; CI sets it, leaving local runs at the parallel default (unset or
`1`).

The `test:ps` lane is best-effort, not a verified Windows guarantee: CI and
local runs execute `pwsh` on macOS/Linux, so a green Pester run only confirms
the script's PowerShell syntax and logic run under those hosts' `pwsh`. It
does not exercise Windows-specific failure modes such as path separators,
`$USERPROFILE`, symlink-creation privileges, or CRLF handling, none of which
have been verified on a Windows host. `test:ps` is not a pre-push gate for
this reason; `test:sh` is the only workspace-script suite pre-push runs, and
`test:ps` remains reachable through CI and `mise run test`/`verify`.

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
  `catalog/.apm/skills/<id>/` with provenance in their `SKILL.md`, even if they are
  otherwise unusual.
- If a managed upstream skill repeatedly fails packaging or rollout, move it to
  the manual lane rather than patching cache or runtime output.
- When changing the active `apm` source, update both the checkout's `mise.toml`
  and `~/.config/mise/config.workstation.toml`.
- Follow the guide in `catalog/.apm/instructions/ai-collaboration.instructions.md` for MCP placement. Root `apm.yml` contains only
  cross-repository global MCP; use the tracked source and regenerate, never
  edit `~/.codex/config.toml`. Desktop MCP setup belongs to bootstrap.
- Runtime assets that a skill places at launch have no `targets:` distribution
  route. For `agmsg-review.config.toml` (spawn puts it in the per-run worker
  home, a hand-started pane in `~/.codex`), use the placement contract in
  `catalog/.apm/skills/agmsg-delegation/references/codex-sandbox.md`.

## agmsg State

`~/.agents/skills/agmsg/db` and `teams` must remain symlinks to
`${XDG_STATE_HOME:-~/.local/state}/agmsg/`; replacing the skill directory would
otherwise erase the roster and history. `native:rehearse --migrate` and
`native:migrate` save and restore the links through `scripts/agmsg-state.sh`,
and `native:migrate-rollback` relinks them. A bare `apm install -g` does not
run that save/restore, so the links are gone when it finishes; the store under
`${XDG_STATE_HOME:-~/.local/state}/agmsg/` survives. For a roster left
unlinked, diagnose with `mise run doctor`, then run
`mise run agmsg:state:restore` (`agmsg:state:save` is the counterpart). The
plain-path rule in
`catalog/.apm/skills/agmsg-delegation/references/roster-recovery.md` still
applies. Remove this workaround only after upstream `AGMSG_HOME` supports both
locations.

## Cache Recovery

When a deployed `SKILL.md` is tiny, placeholder, or differs from a complete
tracked source, compare source, cache, and target first, then repeat
section B of `docs/native-distribution.md` (B4 sets the APM cache aside).

`apm prune` can miss orphaned owner directories and removed nested skills.
Compare `apm_modules/` with both manifest and lock; delete only an unreferenced
path after proving its resolved absolute path remains under `apm_modules/`.
The orphan list printed from a temporary deployment compile is not evidence
about the real workspace. Verify repaired deployed content, then run `mise run
check`.

`apm doctor`'s orphan-package warning is an expected legacy dependency
artifact; do not report it as a user-facing problem.

## Review Focus

For workspace-mechanics changes, verify command semantics, verification-only
`check`, the native rollout order in `docs/native-distribution.md`, and
intentional lockfile changes.
