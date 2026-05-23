# Design And CSS Check Checklist

Use this checklist selectively. Load it when the task asks for UI review, CSS review, visual polish, screenshot comparison, or modern CSS opportunities.

## 1. Product Fit

- Match the product type: operational tools should be dense, calm, and scannable; editorial or brand surfaces can be more expressive.
- Make primary workflows visible without turning the first screen into marketing copy.
- Prefer one clear primary action per region.
- Avoid decorative complexity that competes with repeated-use workflows.

## 2. Visual Hierarchy

- Check whether the eye lands on the right content first.
- Use size, weight, spacing, and position before adding color.
- Keep headings proportionate to their container. Avoid hero-scale type in compact panels.
- Align numeric values, timestamps, and repeated labels for scanning.
- Ensure icons, badges, and text baselines feel optically aligned.

## 3. Layout Robustness

- Verify text fits at mobile and desktop widths.
- Use stable dimensions for toolbars, icon buttons, counters, grids, and fixed-format surfaces.
- Avoid nested cards and page sections styled as floating cards unless the app's system already requires it.
- Check hover, selected, loading, empty, disabled, error, and long-content states.
- Prefer component-local responsive rules when the component appears in multiple containers.

## 4. Color And Contrast

- Use semantic tokens before raw hex values.
- Confirm foreground/background pairs meet contrast expectations.
- Do not communicate status with color alone; add icon, text, shape, or position.
- In dark mode, avoid simply inverting light colors. Use tuned, usually less saturated, tonal variants.
- Watch one-note palettes: too many near-identical hues can flatten hierarchy.

## 5. Modern Color And Gradients

- Prefer `color-mix()` when deriving hover, border, ring, or muted colors from tokens.
- Consider `oklch()` when designing new tokens that need perceptual tuning.
- Consider `linear-gradient(... in oklch, ...)` for vivid gradients where the midpoint should stay lively.
- Use `background-clip: text` only for short display text where gradient text adds meaning or brand value.
- Add fallbacks or avoid modern syntax when the target environment may not support it reliably.
- Avoid multicolor gradients in utilitarian app surfaces unless they mark a specific status, brand moment, or empty-state illustration.

## 6. CSS Architecture

- Prefer native CSS layout primitives over JavaScript measurement when possible.
- Prefer Popover API, anchor positioning, and invoker commands for menus, popovers, tooltips, and dialogs when browser support fits the target.
- Prefer `subgrid` for card grids where child rows must align across siblings.
- Prefer container queries for reusable components whose layout depends on container size rather than viewport size.
- Keep selectors resilient. Avoid styling against incidental DOM structure unless the component owns that structure.
- For Tailwind variants and component attributes, confirm the class selector matches the DOM attributes emitted by the shared primitive.
- Keep browser support explicit when using Limited or Newly available CSS features.

## 7. Interaction And Motion

- Prefer CSS transitions for interruptible hover, focus, pressed, open, and close states.
- Animate opacity and transform before layout, paint-heavy properties, or filter-heavy effects.
- Keep motion short and purposeful; respect `prefers-reduced-motion`.
- Make focus-visible states clear and consistent with the design system.
- Pressed and hover states should not shift layout bounds.

## 8. Accessibility

- Use semantic buttons, links, inputs, dialogs, and lists before ARIA patches.
- Confirm icon-only controls have accessible labels.
- Ensure keyboard order follows visual order.
- Verify disabled and read-only states are visually and semantically distinct.
- Keep live regions and toasts polite unless the event is urgent.

## 9. Implementation Hygiene

- Prefer shared primitives and token variables over one-off class strings.
- Keep styling close to the component only when it is component-specific; move reusable rules to the design system.
- Avoid introducing new dependencies for a small visual effect.
- Check tests or snapshots that assert class names before changing shared styling.
- For generated screenshots, reports, or temporary comparisons, write under the repo `tmp/` directory unless the user names another path.
