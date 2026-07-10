# Task: SaaS pricing table

Build a responsive, three-tier pricing table for a SaaS product called
**Pageform** (a form-builder tool).

## Requirements

- **Three plans**, side by side on desktop:
  - **Starter** — $0/mo. Up to 3 forms, 100 responses/mo, basic fields.
  - **Pro** — $19/mo (or $190/yr). Unlimited forms, 10,000 responses/mo,
    logic branching, file uploads, remove branding.
  - **Team** — $49/mo (or $490/yr). Everything in Pro, plus 5 seats,
    shared workspaces, audit log, priority support.
- A **monthly / annual billing toggle** at the top. Annual billing shows
  the per-month-equivalent price and communicates the saving (two months
  free). Toggling updates all prices without a page reload.
- **Pro is the recommended plan** and must be visually emphasized as the
  default choice.
- Each plan has a **call-to-action button**: Starter → "Get started",
  Pro and Team → "Start free trial".
- Each plan lists its features. Where a plan builds on a cheaper one,
  make the "everything in X, plus" relationship legible rather than
  repeating the full list verbatim.

## Constraints

- Deliver a **single self-contained `index.html`** file: all CSS in a
  `<style>` block and all JS in a `<script>` block. No build step, no
  external network requests, no CDN links, no images from the network
  (inline SVG or CSS is fine).
- Must be **responsive**: the three columns stack into a single readable
  column on narrow (≈375px) viewports.
- No framework is required; vanilla HTML/CSS/JS is expected. If you use a
  framework it must still ship as one self-contained file with no network
  fetches.
- Do not include a real payment flow — the CTA buttons are non-functional
  placeholders.

## Deliverable

A single `index.html` that renders the pricing table and whose billing
toggle works.
