# Review Lanes

Add new lanes by appending the next numbered section with the same fields. `SKILL.md` should stay focused on routing and execution rules.

## Lane Authoring Rules

- `Trigger` must distinguish the lane from nearby lanes and name the artifact or request shape that should select it.
- `Prompt` should define the expert stance without hiding the need for evidence.
- `Cover` should list evidence-checkable review criteria, not taste-only preferences.
- `Deliver` must state whether the lane is review-only or implementation-capable.

## Routing Notes

- Choose one primary lane. Use secondary checks only for specific risks that the primary lane does not cover.
- When a routing note explicitly matches the request, select that primary lane instead of offering a menu. Offer candidates only when multiple triggers are equally strong and the choice would change the review.
- For overlapping UI concerns, choose the lane by the user's main complaint: system consistency → lane 1; accessibility, viewport, or input method behavior → lane 2; missing or vague design direction → lane 3; end-to-end completion → lane 4; one-page visual quality → lane 5; component state behavior → lane 6; conversion → lane 7; entered data and submission → lane 8.
- For form-heavy artifacts, prefer lane 8. Add lane 2 when accessibility or viewport behavior is the main concern, and lane 6 when state coverage is the main concern.
- For broad product flows, prefer lane 4 before judging individual pages or controls.
- For vague visual dissatisfaction, prefer lane 3 first when design instructions may be missing; use lane 1 when a design system exists and should be enforced.
- When the user asks to review, fix, and re-review until the result is strong enough to ship, use Review And Fix Loop mode from `SKILL.md`, then still choose one primary lane from this catalog.
- Use persona overlays from `SKILL.md` only as secondary stance modifiers. Common matches: Evidence Collector for lanes 2 and 6 when visual or browser evidence is thin; Reality Checker for lane 4 or final readiness reviews; Minimal Change Engineer for Review And Fix Loop implementation.

## 1. Design System Review

Trigger:
Use when the artifact includes UI screens, components, layouts, visual styling, themes, or brand-sensitive product surfaces.

Prompt:
Act as a senior product designer and design-system reviewer. Do not say that something "looks off" without naming the broken system rule.

Cover:

- design tokens and semantic token usage
- color palette, contrast intent, and state colors
- typography scale, hierarchy, line length, and rhythm
- spacing rhythm, density, alignment, and layout consistency
- component states: hover, focus, active, disabled, loading, empty, error, success
- reusable component patterns and local one-off divergence
- brand, mood, and product-context alignment

Deliver:
Group findings by severity. For each finding, name the violated design-system criterion, point to evidence, and recommend the smallest fix. If the project lacks tokens, type scale, spacing rules, or component-state guidance, mark that as a design-input gap. If implementation is requested, verify the changed surface against the relevant tokens, component states, and at least one representative viewport or screenshot.

## 2. Accessibility + Multi-Device Review

Trigger:
Use when the artifact includes browser-visible UI, interactive controls, navigation, dialogs, forms, responsive layouts, or motion.

Prompt:
Act as a senior accessibility engineer and multi-device QA reviewer. Verify behavior across input methods and viewports instead of relying on static visual inspection.

Cover:

- WCAG-relevant semantics, names, roles, labels, and relationships
- keyboard navigation, focus order, focus visibility, and escape paths
- screen-reader-friendly status, error, loading, and success announcements
- color contrast and non-color-only communication
- responsive layout across mobile, tablet, and desktop viewports
- touch targets, mobile input ergonomics, and hit areas
- reduced-motion behavior and animation safety
- overflow, clipping, zoom, and long-content behavior

Deliver:
Group findings by severity. Include browser or screenshot evidence when available. Recommend concrete fixes and the minimum verification pass: keyboard flow, representative mobile and desktop viewports, and any relevant accessibility checks. If implementation is requested, rerun the affected keyboard, viewport, and accessibility checks after the change.

## 3. DESIGN.md First Review

Trigger:
Use when the user is unhappy with design output, visual direction, layout consistency, brand fit, or repeated frontend iteration quality, especially before asking the model to keep tweaking the artifact.

Prompt:
Act as a design brief reviewer. Before criticizing the artifact, inspect whether the model was given enough design direction to produce the expected result.

Cover:

- existence and quality of `DESIGN.md`, design brief, or equivalent guidance
- design tokens, color palette, typography scale, spacing system, and layout rules
- component states and interaction rules
- target mood, brand adjectives, density, and product context
- reference screenshots, existing product surfaces, Storybook, or component docs
- mismatch between requested output and provided design inputs

Deliver:
If design guidance is missing or too vague, state that the primary issue is input-specification debt. Recommend the design brief, tokens, typography, spacing, and component rules to create before implementation changes. If guidance exists, use it to review the artifact against the stated criteria. If implementation is requested, first decide whether the fix belongs in the design guidance or the UI implementation, then verify the changed artifact against the updated or existing guidance.

## 4. UX Audit

Trigger:
Use when the artifact includes a real product flow, dashboard, onboarding path, checkout path, admin workflow, or any end-to-end task that should be evaluated in context.

Prompt:
Act as a senior UX designer auditing the core flow. Walk the actual user path from start to finish before judging individual screens.

Cover:

- user goal, entry point, path completion, and exit state
- information architecture and whether the next action is obvious
- empty, loading, partial, error, success, and recovery states across the flow
- friction, dead ends, redundant steps, and ambiguous labels
- state visibility: what the user knows, what changed, and what remains
- trust, confidence, and confirmation before irreversible actions
- evidence gathered from screenshots, browser state, test data, or the live UI

Deliver:
Group findings by flow-breaking severity. Include the exact step where each issue appears and recommend fixes that improve task completion, not just visual polish. If implementation is requested, re-walk the affected flow through the entry point, completion state, and recovery path.

## 5. Rebuild One Page With Real Taste

Trigger:
Use when one page feels generic, visually weak, off-brand, or below the quality bar of polished SaaS/product pages.

Prompt:
Act as a product designer and rebuild this page with a clear product taste, using strong references only as direction rather than copying them.

Cover:

- page purpose, primary user intent, and content hierarchy
- visual direction, density, rhythm, and restraint
- typography, spacing, surfaces, dividers, icon use, and component composition
- reference-quality cues from polished products such as Linear or Stripe when appropriate
- replacement of generic defaults with deliberate design decisions
- preservation of usability, accessibility, and product constraints

Deliver:
When reviewing only, identify the smallest design-system or page-composition changes before proposing a rebuild. When implementation is requested, recommend or implement a full-page redesign. Explain the design direction, the concrete system changes, and the before/after behavioral risks to verify. Verify the redesign with at least one desktop and one mobile check, and confirm core actions remain reachable.

## 6. Interaction And State Perfection Review

Trigger:
Use when the artifact has buttons, menus, dialogs, async actions, tables, filters, panels, or any interactive surface with multiple states.

Prompt:
Act as a senior frontend engineer and make every interaction and state precise.

Cover:

- hover, focus, active, selected, disabled, pressed, expanded, and current states
- loading, optimistic, empty, partial, error, success, retry, and timeout states
- keyboard and pointer parity
- focus management for dialogs, menus, popovers, tabs, and routed transitions
- disabled vs loading semantics and prevention of duplicate submission
- microcopy for status and recovery
- motion timing, reduced motion, and layout stability during state changes

Deliver:
List missing or inconsistent states with evidence. If implementation is requested, add the full state model and verify it with relevant tests or browser interaction, including keyboard and pointer parity for the affected controls.

## 7. Landing Page Conversion Review

Trigger:
Use when the artifact is a landing page, marketing page, launch page, waitlist page, pricing page, product intro, or other conversion-focused surface.

Prompt:
Act as a conversion-focused designer and build or review the landing page for clarity, trust, and action.

Cover:

- first-viewport offer clarity and audience fit
- value proposition, proof, objection handling, and call-to-action hierarchy
- section order, scanability, and narrative momentum
- visual proof: product, screenshots, demos, social proof, metrics, or concrete examples
- pricing, comparison, FAQ, and risk-reversal where relevant
- performance, mobile conversion, accessibility, and analytics hooks

Deliver:
Group findings by conversion impact. Recommend or implement changes that make the page more credible, specific, and action-oriented without turning it into generic marketing filler. If implementation is requested, verify first-viewport clarity, CTA reachability, mobile layout, accessibility basics, and any analytics hook touched by the change.

## 8. Form Usability Review

Trigger:
Use when the artifact includes forms, settings screens, checkout flows, onboarding, search filters, admin inputs, or any user-entered data.

Prompt:
Act as a senior frontend engineer and make this form usable.

Cover:

- real-time validation
- clear inline errors
- sensible defaults
- keyboard and autofill friendliness
- submitting, loading, success, and failure states
- long forms split into steps where appropriate
- mobile input ergonomics and input types
- data loss prevention for destructive navigation or accidental dismissal
- disabled states, retry paths, and recovery from server errors

Deliver:
If the user requested implementation, deliver the full implementation and verification. Otherwise, group findings by severity and recommend fixes that improve completion rate, error recovery, and confidence before submit. Verification should cover keyboard and autofill behavior, validation and inline errors, submit/loading/success/failure states, and mobile input ergonomics when applicable.
