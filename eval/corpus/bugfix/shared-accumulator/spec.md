# Bug: baskets leak items between calls

## Runtime

Python 3 (standard library only). No third-party packages.

## The code

`basket.py`:

```python
def add_items(new_items, basket=[]):
    for item in new_items:
        basket.append(item)
    return basket
```

`add_items` is meant to append `new_items` onto a basket and return it.
Called with no basket, it should start from a fresh, empty basket each
time.

## Symptom

Two independent calls that each omit the `basket` argument do **not**
start fresh. The items from an earlier call reappear in a later one:

```python
add_items(["a", "b"])   # -> ["a", "b"]   (correct)
add_items(["c"])        # -> ["a", "b", "c"]   (WRONG: expected ["c"])
```

Each call that omits `basket` should behave as if it were handed a brand
new empty basket.

## Task

Fix `basket.py` so that:

- A call omitting `basket` always starts from a fresh empty list — items
  never leak from one such call into another.
- Passing an explicit `basket` still appends onto that exact list and
  returns it (e.g. `add_items(["y"], ["x"])` returns `["x", "y"]`).
- The function signature stays call-compatible (callers may still call
  `add_items(items)` or `add_items(items, basket)`).

Do not change behavior beyond fixing the leak. Print nothing on import.
