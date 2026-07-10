# Task: Dashboard empty state

Build the **empty state** for the "Projects" page of a project-management
app called **Cadence**. This is what a brand-new user sees the first time
they open the app, before they have created any project.

## Requirements

- Render a full **Projects page shell**: a top bar with the app name
  "Cadence" and a placeholder avatar on the right, a page heading
  "Projects", and the main content area occupied by the empty state.
- The **empty state** in the content area must:
  - Explain, warmly and briefly, that there are no projects yet and what
    a project is for.
  - Offer a **primary action**: "Create your first project".
  - Offer a **secondary, lower-emphasis path**: "Import from a template".
  - Include a supporting illustration or graphic (inline SVG or CSS —
    no network images) that suits an empty state without being noisy.
- The empty state must read as intentional and inviting, not like an
  error or a blank screen.
- Include one line pointing to help (e.g. a link "Learn about projects")
  that is clearly tertiary.

## Constraints

- Deliver a **single self-contained `index.html`**: all CSS in a
  `<style>` block, any JS in a `<script>` block. No build step, no
  external network requests, no CDN links, no network images.
- **Responsive**: usable from wide desktop down to ~375px wide.
- Buttons and links are non-functional placeholders.
- No framework is required; if you use one it must still ship as one
  self-contained file with no network fetches.

## Deliverable

A single `index.html` that renders the Projects page with its empty
state.
