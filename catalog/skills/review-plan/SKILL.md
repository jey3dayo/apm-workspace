---
name: review-plan
description: Review a pasted implementation, operation, research, or rollout plan without executing it; return a concise human summary, prioritized plan-review findings, and a copy-ready prompt for another agent, with conditional routing for UI/frontend, superpowers, and subagent-suitable work.
---

# Review Plan

Review the user's pasted plan and produce a human-readable review plus a prompt they can paste into a fresh agent. Do not implement the plan, edit files, run deployment, or create follow-up artifacts unless the user explicitly asks for a separate implementation task after the review.

## Workflow

1. Identify the plan type: implementation, operations/release, research, refactor, UI/frontend, superpowers plan, or mixed.
2. State a concise verdict for the human: ready, ready with fixes, blocked, or unclear.
3. Review the plan for blockers, risk, ambiguity, missing verification, sequencing problems, scope creep, and handoff gaps.
4. Apply conditional skill routing rules.
5. Generate a copy-ready prompt that a fresh agent can use with no surrounding conversation.

## Conditional Skill Routing

Include these recommendations in both the review findings and the copy prompt when they apply.

| Condition                                                                                                                                           | Required handling                                                                                                                                                   |
| --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| UI/UX, visual design, frontend pages/components, responsive behavior, interaction states, accessibility, or visual QA                               | Require `ui-ux-pro-max` and `frontend-design`. Review UI/UX, accessibility, responsive behavior, interaction states, visual consistency, and verification coverage. |
| Three or more mostly independent implementation tasks with low shared-file or shared-boundary conflict, and each task has a clear verification path | Recommend `subagent-driven-development` for same-session execution.                                                                                                 |
| Tightly coupled implementation, unclear architecture, one large shared file, or unresolved requirements                                             | Do not recommend `subagent-driven-development`; ask for decomposition or clarification first.                                                                       |
| Existing superpowers plan                                                                                                                           | Preserve the superpowers execution order, checklist style, and handoff conventions. Do not replace the plan's workflow; provide delta-style revision instructions.  |
| Plan creation or major redesign is still needed                                                                                                     | Recommend revising the plan before execution. Do not tell the next agent to execute immediately.                                                                    |

## Review Standards

Prioritize findings by implementation impact:

- `Blocker`: likely prevents correct execution or creates unacceptable safety, data, security, or deployment risk.
- `High`: likely causes rework, user-visible failure, broken verification, or unreliable handoff.
- `Medium`: meaningful ambiguity, missing edge case, sequencing weakness, or maintainability risk.
- `Low`: polish, wording, or optional completeness improvement.

Prefer concrete fixes over abstract advice. If evidence is only in the pasted plan, cite it as `plan text`. If repository evidence is needed but unavailable, mark the item as `Needs verification` rather than inventing facts.

## Output Contract

Return exactly these top-level sections unless the user asks for a different format.

````markdown
## Summary

- Verdict:
- Biggest risks:
- Must-fix items:
- Ready status:

## Review Findings

### Blockers

- [Blocker] <finding and concrete fix>

### High / Medium Risks

- [High] <finding and concrete fix>

### Missing Verification

- [Medium] <finding and concrete fix>

### Sequencing / Scope

- [Low] <finding and concrete fix>

## Copy Prompt

```text
Role:
You are an agent revising the following plan before implementation.

Mode:
Revise only. Do not execute the plan unless the user explicitly asks you to execute after revision.

Required skills:
- <list required skills and why; include conditional UI/frontend/subagent/superpowers guidance when applicable>

Original plan:
<paste or summarize the original plan faithfully. Preserve essential details, commands, file paths, constraints, and acceptance criteria.>

Review findings to address:
<prioritized findings from this review>

Instructions:
- Address blockers first.
- Preserve the original scope unless a finding says the scope is unsafe or incomplete.
- Preserve superpowers conventions if this is a superpowers implementation plan.
- If UI/frontend work is present, include UI/UX, accessibility, responsive, interaction-state, and visual QA requirements.
- If subagent-driven-development is appropriate, decompose into independent tasks with disjoint ownership and verification steps.
- If execution is not yet safe, return an improved plan and open questions instead of implementation steps.

Expected output:
- Revised plan or execution-ready handoff.
- Verification checklist.
- Open questions or blockers.

Constraints:
- Do not ignore unresolved blockers.
- Do not add unrelated features or refactors.
- Keep the response copy-paste ready for the next agent.
```
````

If a category has no findings, write `- None found.` under that category. Keep the human-facing summary short; put detail in the findings and copy prompt.

## Prompt Construction Rules

- Make the copy prompt self-contained: include the original plan content or a faithful compact restatement with all important commands, file paths, constraints, and acceptance criteria.
- Use `Mode: Revise only` by default. Use `Mode: Revise, then execute only if explicitly requested` only when the user's latest request clearly wants execution after revision.
- Do not claim that named skills can be forcibly activated in another runtime. Instead, instruct the next agent to use them.
- Keep the next-agent instructions imperative and testable.
- Do not include private chain-of-thought or hidden reasoning.

## Common Failure Modes

| Failure                                        | Correction                                                                            |
| ---------------------------------------------- | ------------------------------------------------------------------------------------- |
| Reviewing only prose quality                   | Review buildability, risk, verification, sequence, and handoff clarity.               |
| Adding UI skills only to the copy prompt       | Also include UI-specific review findings when UI/frontend content exists.             |
| Over-recommending subagents                    | Recommend `subagent-driven-development` only when tasks are separable and verifiable. |
| Telling the next agent to execute unsafe plans | Keep default mode as revision-only until blockers are resolved.                       |
| Rewriting superpowers plans from scratch       | Preserve their conventions and provide delta-style fixes.                             |
