# Quality rubric — token-bucket

Scored 0–5 per dimension by the judge panel, layered on top of objective
correctness (a solution that fails the hidden tests cannot be rescued by
style).

## Dimensions

1. **Idiomatic (0–5)** — Uses plain Python well: a single small class,
   clear attributes, no needless abstractions, no dependency on anything
   beyond the standard library. Penalize framework cargo-culting or
   reimplementing arithmetic the language gives for free.

2. **Minimal (0–5)** — Solves exactly the stated problem. The refill +
   clamp + conditional-consume logic should read in a handful of lines.
   Penalize speculative features (per-key buckets, threading locks,
   serialization) the spec never asked for.

3. **Readable (0–5)** — The refill math and the consume decision are
   obvious at a glance. Penalize dense one-liners that hide the clamp, or
   unexplained magic constants.

4. **Edge cases handled (0–5)** — Level never exceeds capacity after a
   long idle gap; a rejected request consumes nothing; fractional tokens
   and refill rates work; `elapsed == 0` is handled without drift.

5. **Naming (0–5)** — `capacity`, `refill_per_sec`, `tokens`, `now` (or
   equally clear) — names that state units and intent. Penalize `c`,
   `r`, `t`, or names that mislead about units.
