# catalog

This directory contains the managed catalog for the global APM workspace.

- Edit personal skills in `~/.apm/catalog/.apm/skills/<id>/`
- Keep repository-specific or infrequently used skills in
  `~/.apm/optional-skills/<id>/` instead of this global catalog, and install
  each skill by its direct repository ref.
- Edit shared guidance in `~/.apm/catalog/AGENTS.md`, `agents/**`, `commands/**`, and `rules/**`
- `skills` are authored under `catalog/.apm/skills/**` and staged into the published package at the same path; do not recreate a top-level `catalog/skills/`
- `catalog/.apm/` holds only `skills/`: `prepare:catalog` rebuilds nothing else there, so `validate:catalog` and `prepare:catalog` stop when another primitive appears
- `commands/**` stays top-level because it is runtime-synced shared guidance, not nested skill package content
- Edit this directory directly, then run `mise run prepare:catalog` before commit/push
- Install ref: `jey3dayo/apm-workspace/catalog#main`
