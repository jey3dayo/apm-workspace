# catalog

This directory contains the managed catalog for the global APM workspace.

- Edit skills in `~/.apm/catalog/.apm/skills/<id>/`
- Edit shared guidance in `~/.apm/catalog/AGENTS.md`, `agents/**`, `commands/**`, and `rules/**`
- `skills` live under `.apm/skills/**` because they are installable APM package content
- `commands/**` stays top-level because it is runtime-synced shared guidance, not nested skill package content
- Edit this directory directly, then run `mise run stage-catalog` before commit/push
- Install ref: `jey3dayo/apm-workspace/catalog#main`
