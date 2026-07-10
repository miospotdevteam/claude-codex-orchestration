# Rubric: Migration guide

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Compare against the source of truth in the spec.

## Dimensions

### 1. Accuracy / fidelity to the source
Are all six changes represented correctly?
- **High (5):** Option renames (incl. `retry` number → `retries` object),
  explicit body access, the non-rejecting error model + `throwOnError`,
  the removed `stream()`, the Node bump, and the new `use()` are all
  described correctly; nothing invented.
- **Low (0-1):** Missing or wrong on any breaking change, or invents
  changes not in the source.

### 2. Before/after actionability
Can a reader mechanically update their own code?
- **High (5):** Each breaking change has a concrete v2 → v3 before/after
  (diff or side-by-side) that a user can pattern-match against; the edits
  are obvious.
- **Low (0-1):** Prose-only description with no code, or examples too
  abstract to apply.

### 3. Handling of the subtle error-behavior change
Is the trickiest change explained well?
- **High (5):** Clearly warns that non-2xx no longer rejects by default
  (a silent behavior change), shows the `res.ok`/`status` inspection
  pattern, and shows `throwOnError: true` + `HttpError` to restore old
  behavior.
- **Low (0-1):** Glosses over it, gets the default wrong, or omits how to
  restore throwing.

### 4. Ordering & prioritization
Does the guide lead with what matters most?
- **High (5):** Most impactful/common changes (options, body access,
  errors) come first; prerequisites are up front; the new optional
  feature is clearly secondary.
- **Low (0-1):** Random ordering, buries a common breaking change, or
  gives the optional feature equal prominence.

### 5. Clarity & structure
Is it well organized and readable under upgrade pressure?
- **High (5):** Scannable sections, a clear checklist-like flow,
  consistent code formatting, honest about effort; a reader can migrate
  confidently.
- **Low (0-1):** Disorganized, ambiguous, or so terse the reader can't
  tell what to do.
