---
name: codex-companion-scripts
description: Runtime assets (codex-companion.mjs, prompts, schema) backing the catalog's /codex:* commands. Not directly invocable.
user-invocable: false
disable-model-invocation: true
---

# Codex Companion Scripts

This skill is not meant to be invoked. It exists only to carry the `codex-companion.mjs` runtime, its `lib/` helpers, prompt templates, and the review-output schema to a stable deployed path: `~/.claude/skills/codex-companion-scripts/`.

The catalog's `commands/status.md`, `setup.md`, `rescue.md`, `cancel.md`, `review.md`, `result.md`, `adversarial-review.md` reference `${CLAUDE_PLUGIN_ROOT}/scripts/codex-companion.mjs`. Since those commands are deployed as plain files (not as an installed Claude Code plugin), `CLAUDE_PLUGIN_ROOT` is never set by Claude Code itself for them. `CLAUDE_PLUGIN_ROOT` is instead defined as a global default in `~/.claude/settings.json` `env`, pointing at this skill's deployed directory.

Source: vendored from `openai/codex-plugin-cc/plugins/codex/{scripts,prompts,schemas}` at the commit pinned when this skill was added. Re-sync manually from that upstream path if the companion script changes; there is no APM dependency tracking for this content because APM only resolves `skills/` subpaths, not arbitrary plugin directories.
