# catalog

This directory contains the managed catalog for the global APM workspace.

- Edit personal skills in `catalog/.apm/skills/<id>/`
- Keep repository-specific or infrequently used skills in
  `optional-skills/<id>/` instead of this global catalog, and install
  each skill by its direct repository ref.
- Edit shared guidance in `catalog/.apm/instructions/ai-collaboration.instructions.md` (the global guide; its body below the frontmatter is what every tool reads), `commands/**`, and `rules/**`. `catalog/AGENTS.md` is gone, and `validate:catalog` stops if it comes back. `catalog/commands` holds only `.gitkeep`, and native distribution does not deliver it
- The guide reaches each tool through APM: a user-scope install adds it as the Claude rule `~/.claude/rules/ai-collaboration.md`, and `native:apply` / `native:migrate` run `apm compile -g --clean` to write `~/.codex/AGENTS.md` and `~/.cursor/AGENTS.md`. APM never overwrites a root without its marker. A root that carries the marker and still matches its Build ID is APM output: compile rewrites it, and `--clean` removes an unedited Claude root once the rule covers it. If a Codex or Cursor root (or the file it links to) was edited after compile, the native tasks stop with an error instead of overwriting it; delete the marker line to keep the file as hand-written, or move it aside, then re-run. To keep your own edits, remove the marker line, and APM then treats the file as hand-written; in `~/.claude/CLAUDE.md` also remove the guide, which the rule provides. `native:opencode` copies the body to `~/.config/opencode/AGENTS.md` (OpenCode would otherwise fall back to `~/.claude/CLAUDE.md`) and never overwrites a hand-written file. Roots copied by the old path are described in the known issues of `docs/native-distribution.md`
- Edit agents in `catalog/.apm/agents/<name>.agent.md`; `native:apply` / `native:migrate` install them with `apm install -g`, and they reach Claude and Cursor (Codex and OpenCode receive none)
- `skills` are authored under `catalog/.apm/skills/**` and staged into the published package at the same path; do not recreate a top-level `catalog/skills/`
- `catalog/.apm/` holds only `skills/`, `agents/` and `instructions/ai-collaboration.instructions.md`: regular files inside a skill directory (one holding `SKILL.md`), agents named `agents/<name>.agent.md` directly under `agents/`, and that one instruction. `validate:catalog` stops on anything else there (another primitive, a file outside a skill, another agent name, a symlink or special file, or an entry they cannot read)
- `commands/**` stays top-level because it is shared guidance, not nested skill package content
- Edit this directory directly, then run `mise run check` before commit/push
- Install ref: `jey3dayo/apm-workspace/catalog#main`
- `catalog/apm.yml` sets `targets: [claude, cursor, agent-skills]` so Codex receives no agents. A consumer that targets only `codex` therefore gets nothing from this package, not even skills (APM 0.35.0 fails `apm install <ref> --target codex`); include `agent-skills` in its targets (for example `--target codex,agent-skills`) to receive the skills under `.agents/skills`
