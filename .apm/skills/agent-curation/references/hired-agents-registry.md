# Hired External Agents Registry

This registry tracks external agent collections that were evaluated or curated into this APM workspace. It is an exploration index, not a runtime agent file.

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

| Local agent                               | Source path                                     | Selection reason                                                                                        | Status                                  |
| ----------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| `catalog/agents/frontend-developer.md`    | `engineering/engineering-frontend-developer.md` | General frontend implementation, UI integration, performance, accessibility, and test expectations.     | Curated into workspace-managed catalog. |
| `catalog/agents/ui-designer.md`           | `design/design-ui-designer.md`                  | Visual design systems, component visual language, UI specifications, and design handoff.                | Curated into workspace-managed catalog. |
| `catalog/agents/accessibility-auditor.md` | `testing/testing-accessibility-auditor.md`      | WCAG review, assistive technology testing plans, accessibility audit reports, and remediation guidance. | Curated into workspace-managed catalog. |

### Role Split

- Use `frontend-developer` for implementation and code review of frontend behavior.
- Use `ui-designer` for visual direction, design-system decisions, component specs, and handoff quality.
- Use `accessibility-auditor` for independent accessibility review and remediation planning.

### Refresh Notes

- Re-check upstream `HEAD` and license before refreshing.
- Keep curated agents shorter and more operational than upstream persona files.
- Preserve provenance in the local agent body so copied runtime targets remain traceable.
