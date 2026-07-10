# In-memory key-value store with TTL

Implement an in-memory key-value store whose entries can expire.

## Deliverable

Create a single file `kv_store.py` exposing a class `KVStore`.

## Runtime

Python 3 (standard library only). No third-party packages.

## Interface

```python
KVStore()
```

```python
store.set(key, value, now, ttl=None)   # -> None
store.get(key, now)                     # -> value, or None if absent/expired
store.delete(key)                       # -> True if a key was removed, else False
store.size(now)                         # -> number of live (non-expired) entries at `now`
```

Time is always passed in explicitly as `now` (seconds). The store must
never read a wall clock itself.

## Behavior

- `set(key, value, now, ttl=None)` stores `value` under `key`.
  - If `ttl` is `None`, the entry never expires.
  - Otherwise the entry expires at time `now + ttl`; it is considered
    expired once the query time is `>=` that expiry instant.
  - Setting an existing key replaces both its value and its expiry.
- `get(key, now)` returns the value if the key exists and has not expired
  at `now`; otherwise returns `None`. An expired entry is indistinguishable
  from an absent one.
- `delete(key)` removes the key and returns `True` if it existed
  (expired-but-not-yet-purged still counts as existing), else `False`.
- `size(now)` returns how many entries are live (present and not expired)
  at `now`.

## Constraints

- Deterministic; no I/O, no logging, no wall clock.
- Values may be any non-`None` object. Print nothing on import.
