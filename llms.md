# apm-workspace

`~/.apm` is the working copy and operational source of truth for the global APM workspace for `jey3dayo`.

`~/.config` is bootstrap-only for this workspace model. The external source mapping at `~/.config/nix/agent-skills-sources.nix` is retired and intentionally empty, so it is not an active editing target.

This workspace owns the global APM manifest, the lockfile, the downloaded dependency cache, your personal skill sources, and the shared runtime guidance package.

## What This Workspace Owns

- `apm.yml`: global dependency manifest for user-scope rollout
- `apm.lock.yaml`: resolved commits and install state captured by APM
- `apm_modules/`: downloaded upstream sources; cache only, not an editing surface
- `catalog/`: shared runtime guidance package for AGENTS, agents, commands, and rules
- `src/`: personal authoring source
- `mise.toml`: workspace-local tasks for install, migration, validation, and repair
- `tests/`: Pester coverage for workspace helpers

## Managed Catalog Layout

Workspace assets are split by role.

- Personal skills
  - source: `~/.apm/catalog/skills/<id>/`
- Shared guidance
  - source: `~/.apm/catalog/AGENTS.md`
  - source: `~/.apm/catalog/agents/**`
  - source: `~/.apm/catalog/commands/**`
  - source: `~/.apm/catalog/rules/**`

The tracked layout is intentionally asymmetric:

- `catalog/skills/**` is the authoring layer for personal assets.
- external skills stay visible in `apm.yml` as upstream refs.
- `commands/**` stay top-level inside `catalog/**` because they are synced into runtime targets as shared guidance, not installed as nested skill packages.

Shared runtime guidance is published through the catalog ref in `apm.yml`:

```text
jey3dayo/apm-workspace/catalog#main
```

`apm_modules/` remains a cache-only layer, not an editing surface.

## Operational Guardrails

- Do not edit `apm_modules/`.
- Do not reintroduce `./packages/*` or `~/.apm/skills/` as alternate editing surfaces for managed global skills.
- Keep `~/.config/scripts/replace-bold-headings.ts` available as the one allowed script exception.
- Keep `apm.yml` on upstream refs, especially `jey3dayo/apm-workspace/catalog#main`.
- Keep personal source in `~/.apm/src/**` and runtime guidance in `~/.apm/catalog/**`.
- Treat Codex as a compile target, not a direct user-scope skill target. The current script path is `apm compile --target codex --output ~/.codex/AGENTS.md`.
- Do not use `~/.codex/skills` as the verification source of truth for this workspace. Verify Codex rollout through compile success and `~/.codex/AGENTS.md`.

## Default Flow

```powershell
cd ~/.apm
mise install
mise run apply
mise run doctor
```

## Managed Catalog Update Flow

When a personal skill changes under `~/.apm/catalog/skills/`:

1. Edit `catalog/skills/<id>/` directly.
2. Run `mise run format:markdown:bold-headings` when you want heading normalization.

When shared runtime guidance changes under `~/.apm/catalog/`:

1. Edit `catalog/` directly.
2. Run `mise run stage-catalog`.
3. Review the normalized `catalog/` diff.
4. Commit and push the updated `catalog/`.
5. Run `mise run register-catalog`.
6. Run `mise run doctor` and confirm:
   - `catalog: ... status=ok`
   - target lines show `config=present agents=present commands=present rules=present`

If old package ownership from a previous install state is still hanging around, run `apm prune` once before re-applying.

## Useful Maintenance Commands

- `mise run format`: format Markdown, TOML, and YAML in the workspace
- `mise run format:markdown:bold-headings`: rewrite bold headings only inside personal skills
- `mise run ci:check`: run formatting checks plus validation smoke checks
- `mise run ci`: format, validate, apply, and verify the local workspace rollout
- `mise run validate`: run both workspace and catalog validation
- `mise run validate:workspace`: verify workspace wiring with workspace overrides
- `mise run stage-catalog`: normalize `catalog/` in place before commit and push
- `mise run validate:catalog`: verify managed catalog package integrity
- `mise run catalog:tidy`: normalize the managed catalog, validate it, and print workspace health

## References

- Human overview: `~/.apm/README.md`
- Full contract: `~/.apm/README.md`
- Task catalog: `docs/apm-task-coverage.md`
- Skill guidance: `~/.apm/catalog/skills/apm-usage/SKILL.md`
- Task coverage memo: `docs/apm-task-coverage.md`
- Remaining work: `TODO.md`
