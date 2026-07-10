# Task: Write an on-call runbook

Write an **on-call runbook** for a specific failure mode of a production
service. The audience is an on-call engineer, possibly half-asleep at
3am, who may not know this service deeply. The runbook must let them
diagnose and mitigate the incident safely.

Below is the source of truth: the service description, the alert, and the
operational facts you may use. Do not invent infrastructure beyond what
is given.

## Source of truth

**Service:** `checkout-api` — a stateless HTTP service (12 replicas on
Kubernetes, namespace `payments`) that handles checkout requests. It
depends on:
- `postgres-primary` (orders DB) via PgBouncer (pool max 100).
- `stripe` (external payment API).
- `redis-cache` (idempotency keys; a cache miss is safe, just slower).

**The alert firing this runbook:** `CheckoutApiHighLatencyP99` — p99
latency of `POST /checkout` above 2s for 5 minutes (normal p99 ≈ 300ms).

**Operational facts available to you:**
- Dashboards: Grafana board "checkout-api" shows request rate, p50/p99
  latency, error rate, and a "DB pool saturation" panel (% of PgBouncer
  pool in use).
- Logs: `kubectl logs -n payments deploy/checkout-api` (structured JSON;
  slow queries log `"event":"slow_query"` with `duration_ms`).
- The service exposes `/healthz` (liveness) and `/readyz` (readiness,
  which fails if it can't reach postgres).
- Known contributors to this alert, in rough order of frequency:
  1. **DB pool saturation** — pool at ~100% (visible on the panel); usually
     a slow/locked query or a traffic spike. Mitigation options: identify
     and kill a long-running query (`pg_stat_activity`); or scale
     replicas *down* is wrong — more replicas means more pool pressure.
  2. **Stripe latency** — Stripe's own p99 elevated; check the Stripe
     status page. Nothing to fix on our side except shed load; the alert
     is informational.
  3. **A bad deploy** — latency step-change aligned with a rollout. Check
     the deploy history; `kubectl rollout undo deploy/checkout-api -n
     payments` rolls back.
- **Rollback is always safe** (stateless service). **Restarting** a pod
  is safe. **Scaling up replicas is NOT a safe default here** because it
  increases DB pool pressure — only scale up if the DB pool is healthy
  and CPU is the bottleneck.
- Escalation: if unresolved in 20 minutes, page the `#payments-oncall`
  secondary and the DBA on-call (PagerDuty service "payments-db").

## Requirements

Produce a single Markdown document, `RUNBOOK.md`, that covers:

- **Header**: which alert this runbook is for and a one-line summary of
  what it means and its user impact.
- **Prerequisites**: access/tools the responder needs (kubectl context,
  Grafana, PagerDuty).
- **Triage / diagnosis**: an ordered set of checks that narrows to one of
  the known causes, referencing the specific dashboards, log queries, and
  endpoints above.
- **Mitigation**: the safe action for each cause, calling out explicitly
  which actions are safe (rollback, restart) and which are dangerous
  here (naive scale-up) and why.
- **Escalation**: when and how to escalate.
- A short **verification** step: how to confirm the incident is resolved.

## Constraints

- Use only the infrastructure, commands, and facts in the source of
  truth. Do not invent tools, dashboards, or commands.
- The runbook must preserve the load-bearing safety caveat: scaling up
  replicas is not a safe default because it worsens DB pool pressure.

## Deliverable

A single `RUNBOOK.md`.
