# Quality rubric — dispatch table

Scored 0–5 per dimension, layered on top of objective correctness
(prices preserved + `RULES` table present and correct).

## Dimensions

1. **Chain eliminated (0–5)** — `price` no longer branches on `kind`; the
   `kind`→behavior mapping lives entirely in `RULES`. Penalize a
   half-refactor that keeps some kinds in an `if` and others in the table.

2. **Behavior-preserving (0–5)** — Every `(kind, qty)` price matches the
   original, including the `bulk` `qty >= 100` boundary and the
   `ValueError` on unknown kinds.

3. **Idiomatic (0–5)** — A clean dict of small callables (named
   functions or lambdas), looked up with a graceful miss (e.g.
   `.get`/`try`). Penalize a table that stores data but still needs
   branch logic to interpret it.

4. **Extensible (0–5)** — Adding a kind is one `RULES` entry with no
   change to `price`. Penalize designs where a new kind still forces
   edits to the dispatch function.

5. **Naming (0–5)** — `RULES` plus clear per-kind function names.
   Penalize opaque lambda soup where the reader can't tell which rule is
   which.
