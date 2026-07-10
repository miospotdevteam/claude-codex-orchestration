# Task: Design a feature-flags client SDK surface

Design the **public client SDK surface** for a feature-flag service
called **Togglr**, for use in server-side TypeScript/JavaScript
applications. You are designing the *interface a developer codes
against* — not the backend, not the network protocol.

## Domain & requirements

Togglr evaluates flags for a given **evaluation context** (a user or
request: an id plus arbitrary attributes like `plan`, `country`,
`betaOptIn`). The SDK must let application code:

- **Initialize** a client with an SDK key and options (e.g. polling
  interval, a default/fallback behavior, optional bootstrap data for
  fast cold starts).
- Evaluate a **boolean flag** for a context, with a **caller-supplied
  default** used when the flag is unknown or the client can't evaluate.
- Evaluate **non-boolean flags**: string, number, and JSON variants
  (multivariate flags), each with a typed default.
- Get the **full evaluation detail** for a flag when needed: not just the
  value but *why* (which variation, the reason — e.g. targeting match,
  fallthrough, default/error), for debugging and logging.
- **Subscribe to flag changes** so long-lived processes react when a flag
  is updated, and unsubscribe cleanly.
- **Shut down** the client, flushing any in-flight work and releasing
  resources.

The SDK targets long-running servers (must be safe to hold a single
client for the process lifetime) and must **degrade safely**: if Togglr
is unreachable, evaluations return the caller's default rather than
throwing.

## What to deliver

Produce a single Markdown document, `design.md`, presenting the proposed
surface:

- The **types**: the client interface, options, evaluation context, and
  evaluation-detail shape, as TypeScript signatures.
- The **methods**, each with signature and a one-line description of
  behavior, including the default-value and error/degradation semantics.
- The **change-subscription** and **lifecycle** (init/shutdown) surface.
- A short **usage example** showing initialization, a boolean and a
  multivariate evaluation with defaults, and clean shutdown.
- A brief note on **how the design extends** to future needs (e.g. new
  flag value types, or added evaluation reasons) without breaking callers.

You are proposing the surface — make and state the design decisions. Do
not implement the backend; signatures plus behavior descriptions are the
deliverable. Keep it self-consistent.

## Deliverable

A single `design.md`.
