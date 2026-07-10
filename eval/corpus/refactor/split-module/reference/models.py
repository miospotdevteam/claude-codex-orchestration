class Book:
    def __init__(self, title, author, year):
        self.title = title
        self.author = author
        self.year = year

    def citation(self):
        return f"{self.author}. {self.title} ({self.year})."
