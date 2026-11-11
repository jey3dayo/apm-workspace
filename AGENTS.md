# APM Workspace Guide

The authoring checkout (`~/src/github.com/jey3dayo/apm-workspace`; "the checkout"
below) is the operational source of truth. Keep authoring inputs, generated
targets, and caches separate; never infer ownership from whichever copy is
currently deployed. On the native HOME, `~/.apm` is not the checkout: it holds
only the APM consumer state (rendered manifest, lock, `apm_modules`, migrate
records), so never edit it; the one exception is placing private skills under
`~/.apm/skills/` (see the Private local overrides row).

## Ownership

| Asset                                      | Source of truth                                               | Rule                                                                                                                                                                                                                                                                                                                |
| ------------------------------------------ | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Global personal skills and shared guidance | `catalog/**`                                                  | Edit here; personal skills live in `catalog/.apm/skills/<id>/`, agents in `catalog/.apm/agents/<name>.agent.md`, and shared guidance includes the guide in `catalog/.apm/instructions/ai-collaboration.instructions.md`, commands, and rules. `catalog/.apm/` holds only `skills/`, `agents/` and that instruction. |
| Repository-scoped skills                   | `optional-skills/<id>/**`                                     | The consuming repository installs its direct ref; never add the collection to root `apm.yml`.                                                                                                                                                                                                                       |
| Workspace-only skills                      | `.apm/skills/**`                                              | Maintain child symlinks in `.claude/skills/` and `.agents/skills/`; edit neither bridge.                                                                                                                                                                                                                            |
| Private local overrides                    | `private-skills/.apm/skills/**`                               | Gitignored here, tracked in the private repo. Native distribution does not deliver it: place it under the consumer `~/.apm/skills/` (the one allowed edit of `~/.apm`; `docs/native-distribution.md` "native と手動の境界"). Whether it overrides an identically named catalog skill is unconfirmed.                |
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
version is commit `0bcce09`. Roll out a merged commit with `mise run native:sync` (use the `-- --https`
option when SSH is unavailable). Section B of
`docs/native-distribution.md` also documents the manual steps and rollback.

| Intent          | Command                | Constraint                                                                                                                           |
| --------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Rollout         | `mise run native:sync` | Runs backup and rehearsal before writing HOME; see `docs/native-distribution.md` section B for HTTPS and rollback                    |
| Validation only | `mise run check`       | Runs formatting checks, all linters, offline action-lock verification, manifest and catalog validation, and Bats; does not roll out. |
| Inspection      | `mise run doctor`      | Hidden read-only diagnostics for workspace state and learning-intake reports.                                                        |

Shipping here goes through a PR: work on a feature branch, run
`apm-deploy-verify` with the changed skill names (pass them both times: once
the work is committed the tree is clean, so it cannot infer them from
`git status`) before the push for format and check (its distribution-match step
applies only after the merge and B6, so it reports that step as not run before
then), push the branch and open the PR (`ship` runs this sequence), and watch
its CI run. Merge only when asked. After the PR is merged, update the checkout's `main`, roll
that commit out with `mise run native:sync`, then run `apm-deploy-verify` again
for the distribution match.

`mise.toml` manages the required tools. The bold-heading formatter helper is
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
`APM_TEST_PARALLEL=0` forces `test:sh` to its serial path regardless of the
parallel/flock/shlock guard or `BATS_JOBS`; CI sets it, leaving local runs at
the parallel default (unset or `1`).

The PowerShell lane (the `.ps1` scripts, their Pester suites and `test:ps`) was
removed on 2026-11-10; see git history. Windows is out of scope.

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
  cross-repository global MCP; record it in the tracked source, never edit
  `~/.codex/config.toml`. Native distribution does not deliver
  `dependencies.mcp` (see the boundary table in `docs/native-distribution.md`);
  report such a change as recorded, not delivered. Host-local MCP goes through
  `mise run setup:mcp:host`, and desktop MCP setup belongs to bootstrap.
- Runtime assets that a skill places at launch have no `targets:` distribution
  route. For `agmsg-review.config.toml` (spawn puts it in the per-run worker
  home, a hand-started pane in `~/.codex`), use the placement contract in
  `catalog/.apm/skills/agmsg-delegation/references/codex-sandbox.md`.
- Do not hard-code versioned model IDs in role or tier guidance in skills,
  agent definitions, instructions, or docs. Write in terms of role and tier;
  concrete policy IDs belong in
  `catalog/.apm/skills/orchestrator-worker/references/models.md`. Runtime helper
  allowlists and their focused tests are required mirrors and must change with
  that table. Short aliases in config values (e.g. `model: sonnet`) are allowed.

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
tracked source, compare source, cache, and target first, then run
`mise run native:sync` (it sets the APM cache aside; see section B of
`docs/native-distribution.md`).

`apm prune` can miss orphaned owner directories and removed nested skills.
Compare `apm_modules/` with both manifest and lock; delete only an unreferenced
path after proving its resolved absolute path remains under `apm_modules/`.
The orphan list printed from a temporary deployment compile is not evidence
about the real workspace. Verify repaired deployed content, then run `mise run
check`.

`apm deps list -g` (apm 0.35.0) calls packages orphaned that `apm prune
--dry-run` keeps as required package content. `mise run doctor` runs that
preview in `~/.apm`, the tree `deps list -g` reads, shows the packages it keeps
as `retained`, and does not suggest a prune for them. A package the preview did
not report as retained stays listed as orphaned, so read `apm prune --dry-run`
before acting. When `~/.apm/apm.yml` is missing, the preview fails, or an orphan
count does not match its list, doctor prints the list unchanged with a warning.

## Review Focus

For workspace-mechanics changes, verify command semantics, verification-only
`check`, the native rollout order in `docs/native-distribution.md`, and
intentional lockfile changes.
