# Curated Agents: Placement, Distribution & Sources

Entry-point memo for the curated agents under `catalog/agents/`. It records where curated agents live, how they are distributed, which upstreams they come from, and how to add a new one. Repo-level installability evaluation stays in the `agent-curation` skill registry; this file is the day-to-day placement guide.

## Placement & Distribution

- Location: `catalog/agents/<name>.md` — all curated / vendored agents live here.
- Distribution: the catalog rollout (`mise run deploy`) copies `catalog/agents/*` into each runtime target's `agents/` dir (`~/.claude/agents`, `~/.codex/agents`). `~/.agents` is a skills-only target and receives no agents.
- Formatting: `catalog/agents/` is listed in `.prettierignore`, so the formatter leaves curated agent files in their upstream-derived shape. Only our own generated artifacts get reformatted.

## Sources

Repo-level detail (APM-installability evidence, upstream Codex lane) lives in the registry:
`.apm/skills/agent-curation/references/hired-agents-registry.md`.

| Upstream repo                                   | Commit                                     | License                           |
| ----------------------------------------------- | ------------------------------------------ | --------------------------------- |
| <https://github.com/msitarzewski/agency-agents> | `24485830cd4b3c63a4a357b0664d9dedbab9653a` | MIT (2025 AgentLand Contributors) |

## Per-Agent Mapping

All rows below are curated (adapted) from `msitarzewski/agency-agents`: renamed and with frontmatter adjusted for Claude Code / Codex (`name`, `tools`, `color`); upstream `emoji` / `vibe` dropped. Not verbatim copies.

| Local agent (`catalog/agents/`) | Upstream path                                   | Consumed by             |
| ------------------------------- | ----------------------------------------------- | ----------------------- |
| `frontend-developer.md`         | `engineering/engineering-frontend-developer.md` | general frontend work   |
| `ui-designer.md`                | `design/design-ui-designer.md`                  | visual design / handoff |
| `accessibility-auditor.md`      | `testing/testing-accessibility-auditor.md`      | accessibility review    |

## Retired Agent Contracts

The following verbose persona agents were retired. Their useful contracts are integrated into owning guidance; no runtime agent is distributed for them.

| Retired local agent                 | Upstream path                                        | Integrated into                                      | Status                                                             |
| ----------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------ |
| `agency-evidence-collector.md`      | `testing/testing-evidence-collector.md`              | `review-board` Evidence Collector overlay            | Retired; visual/browser evidence discipline retained.              |
| `agency-reality-checker.md`         | `testing/testing-reality-checker.md`                 | `review-board` readiness judgement                   | Retired; evidence-based ship/block judgement retained.             |
| `agency-minimal-change-engineer.md` | `engineering/engineering-minimal-change-engineer.md` | `implementer` and `review-board` Review And Fix Loop | Retired; minimal evidence-supported diff retained.                 |
| `agency-test-results-analyzer.md`   | `testing/testing-test-results-analyzer.md`           | `review-board` evidence and readiness judgement      | Retired; test-result patterns and residual-risk handling retained. |

## Adding a Curated Agent

1. Place the adapted agent at `catalog/agents/<name>.md` (rename, trim upstream-specific assumptions).
2. Add one row to the Per-Agent Mapping above; add a new Sources row if the upstream repo is new.
3. For upstream evaluation (is it APM-installable?), follow the `agent-curation` skill and record repo-level findings in its registry.
4. Run `mise run deploy` to distribute.
