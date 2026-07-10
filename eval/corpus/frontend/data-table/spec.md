# Task: Sortable, paginated data table

Build a **users data table** for an admin console. The table must handle
sorting, pagination, and the empty / loading / error states that a real
data table needs.

## Requirements

- Render a table of **users** with these columns: Name, Email, Role
  (Admin / Member / Viewer), Status (Active / Invited / Suspended),
  Last active (a date). Include a status indicator (e.g. a colored dot or
  pill), not just raw text.
- **Sorting**: clicking a column header sorts by that column, toggling
  ascending/descending, with a clear indicator of the active sort column
  and direction. At least Name, Role, and Last active must be sortable.
- **Pagination**: page through the data, 10 rows per page, with controls
  showing current page and total, and prev/next (disabled at the ends).
- The table must correctly render all of these states:
  - **Loading** — a skeleton or spinner while data is "loading".
  - **Loaded** — the populated table.
  - **Empty** — a friendly empty state when there are zero users.
  - **Error** — an error state with a retry affordance.
- Provide controls on the page to **simulate each state** (e.g. buttons:
  "Loading", "Loaded", "Empty", "Error") so the states are reviewable.
- Seed **at least 23 sample users** so pagination spans multiple pages.

## Constraints

- Deliver a **single self-contained `index.html`**: all CSS in a
  `<style>` block, all JS in a `<script>` block. No build step, no
  external network requests, no CDN links, no network images.
- The sample data is generated/hard-coded in JS — no fetch.
- **Responsive**: the table must remain usable down to ~375px wide
  (horizontal scroll within a container, a stacked/card layout, or column
  hiding — your choice, but it must not break the page).
- Vanilla HTML/CSS/JS expected. If you use a framework it must still ship
  as one self-contained file with no network fetches.

## Deliverable

A single `index.html` with the data table, working sort and pagination,
and the four selectable states.
