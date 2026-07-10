# Quality rubric — consolidate responses

Scored 0–5 per dimension, layered on top of objective correctness
(behavior preserved + `respond.js` present and correct).

## Dimensions

1. **Duplication removed (0–5)** — The `status: 200` / `status: 404`
   response literals live only in `respond.js`; all three handlers route
   through the helpers. Penalize any handler still hand-building a
   response object.

2. **Behavior-preserving (0–5)** — Status codes, body shapes, and the
   exact error wording are unchanged. Penalize a helper that alters the
   error phrasing or wraps the body differently.

3. **Idiomatic (0–5)** — Small, pure helper functions; clean import into
   `handlers.js`. Penalize over-generalizing into a response "framework"
   the spec never asked for.

4. **Readable (0–5)** — Each handler now reads as "look up, else
   notFound, else ok". Penalize indirection that makes the 200/404 paths
   harder to see than the original.

5. **Naming (0–5)** — `ok` / `notFound` (or equally clear intent-named
   helpers). Penalize names like `resp1` / `make` that hide the status.
