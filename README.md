# apm-workspace

APM-based global skill workspace for `jey3dayo`.

This repository is the day-to-day working copy of `~/.apm`. It owns the global APM manifest, the lockfile, the downloaded dependency cache, and the tracked managed catalog package that is published as `jey3dayo/apm-workspace/catalog#main`.

## What Lives Here

- `apm.yml`: global dependency manifest for user-scope skill rollout
- `apm.lock.yaml`: resolved commits and install state captured by APM
- `apm_modules/`: downloaded dependency sources; cache only, not an editing surface
- `catalog/`: tracked APM package for managed skills plus shared guidance assets (`AGENTS.md`, `agents/`, `rules/`)
- `mise.toml`: workspace-local tasks for install, migration, verification, and repair
- `tests/`: Pester coverage for the workspace helpers

## Source Of Truth

Managed catalog assets use a two-layer model:

- Authoring source: `C:\Users\j138c\.config\agents\src\skills\<id>\`
- Authoring source: `C:\Users\j138c\.config\agents\src\AGENTS.md`, `agents\**`, `rules\**`
- Tracked package: `C:\Users\j138c\.apm\catalog\.apm\skills\<id>\`
- Tracked package: `C:\Users\j138c\.apm\catalog\AGENTS.md`, `agents\**`, `rules\**`

The tracked package is generated from the authoring source and then installed through a single upstream ref in `apm.yml`:

```text
jey3dayo/apm-workspace/catalog#main
```

External skills stay in `apm.yml` as upstream refs and are downloaded into `apm_modules/`. Top-level managed `commands/` are not migrated yet because `agents/src` has no authoritative `commands/` tree.

## Daily Flow

```powershell
cd C:\Users\j138c\.apm
mise install
mise run migrate-external
mise run apply
mise run doctor
```

Useful maintenance commands:

```powershell
mise run validate-catalog
mise run stage-catalog
mise run register-catalog
mise run smoke-catalog
```

## Managed Skill Updates

When a managed catalog asset changes under `C:\Users\j138c\.config\agents\src\`:

1. Update the authoring source.
2. Run `mise run stage-catalog`.
3. Commit and push the updated `catalog/`.
4. Run `mise run register-catalog`.
5. Run `mise run doctor` and confirm:
   - `external selection overlap: count=0`
   - `catalog: ... status=ok`
   - target lines show `config=present agents=present rules=present`

If old package ownership from a previous install state is still hanging around, run `apm prune` once before re-applying.

## More Context

- Operational reference: `C:\Users\j138c\.config\docs\tools\apm-workspace.md`
- Task catalog: `C:\Users\j138c\.config\docs\tools\mise-tasks.md`
- Managed-skill usage guidance: `C:\Users\j138c\.config\agents\src\skills\apm-usage\SKILL.md`
