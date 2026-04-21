# apm-workspace

APM-based global skill workspace for `jey3dayo`.

This repository is the day-to-day working copy of `~/.apm`. It owns the global APM manifest, the lockfile, the downloaded dependency cache, your personal skill sources, and the shared runtime guidance published from this repo.

## What Lives Here

- `apm.yml`: global dependency manifest for user-scope skill rollout
- `apm.lock.yaml`: resolved commits and install state captured by APM
- `apm_modules/`: downloaded dependency sources; cache only, not an editing surface
- `catalog/`: tracked runtime guidance package for shared assets (`AGENTS.md`, `agents/`, `commands/`, `rules/`)
- `src/`: authoring source for your personal assets
- `mise.toml`: workspace-local tasks for install, migration, verification, and repair
- `tests/`: Pester coverage for the workspace helpers

## Workspace Layout

Authoring and deployment are split:

- Personal skills: `~/.apm/catalog/skills/<id>/`
- Shared guidance: `~/.apm/catalog/AGENTS.md`, `agents/**`, `commands/**`, `rules/**`

The layout difference between `src/` and `catalog/` is intentional.

- `catalog/skills/**` is the authoring surface for your personal assets.
- external skills are tracked in `apm.yml` by upstream ref.
- `catalog/**` remains the tracked runtime guidance package for shared assets synced into target roots.

Current APM limitation:

- user-scope install (`apm install -g`) does not yet support local package refs such as `./packages/...`
- keep `apm.yml` on remote refs for global install
- do not switch `apm.yml` to local `./packages/*` refs until user-scope local package support lands in APM

The formatter for bold headings only rewrites personal skills:

```text
tsx ~/.config/scripts/replace-bold-headings.ts ./catalog/skills
```

External skills can still live as upstream refs in `apm.yml` and are downloaded into `apm_modules/`.

## Daily Flow

```powershell
cd ~/.apm
mise install
mise run apply
mise run doctor
```

Useful maintenance commands:

```powershell
mise run format
mise run ci
mise run validate:catalog
mise run stage-catalog
mise run catalog:tidy
mise run register-catalog
mise run smoke-catalog
```

## Managed Skill Updates

When a personal skill changes under `~/.apm/catalog/skills/`:

1. Update `catalog/skills/<id>/`.
2. Run `mise run format:markdown:bold-headings` if you want heading normalization.

When shared runtime guidance changes under `~/.apm/catalog/`:

1. Update `catalog/` directly.
2. Run `mise run stage-catalog`.
3. Review the normalized `catalog/` diff.
4. Run `mise run doctor` and confirm:
   - `catalog: ... status=ok`
   - target lines show `config=present agents=present commands=present rules=present`

If old package ownership from a previous install state is still hanging around, run `apm prune` once before re-applying.

## More Context

- Operational reference: `~/.config/docs/tools/apm-workspace.md`
- Task catalog: `~/.config/docs/tools/mise-tasks.md`
- Managed-skill usage guidance: `~/.apm/catalog/skills/apm-usage/SKILL.md`
- Task coverage memo: `docs/apm-task-coverage.md`
- Remaining work: `TODO.md`
