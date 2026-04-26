# apm-workspace

APM-based global skill workspace for `jey3dayo`.

This repository is the day-to-day working copy of `~/.apm`. `~/.apm` is the source of truth for daily authoring and operation. `~/.config` is not the authoring or operational surface.

Current `apm` CLI source is pinned through `mise` to `pipx:apm-cli@0.9.3`.

## Source Of Truth

- Personal skills: `~/.apm/catalog/skills/<id>/`
- Local-only private skills: `~/.apm/private-skills/.apm/skills/<id>/`
- Shared guidance: `~/.apm/catalog/{AGENTS.md,agents/**,commands/**,rules/**}`
- Dependency selection and accepted upstream state: `~/.apm/apm.yml`, `~/.apm/apm.lock.yaml`
- Downloaded sources: `~/.apm/apm_modules/` is cache only, not an editing surface
- Manual copied skills: `~/.apm/manual-skills/.apm/skills/<skill-id>/`

## Daily Flow

```powershell
cd ~/.apm
mise install
mise run deploy
```

## Core Tasks

- `mise run check`: lightweight validation only
- `mise run verify`: `check` plus catalog smoke verification
- `mise run deploy`: normal local rollout
- `mise run refresh`: refresh checkout and dependency state without deploying
- `mise run upgrade`: accept newer upstream package content
- `mise run refresh:deploy`: run `refresh -> deploy`
- `mise run prepare:catalog`: normalize tracked catalog content
- `mise run install:catalog`: install the pushed catalog ref
- `mise run smoke:catalog`: smoke-test the generated catalog package
- `mise run apply:skills:local`: quick local Codex skill refresh only

## Notes

- Use `mise` tasks rather than `.config` wrapper scripts for normal operation.
- Keep `apm.yml` on remote refs for global install; do not switch it back to many local `./packages/*` refs.
- When an upstream skill cannot stay on the normal managed lane, keep its copied source under `manual-skills/.apm/skills/**` and distribute it through `jey3dayo/apm-workspace/manual-skills`.
- Keep machine-local skills under `private-skills/.apm/skills/**`; this directory is gitignored and only participates in `mise run apply:skills:local`.
- If a skill id exists in both `catalog/skills/**` and `private-skills/.apm/skills/**`, the local private copy wins during `mise run apply:skills:local`.
- Codex is handled via `apm compile --target codex --output ~/.codex/AGENTS.md`, and skills deploy to `~/.agents/skills`.
- `tsx ~/.config/scripts/replace-bold-headings.ts ./catalog` is the only documented exception that reaches into `~/.config`.

More detail lives in `docs/apm-task-coverage.md` and `catalog/skills/apm-usage/SKILL.md`.
