# Quality rubric — pagination off-by-one

Scored 0–5 per dimension, layered on top of objective correctness (repro
fixed, no regressions).

## Dimensions

1. **Root-cause fix (0–5)** — Corrects the 1-based start index
   (`(page - 1) * per_page`). Penalize fixes that special-case `page == 1`
   while leaving the general formula wrong.

2. **Minimal & targeted (0–5)** — Only the index arithmetic changes.
   Penalize rewrites into unrelated helpers or added validation the spec
   never requested.

3. **Behavior preserved (0–5)** — Correct slices for every page,
   including a short final page and an out-of-range page returning `[]`.

4. **Readable (0–5)** — The start/end computation reads clearly as
   1-based paging. Penalize obscure index juggling.

5. **Naming (0–5)** — Keeps clear names (`start`, `end`, `page`,
   `per_page`) or better. Penalize cryptic locals.
