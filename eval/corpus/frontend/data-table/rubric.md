# Rubric: Sortable, paginated data table

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Judge the rendered result and the source together.

## Dimensions

### 1. Table legibility & visual hierarchy
Is the table easy to scan?
- **High (5):** Clear header/row distinction, comfortable row height and
  alignment (numbers/dates aligned sensibly), status shown with a legible
  indicator; the table reads at a glance.
- **Low (0-1):** Cramped or misaligned cells, undifferentiated header,
  status as bare text, visually noisy.

### 2. Sorting & pagination ergonomics
Do the interactions feel correct and obvious?
- **High (5):** Active sort column and direction are clearly indicated;
  clicking toggles asc/desc correctly; pagination shows position and
  total, disables prev/next at the ends, and never shows an out-of-range
  page after a state change.
- **Low (0-1):** No sort indicator, wrong sort order, pagination that
  can go out of range, or controls that don't disable at the boundaries.

### 3. State coverage (loading / empty / error)
Are all four states handled well?
- **High (5):** Distinct, purposeful loading (skeleton/spinner), a
  friendly empty state, and an error state with a working retry; switching
  states never leaves stale rows or broken pagination.
- **Low (0-1):** Missing states, an error state indistinguishable from
  empty, or state changes that corrupt the table.

### 4. Accessibility
Is the table accessible?
- **High (5):** Real `<table>` semantics (or correct ARIA grid roles);
  sortable headers are buttons/`aria-sort` with keyboard support; status
  not conveyed by color alone; pagination controls labeled with visible
  focus.
- **Low (0-1):** Divs pretending to be a table with no semantics,
  mouse-only sorting, color-only status, unlabeled pagination.

### 5. Code clarity
Is the single-file source clean and well-factored?
- **High (5):** One data model, with sort + paginate as pure derivations
  and a single render path off current state; no duplicated row-building;
  readable and free of dead code.
- **Low (0-1):** State smeared across the DOM, sorting/pagination logic
  duplicated or entangled with rendering, copy-pasted markup, magic
  numbers.
