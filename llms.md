# apm-workspace

`C:\Users\j138c\.apm` is the working copy of the global APM workspace for `jey3dayo`.

## What This Workspace Owns

- `apm.yml`: global dependency manifest
- `apm.lock.yaml`: resolved commits and install state
- `apm_modules/`: downloaded upstream sources; cache only
- `catalog/`: tracked managed catalog package published as `jey3dayo/apm-workspace/catalog#main`
- `mise.toml`: workspace tasks
- `tests/`: Pester coverage for helper behavior

## Source Of Truth Model

Managed catalog assets are authored in `C:\Users\j138c\.config\agents\src\` and staged into `catalog/`.

- Skills:
  - source: `C:\Users\j138c\.config\agents\src\skills\<id>\`
  - tracked: `C:\Users\j138c\.apm\catalog\.apm\skills\<id>\`
- Shared guidance:
  - source: `C:\Users\j138c\.config\agents\src\AGENTS.md`
  - source: `C:\Users\j138c\.config\agents\src\agents\**`
  - source: `C:\Users\j138c\.config\agents\src\rules\**`
  - tracked: `C:\Users\j138c\.apm\catalog\AGENTS.md`
  - tracked: `C:\Users\j138c\.apm\catalog\agents\**`
  - tracked: `C:\Users\j138c\.apm\catalog\rules\**`

Top-level managed `commands/` are not migrated yet because `agents/src` has no authoritative `commands/` tree.

## Operational Rules

- Do not edit `apm_modules/`.
- Do not reintroduce `./packages/*` or `~/.apm/skills/` as the global source of truth.
- Keep `apm.yml` on upstream refs, especially `jey3dayo/apm-workspace/catalog#main`.
- After moving a skill into the managed catalog, remove overlapping entries from `C:\Users\j138c\.config\nix\agent-skills-sources.nix`.

## Default Flow

```powershell
cd C:\Users\j138c\.apm
mise install
mise run migrate-external
mise run apply
mise run doctor
```

## Managed Catalog Update Flow

```powershell
cd C:\Users\j138c\.apm
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

- Human overview: `C:\Users\j138c\.apm\README.md`
- Full contract: `C:\Users\j138c\.config\docs\tools\apm-workspace.md`
- Skill guidance: `C:\Users\j138c\.config\agents\src\skills\apm-usage\SKILL.md`
