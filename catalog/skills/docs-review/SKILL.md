---
name: docs-review
description: Review which project entrypoint documents drifted after a change and propose update candidates before editing. Use when the user asks to check docs drift, update docs after a change, or mentions CLAUDE.md, AGENTS.md, llms.txt, TODO.md, DESIGN.md, DESIGN_REVIEW.md, README.md, CHANGELOG.md, or docs/**.
---

# Docs Entrypoint Review

Decide which high-signal entrypoint documents drifted from the change, then propose before editing. Edit only after the user confirms or explicitly asked for updates up front.

## Workflow

### 1. Understand the Change

Start from the newest concrete evidence: user request, `git status` / `git diff`, files changed by the current task, and related config, routes, commands, screens, or workflows.

Done when the change is summarized as one type: implementation, refactor, configuration, operations, UI rule, design system, release-visible behavior, or docs-only cleanup.

### 2. Inventory Entrypoint Documents

Check the repository root and obvious guidance directories for: `AGENTS.md`, `CLAUDE.md`, `llms.txt`, `TODO.md`, `DESIGN.md`, `DESIGN_REVIEW.md`, `README.md`, `CHANGELOG.md`, `docs/**`.

Propose creating a missing document only when the change needs a durable home and no existing document owns it.

Done when every existing entrypoint document is listed as a candidate.

### 3. Classify Ownership

Route each piece of knowledge to its owner document:

| Change or knowledge type                                | Owner                    |
| ------------------------------------------------------- | ------------------------ |
| Agent behavior, repo rules, development workflow        | `AGENTS.md`, `CLAUDE.md` |
| AI-facing index or short repository map (not a runbook) | `llms.txt`               |
| Unfinished work, follow-up tasks, known gaps            | `TODO.md`                |
| Durable reusable UI or visual-system rule               | `DESIGN.md`              |
| Design review process, routing, exceptions, escalation  | `DESIGN_REVIEW.md`       |
| User-facing setup, usage, architecture, operations      | `README.md`, `docs/**`   |
| Release-visible behavior or user-facing change history  | `CHANGELOG.md`           |

Hand off instead of routing here when:

- `DESIGN.md` / `DESIGN_REVIEW.md` split details are the subject → `design-md-workflow`
- broad documentation creation, repair, metadata, tags, size, or link quality → `docs-manager`

### 4. Recommend Before Editing

Produce a compact table:

| file     | judgment                  | reason                                      | proposed change              |
| -------- | ------------------------- | ------------------------------------------- | ---------------------------- |
| `<path>` | `update` / `skip` / `ask` | `<why this document is or is not affected>` | `<minimal edit or question>` |

Judgment rules:

- `update`: the change made existing guidance drift, or introduced reusable knowledge with a clear owner.
- `skip`: the document exists but its contract, audience, and source-of-truth content are unaffected — name the concrete reason, not just "not touched".
- `ask`: ownership, wording, or source of truth is ambiguous.

Prefer fewer, higher-confidence updates. Keep each fact in one owner document unless another document serves a distinct audience.

Done when every inventoried document has a judgment and a reason.

### 5. Edit After Confirmation

When editing is confirmed:

- preserve the existing document language, structure, and level of detail
- make the smallest durable update; keep local implementation detail local, not broad policy
- move a fact between documents only when the current location is clearly the wrong owner
- run the repository's relevant format, check, or test task when available

Done when the report states what changed, what was skipped and why, and any remaining `ask` items.
