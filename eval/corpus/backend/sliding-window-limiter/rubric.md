# Quality rubric — sliding-window rate limiter

Scored 0–5 per dimension, layered on top of objective correctness.

## Dimensions

1. **Idiomatic (0–5)** — A `Map` of client -> timestamps, plain JS. The
   window-eviction reads naturally. Penalize reaching for a dependency or
   a background sweep the spec never asked for.

2. **Minimal (0–5)** — One method, one eviction step, one comparison.
   Penalize per-request full-array rescans when a cheap prune suffices,
   or dead configurability.

3. **Readable (0–5)** — The window boundary (`t > now - windowMs`) and
   the record-only-on-allow rule are both obvious. Penalize tangled
   index math.

4. **Edge cases handled (0–5)** — The `<=` vs `>` window boundary is
   exact; rejected requests record nothing; clients are independent;
   aged-out timestamps are pruned rather than growing unbounded.

5. **Naming (0–5)** — `limit`, `windowMs`, `clientId`, `now` carry their
   units. Penalize names that hide whether the window is ms or seconds.
