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
def t_put_get(M):
    c = M.LRUCache(2)
    c.put("a", 1)
    c.put("b", 2)
    assert c.get("a") == 1
    assert c.get("b") == 2


@test
def t_miss_returns_none(M):
    c = M.LRUCache(2)
    assert c.get("nope") is None


@test
def t_evicts_lru(M):
    c = M.LRUCache(2)
    c.put("a", 1)
    c.put("b", 2)
    c.put("c", 3)  # evicts "a"
    assert c.get("a") is None
    assert c.get("b") == 2
    assert c.get("c") == 3


@test
def t_get_refreshes_recency(M):
    c = M.LRUCache(2)
    c.put("a", 1)
    c.put("b", 2)
    assert c.get("a") == 1  # "a" now most-recent
    c.put("c", 3)           # evicts "b", not "a"
    assert c.get("b") is None
    assert c.get("a") == 1
    assert c.get("c") == 3


@test
def t_update_refreshes_and_no_growth(M):
    c = M.LRUCache(2)
    c.put("a", 1)
    c.put("b", 2)
    c.put("a", 10)  # update -> "a" most-recent, size still 2
    c.put("c", 3)   # evicts "b"
    assert c.get("b") is None
    assert c.get("a") == 10
    assert c.get("c") == 3


@test
def t_capacity_one(M):
    c = M.LRUCache(1)
    c.put("a", 1)
    c.put("b", 2)  # evicts "a"
    assert c.get("a") is None
    assert c.get("b") == 2


@test
def t_put_counts_as_use(M):
    c = M.LRUCache(2)
    c.put("a", 1)
    c.put("b", 2)
    c.put("a", 1)  # touch "a"
    c.put("c", 3)  # evicts "b"
    assert c.get("b") is None
    assert c.get("a") == 1


def main():
    passed = 0
    total = len(TESTS)
    try:
        M = load("lru_cache.py", "lru_cache")
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
