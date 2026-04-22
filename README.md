# apm-workspace

APM-based global skill workspace for `jey3dayo`.

This repository is the day-to-day working copy of `~/.apm`. `~/.apm` is the source of truth for daily authoring and operation. `~/.config` is bootstrap-only and is not the authoring surface.

Current `apm` CLI source is pinned through `mise` to `github:microsoft/apm@v0.9.1`.

Important compatibility note:

- `obra/superpowers` stays on the normal APM-managed lane with `apm >= 0.9.1`.
- Older 0.8.x builds may mis-classify that package layout and drop skills during install.

## What Lives Here

- `apm.yml`: global dependency manifest for user-scope skill rollout
- `apm.lock.yaml`: resolved commits and install state captured by APM
- `apm_modules/`: downloaded dependency sources; cache only, not an editing surface
- `catalog/`: tracked runtime guidance package for shared assets (`AGENTS.md`, `agents/`, `commands/`, `rules/`) plus managed personal skills under `catalog/skills/`
- `manual-skills/`: copied skills that are kept outside the managed APM lane and distributed separately when needed
- `mise.toml`: workspace-local tasks for install, migration, verification, and repair
- `tests/`: Pester coverage for the workspace helpers

## Workspace Layout

Authoring and deployment are split:

- Personal skills: `~/.apm/catalog/skills/<id>/`
- External skills: command-managed entries in `~/.apm/apm.yml` and `~/.apm/apm.lock.yaml`
- Shared guidance: `~/.apm/catalog/AGENTS.md`, `agents/**`, `commands/**`, `rules/**`
- Manual-only copied skills:
  - content: `~/.apm/manual-skills/.apm/skills/<skill-id>/`
  - provenance notes: `~/.apm/manual-skills/upstreams/**`

- `catalog/skills/**` is the authoring surface for your personal assets.
- external skills are managed with `apm install` / `apm uninstall`, recorded in `apm.yml` / `apm.lock.yaml`, and resolved into `apm_modules/`.
- `manual-skills/**` is for copied skills that APM cannot manage cleanly. They are not part of the default `apply` / `doctor` managed lane.
- `~/.config/nix/agent-skills-sources.nix` is retired and intentionally empty; it is not an active source of truth.
- `catalog/**` remains the tracked runtime guidance package for shared assets synced into target roots.

Current APM limitation:

- user-scope install (`apm install -g`) does not yet support local package refs such as `./packages/...`
- keep `apm.yml` on remote refs for global install
- do not switch `apm.yml` to local `./packages/*` refs until user-scope local package support lands in APM
- Codex is handled separately via `apm compile --target codex --output ~/.codex/AGENTS.md`
- Codex skills are deployed to `~/.agents/skills`, not `~/.codex/skills`
- `~/.codex/skills` should be treated as legacy/cleanup-only; this workspace removes it during `mise run apply` to avoid duplicate skill listings
- if `apm` is defined in both `~/.apm/mise.toml` and `~/.config/mise/config.default.toml`, both entries must point to the same source to avoid command-resolution collisions

The formatter for bold headings rewrites Markdown under `catalog/`:

```text
tsx ~/.config/scripts/replace-bold-headings.ts ./catalog
```

This is the only documented exception that reaches into `~/.config`. All other day-to-day references should point to this repository, especially the sections below and `docs/apm-task-coverage.md`.

## Source Of Truth

- Personal skills
  - edit `~/.apm/catalog/skills/<id>/`
- Manual-only copied skills
  - edit `~/.apm/manual-skills/.apm/skills/<skill-id>/`
  - keep them out of `apm.yml`
  - distribute them separately from the default managed rollout
- External skills
  - add with `apm install <package-ref>`
  - remove with `apm uninstall <package-ref>`
  - treat `apm.yml` and `apm.lock.yaml` as command-managed state during normal operation
- Shared guidance
  - edit `~/.apm/catalog/AGENTS.md`, `agents/**`, `commands/**`, `rules/**`

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
mise run ci           # verification only
mise run sync         # upstream refresh
mise run sync:stable  # stable rollout from current manifest + lock
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

When external skills change:

1. Use `apm install <package-ref>` or `apm uninstall <package-ref>`.
2. Review `apm.yml` and `apm.lock.yaml`.
3. Run `mise run apply` when you want to deploy the current manifest and lock without accepting new upstream content.
4. Run `mise run doctor` to verify the deployed state.
5. Use `mise run sync` only when you intentionally want to refresh upstream dependency content.

When a copied skill lives under `~/.apm/manual-skills/`:

1. Treat it as a manually curated copy from upstream.
2. Do not add it to the root `apm.yml`.
3. Keep provenance in the repo-local README for that copied source.
4. Distribute it explicitly, for example with the standalone package ref `jey3dayo/apm-workspace/manual-skills`.

Task semantics:

- `mise run ci` verifies formatting, validation, and smoke checks only. It does not deploy.
- `mise run sync` is the upstream-acceptance flow and is centered on `apm install -g --update`.
- `mise run sync:stable` preserves the broader update -> verify -> apply -> doctor flow for the current manifest and lock.
- `mise run apply` publishes Codex skills into `~/.agents/skills` and keeps `~/.codex/skills` out of the active deployment path.
- direct `apm` invocations should go through `mise`; when exact binary selection matters, use `mise exec github:microsoft/apm@v0.9.1 -- apm ...`.

When shared runtime guidance changes under `~/.apm/catalog/`:

1. Update `catalog/` directly.
2. Run `mise run stage-catalog`.
3. Review the normalized `catalog/` diff.
4. Run `mise run doctor` and confirm:
   - `catalog: ... status=ok`
   - target lines show `config=present agents=present commands=present rules=present`

If old package ownership from a previous install state is still hanging around, run `apm prune` once before re-applying.

## More Context

- Task coverage memo: `docs/apm-task-coverage.md`
- Managed-skill usage guidance: `~/.apm/catalog/skills/apm-usage/SKILL.md`
- This README: `What Lives Here`, `Workspace Layout`, `Daily Flow`, `Managed Skill Updates`
- Remaining work: `TODO.md`
