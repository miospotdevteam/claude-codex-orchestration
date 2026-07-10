# Quality rubric — balanced brackets

Scored 0–5 per dimension, layered on top of objective correctness (repro
fixed, no regressions).

## Dimensions

1. **Root-cause fix (0–5)** — On each closer, compares the popped opener
   against the expected one and fails on mismatch. Penalize fixes that
   only special-case the repro strings or that re-scan with regex counts
   rather than checking nesting.

2. **Minimal & targeted (0–5)** — Builds on the existing stack; adds the
   match check at the pop. Penalize a full rewrite when a two-line change
   suffices.

3. **Behavior preserved (0–5)** — Correctly nested strings still pass;
   stray closers, unclosed openers, and crossed pairs fail; empty string
   passes; non-bracket characters ignored.

4. **Readable (0–5)** — The "pop must equal the matching opener" logic is
   clear. Penalize tangled conditionals.

5. **Naming (0–5)** — Clear names (`stack`, `closeToOpen`, `ch`) or
   better. Penalize opaque single letters for the map.
