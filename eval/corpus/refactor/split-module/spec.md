# Split a mixed module into model and repository

You are given one Python module that mixes an entity definition with its
storage/query logic. Split it into the target modules below **without
changing any observable behavior**.

## Runtime

Python 3 (standard library only). No third-party packages.

## Starting code

`store.py`:

```python
class Book:
    def __init__(self, title, author, year):
        self.title = title
        self.author = author
        self.year = year

    def citation(self):
        return f"{self.author}. {self.title} ({self.year})."


class Catalog:
    def __init__(self):
        self._books = {}
        self._next_id = 1

    def add(self, book):
        book_id = self._next_id
        self._next_id += 1
        self._books[book_id] = book
        return book_id

    def get(self, book_id):
        return self._books.get(book_id)

    def by_author(self, author):
        return [b for b in self._books.values() if b.author == author]

    def all(self):
        return list(self._books.values())
```

The entity (`Book`) and the storage (`Catalog`) are two concerns living
in one file.

## Target shape

Produce **three** files:

1. `models.py` — defines and exports `Book` (with its `citation`
   method), and nothing storage-related.
2. `repository.py` — defines and exports `Catalog` (the storage/query
   logic), and no entity definition.
3. `store.py` — the public entry point: it imports from the two new
   modules and **re-exports** `Book` and `Catalog`, so that existing
   callers who do `from store import Book, Catalog` keep working
   unchanged.

## Requirements

- Public behavior is identical to the starting code:
  - `Catalog.add` assigns ids starting at 1, incrementing by 1, and
    returns the assigned id.
  - `get` returns the book or `None`.
  - `by_author` returns matching books in insertion order.
  - `all` returns every book in insertion order.
  - `Book.citation()` returns `"Author. Title (Year)."`.
- `store.Book` and `models.Book` refer to the same class object; likewise
  `store.Catalog` and `repository.Catalog`.
- No `Book` definition in `repository.py`; no `Catalog` definition in
  `models.py`. Print nothing on import.
