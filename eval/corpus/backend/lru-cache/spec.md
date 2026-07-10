# LRU cache

Implement a fixed-capacity least-recently-used (LRU) cache.

## Deliverable

Create a single file `lru_cache.py` exposing a class `LRUCache`.

## Runtime

Python 3 (standard library only). No third-party packages.

## Interface

```python
LRUCache(capacity)
```

- `capacity` — a positive integer, the maximum number of entries held.

```python
cache.get(key)          # -> value, or None if the key is absent
cache.put(key, value)   # -> None
```

## Behavior

- `get(key)` returns the stored value, or `None` if the key is not
  present. A successful `get` counts as a **use** — it makes that key the
  most-recently-used.
- `put(key, value)` inserts or updates the entry and makes that key the
  most-recently-used. If inserting a new key would exceed `capacity`, the
  **least-recently-used** key is evicted first.
- Updating the value of an existing key does **not** grow the cache and
  refreshes that key's recency.
- Recency is defined by the most recent `get` or `put` touching a key.
  The evicted key on overflow is always the one untouched for the
  longest.

You may assume all values passed to `put` are non-`None`.

## Constraints

- `get` and `put` should each run in roughly constant time (do not
  re-sort the whole cache on every call).
- No I/O, no logging, no global mutable state. Print nothing on import.
