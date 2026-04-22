# Routing Examples

## Rule of Thumb

Ask one question first:

Can this statement guide future UI generation across multiple screens without extra review context?

- If yes, it probably belongs in `DESIGN.md`.
- If no, check whether it is a routing, review, or exception statement and place it in `DESIGN_REVIEW.md`.

## Examples

| Raw statement                                                                        | Destination        | Reason                            |
| ------------------------------------------------------------------------------------ | ------------------ | --------------------------------- |
| "Primary actions use the warm accent and dark text."                                 | `DESIGN.md`        | Durable visual rule               |
| "Only promote this card into shared if loading and empty states match."              | `DESIGN_REVIEW.md` | Promotion rule, not visual system |
| "This settings page keeps a fixed label column and one right-column endpoint."       | `DESIGN.md`        | Reusable layout principle         |
| "Do not move this experimental panel into shared yet."                               | `DESIGN_REVIEW.md` | Local exception                   |
| "Use one standard medium radius token for shared inputs and buttons."                | `DESIGN.md`        | Durable component rule            |
| "When radius differs from shared primitives, require explicit review justification." | `DESIGN_REVIEW.md` | Review governance                 |

## Before / After Split

### Mixed source note

```md
Settings rows should align to one shared control rail, and if a feature breaks this rule it must stay local until review approves promoting it.
```

### Split result

`DESIGN.md`

```md
Settings-style forms should align controls to one shared right-column endpoint.
```

`DESIGN_REVIEW.md`

```md
Feature-local exceptions to the shared control-rail rule require explicit review justification before promotion into shared.
```

## Japanese Examples

- `この配色は複数画面で再利用する前提なので DESIGN.md に入れる`
- `この判断は shared へ昇格させる条件の話なので DESIGN_REVIEW.md に入れる`
- `この画面だけの一時対応なら DESIGN.md に入れず feature-local のまま扱う`
