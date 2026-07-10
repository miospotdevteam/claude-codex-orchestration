# Quality rubric — rename across files

Scored 0–5 per dimension, layered on top of objective correctness (new
names work, old export gone, behavior preserved).

## Dimensions

1. **Complete rename (0–5)** — Both the function and the field are
   renamed everywhere they appear, in both files, with no lingering
   `cartSubtotal` or `item.amount`. Penalize a partial rename that leaves
   a dangling old reference.

2. **Behavior-preserving (0–5)** — `cartTotal` still multiplies price by
   qty and sums; `checkout` still returns the same `{ subtotal, total }`
   math. Penalize any accidental change to the checkout return shape.

3. **Scope discipline (0–5)** — Only the two named things change. The
   `checkout` function name and its `subtotal`/`total` keys are left
   alone. Penalize over-renaming (e.g. renaming `subtotal` inside
   `checkout` too) or drive-by edits.

4. **Readable (0–5)** — The result reads as if it were always written
   with these names; no rename scars (odd aliasing, re-export shims).

5. **Naming consistency (0–5)** — `cartTotal` / `price` used uniformly.
   Penalize mixing old and new vocabulary across the two files.
