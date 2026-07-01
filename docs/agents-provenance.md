# Vendored Agents Provenance

## Purpose

Records the upstream source of vendored agents under `catalog/agents/`. APM cannot install these as packages (they are loose Markdown files in an upstream repo, not APM packages), so they are vendored into the managed catalog and distributed through the normal catalog rollout (`mise run deploy` / `apply`). This file is the source-of-truth for where each vendored agent came from, so it can be audited and re-vendored later.

This file lives outside `catalog/agents/` on purpose: the deploy step copies the entire contents of `catalog/agents/` into each target, so any provenance file placed there would be distributed as if it were an agent.

## Agency Agents

- Upstream repo: <https://github.com/msitarzewski/agency-agents>
- Branch: `main` (no pinned ref; vendored copies, adapted locally)
- Local adaptation: file renamed to the `agency-*` prefix; frontmatter `name` aligned to the file name, `tools`/`color` set for Claude Code.
- Consumed by: the `review-board` skill Persona Overlays (`catalog/skills/review-board/SKILL.md`).

| Vendored file (`catalog/agents/`)   | Upstream path                                        |
| ----------------------------------- | ---------------------------------------------------- |
| `agency-evidence-collector.md`      | `testing/testing-evidence-collector.md`              |
| `agency-reality-checker.md`         | `testing/testing-reality-checker.md`                 |
| `agency-test-results-analyzer.md`   | `testing/testing-test-results-analyzer.md`           |
| `agency-minimal-change-engineer.md` | `engineering/engineering-minimal-change-engineer.md` |

## Re-vendoring

To refresh from upstream, fetch the source file, re-apply the local adaptation (rename to `agency-*`, align frontmatter), and overwrite the file under `catalog/agents/`. Then run the normal catalog rollout to redeploy.
