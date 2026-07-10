# Quality rubric — shared accumulator bug

Scored 0–5 per dimension, layered on top of objective correctness (repro
fixed, no regressions).

## Dimensions

1. **Root-cause fix (0–5)** — Addresses the mutable-default-argument
   trap directly (sentinel default, fresh list per call). Penalize
   band-aids that paper over the symptom (e.g. copying at the call site,
   clearing a shared list) instead of removing the shared default.

2. **Minimal & targeted (0–5)** — The change is confined to the default
   handling. Penalize rewrites that restructure the function or add
   unrelated features.

3. **Behavior preserved (0–5)** — Explicit-basket appends still mutate
   and return the passed list; the append order is unchanged; the
   signature stays call-compatible.

4. **Idiomatic (0–5)** — Uses the standard `None`-sentinel pattern (or an
   equally clean idiom). Penalize non-idiomatic contortions.

5. **Readable (0–5)** — A reader immediately sees why a fresh list is
   created. Penalize a fix whose intent is obscure.
