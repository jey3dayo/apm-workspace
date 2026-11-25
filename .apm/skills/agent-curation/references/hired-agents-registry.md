# Hired External Agents Registry

This registry tracks external agent collections that were evaluated or curated into this APM workspace. It is an exploration index, not a runtime agent file.

## cursor/plugins (pstack)

- Repository: `https://github.com/cursor/plugins`
- Observed commit: `ca782ed8b3c2c521cead8e1720d55c3a5dbf2347` (pstack v0.15.48)
- License: MIT, copyright `2026 Lauren Tan`
- APM direct dependency status: the pstack skills are directly installable as subdirectory skill pins (verified 2026-11-25 in an isolated APM project: `apm install` of the five pins below succeeded and integrated each into `.agents/skills/` and `.claude/skills/`). The agents are not: APM distributes skills, and `pstack/agents/*.md` are plain agent files with no `.agent.md` package shape, so the one agent `no-comments` needs is curated into the catalog instead.
- Pinned skills (root `apm.yml`): `no-comments`, `why`, `architect`, `principle-fix-root-causes`, `principle-redesign-from-first-principles` — the target skill plus the ones it and `comment-sicko` directly reference. Added 2026-11-25 at the same commit: `reframe` and `sharpen`, a standalone pair the user asked for (reframe teaches the expert words for a vague description; sharpen deepens a task before rewriting its prompt).
- Not pinned: `poteto-mode` (a whole operating style whose autonomy and reply rules conflict with this workspace's own orchestrator policy, and whose model selection depends on Cursor-only `~/.cursor/rules/pstack-models.mdc` written by `setup-pstack`) and `arena` (an optional branch from `architect` that pulls in `poteto-mode` and further principles). `no-comments` references `poteto-mode` only for subagent reasoning-level selection; that is covered here by the `orchestrator-worker` models reference.

### Hired Agents

| Local agent                                  | Source path                      | Selection reason                                                                                                      | Status                                  |
| -------------------------------------------- | -------------------------------- | --------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| `catalog/.apm/agents/comment-sicko.agent.md` | `pstack/agents/comment-sicko.md` | The worker the `no-comments` skill spawns: deletes comments in scope and flags symbols that must be reshaped instead. | Curated into workspace-managed catalog. |

### Related Candidates

- The remaining pstack skills (52 of 59 total) were not adopted. Revisit individually if a workflow needs one; do not bulk-import the bundle.
- `pstack/agents/poteto-agent.md` was not hired: it is the general worker for `poteto-mode`, which is not adopted.

## msitarzewski/agency-agents

- Repository: `https://github.com/msitarzewski/agency-agents`
- Observed commit: `24485830cd4b3c63a4a357b0664d9dedbab9653a`
- License: MIT, copyright `2025 AgentLand Contributors`
- APM direct dependency status: not directly installable as observed on 2026-06-30.
- APM evidence:
  - `apm install msitarzewski/agency-agents` failed because the root has no `apm.yml`, `SKILL.md`, hooks, `.apm/`, or `plugin.json`.
  - `apm install msitarzewski/agency-agents/integrations/codex` failed because the subdirectory is not an APM package or Claude skill.
  - `apm install msitarzewski/agency-agents/engineering` failed for the same package-shape reason.
  - `apm install --dry-run msitarzewski/agency-agents/engineering/engineering-frontend-developer.md` rejected the plain `.md` file because APM virtual file installs require `.prompt.md`, `.instructions.md`, `.chatmode.md`, or `.agent.md`.
- Upstream Codex lane: upstream generates `.codex/agents/*.toml` through `./scripts/convert.sh --tool codex` and installs with `./scripts/install.sh --tool codex`; this writes to runtime targets outside the APM workspace source-of-truth lane.

### Hired Agents

| Local agent                                          | Source path                                     | Selection reason                                                                                        | Status                                  |
| ---------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| `catalog/.apm/agents/frontend-developer.agent.md`    | `engineering/engineering-frontend-developer.md` | General frontend implementation, UI integration, performance, accessibility, and test expectations.     | Curated into workspace-managed catalog. |
| `catalog/.apm/agents/ui-designer.agent.md`           | `design/design-ui-designer.md`                  | Visual design systems, component visual language, UI specifications, and design handoff.                | Curated into workspace-managed catalog. |
| `catalog/.apm/agents/accessibility-auditor.agent.md` | `testing/testing-accessibility-auditor.md`      | WCAG review, assistive technology testing plans, accessibility audit reports, and remediation guidance. | Curated into workspace-managed catalog. |

### Retired Agent Contracts

These upstream persona files were evaluated at the repository and commit recorded above, then retired as standalone runtime agents. Only their concise, owning guidance contracts remain.

| Former local agent                                 | Source path                                          | Integrated into                                                          | Status                                                    |
| -------------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------- |
| `catalog/agents/agency-evidence-collector.md`      | `testing/testing-evidence-collector.md`              | `optional-skills/review-board/SKILL.md` Evidence Collector overlay       | Retired; visual and browser evidence discipline retained. |
| `catalog/agents/agency-reality-checker.md`         | `testing/testing-reality-checker.md`                 | `optional-skills/review-board/SKILL.md` readiness judgement              | Retired; evidence-based ship/block judgement retained.    |
| `catalog/agents/agency-minimal-change-engineer.md` | `engineering/engineering-minimal-change-engineer.md` | `catalog/.apm/agents/implementer.agent.md` and Review And Fix Loop       | Retired; minimal evidence-supported diffs retained.       |
| `catalog/agents/agency-test-results-analyzer.md`   | `testing/testing-test-results-analyzer.md`           | `optional-skills/review-board/SKILL.md` evidence and readiness judgement | Retired; test-result patterns and residual risk retained. |

### Role Split

- Use `frontend-developer` for frontend implementation and verification of its own changes.
- Use `ui-designer` for visual direction, design-system decisions, component specs, and handoff quality.
- Use `accessibility-auditor` for independent accessibility review and remediation planning.

### Refresh Notes

- Re-check upstream `HEAD` and license before refreshing.
- Keep curated agents shorter and more operational than upstream persona files.
- Preserve provenance in the local agent body so copied runtime targets remain traceable.
