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
