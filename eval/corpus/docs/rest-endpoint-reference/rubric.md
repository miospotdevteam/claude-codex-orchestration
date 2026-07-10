# Rubric: Document a REST endpoint

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Compare the document against the source of truth in the
spec.

## Dimensions

### 1. Accuracy / fidelity to the source
Does every documented fact match the source, with nothing invented?
- **High (5):** Types, constraints (amount ≥ 50, currency set, length
  caps, expiry range, defaults), status codes, and error codes all match
  the source exactly; no fabricated fields or behaviors.
- **Low (0-1):** Wrong types or constraints, invented fields/endpoints,
  or contradicts the source.

### 2. Completeness
Are all parts of the contract covered?
- **High (5):** Auth, every request field (required/optional + default),
  every response field, the success status, and the full error surface
  (401 / 422 codes / 400 / 429 + Retry-After) are all present.
- **Low (0-1):** Missing auth, omitted fields, or no error documentation.

### 3. Structure & scannability
Can a developer find what they need fast?
- **High (5):** Logical sections (summary → auth → request → response →
  errors → example), a clean parameter table, consistent heading levels;
  skimmable.
- **Low (0-1):** Wall of prose, no sections or tables, hard to locate the
  request fields or error codes.

### 4. Example quality
Are the examples realistic, correct, and runnable?
- **High (5):** A copy-pasteable request (e.g. `curl` with the auth
  header) and a matching response body that are internally consistent and
  obey the documented constraints.
- **Low (0-1):** No example, an example that violates the constraints, or
  request/response that don't correspond.

### 5. Clarity & tone
Is it written for an external integrator?
- **High (5):** Precise, neutral, jargon-controlled prose; constraints
  stated unambiguously; no internal-implementation leakage.
- **Low (0-1):** Vague, ambiguous, or leaks internal handler details the
  consumer can't use.
