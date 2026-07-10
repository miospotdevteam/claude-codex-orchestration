#!/usr/bin/env python3
import importlib.util
import os
import sys
import traceback

CAND = os.path.abspath(sys.argv[1])


def load(fname, modname):
    path = os.path.join(CAND, fname)
    spec = importlib.util.spec_from_file_location(modname, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


TESTS = []


def test(fn):
    TESTS.append(fn)
    return fn


ITEMS = ["a", "b", "c", "d", "e"]


@test
def t_repro_first_page(M):
    assert M.paginate(ITEMS, 1, 2) == ["a", "b"]


@test
def t_second_page(M):
    assert M.paginate(ITEMS, 2, 2) == ["c", "d"]


@test
def t_short_final_page(M):
    assert M.paginate(ITEMS, 3, 2) == ["e"]


@test
def t_out_of_range(M):
    assert M.paginate(ITEMS, 4, 2) == []


@test
def t_per_page_larger_than_list(M):
    assert M.paginate(ITEMS, 1, 100) == ITEMS


@test
def t_page_size_one(M):
    assert M.paginate(ITEMS, 1, 1) == ["a"]
    assert M.paginate(ITEMS, 5, 1) == ["e"]


def main():
    passed = 0
    total = len(TESTS)
    try:
        M = load("paginate.py", "paginate")
    except Exception:
        traceback.print_exc()
        print("RESULT 0 %d" % total)
        sys.exit(1)
    for fn in TESTS:
        try:
            fn(M)
            passed += 1
        except Exception:
            sys.stderr.write("FAIL %s\n" % fn.__name__)
            traceback.print_exc()
    print("RESULT %d %d" % (passed, total))
    sys.exit(0 if passed == total else 1)


main()
