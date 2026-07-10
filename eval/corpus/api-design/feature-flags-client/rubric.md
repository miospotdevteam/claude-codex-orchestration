# Rubric: Feature-flags client SDK surface

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Judge the proposed surface in `design.md`.

## Dimensions

### 1. Ergonomics
Is the common path (evaluate a bool flag with a default) trivial, while
advanced needs stay reachable?
- **High (5):** A one-liner covers the 90% case; typed defaults are
  natural; getting evaluation detail is opt-in, not forced on every call;
  a single client is obviously safe to hold for the process lifetime.
- **Low (0-1):** Boilerplate for a simple check, defaults awkward to
  pass, or detail/logging concerns pollute the simple call.

### 2. Naming & consistency
Are names clear and is the surface internally consistent?
- **High (5):** Method and type names are predictable and uniform across
  the bool/string/number/JSON variants; one naming convention; nothing
  surprising or redundant.
- **Low (0-1):** Ad hoc or clashing names, inconsistent variant naming,
  or the same concept named differently in two places.

### 3. Error handling & safe degradation
Does the design fail safe by construction?
- **High (5):** Evaluations return the caller's default (never throw) when
  the flag is unknown or the service is unreachable; the "why" (error
  reason) is still observable via detail; init/shutdown errors are handled
  sensibly and documented.
- **Low (0-1):** Evaluations can throw on the hot path, no defined
  degradation behavior, or errors are swallowed with no way to observe
  them.

### 4. Extensibility
Can the surface grow without breaking callers?
- **High (5):** New flag value types, new evaluation reasons, or new
  options can be added without changing existing signatures (e.g.
  options object, discriminated reason enum, additive variants); the
  author explains the growth path.
- **Low (0-1):** Rigid positional params or closed types that would force
  a breaking change to extend.

### 5. Type & context design
Are the context and evaluation-detail models well-shaped?
- **High (5):** The evaluation context cleanly carries an id plus
  arbitrary typed attributes; the evaluation-detail shape captures value,
  variation, and reason usefully; generics/typing make defaults and
  return types line up.
- **Low (0-1):** Stringly-typed context, a detail shape that omits the
  reason, or types that force unsafe casts at the call site.
