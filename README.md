# apm-workspace

APM-based global skill workspace for `jey3dayo`.

This repository is the day-to-day working copy of `~/.apm`. `~/.apm` is the source of truth for daily authoring and operation. `~/.config` is not the authoring or operational surface.

Current `apm` CLI source is pinned through `mise` to `pipx:apm-cli@0.26.0`.

## Source Of Truth

- Personal skills: `~/.apm/catalog/skills/<id>/`
- Optional repository-scoped skills: `~/.apm/optional-skills/<id>/`
- Local-only private skills: `~/.apm/private-skills/.apm/skills/<id>/`
- Shared guidance: `~/.apm/catalog/{AGENTS.md,agents/**,commands/**,rules/**}`
- Dependency selection and accepted upstream state: `~/.apm/apm.yml`, `~/.apm/apm.lock.yaml`
- Host-local MCP bootstrap: `~/.apm/mise.toml`, `~/.apm/scripts/apm-workspace.*`
- Checked-out external dependencies: edit and push the upstream checkout, then accept the pushed commit through `~/.apm`
- Downloaded sources: `~/.apm/apm_modules/` is cache only, not an editing surface
- Manual copied skills: `~/.apm/manual-skills/.apm/skills/<skill-id>/`

## Initial Bootstrap

```powershell
cd ~/.apm
mise bootstrap
```

The final hidden bootstrap task detects the host's 1Password MCP command and reconciles the Codex and Claude user-scope entries. `~/.codex/config.toml` and `~/.claude.json` are generated targets, not editing surfaces.

## Daily Flow

```powershell
cd ~/.apm
mise run deploy
```

Before changing workspace mechanics, classify the work as one of:

- Stable rollout: keep `apm.yml` and `apm.lock.yaml` as-is, then use `mise run deploy`.
- Upstream refresh: intentionally accept newer dependency content, then use `mise run upgrade` and review `apm.lock.yaml`.
- Local-only skill sync: refresh local Codex skills only, then use `mise run apply:skills:local`.

For Codex skill changes, verification is not complete until the deployed `~/.agents/skills/<id>/SKILL.md` contains the expected content.

## Core Tasks

- `mise bootstrap`: install the declared environment, then reconcile host-local MCP entries through hidden internal tasks
- `mise run check`: lightweight validation only
- `mise run verify`: `check` plus catalog smoke verification
- `mise run audit:ci:smoke`: temp-install the workspace manifest and run `apm audit --ci`
- `mise run deploy`: normal local rollout
- `mise run refresh`: refresh checkout and dependency state without deploying
- `mise run upgrade`: accept newer upstream package content
- `mise run refresh:deploy`: run `refresh -> deploy`
- `mise run prepare:catalog`: normalize tracked catalog content
- `mise run install:catalog`: install the pushed catalog ref
- `mise run smoke:catalog`: smoke-test the generated catalog package
- `mise run apply:skills:local`: quick local Codex skill refresh only

## External Checkout Flow

Use this when a dependency in `apm.yml` is also checked out locally and that checkout is the source of truth for the change.

1. Edit, verify, commit, and push the external repository.
2. Run `mise run upgrade` in `~/.apm`.
3. Confirm `apm.lock.yaml` points the dependency at the pushed commit.
4. Verify the deployed target, such as `~/.agents/skills/<id>`, contains the updated content.
5. Review unrelated lock drift separately before committing `apm.lock.yaml`.

## Notes

- Use `mise` tasks rather than `.config` wrapper scripts for normal operation.
- Keep `apm.yml` on remote refs for global install; do not switch it back to many local `./packages/*` refs.
- Keep repository-scoped skills out of the root `apm.yml`; add only the required `jey3dayo/apm-workspace/optional-skills/<id>#main` ref to the consuming repository.
- For an upstream bundle with optional sub-skills, keep the upstream reference and select the sub-skill in the consuming repository, for example `apm install nextlevelbuilder/ui-ux-pro-max-skill --skill banner-design`.
- When an upstream skill cannot stay on the normal managed lane, keep its copied source under `manual-skills/.apm/skills/**` and distribute it through `jey3dayo/apm-workspace/manual-skills`.
- Exception: skills that only carry runtime assets for `catalog/commands/**` stay under `catalog/skills/<id>/` with provenance recorded in their own `SKILL.md`.
- Keep machine-local skills under `private-skills/.apm/skills/**`; this directory is gitignored and only participates in `mise run apply:skills:local`.
- If a skill id exists in both `catalog/skills/**` and `private-skills/.apm/skills/**`, the local private copy wins during `mise run apply:skills:local`.
- Codex is handled via `apm compile --target codex --output ~/.codex/AGENTS.md`, and skills deploy to `~/.agents/skills`.
- `tsx ~/.config/scripts/replace-bold-headings.ts ./catalog` is the only documented exception that reaches into `~/.config`.

More detail lives in `docs/apm-task-coverage.md` and `catalog/skills/apm-usage/SKILL.md`.
