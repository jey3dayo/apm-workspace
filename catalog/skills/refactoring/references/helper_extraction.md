# Common Helper Extraction Judgment

Use this reference during Phase 1-D when duplicate code appears inside
components, pages, actions, or repositories. Do not extract only because the
text is similar. First classify the duplicated operation by concern, owner
candidates, and caller rule.

| Concern                                                                 | Owner candidates                                   | Caller rule                                                                | Do not extract when                                                                        |
| ----------------------------------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Cross-cutting contract guard, e.g. `ServerActionResult` shape narrowing | shared `lib/...` boundary owner                    | Callers import the guard instead of re-declaring object-shape checks       | The check is tied to one component's local UI state or one-off framework callback          |
| Feature-specific pure transform, e.g. repository row -> table row       | `features/<feature>/...`                           | Pages/components import the feature helper; keep feature terminology local | The transform is a render fragment, hook-dependent, or uses component-local translations   |
| Feature-specific classification, e.g. profile `role:` or entry type     | feature repository/helper or schema-adjacent file  | Repository, page, export, and tests use one exported predicate/normalizer  | The duplicate appears only in test mocks or fixture setup and mirrors a mocked dependency  |
| Schema/list-backed option conversion                                    | existing schema/constants owner plus feature API   | Reuse exported lists/schemas and expose narrow UI/export helpers as needed | A new helper would fork message ownership or duplicate i18n keys                           |
| Date/filter display conversion                                          | shared component helper when UI contract is shared | Toolbar, chip, and filter consumers share parse/format helpers             | The format belongs to a domain table or timestamp display with different semantics         |
| TSX-local pure UI classification, e.g. tab/step/status parsing          | sibling `*-helpers.ts` or feature helper           | TSX imports pure helpers; helper tests cover classification and fallbacks  | The logic returns JSX, closes over hooks/state, or depends on component-local translations |

## Decision Rule

Extraction is usually worthwhile when the helper is small, pure, used by
multiple production callers, and represents a stable boundary contract or
feature concept.

Keep it local when it closes over hooks/state, render shape, component
translations, or screen-specific copy.

Test-only duplication can stay inside mocks when importing the real helper
would make the test less isolated.

## TSX Helper Extraction Pattern

When a `.tsx` file has too many top-level helper functions, separate render
fragments from pure decisions before moving code:

1. Keep JSX-producing components, hook-dependent code, event handlers, and
   translation lookups in the `.tsx` file unless they are shared UI components.
2. Move pure classification, parsing, fallback mapping, type guards, and
   class-name selection into a sibling `*-helpers.ts` when the logic is owned
   by that screen or component.
3. Move domain status mapping or schema/list-backed conversion into the
   feature owner when the helper is a feature contract, not a presentation
   detail.
4. Add focused helper tests for the moved pure logic, especially fallback
   behavior, type-guard narrowing inputs, and grouped status mappings.
5. Remove completed TODO entries in the same slice; leave only remaining
   follow-up candidates.

Prefer a sibling helper for screen-specific copy-shape logic. Prefer a feature
helper for reusable state-machine/status mapping. Avoid `src/lib` until the
helper is genuinely cross-feature and has a stable caller contract.
