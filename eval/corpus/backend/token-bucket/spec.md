# Token-bucket rate limiter

Implement a token-bucket rate limiter as a small, self-contained module.

## Deliverable

Create a single file `token_bucket.py` exposing a class `TokenBucket`.

## Runtime

Python 3 (standard library only). No third-party packages.

## Interface

```python
TokenBucket(capacity, refill_per_sec, start=0.0)
```

- `capacity` — the maximum number of tokens the bucket can hold.
- `refill_per_sec` — tokens added per second of elapsed time.
- `start` — the timestamp (in seconds) at which the bucket is created.
- A newly-created bucket is **full** (`capacity` tokens available).

```python
bucket.allow(now, tokens=1) -> bool
```

- `now` — the current time in seconds. Callers pass a **non-decreasing**
  clock (each call's `now` is `>=` the previous call's `now`). Time is
  passed in explicitly; the class must never read a wall clock itself.
- `tokens` — how many tokens this request wants to consume (default 1).
- Behavior, in order, on each call:
  1. Refill: add `elapsed * refill_per_sec` tokens, where `elapsed` is
     the seconds since the last time the bucket's level was updated, then
     clamp the level so it never exceeds `capacity`.
  2. If at least `tokens` are now available, consume exactly `tokens` and
     return `True`.
  3. Otherwise consume **nothing** and return `False`.

`capacity`, `refill_per_sec`, `tokens`, and `now` may be non-integer.

## Constraints

- Deterministic: identical call sequences produce identical results.
- No I/O, no logging, no global mutable state.
- The bucket level must never exceed `capacity` no matter how much time
  passes between calls.

## Notes

Your file is the only artifact seen. Do not print anything on import.
