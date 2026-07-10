# Quality rubric — split module

Scored 0–5 per dimension, layered on top of objective correctness
(behavior preserved + the module split present as specified).

## Dimensions

1. **Separation of concerns (0–5)** — `models.py` holds only the entity,
   `repository.py` only the storage/query logic, `store.py` only the
   re-export glue. Penalize logic that leaks across the boundary.

2. **Behavior-preserving (0–5)** — Ids, insertion order, `citation`
   format, and `None` on miss are byte-identical to the original.
   Penalize any incidental semantic drift.

3. **Idiomatic imports (0–5)** — `store.py` re-exports cleanly (e.g. a
   focused `from ... import ...` plus `__all__`). Penalize star-imports
   that leak names or circular imports between the two new modules.

4. **Readable (0–5)** — Each file is short and single-purpose; a reader
   knows where to look for the entity vs the storage. Penalize dead
   re-exports or leftover commented code.

5. **Naming (0–5)** — Module and symbol names match the target
   (`models`, `repository`, `store`, `Book`, `Catalog`). Penalize
   surprising module names that obscure the split.
