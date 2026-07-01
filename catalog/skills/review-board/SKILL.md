---
name: review-board
description: "Select and run expert review lanes for UI, forms, design specifications, accessibility, and multi-device product quality when ordinary /review or code review is too shallow."
---

# Review Board

## Overview

Use this skill when a user wants an expert review rather than a generic code review. It routes the work through a review lane catalog, then uses the selected lane as the evaluation rubric.

Keep the lane catalog in `references/review-lanes.md`. Add future review perspectives there instead of expanding this file.

## Execution Modes

Choose the execution mode before choosing the lane.

### Review Only

Use by default when the user asks for review, audit, critique, assessment, or a menu of lanes.

Review the artifact against one selected lane and any bounded secondary checks. Stop after reporting findings, residual risks, and verification performed.

### Review And Fix Loop

Use when the user asks to fix, implement, iterate through fixes, verify while fixing, or continue until a stated quality bar such as 95 or higher is reached. Japanese triggers such as `直して`, `実装して`, `検証しながら修正`, `レビューと修正を繰り返して`, and `95点以上` also select this mode.

Do not select this mode from subagent-backed review coverage or a second review pass alone. Those stay Review Only unless the user also asks for fixes, implementation, or a quality-bar loop.

Run the loop with one selected lane as the primary rubric and optional secondary checks as bounded supporting rubrics. Continue through review, implementation, verification, and re-review until the primary lane and secondary checks score at least 95, or until a blocker, scope boundary, or three repeated failures prevents further progress.

Do not treat Review And Fix Loop as a review lane. It is the execution mode that controls whether findings are fixed and re-reviewed.

## Workflow

1. Read `references/review-lanes.md` before presenting or choosing lanes.
2. Choose the execution mode: Review Only or Review And Fix Loop.
3. If the artifact is outside the lane catalog's UI/product scope, use a specialist rubric instead of forcing a UI lane. For example, review agent skills with `skill-creator` as the primary rubric and use this skill only for evidence discipline, severity, mode, and output structure.
4. If the user asks only for a menu, show every lane number and title from the catalog, do not list execution modes as lanes, and wait for the user to choose a lane.
5. If the user specifies a lane number or title, use that lane as the selected primary lane.
6. If no lane is specified, infer the best lane from the artifact and choose one primary lane when the catalog routing notes or a lane trigger clearly match.
7. Propose up to 3 candidate lanes only when multiple lane triggers are equally plausible and the choice would materially change the review.
8. Read the full selected lane body or specialist rubric and use it as the primary rubric.
9. Review the artifact with concrete evidence: file references, DOM/browser observations, screenshots, diffs, or repository instructions as available.
10. In Review And Fix Loop mode, continue from review into implementation, verification, re-review, and final diff review instead of stopping at findings.

## Lane Selection

- The `Selected lane` is the primary rubric for the review. Choose exactly one primary lane unless the user explicitly asks for a menu.
- For non-lane artifacts such as skills, agents, commands, rules, or automation definitions, set `Selected lane` to `specialist rubric: <skill or guidance name>` and name the specialist source used.
- `Secondary checks` are supporting rubrics used to avoid blind spots. They can inform evidence gathering and findings, but they do not replace the primary lane.
- When a routing note explicitly matches the request, choose that lane and state the match. Do not present candidates just because adjacent lanes are also relevant.
- When two or more lanes are equally plausible, present up to 3 candidates with one-line reasons and wait for the user only if the choice would change the review outcome.
- Avoid lane inflation. Add a secondary check only when it covers a concrete risk the primary lane does not cover.

## Persona Overlays

Use persona overlays only as supporting rubrics. They adjust stance, evidence discipline, implementation constraints, or readiness judgment; they never replace the selected primary lane, execution mode, evidence minimums, severity model, or output structure.

Use at most two overlays. Add an overlay only when it changes how evidence is gathered, how fixes are constrained, or how ship/readiness claims are judged.

- `Evidence Collector`: Use when visual, browser, responsive, QA, or interaction evidence may be under-collected. It raises evidence expectations; it does not create a separate QA lane.
- `Reality Checker`: Use for launch readiness, production-ready claims, final gates, or inflated quality claims. It sharpens ship/block judgment; it does not override lane criteria.
- `Minimal Change Engineer`: Use in Review And Fix Loop when implementation changes are requested. It constrains fixes to the smallest evidence-supported diff; it does not block required fixes.

When overlays conflict, the primary lane defines what good means, the execution mode defines whether to fix, and the overlay only adjusts stance or evidence discipline.

## Routing Rules

- Treat vague visual complaints as missing criteria until the relevant design system, `DESIGN.md`, design brief, tokens, typography, spacing, component states, and mood are checked.
- When the root cause is missing design guidance, report it as an input-specification gap before blaming the implementation.
- Prefer the lane's stated rubric over ad hoc taste judgments.
- Prefer the relevant specialist skill over an unrelated review lane when the artifact is not a UI, form, design, accessibility, UX, or conversion surface.
- Use existing project guidance first: `AGENTS.md`, `CLAUDE.md`, `DESIGN.md`, `DESIGN_REVIEW.md`, component docs, Storybook, CSS tokens, and tests when present.
- For browser-visible UI, use screenshots or browser inspection when practical. For accessibility and responsive claims, verify with keyboard flow and relevant viewport checks when possible.
- Keep comments actionable: state the violated criterion, evidence, expected behavior, and recommended fix.

## Evidence Minimums

- Always identify the rubric evidence: selected lane body, relevant routing note, and project instructions used.
- For skill, agent, command, or rule reviews, read the artifact source, linked references needed for its routing, adjacent metadata such as `agents/openai.yaml` when present, and repository source-of-truth instructions such as APM ownership rules when applicable.
- For repository artifacts, inspect the implementation source or diff before making code-level findings.
- For browser-visible UI, gather at least: project guidance, design source when present, implementation source or diff, one current screenshot or browser observation, and relevant viewport or focus evidence. If any item is unavailable, say so in `Evidence minimum`.
- For accessibility, responsive, or interaction claims, do not rely on static screenshots alone. Include keyboard, viewport, DOM, or state evidence when practical.
- Do not report a finding without evidence. If a concern is plausible but unverified, list it as a residual verification gap instead.

## Severity

- `P0`: Blocks task completion, prevents access to critical functionality, causes data loss/security exposure, or makes the page unusable for a major user group.
- `P1`: Breaks a core flow, creates serious accessibility failure, hides critical state, or makes recovery from common errors unreliable.
- `P2`: Degrades completion, comprehension, consistency, or confidence, but has a clear workaround.
- `P3`: Polish, consistency, maintainability, or minor usability issue that does not materially block the task.
- Choose severity from user impact and likelihood, not implementation effort.

## Implementation Follow-Through

- In Review And Fix Loop mode, first convert findings into a short implementation plan tied to the selected lane's rubric.
- Apply only fixes supported by evidence or explicitly accepted by the user.
- Run quality gates appropriate to the changed behavior and the repository's instructions.
- Re-review the changed artifact against the primary lane and secondary checks.
- Keep iterating until the review score reaches at least 95, or report the blocker, scope boundary, or repeated failure that prevents reaching it.
- Finish with a final diff review to reject unrelated changes.

## Output

Use this structure unless the user asks for a different format:

```markdown
Mode: <Review Only or Review And Fix Loop>
Selected lane: <primary lane number and title, or "specialist rubric: <source>">
Secondary checks: <optional supporting lanes or "none">

Review basis:

- <lane or specialist rubric and project artifacts used>
- Evidence minimum: <what was verified / what was unavailable>

Findings:

- [P0/P1/P2/P3] <issue>
  Criterion: <violated rubric or project rule>
  Evidence: <file, line, screenshot, DOM/browser observation, diff, or repo instruction>
  Expected behavior: <what should happen>
  Recommended fix: <specific smallest fix>

Implementation plan:

- <only when changes are requested or clearly needed>

Review score:

- <0-100, with ship/block rationale when applicable>

Verification performed:

- <commands, browser checks, screenshots, or "not run" with reason>
```

When there are no actionable issues, say so clearly and list any residual verification gaps.
