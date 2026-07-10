# Quality rubric — Merchant Copilot core

Scored 0–5 per dimension, layered on top of objective correctness. Judge only on
the code; a solution that passes tests with a clean, well-factored design should
outscore one that passes with tangled special-cases.

## Dimensions

1. **Correct state modelling (0–5)** — Pairing, pending confirmations, per-merchant
   state, and the audit log are represented with clear, well-separated data
   structures. Penalize conflating concerns (e.g. mixing pending confirmations
   into the audit log) or per-merchant state that can leak across merchants.

2. **Undo design (0–5)** — Reversal is driven by data captured at commit time
   (previous value / added item / prior list) rather than re-derived guesses.
   The LIFO scan cleanly skips non-undoable and already-undone actions.
   Penalize undo logic that recomputes prior state heuristically or special-cases
   each tool inline without a coherent scheme.

3. **Tier dispatch clarity (0–5)** — AUTO / CONFIRM / DEEPLINK routing and the
   confirm-before-commit flow read clearly, ideally from a single tool registry
   rather than scattered conditionals. Error ordering in `confirm` is explicit.

4. **Boundary & edge handling (0–5)** — TTL boundaries (`>=`), single-use codes
   and confirmations, guest fallback, unknown tools, and merchant isolation are
   handled deliberately, not accidentally. Penalize off-by-one boundaries or
   silently swallowed errors.

5. **Readability & idiom (0–5)** — Idiomatic Python, meaningful names, no dead
   code, no configurability the spec never asked for. Returned copies protect
   internal state. Penalize copy-paste blocks and opaque one-letter fields.
