# Rubric: SDK class API reference

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Compare against the source of truth in the spec.

## Dimensions

### 1. Accuracy / fidelity to the source
Do signatures, defaults, and behaviors match the class exactly?
- **High (5):** Every method signature, option default (`maxValueBytes`
  1 MiB, TTL rules), and edge behavior (throws on oversize/non-JSON,
  `delete`/`has` return semantics, expiry ⇒ `undefined`, `getOrSet`
  coalescing) is stated correctly; nothing invented.
- **Low (0-1):** Wrong signatures/defaults, invented methods, or omitted
  error behavior.

### 2. Completeness of the surface
Is the whole public surface documented?
- **High (5):** Constructor + all seven methods + all option fields
  covered, each with parameters and return value.
- **Low (0-1):** Missing methods, options, or return/throw documentation.

### 3. Edge-case & caveat coverage
Are the subtle behaviors surfaced, not buried?
- **High (5):** Explicitly flags the runtime-unchecked generic on
  `get`/`getOrSet`, the no-expiry default, the oversize/non-serializable
  throws, and the `getOrSet` single-flight coalescing.
- **Low (0-1):** Treats the class as if it never throws and never
  mentions the generic or coalescing caveats.

### 4. Example quality
Is the usage example realistic and correct?
- **High (5):** At least one example showing `set`/`get` and the
  `getOrSet` cache-aside pattern; type-correct against the signatures;
  demonstrates real usage, not a toy.
- **Low (0-1):** No example, or code that doesn't match the signatures.

### 5. Structure & clarity
Is the reference well organized and readable?
- **High (5):** Intro → construction → per-method reference with
  consistent formatting (signature, params, returns, throws); scannable;
  precise prose aimed at an SDK consumer.
- **Low (0-1):** Disorganized, inconsistent method formatting, or vague
  descriptions that don't say what a method returns or throws.
