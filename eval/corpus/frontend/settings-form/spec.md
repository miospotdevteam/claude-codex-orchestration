# Task: Notification preferences settings form

Build a **notification preferences** settings screen for a web app called
**Cadence**.

## Requirements

- Render a settings page with a heading "Notifications" and a short
  description, then the form.
- Group the controls into **three labeled sections**:
  - **Email** — toggles for: Product updates, Weekly summary, Mentions,
    Security alerts. "Security alerts" must be **on and non-optional**
    (shown as always-on / disabled with an explanation).
  - **Push** — toggles for: Mentions, Direct messages, Reminders. Include
    a "Quiet hours" pair of time inputs (from / to) that is only relevant
    when at least one push toggle is on.
  - **Digest frequency** — a single choice among: Off, Daily, Weekly
    (radio-style, exactly one selected).
- The form has a **sticky action bar** with **Save** and **Cancel**.
  - **Save** is disabled until the user has made a change (dirty state).
  - **Cancel** reverts to the last-saved state.
  - After a successful Save, show a brief confirmation and return to a
    clean (non-dirty) state.
- Seed the form with plausible **default values** so it renders populated,
  not empty.

## Constraints

- Deliver a **single self-contained `index.html`**: all CSS in a
  `<style>` block, all JS in a `<script>` block. No build step, no
  external network requests, no CDN links, no network images.
- Persistence is **in-memory only** — "saved state" lives in JS; no
  backend, no `localStorage` requirement (using it is allowed but not
  required).
- **Responsive**: usable from wide desktop down to ~375px wide; the
  sticky action bar must not obscure content on small screens.
- Vanilla HTML/CSS/JS expected. If you use a framework it must still ship
  as one self-contained file with no network fetches.

## Deliverable

A single `index.html` implementing the settings form with working dirty
state, Save, and Cancel.
