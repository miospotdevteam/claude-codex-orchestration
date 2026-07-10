# Replace an if/elif chain with a dispatch table

You are given a pricing function implemented as a long `if/elif` chain on
a string `kind`. Refactor it to dispatch through a lookup table
**without changing any observable behavior**.

## Runtime

Python 3 (standard library only). No third-party packages.

## Starting code

`pricing.py`:

```python
def price(kind, qty):
    if kind == "standard":
        return qty * 10
    elif kind == "bulk":
        if qty >= 100:
            return qty * 7
        return qty * 9
    elif kind == "vip":
        return qty * 8 - 5
    else:
        raise ValueError(f"unknown kind: {kind}")
```

## Target shape

Refactor `pricing.py` so that:

1. A **module-level dict named `RULES`** maps each `kind` string to a
   callable that takes `qty` and returns the price for that kind:
   - `RULES["standard"](qty)` → `qty * 10`
   - `RULES["bulk"](qty)` → `qty * 7` if `qty >= 100`, else `qty * 9`
   - `RULES["vip"](qty)` → `qty * 8 - 5`
2. `price(kind, qty)` looks the `kind` up in `RULES` and delegates to the
   matching callable. There is **no `if/elif` chain over `kind`** left in
   `price`.
3. An unknown `kind` still raises `ValueError` (message may be anything).

## Requirements

- Prices for every `(kind, qty)` are identical to the starting code.
- `RULES` is importable as `pricing.RULES`, is a `dict`, and every value
  is callable.
- Adding a new pricing kind should be a matter of adding one entry to
  `RULES`, not editing branch logic.
- Print nothing on import.
