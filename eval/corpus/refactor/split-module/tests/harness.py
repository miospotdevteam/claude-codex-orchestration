#!/usr/bin/env python3
import ast
import os
import sys
import traceback

CAND = os.path.abspath(sys.argv[1])
sys.path.insert(0, CAND)

TESTS = []


def test(fn):
    TESTS.append(fn)
    return fn


@test
def t_add_returns_incrementing_ids(mods):
    store = mods["store"]
    cat = store.Catalog()
    b1 = store.Book("A", "X", 2000)
    b2 = store.Book("B", "Y", 2001)
    assert cat.add(b1) == 1
    assert cat.add(b2) == 2


@test
def t_get(mods):
    store = mods["store"]
    cat = store.Catalog()
    b = store.Book("A", "X", 2000)
    i = cat.add(b)
    assert cat.get(i) is b
    assert cat.get(999) is None


@test
def t_citation(mods):
    store = mods["store"]
    b = store.Book("The Title", "Ada Lovelace", 1843)
    assert b.citation() == "Ada Lovelace. The Title (1843)."


@test
def t_by_author_order(mods):
    store = mods["store"]
    cat = store.Catalog()
    b1 = store.Book("A", "X", 2000)
    b2 = store.Book("B", "Y", 2001)
    b3 = store.Book("C", "X", 2002)
    cat.add(b1)
    cat.add(b2)
    cat.add(b3)
    assert cat.by_author("X") == [b1, b3]
    assert cat.by_author("Z") == []


@test
def t_all_order(mods):
    store = mods["store"]
    cat = store.Catalog()
    b1 = store.Book("A", "X", 2000)
    b2 = store.Book("B", "Y", 2001)
    cat.add(b1)
    cat.add(b2)
    assert cat.all() == [b1, b2]


@test
def t_split_modules_expose_symbols(mods):
    assert hasattr(mods["models"], "Book")
    assert hasattr(mods["repository"], "Catalog")


@test
def t_store_reexports_same_objects(mods):
    assert mods["store"].Book is mods["models"].Book
    assert mods["store"].Catalog is mods["repository"].Catalog


def _class_names(module_name):
    with open(os.path.join(CAND, module_name), "r", encoding="utf-8") as fh:
        tree = ast.parse(fh.read(), filename=module_name)
    return {node.name for node in tree.body if isinstance(node, ast.ClassDef)}


@test
def t_concerns_are_separated_by_module(mods):
    assert "Book" not in _class_names("repository.py"), "repository.py must not define Book"
    assert "Catalog" not in _class_names("models.py"), "models.py must not define Catalog"


def main():
    passed = 0
    total = len(TESTS)
    try:
        import models
        import repository
        import store
        mods = {"models": models, "repository": repository, "store": store}
    except Exception:
        traceback.print_exc()
        print("RESULT 0 %d" % total)
        sys.exit(1)
    for fn in TESTS:
        try:
            fn(mods)
            passed += 1
        except Exception:
            sys.stderr.write("FAIL %s\n" % fn.__name__)
            traceback.print_exc()
    print("RESULT %d %d" % (passed, total))
    sys.exit(0 if passed == total else 1)


main()
