# Quality rubric — KV store with TTL

Scored 0–5 per dimension, layered on top of objective correctness.

## Dimensions

1. **Idiomatic (0–5)** — A dict keyed to `(value, expiry)` or equivalent,
   plain Python. Penalize background threads, heaps, or scheduler
   machinery the spec never asked for.

2. **Minimal (0–5)** — `set`/`get`/`delete`/`size` are each a few lines
   and the expiry check lives in one place. Penalize duplicated
   expiry-comparison logic scattered across methods.

3. **Readable (0–5)** — The expiry rule (`now >= now_at_set + ttl`) is
   expressed once and clearly. Penalize off-by-one-looking comparisons
   with no clear boundary semantics.

4. **Edge cases handled (0–5)** — `ttl=None` never expires; the `>=`
   boundary is exact; overwriting resets expiry; `size` counts only live
   entries; `delete` reports prior existence correctly.

5. **Naming (0–5)** — `set`/`get`/`delete`/`size`, and an internal
   `expiry`/`expires_at` that names the instant, not the duration.
