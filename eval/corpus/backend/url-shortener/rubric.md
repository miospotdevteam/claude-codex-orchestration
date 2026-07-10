# Quality rubric — URL shortener store

Scored 0–5 per dimension, layered on top of objective correctness.

## Dimensions

1. **Idiomatic (0–5)** — Idiomatic Node/JS: a closure or class over two
   `Map`s, clean CommonJS export. Penalize global state, callback
   ceremony, or pulling in a dependency for base conversion.

2. **Minimal (0–5)** — Just the two-way mapping plus code generation.
   Penalize speculative features (expiry, click counts, custom aliases)
   the spec never asked for.

3. **Readable (0–5)** — The forward map, reverse map, and code generation
   are each easy to follow. Penalize a code generator whose output length
   or charset is hard to reason about.

4. **Edge cases handled (0–5)** — Idempotent re-shorten; distinct codes
   for distinct urls; `resolve` of an unknown code returns `null`;
   invalid input throws `TypeError`; independent store instances.

5. **Naming (0–5)** — `shorten`, `resolve`, `count`, and internal maps
   named for direction of lookup. Penalize opaque names that hide which
   map is url→code vs code→url.
