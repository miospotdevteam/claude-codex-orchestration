# Task: Design the pagination surface for a list API

Design the **pagination surface** for a REST API and its accompanying
TypeScript SDK, for a resource-heavy product called **Inbox** (think:
messages, threads, contacts). You are designing *how clients page through
large collections* — both the wire contract (query params + response
envelope) and the SDK ergonomics over it.

## Domain & requirements

Collections can be very large (millions of messages) and mutate while a
client pages (new messages arrive). The design must:

- Support paging through a list endpoint such as `GET /v1/messages`
  filtered by query params (e.g. `folder`, `unread`).
- Be **stable under concurrent inserts/deletes** — a client paging from
  start to end should not silently skip or duplicate items because the
  set changed mid-scan. (This strongly implies cursor/keyset paging over
  offset paging; justify your choice.)
- Let a client control **page size**, with a sane default and an enforced
  maximum.
- Return, per page, the **items** plus what's needed to fetch the next
  page and to know whether more exist — without leaking internal storage
  details in the cursor.
- Support paging in **both directions** where it makes sense (e.g. newer /
  older), or clearly justify one direction.
- Provide an **SDK ergonomics layer** so app code can iterate the whole
  collection without hand-managing cursors — e.g. an async iterator that
  yields items (or pages) and fetches lazily.
- Define behavior for **edge cases**: an invalid/expired cursor, an empty
  collection, the last page, and a page size over the maximum.

## What to deliver

Produce a single Markdown document, `design.md`, presenting:

- The **wire contract**: the request query params (with defaults and the
  max page size) and the **response envelope** (items + pagination
  metadata) as JSON/TypeScript, including the opaque-cursor representation
  and how "has more" is signaled.
- The **SDK surface**: the list method signature, its options, and the
  iteration helper (async iterator or equivalent) with a usage example
  that pages through everything without manual cursor handling.
- A short rationale for the **cursor-vs-offset decision** and how the
  design stays stable under concurrent mutation.
- The defined **error/edge behavior** for invalid/expired cursors, empty
  results, the final page, and an over-max page size.
- A note on **extensibility**: adding a new filter, a new sort order, or a
  new field to the envelope without breaking existing clients.

You are proposing the surface — make and state the decisions. Keep the
wire contract and the SDK layer consistent with each other.

## Deliverable

A single `design.md`.
