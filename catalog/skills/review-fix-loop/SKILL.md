---
name: review-fix-loop
description: >-
  Run a managed fix-and-review loop for complex implementation work: parallel
  subagent investigation feeding a main-session task backlog, evidence-backed
  triage, and repeated scored reviews until ship quality. Use when the user asks
  for a review fix loop / fix-and-review loop, asks to coordinate subagents with
  a task backlog and repeated quality review, or invokes this skill with a
  compact prompt whose conditions must be recovered from prior conversation and
  nearby repository context.
---

# Review Fix Loop

Turn a broad request into a managed execution loop: discover parallelizable work
with subagents, keep the main-session task list current, do the owner task
locally, and iterate reviews until the result is strong enough to ship.

Core rule: subagents are discovery and sidecar execution capacity, not a
substitute for owning the outcome. The main session owns task selection,
integration, quality gates, and final judgment.

## Context Recovery

When invoked with a short prompt such as "fix and review loop", recover the
missing conditions before asking follow-up questions. Look for target,
constraints, scope, evidence, and stop conditions in this order:

1. the current user message and earlier messages in the same conversation
2. visible task state, plans, review comments, error output, and tool results
3. repository guidance such as `AGENTS.md`, task definitions, tests, and docs
4. the current diff, nearby code, failing checks, logs, or runtime signals

State the recovered frame briefly before dispatching subagents or editing code:

```text
Recovered frame:
- User-visible goal: <from conversation/repo evidence>
- Current owner task: <main-session critical path>
- Scope limits: <files/modules/behaviors inferred from context>
- Evidence source: <checks/logs/screenshots/docs/runtime signal>
- Stop conditions: <hard blockers, see Stop Conditions>
```

Ask the user only when the missing condition changes user-visible behavior,
compatibility, data shape, security boundaries, cost, or external publication.
If a condition is useful but not required, make a conservative assumption, mark
it as an assumption, and proceed.

## Triage Vocabulary

Use one vocabulary for both subagent findings and review comments:

- `do-now`: blocks the owner task, quality gate, or requested behavior
- `accept`: evidence-backed improvement integrated or scheduled in this slice
- `next`: likely useful after the current slice
- `park`: valid follow-up outside the current request or review loop
- `reject`: not actionable, duplicated, contradicted by evidence, or scope creep
  presented as required

For each `do-now` or `accept` entry, record the evidence that will prove it: a
focused test, type/lint/build gate, runtime log line, screenshot, manual
reproduction step, or diff inspection.

## Workflow

1. Frame the target
   - Restate the user-visible outcome, constraints, and hard stop conditions
     (recover them per Context Recovery if the prompt omits them).
   - For a broad or ambiguous area, lock the user-visible action, likely code
     path, evidence source, and reproduction signal first. Do not widen scope
     until evidence connects the wider area.
   - Name the behavioral contract that must stay coherent when the same state
     has multiple representations across layers (UI state, serialized payloads,
     coordinate spaces, state machines, diagnostics, tests): state which
     representation is the source of truth.
   - Identify the current owner task: the next task the main session should do
     locally because it is on the critical path or requires integration
     judgment. Create or update the task list before dispatching agents.

2. Split subagent work
   - Delegate only bounded tasks that can run in parallel without blocking the
     owner task: codebase scouting, option comparison, test inventory,
     migration surface mapping, independent review.
   - Give each subagent a concrete output contract (see Subagent Prompt
     Template).
   - Do not ask multiple subagents the same question unless comparing variants
     intentionally.

3. Backlog the findings
   - Convert subagent results into task-list entries using the triage
     vocabulary, and keep the owner task updated as new facts arrive.

4. Execute the owner task
   - Work locally while subagents run. Integrate only evidence-backed findings.
   - When a subagent changed files, review its diff before building on it.

5. Review loop
   - Run a review pass after each meaningful integration slice.
   - Triage every review comment with the triage vocabulary before spending fix
     time; apply the Low-Quality Review Filter.
   - Score the result 0-100 with the Review Rubric. Fix `do-now` findings and
     re-review until the score is at least 95, or a Stop Condition applies.
   - When a reviewer finds a contract mismatch between representations, update
     the implementation and its observability surface together (debug displays,
     shared type comments, telemetry), and add a test at the exact conversion
     boundary.

6. Quality gates
   - Run the project-appropriate checks before claiming completion; if a gate
     cannot run, record why and what risk remains.
   - Prefer a layered gate set when the work crosses layers: focused unit
     tests, component tests, type checks, relevant backend tests, and the
     repo-level check when feasible.
   - If the issue is visual, native, or integration-heavy, pair automated gates
     with one runtime signal (app log, debug display, screenshot, manual
     interaction), and state whether it was captured after a fresh restart.
   - Do a final diff review against the original request and reject unrelated
     changes.

## Evidence Discipline

- Separate test evidence from runtime evidence: a passing unit test proves the
  helper contract; a screenshot or log proves integration behavior.
- For bugs spanning multiple representations of the same state, have each
  subagent state the expected source of truth and the actual source of truth.
- Treat stale comments, stale names, debug displays, and telemetry as part of
  the contract when they are used to debug the behavior.
- If a generated or reference artifact defines the target experience, record
  its path and the concrete behavior it represents; do not use it as vague
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

The score can reach 95 only when no known critical requirement is broken,
quality gates are clean or explicitly impossible to run, and remaining issues
are minor.

## Low-Quality Review Filter

Reject review comments that are:

- taste-only rewrites without a concrete defect or project convention
- requests to broaden scope beyond the user's task
- contradicted by repository evidence
- duplicates of findings already handled or parked
- speculative "might be bad" claims with no failure mode, file, or behavior
- advice that would reduce type safety, test reliability, security, or scope
  control

When filtering a comment that could resurface later, record `rejected: <reason>`.

## Subagent Prompt Template

```text
You are helping with a bounded side task. The main session owns integration.

Context:
- User-visible goal: <goal>
- Current owner task: <what the main session is doing locally>
- Scope limits: <files/modules/behaviors that are in scope>
- Evidence source: <tests/logs/screenshots/docs/runtime signal to inspect>
- Contract assumptions: <source-of-truth representation / API contract, if relevant>

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

- the same approach failed 3 times (report attempts, errors, alternatives)
- the review score cannot reach 95 without leaving the requested scope
- required credentials, environment, or product judgment is unavailable
- subagent findings conflict and cannot be resolved with local evidence
- quality gates fail for pre-existing or unrelated reasons the user did not ask
  to fix

## Reporting

Final reports include: owner task completed; subagent-derived tasks accepted,
parked, or rejected; key evidence for accepted findings; review-loop score and
remaining risk; quality gates run and their results.
