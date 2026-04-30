---
name: subagent-task-review-loop
description: Use when coordinating parallel subagent investigation with a main-session task backlog and repeated quality review for complex implementation work.
---

# Subagent Task Review Loop

Use this skill to turn a broad request into a managed execution loop: discover
parallelizable work with subagents, keep the main Codex task list current, do the
owner task locally, and iterate reviews until the result is strong enough to ship.

## Core Rule

Treat subagents as discovery and sidecar execution capacity, not as a substitute
for owning the outcome. The main session remains responsible for task selection,
integration, quality gates, and final judgment.

## Workflow

1. **Frame the target**
   - Restate the user-visible outcome, constraints, and hard stop conditions.
   - If the request names a broad or ambiguous area, first lock the
     user-visible action, likely code path, evidence source, and reproduction
     signal. Do not widen the scope until evidence connects the wider area.
   - Identify the current owner task: the next task the main session should do
     locally because it is on the critical path or requires integration judgment.
   - Create or update the local task list before dispatching agents.

2. **Split subagent work**
   - Delegate only bounded tasks that can run in parallel without blocking the
     owner task.
   - Prefer subagent work for codebase scouting, option comparison, test
     inventory, migration surface mapping, and independent review.
   - Give each subagent a concrete output contract: facts found, files touched
     if any, risks, and recommended next task.
   - Do not ask multiple subagents to solve the same question unless comparing
     variants intentionally.

3. **Backlog the findings**
   - Convert subagent results into Codex task-list entries.
   - Mark each entry as one of:
     - `do-now`: blocks the owner task or quality gate
     - `next`: likely useful after current work
     - `park`: valid follow-up, but outside the current request or review loop
     - `reject`: not actionable, duplicated, contradicted by evidence, or being
       presented as required despite being outside the current scope
   - Keep the owner task updated as new facts arrive.

4. **Execute the owner task**
   - Work locally on the current owner task while subagents run.
   - Integrate only evidence-backed findings.
   - Keep edits scoped to the user request and existing project patterns.
   - When a subagent changed files, review its diff before building on it.

5. **Review loop**
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
   - Maximum repeated attempts for the same failed approach: 3. After that,
     report attempts, errors, and alternatives.

6. **Quality gates**
   - Run the project-appropriate checks before claiming completion.
   - If a gate cannot run, record why and what risk remains.
   - Do a final diff review against the original request and reject unrelated
     changes.

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

```text
You are helping with a bounded side task. The main session owns integration.

Context:
- User-visible goal: <goal>
- Current owner task: <what the main session is doing locally>
- Scope limits: <files/modules/behaviors that are in scope>

Your task:
<specific research, implementation, or review task>

Return:
- Findings: evidence-backed bullets with file paths when applicable
- Recommended backlog entries: do-now / next / park / reject
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
- review-loop score and remaining risk
- quality gates run and their result
