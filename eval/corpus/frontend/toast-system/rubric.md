# Rubric: Toast notification system

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Judge the rendered result and the source together.

## Dimensions

### 1. API ergonomics
How pleasant is the trigger API to call from application code?
- **High (5):** One expressive call shows a toast; variants are obvious
  methods or options; title/message and overrides are handled cleanly; a
  developer could adopt it without reading the internals.
- **Low (0-1):** Verbose or awkward call site, must hand-build DOM,
  inconsistent variant handling, or leaks internal details to the caller.

### 2. Variant design & visual coherence
Are the four variants distinct yet clearly one family?
- **High (5):** Success/error/info/warning are instantly distinguishable
  by icon and color, share a consistent shape/typography/spacing system,
  and status is not conveyed by color alone.
- **Low (0-1):** Variants indistinguishable, clashing or arbitrary
  colors, or a different visual language per variant.

### 3. Interaction & edge-case handling
Do stacking, auto-dismiss, pause-on-hover, and manual close all work?
- **High (5):** Toasts stack without overlap, enter/leave smoothly,
  auto-dismiss on a sensible timer, pause on hover, and close on demand;
  many rapid toasts behave sanely (queue/cap rather than chaos).
- **Low (0-1):** Overlap, stuck toasts, broken timers, no pause on hover,
  or the UI breaks under a burst of toasts.

### 4. Motion & accessibility
Are the animations tasteful and is the system accessible?
- **High (5):** Subtle, non-janky transitions that respect
  `prefers-reduced-motion`; toasts are announced to assistive tech (e.g.
  an `aria-live` region / `role="status"`|`"alert"`); close controls are
  focusable/labeled with visible focus.
- **Low (0-1):** Jarring or motion-sickness-inducing animation, ignores
  reduced-motion, no live region, or unlabeled close buttons.

### 5. Code clarity
Is the single-file implementation clean and well-factored?
- **High (5):** Clear separation between the toast API, the queue/timer
  logic, and rendering; no leaks (timers cleared, nodes removed); readable
  and free of dead code.
- **Low (0-1):** Tangled global state, duplicated DOM building, leaked
  timers or detached nodes, magic numbers throughout.
