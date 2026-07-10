# Task: Toast notification system

Build a **toast notification system** — the transient messages that slide
in to confirm an action or report an error.

## Requirements

- Provide a small **API** to trigger a toast from application code, e.g.
  `toast.success("Saved")`, `toast.error("Upload failed")`,
  `toast.info(...)`, `toast.warning(...)`. Name the API as you see fit,
  but a single call must be enough to show a toast.
- Support **four variants**: success, error, info, warning — each
  visually distinct (icon + color), while staying one coherent family.
- Each toast has a message and an optional title, and a **manual dismiss**
  (close) control.
- Toasts **auto-dismiss** after a timeout (default ~4s). Error toasts
  should be stickier (longer, or require manual dismissal — your call,
  but justify it in code or comments).
- **Stacking**: multiple toasts stack in a consistent corner and do not
  overlap; new toasts enter and dismissed toasts leave with a subtle
  animation.
- **Pause on hover**: hovering a toast pauses its auto-dismiss timer so a
  user can read it.
- To make the result reviewable, include four demo buttons on the page —
  one per variant — that each trigger a representative toast. Also
  demonstrate that stacking works (e.g. clicking quickly enqueues
  several).

## Constraints

- Deliver a **single self-contained `index.html`**: all CSS in a
  `<style>` block, all JS in a `<script>` block. No build step, no
  external network requests, no CDN links, no network images (inline SVG
  or CSS for icons).
- Vanilla HTML/CSS/JS expected. If you use a framework it must still ship
  as one self-contained file with no network fetches.
- **Responsive**: toasts remain readable and correctly positioned down to
  ~375px wide.
- Respect `prefers-reduced-motion` for the animations.

## Deliverable

A single `index.html` with the toast system and the demo buttons.
