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
def t_standard(P):
    assert P.price("standard", 5) == 50
    assert P.price("standard", 0) == 0


@test
def t_bulk_boundary(P):
    assert P.price("bulk", 99) == 99 * 9
    assert P.price("bulk", 100) == 100 * 7
    assert P.price("bulk", 250) == 250 * 7


@test
def t_vip(P):
    assert P.price("vip", 10) == 75
    assert P.price("vip", 1) == 3


@test
def t_unknown_raises(P):
    try:
        P.price("mystery", 1)
    except ValueError:
        return
    raise AssertionError("expected ValueError for unknown kind")


@test
def t_rules_is_table(P):
    assert isinstance(P.RULES, dict)
    for k in ("standard", "bulk", "vip"):
        assert k in P.RULES
        assert callable(P.RULES[k])


@test
def t_rules_callables_match(P):
    assert P.RULES["standard"](3) == 30
    assert P.RULES["bulk"](100) == 700
    assert P.RULES["vip"](2) == 11


def _pricing_tree():
    with open(os.path.join(CAND, "pricing.py"), "r", encoding="utf-8") as fh:
        return ast.parse(fh.read(), filename="pricing.py")


def _price_function(tree):
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "price":
            return node
    raise AssertionError("price function not found")


def _is_name(node, name):
    return isinstance(node, ast.Name) and node.id == name


def _is_rules_lookup(node):
    if isinstance(node, ast.Subscript):
        return _is_name(node.value, "RULES") and _is_name(node.slice, "kind")
    if isinstance(node, ast.Call):
        return (
            isinstance(node.func, ast.Attribute)
            and node.func.attr == "get"
            and _is_name(node.func.value, "RULES")
            and len(node.args) >= 1
            and _is_name(node.args[0], "kind")
        )
    return False


def _mentions_kind_string_compare(node):
    if isinstance(node, ast.Compare):
        sides = [node.left] + list(node.comparators)
        has_kind = any(_is_name(side, "kind") for side in sides)
        has_string = any(isinstance(side, ast.Constant) and isinstance(side.value, str) for side in sides)
        return has_kind and has_string
    return any(_mentions_kind_string_compare(child) for child in ast.iter_child_nodes(node))


@test
def t_price_delegates_through_rules_table(P):
    tree = _pricing_tree()
    fn = _price_function(tree)
    delegated_names = set()
    direct_rules_call = False
    for node in ast.walk(fn):
        if isinstance(node, ast.Assign) and _is_rules_lookup(node.value):
            delegated_names.update(target.id for target in node.targets if isinstance(target, ast.Name))
        elif isinstance(node, ast.AnnAssign) and _is_rules_lookup(node.value):
            if isinstance(node.target, ast.Name):
                delegated_names.add(node.target.id)
        elif isinstance(node, ast.Call):
            if _is_rules_lookup(node.func):
                direct_rules_call = True
            elif isinstance(node.func, ast.Name) and node.func.id in delegated_names:
                direct_rules_call = True
    assert direct_rules_call, "price must look up kind in RULES and call the selected rule"


@test
def t_price_has_no_kind_if_elif_chain(P):
    tree = _pricing_tree()
    fn = _price_function(tree)
    for node in ast.walk(fn):
        if isinstance(node, ast.If) and _mentions_kind_string_compare(node.test):
            raise AssertionError("price must not branch on kind with an if/elif chain")


def main():
    passed = 0
    total = len(TESTS)
    try:
        import pricing as P
    except Exception:
        traceback.print_exc()
        print("RESULT 0 %d" % total)
        sys.exit(1)
    for fn in TESTS:
        try:
            fn(P)
            passed += 1
        except Exception:
            sys.stderr.write("FAIL %s\n" % fn.__name__)
            traceback.print_exc()
    print("RESULT %d %d" % (passed, total))
    sys.exit(0 if passed == total else 1)


main()
