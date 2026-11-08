# catalog

This directory contains the managed catalog for the global APM workspace.

- Edit personal skills in `~/.apm/catalog/.apm/skills/<id>/`
- Keep repository-specific or infrequently used skills in
  `~/.apm/optional-skills/<id>/` instead of this global catalog, and install
  each skill by its direct repository ref.
- Edit shared guidance in `~/.apm/catalog/AGENTS.md`, `commands/**`, and `rules/**`
- Edit agents in `~/.apm/catalog/.apm/agents/<name>.agent.md`; `mise run apply` renders them with APM in a temporary project and places them atomically in `~/.claude/agents/<name>.md` and `~/.cursor/agents/<name>.md`, overwriting a differing copy and leaving other files alone (Codex and OpenCode receive none)
- `skills` are authored under `catalog/.apm/skills/**` and staged into the published package at the same path; do not recreate a top-level `catalog/skills/`
- `catalog/.apm/` holds only `skills/` and `agents/`: `prepare:catalog` rebuilds nothing else there, so `validate:catalog` and `prepare:catalog` stop when another primitive appears
- `commands/**` stays top-level because it is runtime-synced shared guidance, not nested skill package content
- Edit this directory directly, then run `mise run prepare:catalog` before commit/push
- Install ref: `jey3dayo/apm-workspace/catalog#main`
