# Bug: page 1 skips the first page of results

## Runtime

Python 3 (standard library only). No third-party packages.

## The code

`paginate.py`:

```python
def paginate(items, page, per_page):
    start = page * per_page
    end = start + per_page
    return items[start:end]
```

`paginate` returns one page of `items`. Pages are **1-based**: `page=1`
is the first page, `page=2` the second, and so on. `per_page` is the page
size.

## Symptom

The first page is never returned. Asking for `page=1` skips the initial
`per_page` items and returns the *second* page's slice instead:

```python
items = ["a", "b", "c", "d", "e"]
paginate(items, 1, 2)   # -> ["c", "d"]   (WRONG: expected ["a", "b"])
```

## Task

Fix `paginate.py` so that, with 1-based pages:

- `page=1` returns the first `per_page` items.
- `page=2` returns the next `per_page`, and so on.
- The final page returns the remaining items even if fewer than
  `per_page`.
- A page past the end returns an empty list.

Keep the signature `paginate(items, page, per_page)` and change nothing
beyond the pagination math. Print nothing on import.
