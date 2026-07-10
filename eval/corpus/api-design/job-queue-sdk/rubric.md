# Rubric: Background-job-queue client SDK

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Judge the proposed surface in `design.md`.

## Dimensions

### 1. Ergonomics (both roles)
Are enqueue and handler-registration pleasant for the common case?
- **High (5):** Enqueuing a job and registering a handler are each a few
  lines; per-job options are a clean optional bag; concurrency and
  shutdown are simple to configure; the 90% path isn't taxed by advanced
  options.
- **Low (0-1):** Heavy boilerplate to enqueue or consume, options awkward
  to pass, or the two roles feel like unrelated APIs.

### 2. Type linkage (producer ↔ worker)
Do payload and result types keep producer and worker in sync?
- **High (5):** A queue is declared once with payload `T` (and result `R`);
  `enqueue` and the handler both derive their types from it, so a mismatch
  is a compile error; job metadata (attempt, id) is typed.
- **Low (0-1):** Stringly-typed queues with `any` payloads, or producer
  and worker types can silently diverge.

### 3. Naming & consistency
Are names clear and uniform across producer, worker, and events?
- **High (5):** Predictable, uniform naming; job states and lifecycle
  event names are one coherent vocabulary; option names read consistently.
- **Low (0-1):** Ad hoc or clashing names, states named differently from
  the events that report them, inconsistent option naming.

### 4. Error handling & retry semantics
Is failure modeled well?
- **High (5):** Retry policy (attempts + backoff) is first-class;
  retryable vs permanent failure is expressible and a permanent failure
  correctly skips remaining attempts; dedup/idempotency semantics are
  defined; graceful shutdown drains in-flight work with a timeout.
- **Low (0-1):** Only "throw = fail" with no retry control, no way to mark
  a permanent failure, or undefined shutdown/dedup behavior.

### 5. Extensibility & observability
Can it grow, and can operators see what's happening?
- **High (5):** A subscribable event surface (completed/failed/retrying/
  stalled) supports logging/metrics; new options, states, or events can be
  added additively without breaking existing code; the growth path is
  explained.
- **Low (0-1):** No observability surface, or adding a state/option/event
  would break existing producers/workers.
