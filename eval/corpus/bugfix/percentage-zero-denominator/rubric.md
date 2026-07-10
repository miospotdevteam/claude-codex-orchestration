# Quality rubric — percentage zero denominator

Scored 0–5 per dimension, layered on top of objective correctness (repro
fixed, no regressions).

## Dimensions

1. **Root-cause fix (0–5)** — Guards the zero-denominator case so the
   division never produces `NaN`. Penalize post-hoc `NaN`-scrubbing
   (`isNaN(x) ? 0 : x`) that masks other `NaN` sources instead of
   handling the zero whole directly.

2. **Minimal & targeted (0–5)** — Adds only the zero guard; the rounding
   expression is untouched. Penalize reformatting or added parameters.

3. **Behavior preserved (0–5)** — Non-zero cases keep exact one-decimal
   rounding (`33.3`, `66.7`, `25`). Penalize a fix that changes rounding
   behavior.

4. **Readable (0–5)** — The zero case is an obvious early return or
   guard. Penalize an opaque conditional expression.

5. **Naming (0–5)** — Keeps clear names (`part`, `whole`).
