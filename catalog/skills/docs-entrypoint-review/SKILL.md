---
name: docs-entrypoint-review
description: Review whether project entrypoint documentation needs updates before editing it. Use when the user asks to check docs drift or update docs after implementation, refactoring, configuration, operational workflow, UI rule, or design-system changes, or mentions CLAUDE.md, AGENTS.md, llms.txt, TODO.md, DESIGN.md, DESIGN_REVIEW.md, README.md, CHANGELOG.md, or docs/**. Default to proposing update candidates first instead of editing immediately.
---

# Docs Entrypoint Review

## Overview

Use this skill to decide which high-signal project entrypoint documents should be updated after a change. It is a router and review workflow, not a generic documentation writer.

Default behavior: inventory candidates, classify each as `update`, `skip`, or `ask`, and present the recommendation before editing. Edit only after the user confirms or explicitly asks for updates.

## Workflow

### 1. Understand the Change

Start from the newest concrete evidence available:

- user request and conversation context
- `git status` and `git diff`
- files changed by the current task
- related config, routes, commands, screens, or workflows

Summarize the change type before recommending documents: implementation, refactor, configuration, operations, UI rule, design system, release-visible behavior, or docs-only cleanup.

### 2. Inventory Entrypoint Documents

Look for existing documents before proposing edits. Check the repository root and obvious guidance directories for:

- `AGENTS.md`
- `CLAUDE.md`
- `llms.txt`
- `TODO.md`
- `DESIGN.md`
- `DESIGN_REVIEW.md`
- `README.md`
- `CHANGELOG.md`
- `docs/**`

Do not create a missing entrypoint document just because it is in this list. Propose creation only when the change clearly needs a durable home and no existing document owns it.

### 3. Classify Ownership

Use this routing table:

| Change or knowledge type                               | Primary document         |
| ------------------------------------------------------ | ------------------------ |
| Agent behavior, repo rules, development workflow       | `AGENTS.md`, `CLAUDE.md` |
| AI-facing index or short repository map                | `llms.txt`               |
| Unfinished work, follow-up tasks, known gaps           | `TODO.md`                |
| Durable reusable UI or visual-system rule              | `DESIGN.md`              |
| Design review process, routing, exceptions, escalation | `DESIGN_REVIEW.md`       |
| User-facing setup, usage, architecture, operations     | `README.md`, `docs/**`   |
| Release-visible behavior or user-facing change history | `CHANGELOG.md`           |

When `DESIGN.md` or `DESIGN_REVIEW.md` is involved, use `design-md-workflow` for the detailed design-document split. Keep durable visual rules in `DESIGN.md`; keep review flow, routing decisions, exceptions, and escalation in `DESIGN_REVIEW.md`; keep backlog or task notes in `TODO.md` or another task tracker.

When the task is broad documentation creation, update, or repair, hand off to `docs-manager`. Also use `docs-manager` when the task is metadata, tags, size, or link quality.

### 4. Recommend Before Editing

Before editing, produce a compact table:

| file     | judgment                  | reason                                      | proposed change              |
| -------- | ------------------------- | ------------------------------------------- | ---------------------------- |
| `<path>` | `update` / `skip` / `ask` | `<why this document is or is not affected>` | `<minimal edit or question>` |

Judgment rules:

- `update`: the change makes existing guidance stale or introduces reusable knowledge with a clear owner.
- `skip`: the document exists but the change does not alter its contract, audience, or source-of-truth content.
- `ask`: the document might need an update, but ownership, wording, or source of truth is ambiguous.

Prefer fewer, higher-confidence updates. Avoid spreading the same fact across multiple documents unless each document has a distinct audience.

### 5. Edit After Confirmation

When editing is confirmed:

- preserve the existing document language, structure, and level of detail
- make the smallest durable update
- do not turn a local implementation detail into broad policy
- do not move facts between documents unless the current location is clearly wrong
- run the repository's relevant format, check, or test task when available

Report what changed, what was intentionally skipped, and any remaining `ask` items.

## Review Checklist

Before finishing, verify:

- every proposed update maps to a clear owner document
- skipped documents have a concrete reason, not just "not touched"
- `DESIGN.md` content is reusable visual guidance, not process or backlog
- `TODO.md` contains only unfinished work or follow-up tasks
- `AGENTS.md` / `CLAUDE.md` changes affect agent or developer behavior, not ordinary prose
- `llms.txt` remains a short index, not a full runbook
