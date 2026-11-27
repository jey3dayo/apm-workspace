# APM Workspace Guide

The authoring checkout (`~/src/github.com/jey3dayo/apm-workspace`; "the checkout"
below) is the operational source of truth. Keep authoring inputs, generated
targets, and caches separate; never infer ownership from whichever copy is
currently deployed. On the native HOME, `~/.apm` is not the checkout: it holds
only the APM consumer state, so never edit it; the one exception is placing
private skills under `~/.apm/skills/` (see the Private local overrides row).

## Ownership

| Asset                                      | Source of truth                                               | Rule                                                                                                                                                                                                                         |
| ------------------------------------------ | ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Global personal skills and shared guidance | `catalog/**`                                                  | Edit here; personal skills live in `catalog/.apm/skills/<id>/`, agents in `catalog/.apm/agents/<name>.agent.md`; shared guidance also lives here.                                                                            |
| Repository-scoped skills                   | `optional-skills/<id>/**`                                     | The consuming repository installs its direct ref; never add the collection to root `apm.yml`.                                                                                                                                |
| Workspace-only skills                      | `.apm/skills/**`                                              | Maintain child symlinks in `.claude/skills/` and `.agents/skills/`; edit neither bridge.                                                                                                                                     |
| Private local overrides                    | `private-skills/.apm/skills/**`                               | Gitignored here, tracked in the private repo. Native distribution does not deliver it: place it under the consumer `~/.apm/skills/` (the one allowed edit of `~/.apm`; `docs/native-distribution.md` "native と手動の境界"). |
| Managed external skills and global MCP     | `apm.yml` + `apm.lock.yaml`                                   | The manifest declares dependencies; the lock records the accepted resolution.                                                                                                                                                |
| Manual upstream copies                     | `manual-skills/.apm/skills/**` + `manual-skills/upstreams/**` | Use only when the normal managed lane cannot package or deploy the upstream skill.                                                                                                                                           |
| Host-local MCP                             | `mise.toml` + `scripts/apm-workspace.sh`                      | Reconcile through `mise bootstrap`; do not edit runtime config.                                                                                                                                                              |
| Cursor user-scope MCP                      | `~/.cursor/mcp.json`                                          | Hand-maintained and outside global APM.                                                                                                                                                                                      |
| Decision records and task ownership        | `docs/package-decisions.md`, `docs/apm-task-coverage.md`      | Record external dependency adds/removals in the former.                                                                                                                                                                      |

`apm_modules/`, `~/.claude/`, `~/.codex/`, and `~/.agents/skills/` are cache or
delivery surfaces. Regenerate them instead of editing them. `apm compile -g`
writes the guide to `~/.codex/AGENTS.md` and `~/.cursor/AGENTS.md`, and Claude
reads it as `~/.claude/rules/ai-collaboration.md`. Legacy root copies from the
old path are covered in the known issues of `docs/native-distribution.md`.

## Task Tracking

`todo.txt` is the source of truth for unfinished work and is managed with
`TODO_FILE=todo.txt tuxedo`. Completed internal tasks are archived in the
sibling `done.txt`. Decision history (why a package or lane was adopted,
removed, or deferred) belongs in `docs/package-decisions.md`; code-change
history lives in git log. `plans/` is gitignored and holds local plan output.
Do not introduce `CHANGELOG.md` and do not recreate `TODO.md` for active work —
those roles are already covered by the three surfaces above.

For the lane inventory, use [`docs/skill-inventory.md`](docs/skill-inventory.md);
for placement rules, use the Install Gate in
`catalog/.apm/skills/apm-usage/SKILL.md`.

## Rollout and Verification

The real HOME is native (`~/.apm/apm.yml` starts with
`# Rendered by scripts/native.sh`); the legacy writer tasks no longer exist.
Section B of `docs/native-distribution.md` documents the manual steps and rollback.

| Intent          | Command                | Constraint                                                                                                        |
| --------------- | ---------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Rollout         | `mise run native:sync` | Runs backup and rehearsal before writing HOME; see `docs/native-distribution.md` section B for HTTPS and rollback |
| Validation only | `mise run check`       | Validation only; does not roll out and never fetches external dependencies.                                       |
| Inspection      | `mise run doctor`      | Hidden read-only diagnostics for workspace state and intake reports.                                              |

A PR that changes `apm.yml` or `apm.lock.yaml` also runs the CI job
`dependency-install`, which installs the external dependencies with a real
`apm install` in a throwaway HOME (`scripts/probe-dependency-install.sh manifest`),
because `check` never fetches them.

Shipping here goes through a PR: work on a feature branch, run
`apm-deploy-verify` with the changed skill names (pass them both times: once
the work is committed the tree is clean, so it cannot infer them from
`git status`) before the push for format and check (its distribution-match step
applies only after the merge and B6, so it reports that step as not run before
then), push the branch and open the PR (`full-stop` runs this sequence), and watch
its CI run. Merge only when asked. Exception: the recurring external-pin bump
routine (weekly, or the same update run manually) commits `apm.yml` /
`apm.lock.yaml` directly to `main` without a PR when every gate passes, and
rolls the commit out with `native:sync` as part of the same run; when any gate
fails it stops and reports instead of pushing. After the PR is merged, update `main` in the
checkout itself, never in a linked worktree (if it needs cleaning up, plan that
with `git-branch-cleanup`), roll
that commit out with `mise run native:sync`, then run `apm-deploy-verify` again
for the distribution match.

Before external sharing, run the repository's full gate. For smaller edits run
touched-file formatting and the relevant focused check; always run `git diff
--check` before committing. Confirm a Codex skill rollout from the deployed
`~/.agents/skills/<id>/SKILL.md`, and confirm workspace-only bridges are
symlinks resolving to `.apm/skills/<id>/SKILL.md`.

Windows is out of scope.

## Editing Rules

- When changing the active `apm` source, update both the checkout's `mise.toml`
  and `~/.config/mise/config.dev.toml`.
- MCP placement follows the MCP Ownership Gate in
  `catalog/.apm/skills/apm-usage/SKILL.md`.
- Read `docs/dependency-holds.txt` before bumping an external dependency. Do not
  bump a held one; `validate:workspace` fails on it. Release a hold by deleting
  its line in the same PR and recording the decision in `docs/package-decisions.md`.
- Do not hard-code versioned model IDs in role or tier guidance in skills,
  agent definitions, instructions, or docs. Write in terms of role and tier;
  concrete policy IDs belong in
  `catalog/.apm/skills/orchestrator-worker/references/models.md`. Runtime helper
  allowlists and their focused tests are required mirrors and must change with
  that table. Short aliases in config values (e.g. `model: sonnet`) are allowed.

## Cache Recovery

When a deployed `SKILL.md` is tiny, placeholder, or differs from a complete
tracked source, compare source, cache, and target first, then run
`mise run native:sync` (it sets the APM cache aside; see section B of
`docs/native-distribution.md`). The conditions for manually deleting entries
under `apm_modules/` are in the Guardrails of
`catalog/.apm/skills/apm-usage/SKILL.md`. After a repair, verify the deployed
content, then run `mise run check`.

## Review Focus

For workspace-mechanics changes, verify command semantics, verification-only
`check`, the native rollout order in `docs/native-distribution.md`, and
intentional lockfile changes.
