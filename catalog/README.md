# catalog

This directory contains the managed catalog for the global APM workspace.

- Edit personal skills in `~/.apm/catalog/skills/<id>/`
- Edit shared guidance in `~/.apm/catalog/AGENTS.md`, `agents/**`, `commands/**`, and `rules/**`
- `skills` are authored under `catalog/skills/**` and staged into the published package
- `commands/**` stays top-level because it is runtime-synced shared guidance, not nested skill package content
- Edit this directory directly, then run `mise run stage-catalog` before commit/push
- Install ref: `jey3dayo/apm-workspace/catalog#main`
