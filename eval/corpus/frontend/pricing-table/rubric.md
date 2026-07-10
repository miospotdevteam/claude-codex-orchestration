# Rubric: SaaS pricing table

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Judge the rendered result and the source together.

## Dimensions

### 1. Visual hierarchy & emphasis
Does the eye land on the recommended Pro plan, then read prices, then
features, in a clear order?
- **High (5):** Pro is unmistakably emphasized (badge, elevation, accent)
  without shouting; price is the largest element per card; consistent
  spacing rhythm. Reads as a designed product, not a wireframe.
- **Low (0-1):** All three plans look identical or emphasis is arbitrary;
  prices and feature lists compete; cramped or uneven spacing.

### 2. Billing toggle ergonomics
Is the monthly/annual toggle obvious, and does switching feel clear?
- **High (5):** Toggle state is obvious at a glance, the saving is
  communicated in words (e.g. "2 months free"), and all prices update
  correctly and instantly on switch.
- **Low (0-1):** Toggle is ambiguous or unlabeled, prices don't all
  update, the annual saving is unstated, or the math is wrong.

### 3. Responsiveness & layout robustness
Does the layout hold from wide desktop down to ~375px?
- **High (5):** Columns stack gracefully into one readable column; no
  overflow, clipping, or horizontal scroll; touch targets stay usable.
- **Low (0-1):** Breaks, overlaps, overflows, or forces horizontal
  scrolling on narrow screens.

### 4. Accessibility
Can the table be used with keyboard and assistive tech?
- **High (5):** Toggle is a real control reachable and operable by
  keyboard with a discernible state (e.g. `aria-pressed`/`role`), buttons
  are focusable with visible focus, color contrast is adequate, and
  price changes are perceivable (not color-only).
- **Low (0-1):** Toggle is a bare `div` with no keyboard access or state,
  no focus styles, or fails contrast.

### 5. Code clarity
Is the single-file source clean and maintainable?
- **High (5):** Sensible structure, semantic HTML, no dead code, plan
  data expressed once rather than duplicated across markup and script;
  readable CSS with a coherent naming approach.
- **Low (0-1):** Copy-pasted blocks, magic values everywhere, tangled or
  duplicated logic, inline style soup.
