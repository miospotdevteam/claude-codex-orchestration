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
def t_starts_full(M):
    b = M.TokenBucket(10, 1)
    assert b.allow(0, 10) is True
    assert b.allow(0, 1) is False


@test
def t_partial_consume(M):
    b = M.TokenBucket(5, 1)
    assert b.allow(0, 3) is True
    assert b.allow(0, 3) is False  # only 2 left
    assert b.allow(0, 2) is True   # now empty
    assert b.allow(0, 1) is False


@test
def t_reject_consumes_nothing(M):
    b = M.TokenBucket(5, 1)
    assert b.allow(0, 4) is True   # 1 left
    assert b.allow(0, 5) is False  # rejected, still 1 left
    assert b.allow(0, 1) is True


@test
def t_refill_over_time(M):
    b = M.TokenBucket(10, 1)
    assert b.allow(0, 10) is True  # empty
    assert b.allow(0, 1) is False
    assert b.allow(5, 5) is True   # 5 refilled by t=5
    assert b.allow(5, 1) is False


@test
def t_never_exceeds_capacity(M):
    b = M.TokenBucket(10, 5)
    assert b.allow(0, 10) is True          # empty
    assert b.allow(1000, 10) is True       # long idle, but capped at 10
    assert b.allow(1000, 1) is False


@test
def t_default_one_token(M):
    b = M.TokenBucket(2, 0)
    assert b.allow(0) is True
    assert b.allow(0) is True
    assert b.allow(0) is False


@test
def t_fractional(M):
    b = M.TokenBucket(1.0, 0.5)
    assert b.allow(0, 1.0) is True      # empty
    assert b.allow(1, 0.5) is True      # 0.5 refilled at t=1
    assert b.allow(1, 0.1) is False


@test
def t_incremental_refill(M):
    b = M.TokenBucket(10, 2)
    assert b.allow(0, 10) is True   # empty
    assert b.allow(1, 2) is True    # exactly 2 at t=1
    assert b.allow(1, 1) is False


def main():
    passed = 0
    total = len(TESTS)
    try:
        M = load("token_bucket.py", "token_bucket")
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
