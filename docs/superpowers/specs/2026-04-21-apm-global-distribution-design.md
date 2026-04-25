# APM Global Distribution Redesign

## Summary

This design restores an `apm -g` centered global skill workflow while keeping personal skills authored in `~/.apm/catalog/skills/**`.

The key change is to treat two sources as first-class inputs:

- Personal skills: `catalog/skills/**`
- External skills: `apm install/uninstall` managed entries in `apm.yml` and `apm.lock.yaml`

`catalog#main` remains the shared guidance package for `AGENTS.md`, `agents/**`, `commands/**`, and `rules/**`, but it is no longer the only source of deployed skills. The lockfile must keep resolved external skills visible instead of collapsing everything into a single catalog package entry.

## Goals

- Restore external skill resolution through `apm install/uninstall`
- Keep `apm.lock.yaml` populated with individual external skill entries
- Avoid manual editing of `apm.yml` during normal operation
- Keep personal skills owned in this repository under `catalog/skills/**`
- Make `mise run apply` offline and reproducible from local state
- Deploy to both `~/.claude/skills` and `~/.codex/skills`
- Avoid duplicate skill entries in clients
- Update user-facing docs to match the new workflow

## Non-Goals

- Reintroducing Nix as a skill distribution source
- Keeping the current catalog-only skill rollout model
- Supporting online fetches during `apply`
- Deploying multiple aliases for the same skill within one target

## Source Of Truth

### Personal skills

Personal skills continue to be authored directly in:

- `catalog/skills/<skill-id>/`

These files remain tracked in git and are distributed locally by workspace commands.

### External skills

External skills are managed by APM commands, not by hand-editing the manifest:

- Add: `apm install <package-ref>`
- Remove: `apm uninstall <package-ref>`

The authoritative files are:

- `apm.yml`
- `apm.lock.yaml`

Normal user flow should treat those files as command-managed state even though they remain committed to git.

### Shared guidance

Shared runtime guidance continues to live in:

- `catalog/AGENTS.md`
- `catalog/agents/**`
- `catalog/commands/**`
- `catalog/rules/**`

## Desired Command Model

### APM commands

APM commands are the canonical entry point for external dependency changes.

- `apm install/uninstall`
  - updates manifest intent
  - updates the lockfile
  - does not require users to edit `apm.yml` directly

### Workspace commands

Workspace `mise` tasks are responsible for orchestration and local deployment.

- `mise run update`
  - updates the `~/.apm` checkout when safe
  - refreshes dependency resolution
  - may require network access

- `mise run apply`
  - performs local deployment only
  - must work offline
  - consumes existing `apm.yml`, `apm.lock.yaml`, `apm_modules/`, and `catalog/skills/**`

- `mise run ci`
  - verification only
  - must not mutate deployed targets

- `mise run sync` or equivalent meta-task
  - optional convenience entry point
  - composes `update`, `ci`, and `apply`

## Architecture

### High-level flow

1. Personal skills are authored in `catalog/skills/**`
2. External skills are registered with `apm install/uninstall`
3. `update` refreshes the repository checkout and dependency resolution
4. `apply` combines personal and external skills into per-target deployment plans
5. Shared guidance is synced separately from skill deployment

### Split responsibilities

The implementation should explicitly separate:

- manifest and lock management
- deployment plan generation
- target filesystem application
- shared guidance sync

This keeps the behavior understandable and reduces accidental coupling between skill rollout and AGENTS/config distribution.

## Deployment Model

### Inputs to `apply`

`apply` must only use local state:

- `catalog/skills/**`
- `apm.yml`
- `apm.lock.yaml`
- `apm_modules/`

If a required external skill is not available locally, `apply` fails fast instead of fetching it.

### Outputs of `apply`

The primary outputs are:

- `~/.claude/skills`
- `~/.codex/skills`

Secondary targets may remain supported, but the design should prioritize these two.

### Shared guidance outputs

Shared guidance sync stays as a separate phase after skill deployment planning:

- `~/.claude/CLAUDE.md`
- `~/.codex/AGENTS.md`
- related `agents/**`, `commands/**`, and `rules/**`

This prevents guidance-only changes from being entangled with skill inventory logic.

## Target Name Normalization

Each source skill has one canonical source id, for example:

- `superpowers:brainstorming`

Deployment must use a target-aware canonicalization function:

- `formatSkillName(target, sourceSkillId)`

Expected behavior:

- Claude target can usually preserve the source id
- Codex target may normalize names to a client-compatible form
- One source skill becomes exactly one deployed directory per target
- No alias duplication within a single target

The deployment layer must keep a reversible mapping between:

- source id
- target
- deployed name

That mapping is required for correct update, delete, and collision detection behavior.

## Collision Rules

Before touching target directories, deployment planning must detect:

- personal skill vs external skill name collisions
- Codex-normalized name collisions
- duplicate source ids in the combined inventory

Any collision must stop `apply` with a clear error.

## `apm.lock.yaml` Expectations

The lockfile must once again record resolved external skills individually.

Required properties:

- external skills remain visible as distinct entries
- repository, resolved commit, and deployed file information stay inspectable
- lockfile size is allowed to grow as a consequence of explicit dependency ownership

The current catalog-only shrinkage is considered a regression for this workflow.

## `mise.toml` Redesign

The task layout should be reorganized following `mise` best practices:

### Command tasks

- `apply`
- `update`
- `doctor`
- validation and formatting leaf tasks

### Aggregation tasks

- `validate`
- `check:format`
- `ci:check`

### Meta tasks

- `ci` for verification only
- `sync` or `install` for end-to-end local workflow

Tasks whose naming or semantics are rooted in the catalog-only migration should be reviewed and either:

- retained as internal maintenance commands
- renamed
- or removed if no longer needed

## Documentation Changes

### `README.md`

Update the README to describe the new stable workflow:

- add an explicit `Source Of Truth` section for personal skills and external skills
- personal skills live in `catalog/skills/**`
- external skills are managed with `apm install/uninstall`
- `update` refreshes dependency state
- `apply` deploys locally from lockfile-backed local state
- `ci` verifies only

Remove wording that implies:

- catalog-only skill rollout
- intentionally small lockfiles
- Codex not using deployed skills

### `llms.txt`

Update `llms.txt` to reflect the same operational model in concise agent-facing terms:

- include the same `Source Of Truth` summary as README in shorter form
- do not hand-edit `apm.yml` during normal use
- use `apm install/uninstall` for external skills
- use `mise run update` for refresh
- use `mise run apply` for offline local deployment
- personal skills remain in `catalog/skills/**`

### Repo `AGENTS.md`

Do not add a repo-root `AGENTS.md` in this implementation slice.

- the repository does not currently have a stable local `AGENTS.md`
- the Source Of Truth rules should live in `README.md` and `llms.txt` first
- a repo-root `AGENTS.md` can be added later once the workflow and naming behavior settle

### `TODO.md`

Record the unresolved concern around target-specific name normalization:

- current plan uses `formatSkillName(target, sourceSkillId)`
- Codex compatibility may require further tuning
- the rule should remain easy to revise without changing authoring ids

This concern belongs in `TODO.md`, not `AGENTS.md`, because it is an implementation concern rather than a stable operating rule.

## Error Handling

`apply` should fail immediately when:

- `apm.yml` and `apm.lock.yaml` are inconsistent
- a locked external skill is missing from local materialized dependencies
- name normalization produces invalid or empty output
- target name collisions are detected
- staging succeeds but final target replacement fails

The system should prefer explicit failure over partial success.

## Atomicity

Deployment should be staged in temporary directories and swapped into place only after a target plan is complete.

This avoids partially updated target skill trees when:

- a later skill fails to stage
- collision detection is incomplete
- filesystem replacement fails mid-run

## Testing Strategy

### Unit-level behavior

Add or update tests for:

- target-aware name normalization
- collision detection
- source id to deployed name mapping
- lockfile/manifest consistency checks

### Workflow behavior

Cover:

- adding an external skill and applying locally
- removing an external skill and cleaning up target directories
- offline `apply` with pre-resolved state
- failure when required local external content is missing

### Task-level behavior

Validate:

- `mise.toml` task DAG after the redesign
- shell and PowerShell parity for `apply`, `update`, and validation commands
- `ci` remaining side-effect free

## Risks

- Codex naming behavior may still differ from expectations after initial normalization
- Existing users may rely on catalog-only semantics without realizing it
- Removing or renaming old tasks can break undocumented habits
- External skill resolution and local materialization behavior in APM may impose practical constraints that require small workflow adjustments

## Migration Strategy

1. Restore external dependency ownership in `apm.yml` and `apm.lock.yaml`
2. Redesign deployment planning around combined personal and external inventories
3. Make `apply` consume lock-backed local state only
4. Rework `mise.toml` task semantics
5. Update `README.md`, `llms.txt`, and `TODO.md`
6. Verify shell, PowerShell, and task behavior

## Open Questions

- What exact Codex normalization rule set is needed beyond the initial prefix-removal approach
- Whether all currently supported secondary targets should share the same normalization behavior as Claude or Codex
- Whether APM exposes enough stable metadata to avoid maintaining extra local deployment mapping state

## Recommendation

Proceed with the dual-source model:

- personal skills from `catalog/skills/**`
- external skills from `apm install/uninstall` managed `apm.yml` and `apm.lock.yaml`

This best matches the intended operator workflow, preserves explicit ownership of external skills, and avoids returning to Nix-based distribution.
