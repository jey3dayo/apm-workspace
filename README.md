# apm-workspace

APM-based global skill workspace for `jey3dayo`.

This repository is the day-to-day working copy of `~/.apm`. It owns the global APM manifest, the lockfile, the downloaded dependency cache, and the tracked managed catalog package that is published as `jey3dayo/apm-workspace/catalog#main`.

## What Lives Here

- `apm.yml`: global dependency manifest for user-scope skill rollout
- `apm.lock.yaml`: resolved commits and install state captured by APM
- `apm_modules/`: downloaded dependency sources; cache only, not an editing surface
- `catalog/`: tracked APM package for managed skills plus shared guidance assets (`AGENTS.md`, `agents/`, `commands/`, `rules/`)
- `mise.toml`: workspace-local tasks for install, migration, verification, and repair
- `tests/`: Pester coverage for the workspace helpers

## Source Of Truth

Managed catalog assets are edited directly in `~/.apm/catalog/`.

- Skills: `~/.apm/catalog/.apm/skills/<id>/`
- Shared guidance: `~/.apm/catalog/AGENTS.md`, `agents/**`, `commands/**`, `rules/**`
- Transitional mirror: `~/.config/agents/src/**`

The layout difference between `catalog/.apm/skills/` and `catalog/commands/` is intentional.

- `catalog/.apm/skills/<id>/` is the APM package namespace for installable skills.
- `catalog/commands/**` is not a skill package subtree. It is shared runtime guidance that is synced into target roots as `commands/**` alongside `AGENTS.md`, `agents/**`, and `rules/**`.
- Keep this split unless the runtime sync contract itself changes.

`mise run stage-catalog` now normalizes the tracked package and refreshes the transitional mirror. Global install still happens through a single upstream ref in `apm.yml`:

```text
jey3dayo/apm-workspace/catalog#main
```

External skills stay in `apm.yml` as upstream refs and are downloaded into `apm_modules/`.

## Daily Flow

```powershell
cd ~/.apm
mise install
mise run migrate-external
mise run apply
mise run doctor
```

Useful maintenance commands:

```powershell
mise run format
mise run ci
mise run validate-catalog
mise run stage-catalog
mise run catalog:tidy
mise run register-catalog
mise run smoke-catalog
```

## Managed Skill Updates

When a managed catalog asset changes under `~/.apm/catalog/`:

1. Update `catalog/` directly.
2. Run `mise run stage-catalog`.
3. Review the normalized `catalog/` diff and the refreshed mirror under `~/.config/agents/src/`.
4. Commit and push the updated `catalog/`.
5. Run `mise run register-catalog`.
6. Run `mise run doctor` and confirm:
   - `external selection overlap: count=0`
   - `catalog: ... status=ok`
   - target lines show `config=present agents=present commands=present rules=present`

If old package ownership from a previous install state is still hanging around, run `apm prune` once before re-applying.

## More Context

- Operational reference: `~/.config/docs/tools/apm-workspace.md`
- Task catalog: `~/.config/docs/tools/mise-tasks.md`
- Managed-skill usage guidance: `~/.apm/catalog/.apm/skills/apm-usage/SKILL.md`
- Task coverage memo: `docs/apm-task-coverage.md`
- Remaining work: `TODO.md`
