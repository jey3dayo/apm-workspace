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

Managed catalog assets use a two-layer model:

- Authoring source: `~/.config/agents/src/skills/<id>/`
- Authoring source: `~/.config/agents/src/AGENTS.md`, `agents/**`, `commands/**`, `rules/**`
- Tracked package: `~/.apm/catalog/.apm/skills/<id>/`
- Tracked package: `~/.apm/catalog/AGENTS.md`, `agents/**`, `commands/**`, `rules/**`

The tracked package is generated from the authoring source and then installed through a single upstream ref in `apm.yml`:

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

When a managed catalog asset changes under `~/.config/agents/src/`:

1. Update the authoring source.
2. Run `mise run stage-catalog`.
3. Commit and push the updated `catalog/`.
4. Run `mise run register-catalog`.
5. Run `mise run doctor` and confirm:
   - `external selection overlap: count=0`
   - `catalog: ... status=ok`
   - target lines show `config=present agents=present commands=present rules=present`

If old package ownership from a previous install state is still hanging around, run `apm prune` once before re-applying.

## More Context

- Operational reference: `~/.config/docs/tools/apm-workspace.md`
- Task catalog: `~/.config/docs/tools/mise-tasks.md`
- Managed-skill usage guidance: `~/.config/agents/src/skills/apm-usage/SKILL.md`
- Task coverage memo: `docs/apm-task-coverage.md`
- Remaining work: `TODO.md`
