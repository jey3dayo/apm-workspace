---
name: prepare-goal
description: Turn rough intent, conversation history, issue text, plans, or task notes into an audit-friendly `/goal` contract for Codex or Claude Code. Use when the user wants help deciding or writing a goal, asks whether a task is suitable for `/goal`, says a goal is hard to define, or wants a paste-ready `/goal` with scope, constraints, validation, and stop conditions.
---

# Prepare Goal

Prepare a clear, verifiable goal before starting a long-running agent loop.

Use this skill to convert messy intent into a contract the agent and evaluator can audit. Do not treat `/goal` as a place for discovery-only work or a loose backlog. A good goal has one objective, bounded scope, explicit constraints, observable evidence, and a stop rule.

This skill is output-only and overrides the normal implementation default while it is active. Draft the `/goal` command and stop. You may do minimal read-only context inspection for goal drafting, but do not edit files, run validation commands, execute the generated `/goal`, or start implementation unless the user separately sends that `/goal` as a new instruction.

## Workflow

1. Read the current context
   - Use the conversation, referenced issue, plan, TODO, logs, or repo guidance already available.
   - If repo context matters, inspect the smallest relevant files first: `AGENTS.md`, task files, package scripts, CI definitions, or the named module.
   - Do not invent validation commands. Use only commands already known from the context or discovered in repo scripts/docs; otherwise use artifact/manual evidence or mark the missing command as an open question.
   - When the request comes from external source material such as PR comments, issue text, CI logs, or review threads, preserve the source constraints in the final goal. Carry over known review comment IDs, failing job/check names, failing commands, explicit non-goals, and requested retry limits instead of generalizing the task.

2. Classify goal readiness
   - `ready`: one objective, known scope, and clear validation evidence are available.
   - `needs-clarification`: one or two missing facts block a reliable goal.
   - `not-goal-ready`: the work is broad discovery, product judgment, architecture exploration, or an unrelated backlog.

3. Normalize the objective
   - State exactly one durable objective.
   - Split unrelated objectives instead of packing them into one `/goal`.
   - Prefer outcome wording over activity wording: "auth migration is complete" rather than "work on auth migration."

4. Define the contract
   - Scope: files, modules, commands, issues, or queues that are in bounds.
   - Constraints: files, behavior, APIs, secrets, generated outputs, or workflows that must not change.
   - Done when: functional requirements and observable completion evidence.
   - Verification: known commands, if available, and artifacts or reports that prove completion. Keep commands separate from artifacts/reports.
   - Stop if: repeated failure, missing permission, high-risk action, unclear requirement, time/turn/token limit.

5. Check auditability
   - The completion judge must be able to decide from evidence the agent reports in the conversation.
   - Require the agent to report command names, exit status, changed files, and remaining risks.
   - If evidence depends on a file or command, tell the agent to surface the relevant result before claiming completion.

## Output Format

Always finish with a copy-paste-ready goal block when readiness is `ready`. Put the final `/goal` on one continuous command block so the user can paste it directly. Do not bury the final command inside analysis prose.

When readiness is `ready`, stop immediately after the final `/goal` command block. Do not add follow-up implementation narration, do not announce that work is starting, and do not enter a task loop until the user separately invokes the generated `/goal`.

When readiness is `ready`, return this structure:

```text
Goal readiness: ready

Why:
- <short reason>

Paste-ready /goal:
/goal <one objective>. Done means <observable end state>. Scope: <allowed scope>. Constraints: <non-goals and forbidden changes, including source constraints from PR/issue/CI/review context>. Verification commands: <known commands only, or "none known">. Verification artifacts/reports: <evidence the agent must surface>. Stop if <same root cause fails 3 times, requested retry limit is reached, blockers, risky actions, or budget>.

Audit checklist:
- Objective is singular: yes/no
- Scope is bounded: yes/no
- Done state is observable: yes/no
- Verification is explicit: yes/no
- Stop conditions are explicit: yes/no

Open questions:
- <only questions required before running the goal; omit if none>
```

Then append a separate final block:

````markdown
Final /goal command:

```text
/goal <same paste-ready command, with no prefix text inside the block>
```
````

If the goal is not ready, do not force a `/goal`. Recommend the next best step instead: plan, research, clarification, task split, or a smaller first goal.

When readiness is `needs-clarification` or `not-goal-ready`, do not include `Paste-ready /goal` or `Final /goal command` blocks. Ask at most two blocking questions, or recommend the next best step when questions would not make the work goal-ready.

Use this not-ready structure:

```text
Goal readiness: <needs-clarification or not-goal-ready>

Why:
- <short reason>

Next step:
- <clarification question, task split, research step, or smaller first goal>

Open questions:
- <only blocking questions, maximum two; omit if none>
```

## Goal Contract Template

Use this as the internal shape when drafting:

```text
Objective:
<one outcome>

Inputs to read first:
- <files, issue, plan, logs, or docs>

Scope:
- Allowed:
- Forbidden:

Done when:
- Functional:
- Observable evidence:
- Non-regression:

Verification:
- Commands:
- Artifacts or reports:

Stop if:
- Same root cause fails 3 times
- Required access or context is missing
- A destructive or high-risk action is needed
- The turn/time/token budget is reached
```

## Examples

Rough request:

```text
Fix auth all the way through.
```

Prepared goal:

```text
/goal Auth module repair is complete. Done means the failing auth behavior is fixed, all call sites in scope still use the intended public API, `npm test -- test/auth` exits 0, `npm run lint` exits 0, and the final report lists changed files plus verification output. Scope: auth module and directly related tests only. Constraints: do not change public route behavior, do not modify unrelated snapshots, and do not edit secret or environment files. Stop if the same command fails 3 times with the same root cause, required product behavior is unclear, or a destructive action is needed.
```

Rough request:

```text
Do all TODO items.
```

Response direction:

```text
Goal readiness: not-goal-ready

Why:
- "all TODO items" is an unrelated backlog, not one durable objective.

Next step:
- Read TODO, group items by objective, then create one `/goal` for the highest-priority bounded group.
```
