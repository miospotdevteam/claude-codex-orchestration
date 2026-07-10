"""Hidden test harness for merchant-copilot-core.

Usage: python3 harness.py <candidate_dir>
Loads <candidate_dir>/copilot.py, runs every test, prints one line per test
(PASS <name> / FAIL <name> [reason]), then a final line: RESULT <passed> <total>.
Exit 0 iff passed == total (even on import failure it prints RESULT 0 <total>).
"""
import sys
import os
import importlib.util

TESTS = []


def test(fn):
    TESTS.append((fn.__name__, fn))
    return fn


def load(cand_dir):
    path = os.path.join(cand_dir, "copilot.py")
    spec = importlib.util.spec_from_file_location("candidate_copilot", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod  # register before exec so @dataclass loads
    spec.loader.exec_module(mod)
    return mod.Copilot


def paired(C, sender="s1", merchant="m1", now=1000):
    c = C()
    code = c.issue_pairing_code(merchant, now)
    c.pair(sender, code, now)
    return c


# ---- pairing ----
@test
def pair_success(C):
    c = C()
    code = c.issue_pairing_code("m1", 1000)
    r = c.pair("s1", code, 1100)
    assert r == {"ok": True, "merchantId": "m1"}, r


@test
def pair_invalid_code(C):
    c = C()
    assert c.pair("s1", "nope", 1000) == {"ok": False, "error": "invalid_code"}


@test
def pair_expired_at_boundary(C):
    c = C()
    code = c.issue_pairing_code("m1", 1000)
    assert c.pair("s1", code, 1300) == {"ok": False, "error": "code_expired"}


@test
def pair_valid_just_before_expiry(C):
    c = C()
    code = c.issue_pairing_code("m1", 1000)
    assert c.pair("s1", code, 1299)["ok"] is True


@test
def pair_code_single_use(C):
    c = C()
    code = c.issue_pairing_code("m1", 1000)
    assert c.pair("s1", code, 1000)["ok"] is True
    assert c.pair("s2", code, 1000) == {"ok": False, "error": "code_used"}


@test
def issue_returns_distinct_codes(C):
    c = C()
    a = c.issue_pairing_code("m1", 1000)
    b = c.issue_pairing_code("m1", 1000)
    assert a != b


@test
def revoke_success_then_guest(C):
    c = paired(C)
    assert c.revoke("s1", 1000) == {"ok": True}
    assert c.dispatch("s1", "view_report", {}, 1000) == {"status": "guest"}


@test
def revoke_not_paired(C):
    c = C()
    assert c.revoke("s1", 1000) == {"ok": False, "error": "not_paired"}


@test
def rebind_sender_to_new_merchant(C):
    c = C()
    c.pair("s1", c.issue_pairing_code("m1", 1000), 1000)
    c.pair("s1", c.issue_pairing_code("m2", 1000), 1000)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    assert c.get_state("m2")["settings"] == {"a": 1}
    assert c.get_state("m1")["settings"] == {}


# ---- dispatch ----
@test
def dispatch_guest_when_unpaired(C):
    c = C()
    assert c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000) == {"status": "guest"}
    assert c.get_state("m1")["settings"] == {}


@test
def dispatch_unknown_tool(C):
    c = paired(C)
    assert c.dispatch("s1", "frobnicate", {}, 1000) == {"status": "error", "error": "unknown_tool"}


@test
def auto_set_setting_effect(C):
    c = paired(C)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 7}, 1000)
    assert c.get_state("m1")["settings"] == {"a": 7}


@test
def auto_set_setting_result_shape(C):
    c = paired(C)
    r = c.dispatch("s1", "set_setting", {"key": "a", "value": 7}, 1000)
    assert r == {"status": "done", "result": {"key": "a", "value": 7}}, r


@test
def auto_bump_counter(C):
    c = paired(C)
    assert c.dispatch("s1", "bump_counter", {}, 1000)["result"] == {"counter": 1}
    assert c.dispatch("s1", "bump_counter", {}, 1000)["result"] == {"counter": 2}
    assert c.get_state("m1")["counter"] == 2


@test
def auto_write_is_audited(C):
    c = paired(C)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    log = c.audit_log("m1")
    assert len(log) == 1 and log[0]["tool"] == "set_setting" and log[0]["kind"] == "action"


@test
def view_report_result_shape(C):
    c = paired(C)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    r = c.dispatch("s1", "view_report", {}, 1000)
    assert r == {"status": "done", "result": {"settings": {"a": 1}, "itemCount": 0}}, r


@test
def view_report_not_audited(C):
    c = paired(C)
    c.dispatch("s1", "view_report", {}, 1000)
    assert c.audit_log("m1") == []


@test
def deeplink_no_execute_no_audit(C):
    c = paired(C)
    r = c.dispatch("s1", "open_billing", {}, 1000)
    assert r["status"] == "deeplink" and isinstance(r["url"], str) and r["url"]
    assert c.audit_log("m1") == []


# ---- confirm ----
@test
def confirm_pending_not_executed(C):
    c = paired(C)
    r = c.dispatch("s1", "add_item", {"name": "x"}, 1000)
    assert r["status"] == "pending" and isinstance(r["confirmationId"], str)
    assert r["preview"] == {"tool": "add_item", "args": {"name": "x"}}
    assert c.get_state("m1")["items"] == []
    assert c.audit_log("m1") == []


@test
def confirm_commits(C):
    c = paired(C)
    cid = c.dispatch("s1", "add_item", {"name": "x"}, 1000)["confirmationId"]
    r = c.confirm("s1", cid, 1010)
    assert r == {"status": "done", "result": {"added": "x", "count": 1}}, r
    assert c.get_state("m1")["items"] == ["x"]
    assert len(c.audit_log("m1")) == 1


@test
def confirm_unknown(C):
    c = paired(C)
    assert c.confirm("s1", "conf-nope", 1000) == {"status": "error", "error": "unknown_confirmation"}


@test
def confirm_already_confirmed(C):
    c = paired(C)
    cid = c.dispatch("s1", "add_item", {"name": "x"}, 1000)["confirmationId"]
    c.confirm("s1", cid, 1000)
    assert c.confirm("s1", cid, 1000) == {"status": "error", "error": "already_confirmed"}


@test
def confirm_wrong_sender(C):
    c = paired(C)
    c.pair("s2", c.issue_pairing_code("m1", 1000), 1000)
    cid = c.dispatch("s1", "add_item", {"name": "x"}, 1000)["confirmationId"]
    assert c.confirm("s2", cid, 1000) == {"status": "error", "error": "wrong_sender"}


@test
def confirm_expired_at_boundary(C):
    c = paired(C)
    cid = c.dispatch("s1", "add_item", {"name": "x"}, 1000)["confirmationId"]
    assert c.confirm("s1", cid, 1120) == {"status": "error", "error": "confirmation_expired"}


@test
def confirm_valid_just_before_expiry(C):
    c = paired(C)
    cid = c.dispatch("s1", "add_item", {"name": "x"}, 1000)["confirmationId"]
    assert c.confirm("s1", cid, 1119)["status"] == "done"


@test
def confirm_error_precedence_wrong_sender_before_expired(C):
    # both wrong_sender and expired apply; spec order checks wrong_sender first
    c = paired(C)
    c.pair("s2", c.issue_pairing_code("m1", 1000), 1000)
    cid = c.dispatch("s1", "add_item", {"name": "x"}, 1000)["confirmationId"]
    assert c.confirm("s2", cid, 5000) == {"status": "error", "error": "wrong_sender"}


# ---- audit / isolation ----
@test
def audit_order_and_seq_increasing(C):
    c = paired(C)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    cid = c.dispatch("s1", "add_item", {"name": "x"}, 1001)["confirmationId"]
    c.confirm("s1", cid, 1002)
    c.dispatch("s1", "bump_counter", {}, 1003)
    log = c.audit_log("m1")
    assert [e["tool"] for e in log] == ["set_setting", "add_item", "bump_counter"], log
    seqs = [e["seq"] for e in log]
    assert seqs == sorted(seqs) and len(set(seqs)) == 3


@test
def merchant_isolation_state(C):
    c = C()
    c.pair("s1", c.issue_pairing_code("m1", 1000), 1000)
    c.pair("s2", c.issue_pairing_code("m2", 1000), 1000)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    c.dispatch("s2", "set_setting", {"key": "b", "value": 2}, 1000)
    assert c.get_state("m1")["settings"] == {"a": 1}
    assert c.get_state("m2")["settings"] == {"b": 2}


@test
def merchant_isolation_audit(C):
    c = C()
    c.pair("s1", c.issue_pairing_code("m1", 1000), 1000)
    c.pair("s2", c.issue_pairing_code("m2", 1000), 1000)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    c.dispatch("s2", "set_setting", {"key": "b", "value": 2}, 1000)
    assert len(c.audit_log("m1")) == 1 and len(c.audit_log("m2")) == 1


# ---- undo ----
@test
def undo_set_setting_restores_prev(C):
    c = paired(C)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 2}, 1001)
    assert c.undo("s1", 1002) == {"status": "undone", "undidSeq": 2}
    assert c.get_state("m1")["settings"] == {"a": 1}


@test
def undo_set_setting_removes_new_key(C):
    c = paired(C)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    c.undo("s1", 1001)
    assert c.get_state("m1")["settings"] == {}


@test
def undo_add_item_removes_it(C):
    c = paired(C)
    cid = c.dispatch("s1", "add_item", {"name": "x"}, 1000)["confirmationId"]
    c.confirm("s1", cid, 1000)
    c.undo("s1", 1001)
    assert c.get_state("m1")["items"] == []


@test
def undo_delete_all_restores(C):
    c = paired(C)
    for i, name in enumerate(["x", "y"]):
        cid = c.dispatch("s1", "add_item", {"name": name}, 1000 + i)["confirmationId"]
        c.confirm("s1", cid, 1000 + i)
    cid = c.dispatch("s1", "delete_all_items", {}, 1005)["confirmationId"]
    c.confirm("s1", cid, 1005)
    assert c.get_state("m1")["items"] == []
    c.undo("s1", 1006)
    assert c.get_state("m1")["items"] == ["x", "y"]


@test
def undo_is_lifo(C):
    c = paired(C)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    cid = c.dispatch("s1", "add_item", {"name": "x"}, 1001)["confirmationId"]
    c.confirm("s1", cid, 1001)
    c.undo("s1", 1002)  # undoes add_item (most recent undoable)
    assert c.get_state("m1")["items"] == [] and c.get_state("m1")["settings"] == {"a": 1}
    c.undo("s1", 1003)  # undoes set_setting
    assert c.get_state("m1")["settings"] == {}


@test
def undo_marks_undone_and_appends_compensation(C):
    c = paired(C)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    c.undo("s1", 1001)
    log = c.audit_log("m1")
    action = [e for e in log if e["kind"] == "action"][0]
    comp = [e for e in log if e["kind"] == "compensation"]
    assert action["undone"] is True
    assert len(comp) == 1 and comp[0]["tool"] == "undo" and comp[0]["args"] == {"seq": action["seq"]}


@test
def undo_skips_already_undone(C):
    c = paired(C)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    c.undo("s1", 1001)
    assert c.undo("s1", 1002) == {"status": "error", "error": "nothing_to_undo"}


@test
def undo_skips_non_undoable_bump(C):
    c = paired(C)
    c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
    c.dispatch("s1", "bump_counter", {}, 1001)
    r = c.undo("s1", 1002)  # must skip bump_counter and undo set_setting
    assert r["status"] == "undone" and r["undidSeq"] == 1, r
    assert c.get_state("m1")["settings"] == {} and c.get_state("m1")["counter"] == 1


@test
def undo_nothing_to_undo_when_only_non_undoable(C):
    c = paired(C)
    c.dispatch("s1", "bump_counter", {}, 1000)
    assert c.undo("s1", 1001) == {"status": "error", "error": "nothing_to_undo"}


@test
def undo_not_paired(C):
    c = C()
    assert c.undo("s1", 1000) == {"status": "error", "error": "not_paired"}


# ---- integrity ----
@test
def get_state_returns_copies(C):
    c = paired(C)
    cid = c.dispatch("s1", "add_item", {"name": "x"}, 1000)["confirmationId"]
    c.confirm("s1", cid, 1000)
    st = c.get_state("m1")
    st["items"].append("mutant")
    assert c.get_state("m1")["items"] == ["x"]


@test
def deterministic_replay(C):
    def run():
        c = paired(C)
        c.dispatch("s1", "set_setting", {"key": "a", "value": 1}, 1000)
        cid = c.dispatch("s1", "add_item", {"name": "x"}, 1001)["confirmationId"]
        c.confirm("s1", cid, 1002)
        c.undo("s1", 1003)
        return c.get_state("m1"), c.audit_log("m1")
    assert run() == run()


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: harness.py <candidate_dir>\n")
        print("RESULT 0 %d" % len(TESTS))
        return 1
    total = len(TESTS)
    try:
        C = load(sys.argv[1])
    except Exception as e:  # import/exec failure = all fail, but still emit RESULT
        sys.stderr.write("load failed: %r\n" % e)
        for name, _ in TESTS:
            print("FAIL %s: import error" % name)
        print("RESULT 0 %d" % total)
        return 1
    passed = 0
    for name, fn in TESTS:
        try:
            fn(C)
            print("PASS %s" % name)
            passed += 1
        except AssertionError as e:
            print("FAIL %s: %s" % (name, str(e)[:120]))
        except Exception as e:  # noqa
            print("FAIL %s: %r" % (name, e))
    print("RESULT %d %d" % (passed, total))
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
