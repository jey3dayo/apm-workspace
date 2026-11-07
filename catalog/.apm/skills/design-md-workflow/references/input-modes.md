# Input Modes

## Goal

Choose the lightest input mode that still gives enough evidence to write stable rules.

## Existing code

Use when the repository already contains implemented UI.

What to do:

- inspect repeated tokens, primitives, and layout patterns
- distinguish shared system rules from accidental local literals
- compare neighboring screens before declaring something "global"

Best for:

- extracting `DESIGN.md` from reality
- repairing drift between docs and code

## Screenshots or attached images

Use when visuals exist but the code is absent or incomplete.

What to do:

- describe hierarchy, spacing rhythm, component family resemblance, and motion clues
- stay conservative about hidden states and responsive behavior
- avoid over-specifying exact values unless they are visually obvious and important

Best for:

- early design-system capture
- reverse-engineering visual language from mockups

## Live URL

Use when a deployed interface is the best available evidence.

What to do:

- inspect multiple pages if possible before writing system-level rules
- separate content from reusable design language
- treat broken or inconsistent pages as evidence to review, not as automatic design rules

Best for:

- extracting a starting `DESIGN.md`
- checking whether a current UI already matches its docs

## Rough product intent

Use when there is little or no UI evidence yet.

What to do:

- write a narrower design system than usual
- define theme, color roles, typography direction, and layout principles first
- defer detailed component rules until evidence exists

Best for:

- creating both files from scratch
- bootstrapping a repository for future AI-assisted UI work

## Existing docs

Use when `DESIGN.md` or `DESIGN_REVIEW.md` already exists.

What to do:

- preserve the file roles first
- remove off-topic content before adding new sections
- treat the file that best matches the current UI and has less role drift as the baseline when the pair disagrees

Best for:

- incremental cleanup
- restoring strict separation after role drift
