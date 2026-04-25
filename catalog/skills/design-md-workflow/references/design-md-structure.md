# `DESIGN.md` Structure

## Purpose

`DESIGN.md` is the durable visual contract for a repository. Write it so a future AI agent can generate consistent UI without re-deriving the design system from scratch.

Keep it visual, reusable, stable, and understandable without review-process context.

## Format Contract

`DESIGN.md` combines two layers:

- YAML front matter contains normative, machine-readable design tokens.
- Markdown body contains human-readable rationale for how and why to apply those tokens.

The token layer is the source of exact values. The prose layer explains intent and application. If they disagree, repair the mismatch instead of treating prose as an override for broken tokens.

Common token groups:

- `colors`: semantic color values as sRGB hex strings.
- `typography`: named text roles with fields such as `fontFamily`, `fontSize`, `fontWeight`, `lineHeight`, and `letterSpacing`.
- `rounded`: radius scale tokens.
- `spacing`: spacing scale tokens.
- `components`: reusable component appearance tokens.

Use token references such as `{colors.primary}` when one token depends on another. Broken references are errors.

## Allowed Content

Include:

- visual theme and atmosphere
- semantic colors and their roles
- typography roles and hierarchy
- elevation, radius, and surface patterns
- reusable component appearance rules
- layout, spacing, motion, and responsive principles
- accessibility rules only when they directly affect reusable UI presentation

## Forbidden Content

Do not include:

- review flow
- escalation rules
- shared-vs-local ownership decisions
- temporary exceptions
- feature-specific product logic
- TODOs, backlog notes, or "later decide" placeholders
- long implementation inventories tied to one screen

If a statement explains where a rule should live, it belongs in `DESIGN_REVIEW.md`, not here.
If a statement needs local ownership history to make sense, it does not belong here.

## Canonical Section Set

Use this section order when the evidence supports it. Sections are optional, but sections that exist should stay in canonical order:

1. `## Overview`, `## Brand & Style`, or `## Visual Theme & Atmosphere`
2. `## Colors`
3. `## Typography`
4. `## Layout` or `## Layout & Spacing`
5. `## Elevation & Depth` or `## Elevation`
6. `## Shapes`
7. `## Components`
8. `## Do's and Don'ts`

Omit unsupported sections. Do not add empty placeholders.

Preserve unknown section headings when they contain useful design rationale, but do not duplicate a section heading. Duplicate sections are invalid and should be repaired.

## Component Tokens

Use component tokens for reusable appearance decisions, not feature-local implementation details.

Common component properties include:

- `backgroundColor`
- `textColor`
- `typography`
- `rounded`
- `padding`
- `size`
- `height`
- `width`

Represent variants such as hover, active, or pressed as separate related component entries. Unknown component properties can remain when useful, but expect lint warnings and explain or simplify them before finalizing.

## Official Lint Checks

Run the official linter from the target project when possible:

```bash
rtk npx @google/design.md lint DESIGN.md
```

Use findings from these rule families:

- `broken-ref`: token references that do not resolve.
- `missing-primary`: colors exist but no `primary` color exists.
- `contrast-ratio`: component text/background pairs below WCAG AA contrast.
- `orphaned-tokens`: color tokens not referenced by any component.
- `token-summary`: informational token counts by section.
- `missing-sections`: optional token groups such as spacing or rounded are absent.
- `missing-typography`: colors exist but typography tokens are absent.
- `section-order`: sections appear outside canonical order.

Lint findings should improve `DESIGN.md` as the visual contract. Put process, routing, exception, and escalation decisions in `DESIGN_REVIEW.md`.

## Extraction Rules

### From code

- infer reusable tokens, roles, and recurring composition rules
- prefer semantic names over raw implementation details
- avoid copying one-off literals unless they clearly represent a shared system

### From screenshots

- describe durable patterns, not pixel-perfect trivia
- capture hierarchy, rhythm, contrast, and component family behavior
- avoid guessing hidden states or unsupported responsive behavior

### From a live URL

- treat the rendered UI as evidence, not as perfect truth
- separate repeated system patterns from page-specific content
- ignore accidental inconsistencies unless they are clearly intentional

### From rough intent

- write only the rules that can be justified from the requested tone and product direction
- keep the system narrower than usual
- avoid inventing deep component rules without evidence

## Writing Rules

- Prefer rules that can survive multiple features.
- Use semantic roles such as "Primary", "Surface 300", or "Caption" instead of raw literals when the role is established.
- Explain how a rule is used, not only what the value is.
- If a rule is probably temporary or local, exclude it.
