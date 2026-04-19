# apm-workspace

`~/.apm` is the working copy of the global APM workspace for `jey3dayo`.

## What This Workspace Owns

- `apm.yml`: global dependency manifest
- `apm.lock.yaml`: resolved commits and install state
- `apm_modules/`: downloaded upstream sources; cache only
- `catalog/`: tracked managed catalog package published as `jey3dayo/apm-workspace/catalog#main`
- `mise.toml`: workspace tasks
- `tests/`: Pester coverage for helper behavior

## Source Of Truth Model

Managed catalog assets are authored in `~/.config/agents/src/` and staged into `catalog/`.

- Skills:
  - source: `~/.config/agents/src/skills/<id>/`
  - tracked: `~/.apm/catalog/.apm/skills/<id>/`
- Shared guidance:
  - source: `~/.config/agents/src/AGENTS.md`
  - source: `~/.config/agents/src/agents/**`
  - source: `~/.config/agents/src/rules/**`
  - tracked: `~/.apm/catalog/AGENTS.md`
  - tracked: `~/.apm/catalog/agents/**`
  - tracked: `~/.apm/catalog/rules/**`

Top-level managed `commands/` are not migrated yet because `agents/src` has no authoritative `commands/` tree.

## Operational Rules

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

```powershell
cd ~/.apm
mise run stage-catalog
# commit and push catalog/
mise run register-catalog
mise run doctor
```

Healthy output includes:

- `external selection overlap: count=0`
- `catalog: ... status=ok`
- target lines with `config=present agents=present rules=present`

## References

- Human overview: `~/.apm/README.md`
- Full contract: `~/.config/docs/tools/apm-workspace.md`
- Skill guidance: `~/.config/agents/src/skills/apm-usage/SKILL.md`
