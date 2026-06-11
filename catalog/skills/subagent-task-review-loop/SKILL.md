---
name: subagent-task-review-loop
description: Use when coordinating parallel subagent investigation with a main-session task backlog and repeated quality review for complex implementation work, including compact invocations where conditions should be recovered from prior conversation and nearby repository context.
---

# Subagent Task Review Loop

Use this skill to turn a broad request into a managed execution loop: discover
parallelizable work with subagents, keep the main Codex task list current, do the
owner task locally, and iterate reviews until the result is strong enough to ship.

## Core Rule

Treat subagents as discovery and sidecar execution capacity, not as a substitute
for owning the outcome. The main session remains responsible for task selection,
integration, quality gates, and final judgment.

## Context Recovery

When the user invokes this skill with a short prompt such as "fix and review
loop", recover the missing conditions before asking follow-up questions.

Look for the target, constraints, scope, evidence, and stop conditions in this
order:

1. the current user message and earlier messages in the same conversation
2. visible task state, plans, review comments, error output, and tool results
3. repository guidance such as `AGENTS.md`, task definitions, tests, and docs
4. the current diff, nearby code, failing checks, logs, screenshots, or runtime
   signals

State the recovered frame briefly before dispatching subagents or editing code.
Ask the user only when the missing condition changes user-visible behavior,
compatibility, data shape, security boundaries, cost, external publication, or
other high-impact choices. If a condition is useful but not required, make a
conservative assumption, mark it as an assumption, and proceed.

## Workflow

1. Frame the target
   - Restate the user-visible outcome, constraints, and hard stop conditions.
   - If the prompt omits these fields, recover them from prior conversation and
     nearby repository context before asking the user.
   - If the request names a broad or ambiguous area, first lock the
     user-visible action, likely code path, evidence source, and reproduction
     signal. Do not widen the scope until evidence connects the wider area.
   - Identify the behavioral contract that must stay coherent across layers
     such as UI state, DOM geometry, native bounds, API payloads, diagnostics,
     and tests. Name the coordinate space or state machine explicitly when the
     bug involves layout, native shells, overlays, IPC, or cross-process data.
   - Identify the current owner task: the next task the main session should do
     locally because it is on the critical path or requires integration judgment.
   - Create or update the local task list before dispatching agents.

2. Split subagent work
   - Delegate only bounded tasks that can run in parallel without blocking the
     owner task.
   - Prefer subagent work for codebase scouting, option comparison, test
     inventory, migration surface mapping, and independent review.
   - Give each subagent a concrete output contract: facts found, files touched
     if any, risks, and recommended next task.
   - Do not ask multiple subagents to solve the same question unless comparing
     variants intentionally.

3. Backlog the findings
   - Convert subagent results into Codex task-list entries.
   - Mark each entry as one of:
     - `do-now`: blocks the owner task or quality gate
     - `accept`: evidence-backed improvement already integrated or scheduled in
       the current slice
     - `next`: likely useful after current work
     - `park`: valid follow-up, but outside the current request or review loop
     - `reject`: not actionable, duplicated, contradicted by evidence, or being
       presented as required despite being outside the current scope
   - For each `do-now` or `accept` entry, record the evidence that will prove it:
     a focused test, type/lint/build gate, runtime log line, screenshot, manual
     reproduction step, or diff inspection.
   - Keep the owner task updated as new facts arrive.

4. Execute the owner task
   - Work locally on the current owner task while subagents run.
   - Integrate only evidence-backed findings.
   - Keep edits scoped to the user request and existing project patterns.
   - When a subagent changed files, review its diff before building on it.

5. Review loop
   - Run a review pass after each meaningful integration slice.
   - Triage every review comment into `actionable`, `park`, or `reject` before
     spending fix time.
   - Convert actionable review comments into task-list entries: `do-now` when
     they block the score, quality gate, or requested behavior; `next` when they
     are useful after the current slice.
   - Score the result from 0 to 100 using the review rubric below.
   - Fix actionable findings and re-review until the score is at least 95, or
     until further improvement is blocked by scope, missing input, or diminishing
     returns that should be reported.
   - When reviewers find a contract mismatch, update both the implementation and
     its observability surface. Examples: keep debug HUD values in the same
     coordinate space as native payloads, update shared type comments and Rust
     DTO comments together, and add tests for the exact conversion boundary.
   - Maximum repeated attempts for the same failed approach: 3. After that,
     report attempts, errors, and alternatives.

6. Quality gates
   - Run the project-appropriate checks before claiming completion.
   - If a gate cannot run, record why and what risk remains.
   - Prefer a layered gate set when the work crosses layers: focused unit tests
     for pure helpers, component tests for UI behavior, type checks, relevant
     backend tests, and the repo-level check when feasible.
   - If the issue is visual, native, or integration-heavy, pair automated gates
     with one runtime signal such as an app log, debug HUD row, screenshot, or
     manual interaction result. State whether the runtime signal was captured
     before or after a fresh restart.
   - Do a final diff review against the original request and reject unrelated
     changes.

## Evidence Discipline

Use evidence to keep the loop from drifting:

- Separate test evidence from runtime evidence. A passing unit test proves the
  helper contract, while a screenshot or native log proves integration behavior.
- For bugs involving multiple coordinate spaces or state machines, ask each
  subagent to state the expected source of truth and the actual source of truth.
- Treat stale comments, stale function names, debug displays, and telemetry as
  part of the contract when they are used to debug the behavior.
- If a generated or reference artifact defines the target experience, record the
  artifact path and the concrete behavior it represents. Do not use it as vague
  taste input.
- When hot reload or partial state could contaminate evidence, prefer a fresh
  restart for final runtime verification.

## Review Rubric

Start from 100 and subtract for concrete issues only:

| Issue class                                                                | Typical deduction |
| -------------------------------------------------------------------------- | ----------------- |
| Broken behavior, data loss, security issue, or failed critical requirement | -20 to -40        |
| Type error, failing test, lint failure, or build failure                   | -10 to -25        |
| Incomplete edge handling or missing validation in touched behavior         | -5 to -15         |
| Scope creep, needless refactor, or unmanaged unrelated diff                | -5 to -15         |
| Weak maintainability that will likely cause near-term rework               | -3 to -10         |
| Minor style or naming issue with low risk                                  | -1 to -3          |

The score can reach 95 only when no known critical requirement is broken, quality
gates are clean or explicitly impossible to run, and remaining issues are minor.

## Low-Quality Review Filter

Ignore review comments that are not actionable. Do not spend loop budget on:

- taste-only rewrites without a concrete defect or project convention
- requests to broaden scope beyond the user's task
- comments contradicted by repository evidence
- duplicate findings already handled or parked
- speculative "might be bad" claims with no failure mode, file, or behavior
- advice that would reduce type safety, test reliability, security, or scope control

When filtering a comment, record the reason briefly as `rejected: <reason>` if it
could otherwise resurface later.

## Subagent Prompt Template

For compact invocations, use this short frame in the main session before
creating subagent prompts:

```text
Recovered frame:
- User-visible goal: <from conversation/repo evidence>
- Current owner task: <main-session critical path>
- Scope limits: <files/modules/behaviors inferred from context>
- Evidence source: <checks/logs/screenshots/docs/runtime signal>
- Stop conditions: <hard blockers or 3 failed attempts>
```

```text
You are helping with a bounded side task. The main session owns integration.

Context:
- User-visible goal: <goal>
- Current owner task: <what the main session is doing locally>
- Scope limits: <files/modules/behaviors that are in scope>
- Evidence source: <tests/logs/screenshots/docs/runtime signal to inspect>
- Contract assumptions: <coordinate space/state machine/API contract, if relevant>

Your task:
<specific research, implementation, or review task>

Return:
- Findings: evidence-backed bullets with file paths when applicable
- Recommended backlog entries: do-now / next / park / reject
- Evidence needed to prove each do-now finding is fixed
- Risks or unknowns
- Files changed, if any
```

## Stop Conditions

Stop the loop and report instead of continuing when:

- the same approach failed 3 times
- review score cannot reach 95 without leaving the requested scope
- required credentials, environment, or product judgment is unavailable
- subagent findings conflict and cannot be resolved with local evidence
- quality gates fail for pre-existing or unrelated reasons that the user did not
  ask to fix

## Reporting

Final reports should include:

- owner task completed
- subagent-derived tasks accepted, parked, or rejected
- key evidence used for accepted findings
- review-loop score and remaining risk
- quality gates run and their result
