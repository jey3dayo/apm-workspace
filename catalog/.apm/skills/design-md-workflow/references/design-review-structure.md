# `DESIGN_REVIEW.md` Structure

## Purpose

`DESIGN_REVIEW.md` is the operational guide for reviewing UI and deciding where design changes should live.

Keep it about routing, review, and escalation. Keep visual system rules out of it unless they are quoted briefly to explain a routing decision.
Do not use it for backlog capture, broad product planning, or generic implementation notes.

## Recommended Section Set

Use this section order by default:

1. `## Purpose`
2. `## Scope`
3. `## Routing Rules`
4. `## Review Flow`
5. `## Review Format`
6. `## Escalation`
7. `## Notes`

## Routing Rules

Define how to decide between:

- `DESIGN.md`
- shared UI primitives or shared references
- feature-local components

Promote into shared only when semantics, state model, and accessibility behavior are aligned. Do not promote based on visual similarity alone.
If the decision is still fundamentally about reusable visual language, move that rule into `DESIGN.md` and keep only the routing rule here.

## Review Flow

Default evaluation order:

1. `DESIGN.md`
2. shared UI or reference surfaces
3. feature-local components

Use this file to explain the order and the promotion criteria, not to restate the full visual language.

## Review Format

If the repository has no existing format, use this Japanese review format:

```md
総合判定: OK | 調整推奨 | 大幅修正推奨

- 構造: OK | 要修正 | 不足
  理由: ...
- 雰囲気記述: OK | 要修正 | 不足
  理由: ...
- 色: OK | 要修正 | 不足
  理由: ...
- タイポグラフィ: OK | 要修正 | 不足
  理由: ...
- コンポーネント: OK | 要修正 | 不足
  理由: ...
- レイアウト: OK | 要修正 | 不足
  理由: ...
- Stitch再利用性: OK | 要修正 | 不足
  理由: ...

優先修正:

1. ...
2. ...
3. ...
```

## Escalation

Escalate when:

- the rule might belong in both `DESIGN.md` and shared code
- the exception appears in multiple screens
- the design language is contradictory or under-specified
- the team needs an explicit local exception that should not spread

When escalating, state which decision is unresolved and what evidence is missing.

## Notes

- Prefer the smallest correction that restores clear ownership.
- Keep review operations separate from design-system authoring.
- Document intentional local exceptions explicitly so they do not silently spread.
