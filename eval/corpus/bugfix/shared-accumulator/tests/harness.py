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


@test
def t_repro_no_leak(M):
    # The pinned repro: separate default-basket calls must not share state.
    first = M.add_items(["a", "b"])
    assert first == ["a", "b"]
    second = M.add_items(["c"])
    assert second == ["c"], "items leaked between calls: %r" % (second,)


@test
def t_default_returns_distinct_lists(M):
    a = M.add_items([1])
    b = M.add_items([2])
    assert a == [1]
    assert b == [2]
    assert a is not b


@test
def t_explicit_basket_appends(M):
    bag = ["x"]
    out = M.add_items(["y"], bag)
    assert out == ["x", "y"]
    assert out is bag  # appends onto the passed list


@test
def t_empty_new_items(M):
    assert M.add_items([]) == []


@test
def t_order_preserved(M):
    assert M.add_items([3, 1, 2]) == [3, 1, 2]


def main():
    passed = 0
    total = len(TESTS)
    try:
        M = load("basket.py", "basket")
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
