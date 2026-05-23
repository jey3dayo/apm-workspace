---
name: design-check
description: Review frontend UI and CSS implementation for visual quality, accessibility, design-system fit, CSS correctness, and modern CSS opportunities. Use when asked to check UI, review CSS, improve visual polish, evaluate design choices, inspect Tailwind or React styling, compare screenshots, audit styling decisions, or look for useful CSS techniques such as OKLCH gradients, color-mix, background-clip text, popover, anchor positioning, subgrid, container queries, scroll-driven animation, focus-visible, and reduced-motion support.
---

# Design Check

Use this skill as a practical design and CSS review pass. Prefer concrete findings tied to files, screenshots, or live browser observations over broad design advice.

## Workflow

1. Identify the review target: changed files, named components, screenshot, Storybook story, route, or live localhost view.
2. Read the project's design source of truth first when present: `DESIGN.md`, `CLAUDE.md`, README design notes, theme tokens, and shared UI primitives.
3. Inspect implementation with `rg` before broad file reads. Look for raw colors, ad hoc gradients, arbitrary spacing, motion, focus styles, contrast-sensitive text, duplicated styling, avoidable JavaScript, fragile selectors, and unsupported CSS.
4. For local UI, use a browser screenshot when the route or story is known. Check desktop and mobile sizes when layout or text fit could change.
5. Review against the checklist in `references/checklist.md` when the task is non-trivial or specifically asks for design quality.
6. Report findings by severity with file/line references when reviewing code. If implementing fixes, keep changes scoped and verify with the project's normal checks.

## Evidence Modes

State the evidence mode when it affects confidence:

- **Diff review**: inspect the actual diff. If no diff exists, say the review is of current files, not changed lines.
- **Code review**: ground findings in file/line references and separate confirmed issues from visual or behavior hypotheses.
- **Screenshot-only review**: produce visual observations, then list implementation hypotheses separately. Ask for the route, component, story, or CSS file needed for code-level findings.
- **External material review**: inspect the provided URL or excerpt before attributing claims to it. If only technique names are provided, treat them as a candidate list, not as source-backed slide claims.
- **Live/browser review**: report viewport, theme, and route/story checked. If browser verification was not performed, list it as a verification gap.

Only report commands, browser checks, screenshots, notifications, or tests that were actually performed in the current task.

## CSS Correctness Checks

When a finding depends on CSS actually matching runtime DOM or build output, inspect the relevant owner before asserting:

- For Tailwind `data-*`, arbitrary variants, custom variants, or plugin behavior, compare the class against the rendered attribute or the wrapper component that emits it.
- For shared primitives, inspect the primitive owner before judging callers. Example: review `ScrollArea` before deciding whether scrollbar orientation classes match.
- For modern CSS, check the target environment and `@supports`/fallback shape before recommending production use.
- If support or generated CSS cannot be verified, phrase the finding as a risk and name the missing verification.

## Review Priorities

- Functional clarity first: hierarchy, state, interaction affordance, readable labels, and scan speed.
- Accessibility next: semantic controls, keyboard/focus behavior, contrast, reduced motion, and non-color cues.
- System fit next: use existing tokens, spacing, radius, typography, icon set, and component primitives before adding new styling.
- CSS quality next: prefer resilient layout, clear selectors, native browser behavior, and maintainable token-derived styling.
- Modern CSS last: suggest newer CSS only when it simplifies code, removes JavaScript, improves perceptual quality, or matches an existing design direction.

## Modern CSS Gate

Consider modern CSS techniques when they help the specific UI:

- `linear-gradient(... in oklch, ...)` for smoother vivid gradients when gradients are already appropriate.
- `oklch()` tokens for perceptual color tuning when the project already accepts modern color syntax.
- `color-mix()` for token-derived state colors instead of hardcoded variants.
- `background-clip: text` with transparent text only for brand, hero, empty-state, or celebratory text where a plain token would underperform.
- Popover API, anchor positioning, and `command` / `commandfor` when they replace fragile custom menu, tooltip, dialog, or popover JavaScript.
- `subgrid` when repeated cards or rows need internal alignment across siblings.
- Container queries for component-local responsive behavior.
- `:focus-visible`, `:has()`, `@starting-style`, and `prefers-reduced-motion` when they reduce JavaScript or fix interaction quality.

Do not introduce a modern CSS feature just because it exists. Call out browser/support risk when the UI targets embedded webviews, older Safari, email HTML, PDFs, or native wrappers.

## Output

For reviews, lead with findings:

```markdown
**Findings**

- [P1] File/line: issue and impact. Suggested fix.
- [P2] File/line: issue and impact. Suggested fix.

**Notes**

- Modern CSS opportunities: ...
- Verification gaps: ...
```

For implementation, summarize changed files and verification commands. Include screenshot or browser verification when the change affects layout, color, or interaction.
