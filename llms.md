# apm-workspace

`~/.apm` is the working copy of the global APM workspace for `jey3dayo`.

This workspace owns the global APM manifest, the lockfile, the downloaded dependency cache, and the tracked managed catalog package published as `jey3dayo/apm-workspace/catalog#main`.

## What This Workspace Owns

- `apm.yml`: global dependency manifest for user-scope rollout
- `apm.lock.yaml`: resolved commits and install state captured by APM
- `apm_modules/`: downloaded upstream sources; cache only, not an editing surface
- `catalog/`: tracked managed catalog package for skills and shared guidance assets
- `mise.toml`: workspace-local tasks for install, migration, validation, and repair
- `tests/`: Pester coverage for workspace helpers

## Source Of Truth Model

Managed catalog assets live directly in `~/.apm/catalog/`.

- Skills
  - source: `~/.apm/catalog/.apm/skills/<id>/`
- Shared guidance
  - source: `~/.apm/catalog/AGENTS.md`
  - source: `~/.apm/catalog/agents/**`
  - source: `~/.apm/catalog/commands/**`
  - source: `~/.apm/catalog/rules/**`

The tracked layout is intentionally asymmetric:

- `skills` live under `.apm/skills/**` because they are packaged as installable APM skill content.
- `commands` stay at top-level `commands/**` because they are synced into runtime targets as shared guidance, not installed as nested skill packages.
- Do not move `commands/**` under `.apm/**` unless you are deliberately redesigning the runtime asset contract.

The managed catalog is published through the single upstream ref in `apm.yml`:

```text
jey3dayo/apm-workspace/catalog#main
```

External skills remain upstream refs in `apm.yml` and are downloaded into `apm_modules/`.

## Operational Guardrails

- Do not edit `apm_modules/`.
- Do not reintroduce `./packages/*` or `~/.apm/skills/` as the global source of truth.
- Keep `apm.yml` on upstream refs, especially `jey3dayo/apm-workspace/catalog#main`.
- After moving a skill into the managed catalog, remove overlapping entries from `~/.config/nix/agent-skills-sources.nix`.

## Default Flow

```powershell
cd ~/.apm
mise install
mise run migrate-external
mise run apply
mise run doctor
```

## Managed Catalog Update Flow

When a managed catalog asset changes under `~/.apm/catalog/`:

1. Edit `catalog/` directly.
2. Run `mise run stage-catalog`.
3. Review the normalized `catalog/` diff.
4. Commit and push the updated `catalog/`.
5. Run `mise run register-catalog`.
6. Run `mise run doctor` and confirm:
   - `external selection overlap: count=0`
   - `catalog: ... status=ok`
   - target lines show `config=present agents=present commands=present rules=present`

If old package ownership from a previous install state is still hanging around, run `apm prune` once before re-applying.

## Useful Maintenance Commands

- `mise run format`: format Markdown, TOML, and YAML in the workspace
- `mise run ci:check`: run formatting checks plus validation smoke checks
- `mise run ci`: format, validate, apply, and verify the local workspace rollout
- `mise run stage-catalog`: restage the tracked managed catalog package
- `mise run validate-catalog`: verify tracked catalog package integrity
- `mise run catalog:tidy`: restage the tracked catalog, validate it, and print workspace health

## References

- Human overview: `~/.apm/README.md`
- Full contract: `~/.config/docs/tools/apm-workspace.md`
- Task catalog: `~/.config/docs/tools/mise-tasks.md`
- Skill guidance: `~/.apm/catalog/.apm/skills/apm-usage/SKILL.md`
- Task coverage memo: `docs/apm-task-coverage.md`
- Remaining work: `TODO.md`
