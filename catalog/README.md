# catalog

This directory contains the managed catalog for the global APM workspace.

## Authoring

- Edit personal skills in `catalog/.apm/skills/<id>/`
- Keep repository-specific or infrequently used skills in
  `optional-skills/<id>/` instead of this global catalog, and install
  each skill by its direct repository ref.
- Edit shared guidance in `catalog/.apm/instructions/ai-collaboration.instructions.md` (the global guide), `commands/**`, and `rules/**`. `catalog/AGENTS.md` is gone, and `validate:catalog` stops if it comes back. `catalog/commands` holds only `.gitkeep`, and native distribution does not deliver it
- `catalog/.apm/instructions/claude-md-design.instructions.md` uses `applyTo` for edits to the catalog instructions.
- Edit agents in `catalog/.apm/agents/<name>.agent.md`; see [`docs/agents-provenance.md`](../docs/agents-provenance.md) for sources and distribution.
- `skills` are authored under `catalog/.apm/skills/**` and staged into the published package at the same path; do not recreate a top-level `catalog/skills/`
- `catalog/.apm/` holds only `skills/`, `agents/`, `instructions/ai-collaboration.instructions.md` and `instructions/claude-md-design.instructions.md`: regular files inside a skill directory (one holding `SKILL.md`), agents named `agents/<name>.agent.md` directly under `agents/`, and those two instructions. `validate:catalog` stops on anything else there (another primitive, a file outside a skill, another agent name, another instruction, a symlink or special file, or an entry they cannot read)
- `commands/**` stays top-level because it is shared guidance, not nested skill package content
- Edit this directory directly, then run `mise run check` before commit/push

## Distribution

- The global guide reaches Claude as a rule, Codex and Cursor as compiled roots, and OpenCode through a separate sync stage. The scoped `claude-md-design` instruction reaches Claude as a rule; global compile omits it from Codex and Cursor roots. See [`docs/native-distribution.md`](../docs/native-distribution.md) for delivery and recovery.
- APM does not overwrite a root without its marker. `native:sync` stops when an APM-marked Codex or Cursor root, including its linked file, was edited after compile. To keep it as hand-written, remove the marker, or move the file aside before re-running. For a hand-written `~/.claude/CLAUDE.md`, also remove the global guide from the file because the Claude rule supplies it.
- Install ref: `jey3dayo/apm-workspace/catalog#main`
- `catalog/apm.yml` sets `targets: [claude, cursor, agent-skills]` so Codex receives no agents. A consumer that targets only `codex` therefore gets nothing from this package, not even skills (APM 0.35.0 fails `apm install <ref> --target codex`); include `agent-skills` in its targets (for example `--target codex,agent-skills`) to receive the skills under `.agents/skills`
