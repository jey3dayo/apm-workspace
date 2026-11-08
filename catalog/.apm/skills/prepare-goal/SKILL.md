---
name: prepare-goal
description: "Use when the user wants help deciding, writing, or automatically starting a `/goal`; gives rough intent, implementation/fix/proceed instructions, incremental next-step instructions, issue text, plans, TODOs, review notes, or asks what the practical landing point should be."
---

# Prepare Goal

Convert messy intent into a verifiable goal contract before a long-running agent loop. A good goal has one objective, bounded scope, explicit constraints, observable evidence, and a stop rule. Do not treat `/goal` as a place for discovery-only work or a loose backlog.

## Workflow

1. Read the current context
   - Use the conversation, referenced issue, plan, TODO, logs, or repo guidance already available. If repo context matters, inspect the smallest relevant files first: `AGENTS.md`, task files, package scripts, CI definitions, current diff/status, or the named module.
   - Treat a small next step such as "continue", "same thing", or "this too" as a clue to infer the larger intended outcome, not as the whole goal.
   - Do not invent validation commands. Use only commands already known from context or discovered in repo scripts/docs; otherwise use artifact/manual evidence or mark the missing command as an open question.
   - When the request comes from PR comments, issue text, CI logs, or review threads, carry the source constraints into the goal: known comment IDs, failing job/check names, failing commands, explicit non-goals, requested retry limits.

2. Infer the nearest durable objective
   - Separate the immediate instruction from the likely higher-level objective behind it, and prefer the nearest practical landing point that can be completed, verified, and reported in one agent run.
   - Separate facts already in context from assumptions and execution-time lookups. If links, branches, commands, or outputs are not known yet, require the future agent to resolve and report them.
   - State the inference briefly so the user can correct it, and list key assumptions that affect scope, verification, or stop conditions.
   - If multiple materially different higher-level goals are plausible, do not guess silently: ask at most two blocking questions or propose a smaller first goal.

3. Classify readiness and pick the execution mode
   - Readiness: `ready` (one objective, known scope, clear validation evidence) / `needs-clarification` (one or two missing facts) / `not-goal-ready` (broad discovery, product judgment, architecture exploration, unrelated backlog).
   - Mode `auto-start` is the default when readiness is `ready` and the message is action-oriented: "implement", "fix", "continue", "next", "proceed", "do this", "set a goal", "run the goal command", "goal and proceed".
   - Mode `draft-only` only when the user explicitly asks to draft, write, review, prepare, or copy a goal without starting work (draft-only, copy-only, "do not start", review wording only). In draft-only mode, minimal read-only context inspection is fine, but do not edit files, run validation commands, create the goal, or start implementation.
   - Ambiguous messages: prefer `draft-only` for review-like requests, `auto-start` for action-like requests.

4. Normalize the objective
   - Exactly one durable objective, outcome wording over activity wording: "auth migration is complete", not "work on auth migration".
   - Split unrelated objectives into separate goals.

5. Split execution into minimal task units
   - Each unit has one owner, one local outcome, one evidence point (e.g. inspect context, update one skill section, run one validation command, review the diff).
   - Split when items have different user-visible outcomes, validation evidence, or source constraints, or complete independently. Bundle 2-3 tightly related edits that share the same failing behavior, validation command, review thread, module, or outcome. Do not merge unrelated backlog items just because they share source material.
   - Order units so each step's evidence guides the next. If the first unit is discovery, bound it to named files, issues, diffs, logs, or scripts; do not make open-ended discovery the whole goal.

6. Define the contract and check auditability
   - Scope (in-bounds files/modules/commands/issues), constraints (must-not-change files, behavior, APIs, secrets, workflows), ordered task sequence, done-when evidence, verification (known commands separated from artifacts/reports; deployment/push/remote checks conditional unless required), stop rule (repeated failure, missing permission, high-risk action, unclear requirement, budget).
   - The completion judge must be able to decide from evidence reported in the conversation: command names, exit status, changed files, remaining risks, and which task units were completed/skipped/blocked. For long-running work require step reports in this shape: `Step N: <unit> -> completed/skipped/blocked; evidence: <command, file, artifact, or observation>; next: <next unit or stop reason>`.

## Goal Sentence Template

Both modes use the same single-command shape:

```text
<one objective>. Done means <observable end state>. Scope: <allowed scope>. Task sequence: <ordered minimal task units, each with a local outcome and evidence point>. Constraints: <non-goals and forbidden changes, including source constraints from PR/issue/CI/review context>. Verification commands: <known commands only, or "none known">. Verification artifacts/reports: <evidence the agent must surface, including completed/skipped/blocked task units>. Stop if <same root cause fails 3 times, requested retry limit is reached, blockers, risky actions, or budget>.
```

## Output Format

Start every response with this header:

```text
Goal readiness: <ready / needs-clarification / not-goal-ready>
Execution mode: <auto-start / draft-only>   (only when ready)

Why:
- <short reason>
- Immediate request: <what the user explicitly asked for>
- Inferred landing point: <nearest durable objective>
- Key assumptions: <scope or validation assumptions, or "none">
```

### Auto-start mode

Do not print a paste-ready `/goal` block or ask the user to paste anything. After the header, show `Starting goal:` followed by the goal sentence, create the goal through the active goal mechanism when available (calling the goal-creation tool is expected behavior, not optional), then start execution in the same turn unless a stop condition is already true. If no goal-creation tool exists in the environment, treat the `Starting goal` text as the active contract and start work under it.

### Draft-only mode

After the header, print the goal as `Paste-ready /goal:` plus an audit checklist (objective singular / scope bounded / task sequence minimal and ordered / done state observable / verification explicit / stop conditions explicit — yes/no each), any blocking open questions, then finish with a separate final block:

````markdown
Final /goal command:

```text
/goal <goal sentence, with no prefix text inside the block>
```
````

Stop immediately after the final block. No follow-up implementation narration, no announcing that work is starting, no task loop.

### Not ready

When readiness is `needs-clarification` or `not-goal-ready`, do not include any `/goal` block. After the header, give the next best step (clarification question, task split, research step, or a smaller first goal) and at most two blocking questions.

## Examples

Action request, ready:

```text
Fix auth all the way through.
```

```text
Goal readiness: ready
Execution mode: auto-start

Why:
- The request asks for a fix and the landing point is a bounded module repair.
- Immediate request: fix auth.
- Inferred landing point: auth module repair is complete and verified.
- Key assumptions: `npm test -- test/auth` and `npm run lint` are the validation commands.

Starting goal:
Auth module repair is complete. Done means the failing auth behavior is fixed, all call sites in scope still use the intended public API, `npm test -- test/auth` exits 0, `npm run lint` exits 0, and the final report lists changed files plus verification output. Scope: auth module and directly related tests only. Task sequence: inspect the failing auth behavior and relevant tests; apply the smallest auth-module fix with direct test coverage; run the named auth test and lint commands; review the diff for unrelated changes. Constraints: do not change public route behavior, do not modify unrelated snapshots, do not edit secret or environment files. Verification commands: `npm test -- test/auth`, `npm run lint`. Verification artifacts/reports: changed-file list, per-unit completed/skipped/blocked report. Stop if the same command fails 3 times with the same root cause, required product behavior is unclear, or a destructive action is needed.
```

Not goal-ready:

```text
Do all TODO items.
```

```text
Goal readiness: not-goal-ready

Why:
- "all TODO items" is an unrelated backlog, not one durable objective.

Next step:
- Read TODO, group items by objective, then create one `/goal` for the highest-priority bounded group.
```
