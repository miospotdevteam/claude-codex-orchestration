# Quality rubric — LRU cache

Scored 0–5 per dimension, layered on top of objective correctness.

## Dimensions

1. **Appropriate O(1) structure (0–5)** — Uses a data structure that
   supports lookup, recency refresh, insertion, and eviction in roughly
   constant time, and keeps the structure's invariants clear. Full credit
   is available for any clean implementation strategy that satisfies this
   complexity target.

2. **Minimal (0–5)** — `get`, `put`, and eviction read in a few lines
   each. Penalize dead code, unused helpers, or configurability the spec
   never requested (TTL, stats, thread locks).

3. **Readable recency and eviction logic (0–5)** — The recency update and
   the eviction step are each obvious, with the oldest-touched key clearly
   identified and removed. Penalize logic whose control flow or state
   updates make the eviction order hard to audit.

4. **Edge cases handled (0–5)** — Miss returns `None`; updating an
   existing key neither grows the cache nor loses its refreshed recency;
   capacity 1 works; eviction always drops the correct (oldest-touched)
   key.

5. **Naming (0–5)** — `capacity`, `get`, `put`, and internal storage
   named for intent. Penalize opaque single-letter fields.
