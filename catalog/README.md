# catalog

This directory contains the managed catalog for the global APM workspace.

- Edit personal skills in `~/.apm/catalog/.apm/skills/<id>/`
- Keep repository-specific or infrequently used skills in
  `~/.apm/optional-skills/<id>/` instead of this global catalog, and install
  each skill by its direct repository ref.
- Edit shared guidance in `~/.apm/catalog/AGENTS.md`, `commands/**`, and `rules/**`
- Edit agents in `~/.apm/catalog/.apm/agents/<name>.agent.md`; `mise run apply` renders them with APM in a temporary project and places them atomically in `~/.claude/agents/<name>.md` and `~/.cursor/agents/<name>.md`, overwriting a differing regular file and leaving other files alone (Codex and OpenCode receive none). A symlink there (for example into dotfiles) is kept when its content already matches; when it differs, apply stops before placing anything instead of cutting the link
- `skills` are authored under `catalog/.apm/skills/**` and staged into the published package at the same path; do not recreate a top-level `catalog/skills/`
- `catalog/.apm/` holds only `skills/` and `agents/`, and only what `prepare:catalog` rebuilds: regular files inside a skill directory (one holding `SKILL.md`) and agents named `agents/<name>.agent.md` directly under `agents/`. `validate:catalog` and `prepare:catalog` stop on anything else there (another primitive, a file outside a skill, another agent name, a symlink or special file, or an entry they cannot read)
- `commands/**` stays top-level because it is runtime-synced shared guidance, not nested skill package content
- Edit this directory directly, then run `mise run prepare:catalog` before commit/push
- Install ref: `jey3dayo/apm-workspace/catalog#main`
- `catalog/apm.yml` sets `targets: [claude, cursor, agent-skills]` so Codex receives no agents. A consumer that targets only `codex` therefore gets nothing from this package, not even skills (APM 0.35.0 fails `apm install <ref> --target codex`); include `agent-skills` in its targets (for example `--target codex,agent-skills`) to receive the skills under `.agents/skills`
