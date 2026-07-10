# Quality rubric — inclusive date range

Scored 0–5 per dimension, layered on top of objective correctness (repro
fixed, no regressions).

## Dimensions

1. **Root-cause fix (0–5)** — Corrects the end comparison to `<=` so the
   range is inclusive. Penalize special-casing the exact repro date
   instead of fixing the operator.

2. **Minimal & targeted (0–5)** — One operator changes; the parsing and
   the `start` check are left intact. Penalize rewriting the date
   handling or swapping libraries.

3. **Behavior preserved (0–5)** — Both endpoints inclusive, interior
   inside, out-of-range outside. Penalize a fix that makes `start`
   exclusive while fixing `end`.

4. **Readable (0–5)** — The inclusive intent is obvious from the
   comparison. Penalize convoluted date math.

5. **Naming (0–5)** — Clear locals (`d`, `start`, `end`) or better.
