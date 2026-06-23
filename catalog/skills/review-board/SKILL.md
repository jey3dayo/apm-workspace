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
4. If no lane is specified, infer the best lane from the artifact and propose up to 3 candidates with one-line reasons.
5. If one lane is clearly best and no user decision is needed, choose it and state why.
6. Read the full selected lane body and use it as the review rubric.
7. Review the artifact with concrete evidence: file references, DOM/browser observations, screenshots, diffs, or repository instructions as available.
8. If the user says "fix", "implement", "直して", or "実装して", continue from review into implementation and verification instead of stopping at findings.

## Routing Rules

- Treat vague visual complaints as missing criteria until the relevant design system, `DESIGN.md`, design brief, tokens, typography, spacing, component states, and mood are checked.
- When the root cause is missing design guidance, report it as an input-specification gap before blaming the implementation.
- Prefer the lane's stated rubric over ad hoc taste judgments.
- Use existing project guidance first: `AGENTS.md`, `CLAUDE.md`, `DESIGN.md`, `DESIGN_REVIEW.md`, component docs, Storybook, CSS tokens, and tests when present.
- For browser-visible UI, use screenshots or browser inspection when practical. For accessibility and responsive claims, verify with keyboard flow and relevant viewport checks when possible.
- Keep comments actionable: state the violated criterion, evidence, expected behavior, and recommended fix.

## Output

Use this structure unless the user asks for a different format:

```markdown
Selected lane: <number and title>

Review basis:

- <lane rubric and project artifacts used>

Findings:

- [P0/P1/P2/P3] <issue>
  Evidence: <file, line, screenshot, or browser observation>
  Recommended fix: <specific fix>

Implementation plan:

- <only when changes are requested or clearly needed>

Verification performed:

- <commands, browser checks, screenshots, or "not run" with reason>
```

When there are no actionable issues, say so clearly and list any residual verification gaps.
