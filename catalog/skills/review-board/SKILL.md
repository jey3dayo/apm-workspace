---
name: review-board
description: "Select and run expert review lanes for UI, forms, design specifications, accessibility, and multi-device product quality when ordinary /review or code review is too shallow."
---

# Review Board

## Overview

Use this skill when a user wants an expert review rather than a generic code review. It routes the work through a review lane catalog, then uses the selected lane as the evaluation rubric.

Keep the lane catalog in `references/review-lanes.md`. Add future review perspectives there instead of expanding this file.

## Workflow

1. Read `references/review-lanes.md` before presenting or choosing lanes.
2. If the user asks for a menu, show every lane number and title from the catalog.
3. If the user specifies a lane number or title, use that lane.
4. If no lane is specified, infer the best lane from the artifact and choose one primary lane when the catalog routing notes or a lane trigger clearly match.
5. Propose up to 3 candidate lanes only when multiple lane triggers are equally plausible and the choice would materially change the review.
6. Read the full selected lane body and use it as the review rubric.
7. Review the artifact with concrete evidence: file references, DOM/browser observations, screenshots, diffs, or repository instructions as available.
8. If the user says "fix", "implement", "直して", or "実装して", continue from review into implementation, verification, and final diff review instead of stopping at findings.

## Lane Selection

- The `Selected lane` is the primary rubric for the review. Choose exactly one primary lane unless the user explicitly asks for a menu.
- `Secondary checks` are supporting rubrics used to avoid blind spots. They can inform evidence gathering and findings, but they do not replace the primary lane.
- When a routing note explicitly matches the request, choose that lane and state the match. Do not present candidates just because adjacent lanes are also relevant.
- When two or more lanes are equally plausible, present up to 3 candidates with one-line reasons and wait for the user only if the choice would change the review outcome.
- Avoid lane inflation. Add a secondary check only when it covers a concrete risk the primary lane does not cover.

## Routing Rules

- Treat vague visual complaints as missing criteria until the relevant design system, `DESIGN.md`, design brief, tokens, typography, spacing, component states, and mood are checked.
- When the root cause is missing design guidance, report it as an input-specification gap before blaming the implementation.
- Prefer the lane's stated rubric over ad hoc taste judgments.
- Use existing project guidance first: `AGENTS.md`, `CLAUDE.md`, `DESIGN.md`, `DESIGN_REVIEW.md`, component docs, Storybook, CSS tokens, and tests when present.
- For browser-visible UI, use screenshots or browser inspection when practical. For accessibility and responsive claims, verify with keyboard flow and relevant viewport checks when possible.
- Keep comments actionable: state the violated criterion, evidence, expected behavior, and recommended fix.

## Evidence Minimums

- Always identify the rubric evidence: selected lane body, relevant routing note, and project instructions used.
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

- When implementation is requested, first convert findings into a short implementation plan tied to the selected lane's rubric.
- Apply only fixes supported by evidence or explicitly accepted by the user.
- Run quality gates appropriate to the changed behavior and the repository's instructions.
- Re-review the changed artifact against the primary lane and secondary checks.
- Finish with a final diff review to reject unrelated changes.

## Output

Use this structure unless the user asks for a different format:

```markdown
Selected lane: <primary lane number and title>
Secondary checks: <optional supporting lanes or "none">

Review basis:

- <lane rubric and project artifacts used>
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
