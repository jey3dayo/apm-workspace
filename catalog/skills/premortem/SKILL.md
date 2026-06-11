---
name: premortem
description: Use when planning, requirements, design, estimation, or task decomposition needs pre-implementation failure prediction, blind-spot discovery, planning review, design validation, or answers to "what could go wrong" / "what am I missing". Use before implementation begins.
---

# Premortem Analysis

Premortem analysis assumes the project has failed and works backward to identify the likely causes before implementation starts. The output is a short set of high-signal risks, evidence from the repository, and concrete decisions or follow-up work.

## Use This Skill When

- A user asks for `premortem`, planning review, design validation, "what could go wrong", or "what am I missing".
- A plan, spec, task decomposition, architecture proposal, or release strategy exists but implementation has not started.
- The risk is cross-cutting: security, reliability, migration, operations, compliance, cost, data integrity, or reversibility.
- A team is about to commit to technology selection or scope estimates.

Do not use it as a post-implementation code review. Use `predictive-analysis`, `code-review`, or project-specific review skills after code exists.

## Output Contract

For auto mode, return this shape:

```markdown
## Premortem

### Context

- Domain:
- Maturity:
- Tech stack:
- Scale:
- Evidence:

### Findings

| Risk            | Status                                                   | Severity                       | Evidence             | Recommended next action |
| --------------- | -------------------------------------------------------- | ------------------------------ | -------------------- | ----------------------- |
| <failure cause> | Covered / Needs Clarification / Missing / Not Applicable | Critical / High / Medium / Low | <file or user input> | <small next action>     |

### Questions

1. <question> - Why it matters: <one line>

### Next Actions

1. <highest-priority action>
```

Ask about GitHub Issue creation only after the report is complete, and never create issues without explicit user approval.

## Modes

Choose the mode from the user's request. If no mode is specified, use auto mode.

| Mode        | Use when                                                        | First response                                            |
| ----------- | --------------------------------------------------------------- | --------------------------------------------------------- |
| Auto        | Repo context is available or the user wants fast risk discovery | Run analysis and return the report                        |
| Batch       | The user wants to answer questions before analysis              | Present all 3-5 questions with "Why it matters"           |
| Interactive | The user wants a discussion                                     | Ask one question at a time, max 2 follow-ups per question |

### Auto Mode

1. Infer context from user input and repository files.
2. Select 3-5 premortem questions.
3. Answer each question from available evidence.
4. Classify gaps.
5. Return prioritized risks and next actions.

Auto mode is report-only by default. GitHub Issue registration is an optional follow-up that requires explicit confirmation.

### Batch Mode

First response must only present all questions.

For each question include:

- question title
- concrete question text
- one-line "Why it matters"

Do not auto-answer, run gap analysis, or ask about GitHub Issues until the user has answered.

### Interactive Mode

Ask one question at a time. For each answer:

- detect missing concepts
- ask at most 2 follow-ups
- then move to the next question

Generate the report after all questions have been answered or the user asks to stop.

## Context Gathering

Use cheap local evidence first.

Priority:

1. user-provided project description, plan, spec, issue, or design document
2. `README.md`, `AGENTS.md`, `CLAUDE.md`
3. `.kiro/steering/*.md`, `.kiro/specs/**`, `docs/**`
4. dependency manifests such as `package.json`, `requirements.txt`, `pyproject.toml`, `Cargo.toml`, `go.mod`
5. code search for implementations relevant to selected questions

Use `rg` or the repository's preferred search wrapper. Load reference files only when the selected domain needs them.

If no repository path or project files are available, use the user input as the only evidence. Do not imply that workflows, manifests, or implementation files exist; classify those details as `Missing` or `Needs Clarification`.

## Context Model

Summarize the project as:

```python
@dataclass
class ProjectContext:
    domain: str
    maturity: str
    tech_stack: list[str]
    scale: str
    description: str
    evidence: list[str]
```

### Inference Hints

- Domain: infer from stack and keywords (`React` / `API` -> web-development, `Swift` / `iOS` -> mobile-apps, `Spark` / `ETL` -> data-systems, `LLM` / `RAG` / `ML` -> ai-ml).
- Maturity: `poc`, `prototype`, `MVP`, `beta`, `production`, `enterprise`.
- Scale: use explicit user counts/data volume when available; otherwise mark unknown.
- Evidence: cite file paths or "user input"; do not invent evidence.
- Unknowns: write `unknown` or a bounded phrase such as `release planning, production readiness unknown`; set severity from blast radius, not from guessed maturity.

## Question Selection

Select 3-5 questions from:

- `references/questions/generic.yaml` (architecture, security, reliability, cost, monitoring, testing, delivery, reversibility, dependencies)
- `references/questions/web-development.yaml`
- `references/questions/mobile-apps.yaml`
- `references/questions/data-systems.yaml`
- `references/questions/infrastructure.yaml`
- `references/questions/security.yaml`
- `references/questions/ai-ml.yaml`

Technical risk is not the only failure mode. When the plan involves deadlines, multiple teams, or unsettled scope, include at least one `delivery` question from `generic.yaml`.

Prefer questions with:

- direct trigger keyword match
- domain relevance
- maturity relevance
- tech-stack relevance
- high blast radius if missed

Avoid overloading one category. As a default, use no more than 2 questions from the same category unless the project is clearly dominated by that area.

### Context-Specific Risk Lenses

After selecting general questions, add or swap in risks that match the project shape.

| Signal                                                 | Premortem lens                                                                                 |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| Desktop, Tauri, Electron, installer, release artifacts | platform matrix, signing/notarization, install-and-launch smoke tests, rollback/unpublish path |
| Local-first data, sync, cache, import/export           | invariants, partial writes, idempotency, corruption recovery, backup/restore                   |
| Auth, sessions, permissions, identity                  | authorization boundary, expiry/revocation, privilege changes, audit trail                      |
| Data import, migration, ETL                            | validation boundary, partial failure policy, lineage, replay, rollback                         |
| CI/CD, release flow, deployment                        | gates, secrets, artifact provenance, environment drift, observability                          |
| LLM features, RAG, agents, ML models                   | output quality evaluation, hallucination handling, prompt injection, provider fallback, cost   |
| Hard deadline, multi-team, unsettled scope             | scope cut line, estimation basis, external-team waits, key-person risk, change process         |

Use these as prompts for question selection, not as a fixed checklist. Only include a lens when the user input or repository evidence supports it.

## Gap Classification

Classify each selected question with this rubric:

| Status              | Meaning                                                                                        |
| ------------------- | ---------------------------------------------------------------------------------------------- |
| Covered             | Evidence clearly answers the question and includes operational detail                          |
| Needs Clarification | Evidence partially answers it but leaves a decision, owner, threshold, or failure mode unclear |
| Missing             | No useful evidence found                                                                       |
| Not Applicable      | The project context makes the question irrelevant                                              |

Severity:

- Critical: likely security incident, data loss, irreversible migration failure, compliance breach, or production outage.
- High: likely major rework, customer-visible failure, operational blind spot, or launch blocker.
- Medium: meaningful cost, maintainability, or delivery risk.
- Low: useful improvement with limited blast radius.

## Question Format

```markdown
## Q1: Authentication and authorization boundary

Is the authentication and authorization strategy explicit enough to implement safely?

- Which identity provider or session model is used?
- Where is authorization enforced?
- How are token/session expiry and revocation handled?
- What audit trail is required?

Why it matters: Auth decisions are expensive to retrofit and failures create direct security exposure.
```

Keep questions concrete enough that an answer can be classified as Covered / Needs Clarification / Missing.

## Recommended Action Rules

Good recommendations are small and assignable.

- Prefer "document the decision in `<path>`" over "think about architecture".
- Prefer "add rollback criteria before migration" over "ensure safety".
- Include the missing decision, owner, threshold, or artifact.
- Do not recommend broad rewrites unless the risk is structural.

## Scripts

Use scripts when available and helpful; otherwise perform the workflow manually with repository search.

```bash
python3 scripts/analyze_context.py \
  --input "project description" \
  --files "package.json,README.md" \
  --output context.json \
  --questions-dir references/questions/

python3 scripts/gap_analyzer.py \
  --questions context.json \
  --output gaps.json \
  --project-root .

python3 scripts/format_report.py \
  --session gaps.json \
  --output report.md
```

GitHub Issue creation is optional and must be approved:

```bash
python3 scripts/github_integration.py \
  --gaps gaps.json \
  --mode critical_high \
  --dry-run
```

Run a dry run first. Only create issues when the user explicitly approves the exact mode.

## Integration Notes

- With spec/design workflows: run premortem after design is drafted and before task breakdown.
- With task-router workflows: use premortem before assigning implementation subtasks for complex or high-risk work.
- With CI/release workflows: focus questions on rollback, observability, secrets, migration, and owner handoff.

## Common Failure Modes

| Failure                                               | Correction                                                        |
| ----------------------------------------------------- | ----------------------------------------------------------------- |
| Asking generic questions                              | Tie each question to domain, maturity, stack, and evidence.       |
| Treating absence of docs as absence of implementation | Search code when the selected risk could be implemented silently. |
| Creating issues too early                             | Report first; ask once after the report.                          |
| Over-indexing on scripts                              | Use scripts as helpers, not as a reason to skip judgment.         |
| Skipping Not Applicable                               | Mark irrelevant risks explicitly so the report stays focused.     |

## Progressive Disclosure

Keep the initial read small:

- Load `SKILL.md` first.
- Load question YAML only for the selected domain plus `generic`.
- Load framework references only when domain inference or scoring is unclear.
- Load scripts only when executing the scripted workflow.

## References

- `references/frameworks/analysis-flow.md` for question generation details.
- `references/frameworks/domain-detection.md` for domain detection details.
- `references/questions/*.yaml` for the question pool.
- `references/examples/*.yaml` for example sessions.
