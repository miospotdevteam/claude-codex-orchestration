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
def t_set_get(M):
    s = M.KVStore()
    s.set("a", 1, now=0)
    assert s.get("a", now=0) == 1


@test
def t_missing_none(M):
    s = M.KVStore()
    assert s.get("nope", now=0) is None


@test
def t_ttl_expiry_boundary(M):
    s = M.KVStore()
    s.set("k", "v", now=0, ttl=10)
    assert s.get("k", now=9) == "v"
    assert s.get("k", now=10) is None  # expired exactly at boundary


@test
def t_ttl_none_never_expires(M):
    s = M.KVStore()
    s.set("k", "v", now=0, ttl=None)
    assert s.get("k", now=10_000) == "v"


@test
def t_overwrite_resets_ttl(M):
    s = M.KVStore()
    s.set("k", "v1", now=0, ttl=10)
    s.set("k", "v2", now=8, ttl=10)  # new expiry at 18
    assert s.get("k", now=12) == "v2"
    assert s.get("k", now=18) is None


@test
def t_delete_existing(M):
    s = M.KVStore()
    s.set("k", "v", now=0)
    assert s.delete("k") is True
    assert s.delete("k") is False
    assert s.get("k", now=0) is None


@test
def t_delete_expired_still_true(M):
    s = M.KVStore()
    s.set("k", "v", now=0, ttl=5)
    # not yet purged by a get; delete should still report it existed
    assert s.delete("k") is True


@test
def t_size_counts_live_only(M):
    s = M.KVStore()
    s.set("a", 1, now=0, ttl=5)
    s.set("b", 2, now=0, ttl=None)
    s.set("c", 3, now=0, ttl=100)
    assert s.size(now=0) == 3
    assert s.size(now=5) == 2  # "a" expired


def main():
    passed = 0
    total = len(TESTS)
    try:
        M = load("kv_store.py", "kv_store")
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
