---
name: codex-system
description: |
  Consult Codex CLI for non-trivial decisions when the local answer is uncertain,
  trade-off heavy, or worth a second opinion. Use it for design choices,
  implementation approaches, debugging strategies, refactoring plans, and code review.
  Do not consult for obvious single-step edits or rote execution.
  Explicit triggers: "think deeper", "analyze", "second opinion", "consult codex".
metadata:
  short-description: Claude Code ↔ Codex CLI collaboration
---

# Codex System — Deep Reasoning Partner

## Codex CLI is your deep-reasoning fallback for non-trivial decisions

This skill is self-contained. If an external delegation rule file is missing,
follow the guidance in this file and the local `references/` templates only.

## Context Management (CRITICAL)

### Prefer a Fresh Subagent When the Runtime Supports It

| Situation                              | Method                       |
| -------------------------------------- | ---------------------------- |
| Detailed design consultation           | Fresh subagent (recommended) |
| Debug analysis                         | Fresh subagent (recommended) |
| Short questions (1-2 sentence answers) | Direct call OK               |

## When to Consult

| Situation              | Trigger Examples                       |
| ---------------------- | -------------------------------------- |
| Design decisions       | "How to design?" "Architecture"        |
| Debugging              | "Why doesn't it work?" "Error" "Debug" |
| Trade-off analysis     | "Which is better?" "Compare" "Which?"  |
| Complex implementation | "How to implement?" "How to build?"    |
| Refactoring            | "Refactor" "Simplify"                  |
| Code review            | "Review this" "Check this"             |

## When NOT to Consult

- Simple file edits, typo fixes
- Following explicit user instructions
- git commit, running tests, linting
- Tasks with obvious single solutions

## How to Consult

### Recommended: Fresh Subagent Pattern

Use a fresh subagent when your runtime provides one. Keep the main thread focused
on the current task and let the subagent return a concise recommendation.

```
Subagent prompt:
Consult Codex about: {topic}

Run:
codex exec --sandbox read-only "
{question for Codex}
" 2>/dev/null

Return a concise summary:
- recommendation
- rationale
- risks / alternatives
```

Runtime note:

- Claude Code: use its Task/subagent facility if available
- Codex desktop/app runtimes: use the runtime's fresh agent / `spawn_agent` equivalent if available
- If no subagent facility exists, use the direct-call path below

### Direct Call (Short Questions Only)

For quick questions expecting 1-2 sentence answers:

```bash
codex exec --sandbox read-only "Brief question" 2>/dev/null
```

### Workflow (Subagent)

1. Start a fresh subagent for this consultation
2. Continue your work → Subagent runs in parallel
3. Receive summary → Subagent returns concise insights

### Session Continuity

Codex sessions are stored per CWD.
The review skills (`codex-code-review`, `codex-plan-review`) can use
`resume --last` to inherit context from a prior Codex consultation in the same CWD.

If there was no prior consultation for the same task in the same CWD,
start fresh instead of resuming.

### Quick Reference

| Use Case                    | Sandbox Mode      | Command Pattern                                         |
| --------------------------- | ----------------- | ------------------------------------------------------- |
| Analysis, review, debug     | `read-only`       | `codex exec --sandbox read-only "..." 2>/dev/null`      |
| Implementation, refactoring | `workspace-write` | `codex exec --full-auto "..." 2>/dev/null`              |
| Resume previous session     | Inherited         | `echo "prompt" \| codex exec resume --last 2>/dev/null` |

> **Note**: resume 時は `--sandbox` を指定できない（セッション元の設定が自動的に引き継がれる）。`--full-auto`, `--all` 等のフラグは指定可能。

## Language Protocol

1. Ask Codex in **English**
2. Receive response in **English**
3. Execute based on advice (or let Codex execute if that path was chosen intentionally)
4. Report to user in **their preferred language**

## Task Templates

### Design Review

```bash
codex exec --sandbox read-only "
Review this design approach for: {feature}

Context:
{relevant code or architecture}

Evaluate:
1. Is this approach sound?
2. Alternative approaches?
3. Potential issues?
4. Recommendations?
" 2>/dev/null
```

### Debug Analysis

```bash
codex exec --sandbox read-only "
Debug this issue:

Error: {error message}
Code: {relevant code}
Context: {what was happening}

Analyze root cause and suggest fixes.
" 2>/dev/null
```

### Code Review

Use `references/code-review-task.md` if it exists; otherwise use the inline review framing above.

### Refactoring

Use `references/refactoring-task.md` if it exists; otherwise adapt the direct-call template above.

## Integration with Gemini

| Task                | Use                              |
| ------------------- | -------------------------------- |
| Need research first | Gemini → then Codex              |
| Design decision     | Codex directly                   |
| Library comparison  | Gemini research → Codex decision |

## Selection Rule

- Fresh subagent: choose for design, debugging, trade-off analysis, and other consultations where you want a concise sidecar answer
- Direct call: choose for short questions expecting a 1-2 sentence answer
- No consultation: choose for typo fixes, rote edits, explicit user instructions with an obvious path, and routine git/test/lint work
