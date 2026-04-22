---
name: design-md-workflow
description: Create, update, and review a paired `DESIGN.md` and `DESIGN_REVIEW.md` workflow for AI-assisted UI work. Use when Codex needs to extract a durable design system from existing code, screenshots, URLs, or rough product intent; decide whether guidance belongs in `DESIGN.md`, shared UI, or feature-local code; enforce strict Stitch-style `DESIGN.md` boundaries; or route review logic, exceptions, and escalation rules into `DESIGN_REVIEW.md`.
---

# Design MD Workflow

## Overview

This skill produces a strict two-document system:

- `DESIGN.md`: the machine-readable visual source of truth
- `DESIGN_REVIEW.md`: the operational review and routing guide

Treat them as complementary, not interchangeable. `DESIGN.md` holds durable visual rules. `DESIGN_REVIEW.md` holds review process, routing, exceptions, and escalation.

Mirror the language and terminology already used by the repository. Do not force English output just because this skill is written in English.

## Output Contract

### `DESIGN.md`

Use for:

- reusable visual rules
- visual system decisions that should survive feature changes
- guidance that an AI coding agent can apply across multiple screens

Do not use for:

- review flow
- escalation policy
- "put this in shared vs local" decisions
- feature-local exceptions
- backlog items, open questions, or implementation notes

### `DESIGN_REVIEW.md`

Use for:

- routing rules: `DESIGN.md` vs shared vs feature-local
- review checklists and output formats
- escalation paths when scope or ownership is unclear
- explicit exception handling
- brief quotations of visual rules only when needed to explain a routing decision

Do not use it as a dumping ground for weak design thinking. If a stable visual rule is discoverable, encode it in `DESIGN.md`.

## Workflow

### 1. Gather Inputs

Start from whatever is available:

- existing `DESIGN.md` or `DESIGN_REVIEW.md`
- UI code and shared component primitives
- screenshots or attached images
- live URLs
- rough product or feature intent

Choose the relevant input mode from `references/input-modes.md`.

### 2. Inspect Existing Documents First

If both documents exist:

- preserve each file's role
- remove role drift instead of blending the files further
- treat the file that best matches the current UI and has less role drift as the stronger source of truth
- update the weaker file to match that stronger source of truth

If only one file exists:

- keep the existing file in its current role
- create only the missing counterpart

If neither file exists:

- create both together by default

### 3. Extract Durable Visual Rules First

Before writing anything, identify the rules that are:

- reusable across screens
- visual rather than operational
- stable enough to guide future implementation

Write those into `DESIGN.md` using the structure in `references/design-md-structure.md`.
Keep the result narrow enough that a Stitch-style agent could reuse it without reading review context.

### 4. Route Overflow Out of `DESIGN.md`

If content is hard to encode as a reusable visual rule, do not force it into `DESIGN.md`.

Route content into `DESIGN_REVIEW.md` when it is about:

- review operations
- placement decisions
- shared-vs-local promotion rules
- one-off exceptions
- escalation or ambiguity handling

Use `references/routing-examples.md` when the split is unclear.
Use `references/design-review-structure.md` when drafting or repairing `DESIGN_REVIEW.md`.

### 5. Draft or Update the Pair Explicitly

When a request mixes visual rules with process or policy:

- split the result into both documents on purpose
- say what belongs in each document
- avoid hybrid sections that combine visual guidance and review logic

When updating an existing pair:

- prefer small in-place corrections
- remove off-topic content from the wrong file
- rewrite for clarity instead of appending contradictory notes

### 6. Review the Result

Before finishing, check:

- every section in `DESIGN.md` can guide future UI generation
- every section in `DESIGN_REVIEW.md` helps a reviewer decide where a rule should live
- no feature-local exception remains in `DESIGN.md`
- no durable visual rule was left only in `DESIGN_REVIEW.md`
- no section depends on hidden team history to be understandable

## Quick Routing Test

Ask these questions in order:

1. Does this statement tell a future agent what UI should look or feel like across multiple screens?
   - If yes, it belongs in `DESIGN.md`.
2. Does this statement tell a reviewer where a rule should live, when to promote it, or when to keep it local?
   - If yes, it belongs in `DESIGN_REVIEW.md`.
3. Is it neither reusable visual guidance nor review-routing guidance?
   - Keep it out of both files unless the user explicitly asks to document it elsewhere.

## Default Behaviors

- If evidence is incomplete, prefer narrower rules over invented detail.
- Omit unsupported sections instead of fabricating content.
- Prefer semantic rules over implementation literals when a pattern clearly repeats.
- If a rule appears once and is not obviously reusable, keep it out of `DESIGN.md`.
- If a repeated decision depends on review judgment rather than visual style, place it in `DESIGN_REVIEW.md`.

## Japanese Examples

### Review Output Example

```md
総合判定: 調整推奨

- 構造: OK
  理由: `DESIGN.md` と `DESIGN_REVIEW.md` の責務は分離できている。
- 色: 要修正
  理由: 色の役割は書かれているが、 semantic role と再利用条件が弱い。
- Stitch再利用性: 要修正
  理由: 画面固有の運用メモが `DESIGN.md` に混ざっている。

優先修正:

1. feature-local な例外を `DESIGN_REVIEW.md` に移す
2. `DESIGN.md` の色を semantic role 単位で言い直す
```

### Routing Example

- `設定フォームではラベル列を固定し、右カラム終端をそろえる` -> `DESIGN.md`
- `この画面だけは実験中なので shared に上げない` -> `DESIGN_REVIEW.md`
- `このコンポーネントを shared に上げる条件は state model と a11y が一致すること` -> `DESIGN_REVIEW.md`

### Overflow Example

- `これは DESIGN_REVIEW.md に入れる。理由は review flow と feature-local exception の判断であり、再利用可能な視覚ルールではない。`

## References

- `references/design-md-structure.md`
- `references/design-review-structure.md`
- `references/routing-examples.md`
- `references/input-modes.md`
