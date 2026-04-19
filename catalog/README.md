# catalog

This directory is the managed catalog source of truth for the global APM workspace.

- Edit skills in `~/.apm/catalog/.apm/skills/<id>/`
- Edit shared guidance in `~/.apm/catalog/AGENTS.md`, `agents/**`, `commands/**`, and `rules/**`
- `skills` live under `.apm/skills/**` because they are installable APM package content
- `commands/**` stays top-level because it is runtime-synced shared guidance, not nested skill package content
- `mise run stage-catalog` normalizes this package and refreshes the transitional mirror in `~/.config/agents/src/`
- Install ref: `jey3dayo/apm-workspace/catalog#main`