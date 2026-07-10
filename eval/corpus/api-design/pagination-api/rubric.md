# Rubric: List/pagination API surface

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Judge the proposed surface in `design.md`.

## Dimensions

### 1. Correctness under mutation (the core design choice)
Does the scheme avoid skips/duplicates as the collection changes?
- **High (5):** Chooses cursor/keyset paging with a clear justification,
  and explains why it's stable under concurrent inserts/deletes where
  offset paging would skip or duplicate; the cursor encodes a stable
  position, not an offset.
- **Low (0-1):** Offset/page-number paging with no acknowledgment of the
  mutation hazard, or a cursor scheme that doesn't actually prevent
  skips/dupes.

### 2. Ergonomics (SDK iteration)
Can app code consume the whole collection painlessly?
- **High (5):** An async iterator (or equivalent) yields items/pages and
  fetches lazily so callers never touch a cursor; page-size control is
  simple; the common "iterate everything" case is a few lines.
- **Low (0-1):** Callers must manually thread cursors, or there's no
  iteration helper and no clean way to consume all pages.

### 3. Contract clarity & consistency
Are the wire contract and SDK coherent and well specified?
- **High (5):** Request params (defaults, enforced max) and the response
  envelope (items + next-cursor + has-more) are precisely specified and
  consistent with the SDK layer; the cursor is genuinely opaque (no leaked
  storage internals).
- **Low (0-1):** Vague or inconsistent envelope, cursor leaks internal
  keys, or SDK and wire contract disagree.

### 4. Edge-case & error handling
Are the boundary conditions defined?
- **High (5):** Defined behavior for invalid/expired cursor, empty
  collection, last page (how "no more" is signaled), and page size over
  the max (clamp vs error — stated); errors are typed/meaningful.
- **Low (0-1):** Edge cases unaddressed, an over-max size silently
  ignored, or no defined behavior for a bad cursor.

### 5. Extensibility
Can the surface grow without breaking clients?
- **High (5):** New filters, sort orders, or envelope fields can be added
  additively; the opaque cursor lets the server change its keyset without
  a client change; the growth path is explained.
- **Low (0-1):** Adding a filter or field would break clients, or a
  transparent cursor pins the server's internals into the contract.
