# Task: Design a background-job-queue client SDK

Design the **client SDK surface** for a background-job-queue service
called **Relay**, for Node.js/TypeScript apps. Producers enqueue jobs;
workers consume and process them. You are designing the *library API app
code uses* — both sides — not the queue backend.

## Domain & requirements

The SDK must cover both roles:

**Producer side:**
- **Enqueue** a job onto a named queue with a typed payload.
- Per-job options: **delay** (run no earlier than N ms / a timestamp),
  **priority**, **max attempts / retry policy** (e.g. backoff strategy),
  a **dedup/idempotency key** (enqueuing twice with the same key within a
  window is a no-op), and a **job id** for later lookup.
- **Query** a job's status by id (waiting / active / completed / failed /
  delayed) and its result or last error.
- Support **bulk enqueue** of many jobs efficiently.

**Worker side:**
- **Register a handler** for a named queue: a typed async function that
  receives the job (payload + metadata like attempt number) and either
  returns a result (success) or throws (failure → retry per policy).
- Control **concurrency** (how many jobs a worker processes at once).
- A handler must be able to report **progress** and to distinguish a
  **retryable** failure from a **permanent** one (a permanent failure
  should not consume remaining attempts).
- **Graceful shutdown**: stop taking new jobs, let in-flight jobs finish
  (up to a timeout), then release resources.
- **Lifecycle/observability events**: completed, failed, retrying, stalled
  — subscribable for logging/metrics.

The payload and the result should be **type-linked**: if a queue is
declared to carry payload `T` and produce result `R`, both `enqueue` and
the handler should be typed accordingly so producer and worker can't
drift.

## What to deliver

Produce a single Markdown document, `design.md`, presenting:

- The **types**: how a queue is declared/typed (payload + result), the
  enqueue options, the job/status shape, and the handler signature
  (including the job metadata and the progress/retry-control surface).
- The **producer API** and the **worker API** as method signatures with
  one-line behavior notes, including dedup, retry policy, bulk enqueue,
  status query, concurrency, and graceful shutdown.
- The **event-subscription** surface for observability.
- A **worked example**: declare a typed queue, enqueue a job with options,
  and a worker handler that reports progress, throws a permanent vs
  retryable error appropriately, and shuts down gracefully.
- A note on **extensibility**: adding a new job option, a new job state,
  or a new lifecycle event without breaking existing producers/workers.

You are proposing the surface — make and state the decisions. Keep
producer and worker types consistent (the example must type-check against
the declared queue).

## Deliverable

A single `design.md`.
