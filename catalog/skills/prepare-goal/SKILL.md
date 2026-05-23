---
name: prepare-goal
description: Use when the user wants help deciding or writing a `/goal`, gives rough intent, incremental next-step instructions, issue text, plans, TODOs, review notes, or asks what the practical landing point should be.
---

# Prepare Goal

Prepare a clear, verifiable goal before starting a long-running agent loop.

Use this skill to convert messy intent into a contract the agent and evaluator can audit. Do not treat `/goal` as a place for discovery-only work or a loose backlog. A good goal has one objective, bounded scope, explicit constraints, observable evidence, and a stop rule.

This skill is output-only and overrides the normal implementation default while it is active. Draft the `/goal` command and stop. You may do minimal read-only context inspection for goal drafting, but do not edit files, run validation commands, execute the generated `/goal`, or start implementation unless the user separately sends that `/goal` as a new instruction.

## Workflow

1. Read the current context
   - Use the conversation, referenced issue, plan, TODO, logs, or repo guidance already available.
   - When the user gives a small next step such as "continue", "same thing", "next work", or "this too", treat it as a clue to infer the larger intended outcome, not as the whole goal by itself.
   - If repo context matters, inspect the smallest relevant files first: `AGENTS.md`, task files, package scripts, CI definitions, current diff/status, or the named module.
   - Do not invent validation commands. Use only commands already known from the context or discovered in repo scripts/docs; otherwise use artifact/manual evidence or mark the missing command as an open question.
   - When the request comes from external source material such as PR comments, issue text, CI logs, or review threads, preserve the source constraints in the final goal. Carry over known review comment IDs, failing job/check names, failing commands, explicit non-goals, and requested retry limits instead of generalizing the task.

2. Infer the nearest durable objective
   - Separate the user's immediate instruction from the likely higher-level objective behind it.
   - Prefer the nearest practical landing point that moves the larger outcome forward and can be completed, verified, and reported in one agent run.
   - Use the smallest relevant evidence available: recent conversation, repo guidance, TODOs, issue or PR text, plans, current diff/status, known validation commands, and prior constraints already visible in context.
   - Separate facts already present in context from assumptions and execution-time lookups. If links, branches, commands, or generated outputs are not known yet, require the future agent to resolve and report them instead of pretending they are already fixed.
   - State the inference briefly in the response so the user can correct it before running the generated `/goal`.
   - List key assumptions when they affect scope, verification, or stop conditions.
   - If multiple materially different higher-level goals are plausible, do not guess silently. Ask at most two blocking questions or propose a smaller first goal.

3. Classify goal readiness
   - `ready`: one objective, known scope, and clear validation evidence are available.
   - `needs-clarification`: one or two missing facts block a reliable goal.
   - `not-goal-ready`: the work is broad discovery, product judgment, architecture exploration, or an unrelated backlog.

4. Normalize the objective
   - State exactly one durable objective.
   - Split unrelated objectives instead of packing them into one `/goal`.
   - Prefer outcome wording over activity wording: "auth migration is complete" rather than "work on auth migration."

5. Define the contract
   - Scope: files, modules, commands, issues, or queues that are in bounds.
   - Constraints: files, behavior, APIs, secrets, generated outputs, or workflows that must not change.
   - Done when: functional requirements and observable completion evidence.
   - Verification: known commands, if available, and artifacts or reports that prove completion. Keep commands separate from artifacts/reports, and make optional deployment, push, or remote checks conditional unless the user or repo guidance requires them.
   - Stop if: repeated failure, missing permission, high-risk action, unclear requirement, time/turn/token limit.

6. Check auditability
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
- Immediate request: <what the user explicitly asked for>
- Inferred landing point: <nearest durable objective>
- Key assumptions: <scope or validation assumptions, or "none">

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

Immediate request:
<what the user explicitly asked for>

Inferred landing point:
<nearest durable objective and why it is the right size>

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

Incremental request:

```text
Next, polish this skill so I do not have to keep spelling out each next task.
```

Prepared direction:

```text
Goal readiness: ready

Why:
- The immediate request is to polish a skill, and the inferred landing point is a bounded behavior change: the skill should infer the nearest durable goal behind incremental instructions.
- Immediate request: polish the current skill.
- Inferred landing point: update the skill guidance so it distinguishes small next-step instructions from the larger objective and proposes a verifiable `/goal`.
- Key assumptions: the skill remains output-only and does not execute the generated `/goal`.
```
