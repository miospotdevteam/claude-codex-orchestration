"""Hidden conformance suite for mvcc-savepoint-store.

Usage: python3 harness.py <candidate_dir>
"""
import importlib.util
import os
import sys


sys.dont_write_bytecode = True


TESTS = []


def test(fn):
    TESTS.append((fn.__name__, fn))
    return fn


def load(candidate_dir):
    path = os.path.join(candidate_dir, "mvcc_store.py")
    spec = importlib.util.spec_from_file_location("candidate_mvcc_store", path)
    module = importlib.util.module_from_spec(spec)
    # Register before exec so @dataclass (which resolves via sys.modules) loads.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module.MVCCStore


def commit_value(store, tx_id, seq, key, value):
    store.begin(tx_id)
    store.put(tx_id, key, value)
    return store.commit(tx_id, seq)


def commit_delete(store, tx_id, seq, key):
    store.begin(tx_id)
    store.delete(tx_id, key)
    return store.commit(tx_id, seq)


@test
def begin_uses_zero_snapshot_initially(Store):
    store = Store()
    assert store.begin("t") == {"status": "ok", "snapshot": 0}


@test
def committed_value_visible_to_later_transaction(Store):
    store = Store()
    store.begin("writer")
    store.put("writer", "k", {"n": 1})
    assert store.commit("writer", 7) == {
        "status": "committed", "commit": 7, "writes": 1
    }
    assert store.begin("reader") == {"status": "ok", "snapshot": 7}
    assert store.get("reader", "k") == {
        "status": "ok", "found": True, "value": {"n": 1}
    }


@test
def same_key_concurrent_writer_conflicts(Store):
    store = Store()
    store.begin("a")
    store.begin("b")
    store.put("a", "k", "A")
    store.put("b", "k", "B")
    store.commit("a", 1)
    assert store.commit("b", 2) == {"status": "conflict", "keys": ["k"]}


@test
def transaction_ids_remain_single_use_after_commit(Store):
    store = Store()
    store.begin("t")
    store.commit("t", 3)
    assert store.begin("t") == {
        "status": "error", "error": "duplicate_transaction"
    }


@test
def invalid_commit_sequence_leaves_transaction_open(Store):
    store = Store()
    store.begin("t")
    store.put("t", "k", "v")
    assert store.commit("t", True) == {
        "status": "error", "error": "invalid_commit_sequence"
    }
    assert store.commit("t", 4) == {
        "status": "committed", "commit": 4, "writes": 1
    }


@test
def unknown_and_closed_transaction_errors_are_distinct(Store):
    store = Store()
    assert store.get("never", "k") == {
        "status": "error", "error": "unknown_transaction"
    }
    store.begin("done")
    store.abort("done")
    assert store.get("done", "k") == {
        "status": "error", "error": "transaction_closed"
    }


@test
def rollback_keeps_named_savepoint_and_removes_later_ones(Store):
    store = Store()
    store.begin("t")
    store.put("t", "k", 1)
    store.savepoint("t", "outer")
    store.put("t", "k", 2)
    store.savepoint("t", "inner")
    store.put("t", "k", 3)
    assert store.rollback_to("t", "outer") == {"status": "ok"}
    assert store.get("t", "k")["value"] == 1
    assert store.rollback_to("t", "inner") == {
        "status": "error", "error": "unknown_savepoint"
    }
    assert store.rollback_to("t", "outer") == {"status": "ok"}


@test
def release_keeps_writes_but_removes_named_and_later_savepoints(Store):
    store = Store()
    store.begin("t")
    store.savepoint("t", "a")
    store.put("t", "k", "kept")
    store.savepoint("t", "b")
    assert store.release("t", "a") == {"status": "ok"}
    assert store.get("t", "k")["value"] == "kept"
    assert store.rollback_to("t", "a")["error"] == "unknown_savepoint"
    assert store.rollback_to("t", "b")["error"] == "unknown_savepoint"


@test
def savepoint_capture_is_deep_and_isolated(Store):
    store = Store()
    store.begin("t")
    value = {"nested": [1]}
    store.put("t", "k", value)
    store.savepoint("t", "s")
    value["nested"].append(99)
    store.put("t", "k", {"nested": [2]})
    store.rollback_to("t", "s")
    assert store.get("t", "k")["value"] == {"nested": [1]}


@test
def garbage_collection_keeps_only_latest_anchor_below_cutoff(Store):
    store = Store()
    for tx_id, seq, value in [("a", 1, "v1"), ("b", 2, "v2"), ("c", 3, "v3")]:
        store.begin(tx_id)
        store.put(tx_id, "k", value)
        store.commit(tx_id, seq)
    assert store.collect_garbage(99) == {"status": "ok", "cutoff": 4, "removed": 2}
    assert store.history("k") == [
        {"commit": 3, "deleted": False, "value": "v3"}
    ]


@test
def oldest_open_snapshot_pins_garbage_collection(Store):
    store = Store()
    for tx_id, seq in [("a", 1), ("b", 2), ("c", 3)]:
        store.begin(tx_id)
        store.put(tx_id, "k", seq)
        store.commit(tx_id, seq)
    store.begin("old")  # snapshot 3
    store.begin("new-writer")
    store.put("new-writer", "k", 4)
    store.commit("new-writer", 4)
    assert store.collect_garbage(99) == {"status": "ok", "cutoff": 3, "removed": 1}
    assert [item["commit"] for item in store.history("k")] == [2, 3, 4]
    assert store.get("old", "k")["value"] == 3


@test
def garbage_collection_retains_tombstone_anchor_and_exact_cutoff(Store):
    store = Store()
    store.begin("a")
    store.put("a", "k", "old")
    store.commit("a", 1)
    store.begin("b")
    store.delete("b", "k")
    store.commit("b", 2)
    store.begin("c")
    store.put("c", "k", "new")
    store.commit("c", 4)
    assert store.collect_garbage(4) == {"status": "ok", "cutoff": 4, "removed": 1}
    assert store.history("k") == [
        {"commit": 2, "deleted": True},
        {"commit": 4, "deleted": False, "value": "new"},
    ]


# ---- transaction lifecycle and snapshots ----
@test
def read_only_commit_advances_snapshot_sequence(Store):
    store = Store()
    store.begin("reader")
    assert store.commit("reader", 9) == {
        "status": "committed", "commit": 9, "writes": 0
    }
    assert store.begin("next") == {"status": "ok", "snapshot": 9}


@test
def duplicate_transaction_rejected_while_open_without_damage(Store):
    store = Store()
    store.begin("t")
    store.put("t", "k", 1)
    assert store.begin("t")["error"] == "duplicate_transaction"
    assert store.get("t", "k")["value"] == 1


@test
def abort_discards_uncommitted_writes(Store):
    store = Store()
    store.begin("t")
    store.put("t", "k", "ghost")
    assert store.abort("t") == {"status": "aborted"}
    store.begin("reader")
    assert store.get("reader", "k") == {"status": "ok", "found": False}
    assert store.history("k") == []


@test
def conflict_closes_before_commit_sequence_validation(Store):
    store = Store()
    store.begin("loser")
    store.put("loser", "k", "old")
    commit_value(store, "winner", 3, "k", "new")
    assert store.commit("loser", 4) == {"status": "conflict", "keys": ["k"]}
    assert store.commit("loser", 0) == {
        "status": "error", "error": "transaction_closed"
    }


@test
def read_only_commit_reports_zero_writes(Store):
    store = Store()
    store.begin("t")
    store.get("t", "missing")
    store.scan("t")
    assert store.commit("t", 11) == {
        "status": "committed", "commit": 11, "writes": 0
    }


@test
def equal_commit_sequence_is_invalid_but_retryable(Store):
    store = Store()
    commit_value(store, "a", 5, "a", 1)
    store.begin("b")
    store.put("b", "b", 2)
    assert store.commit("b", 5)["error"] == "invalid_commit_sequence"
    assert store.commit("b", 8)["status"] == "committed"


@test
def store_instances_have_no_shared_state(Store):
    left = Store()
    right = Store()
    commit_value(left, "same-id", 7, "k", {"v": 1})
    assert right.begin("same-id") == {"status": "ok", "snapshot": 0}
    assert right.get("same-id", "k") == {"status": "ok", "found": False}


@test
def old_snapshot_does_not_see_later_insert(Store):
    store = Store()
    store.begin("old")
    commit_value(store, "writer", 2, "k", "later")
    assert store.get("old", "k") == {"status": "ok", "found": False}


@test
def old_snapshot_sees_value_before_overwrite(Store):
    store = Store()
    commit_value(store, "one", 1, "k", "v1")
    store.begin("old")
    commit_value(store, "two", 2, "k", "v2")
    assert store.get("old", "k")["value"] == "v1"


@test
def old_snapshot_sees_value_before_tombstone(Store):
    store = Store()
    commit_value(store, "one", 1, "k", "live")
    store.begin("old")
    commit_delete(store, "two", 2, "k")
    assert store.get("old", "k") == {
        "status": "ok", "found": True, "value": "live"
    }
    store.begin("new")
    assert store.get("new", "k") == {"status": "ok", "found": False}


@test
def transaction_reads_own_new_value(Store):
    store = Store()
    store.begin("t")
    store.put("t", "k", [1, 2])
    assert store.get("t", "k")["value"] == [1, 2]


@test
def transaction_reads_own_tombstone(Store):
    store = Store()
    commit_value(store, "seed", 1, "k", 1)
    store.begin("t")
    store.delete("t", "k")
    assert store.get("t", "k") == {"status": "ok", "found": False}


@test
def aborted_deletion_is_invisible(Store):
    store = Store()
    commit_value(store, "seed", 1, "k", "kept")
    store.begin("t")
    store.delete("t", "k")
    store.abort("t")
    store.begin("reader")
    assert store.get("reader", "k")["value"] == "kept"


@test
def final_buffered_operation_wins_and_creates_one_version(Store):
    store = Store()
    store.begin("t")
    store.put("t", "k", 1)
    store.delete("t", "k")
    store.put("t", "k", 3)
    assert store.commit("t", 4)["writes"] == 1
    assert store.history("k") == [
        {"commit": 4, "deleted": False, "value": 3}
    ]


@test
def commit_sequence_gaps_are_preserved(Store):
    store = Store()
    commit_value(store, "a", 10, "a", 1)
    commit_value(store, "b", 100, "b", 2)
    assert store.begin("r")["snapshot"] == 100
    assert [item["commit"] for item in store.history("b")] == [100]


@test
def uncommitted_writes_are_isolated(Store):
    store = Store()
    store.begin("writer")
    store.put("writer", "k", "private")
    store.begin("reader")
    assert store.get("reader", "k") == {"status": "ok", "found": False}


# ---- copies and delete intents ----
@test
def put_deep_copies_caller_input(Store):
    store = Store()
    value = {"a": [{"b": 1}]}
    store.begin("t")
    store.put("t", "k", value)
    value["a"][0]["b"] = 99
    store.commit("t", 1)
    store.begin("r")
    assert store.get("r", "k")["value"] == {"a": [{"b": 1}]}


@test
def get_returns_deep_copy(Store):
    store = Store()
    commit_value(store, "w", 1, "k", {"a": [[1]]})
    store.begin("r")
    first = store.get("r", "k")["value"]
    first["a"][0].append(2)
    assert store.get("r", "k")["value"] == {"a": [[1]]}


@test
def history_returns_deep_copy(Store):
    store = Store()
    commit_value(store, "w", 1, "k", {"a": [1]})
    exposed = store.history("k")
    exposed[0]["value"]["a"].append(2)
    exposed.append({"commit": 99, "deleted": True})
    assert store.history("k") == [
        {"commit": 1, "deleted": False, "value": {"a": [1]}}
    ]


@test
def delete_reports_current_view_and_repeat_becomes_absent(Store):
    store = Store()
    commit_value(store, "seed", 1, "k", 1)
    store.begin("t")
    assert store.delete("t", "k") == {"status": "ok", "existed": True}
    assert store.delete("t", "k") == {"status": "ok", "existed": False}


@test
def delete_absent_key_still_commits_tombstone(Store):
    store = Store()
    store.begin("t")
    assert store.delete("t", "missing") == {"status": "ok", "existed": False}
    assert store.commit("t", 2)["writes"] == 1
    assert store.history("missing") == [{"commit": 2, "deleted": True}]


@test
def put_after_own_delete_restores_presence(Store):
    store = Store()
    commit_value(store, "seed", 1, "k", "old")
    store.begin("t")
    store.delete("t", "k")
    store.put("t", "k", "new")
    assert store.get("t", "k")["value"] == "new"
    store.commit("t", 2)
    assert store.history("k")[-1]["deleted"] is False


@test
def delete_after_own_put_reports_present(Store):
    store = Store()
    store.begin("t")
    store.put("t", "new", 1)
    assert store.delete("t", "new") == {"status": "ok", "existed": True}


# ---- ordered scans ----
@test
def scan_returns_visible_keys_in_string_order(Store):
    store = Store()
    store.begin("w")
    for key in ["z", "a", "aa", "b"]:
        store.put("w", key, key.upper())
    store.commit("w", 1)
    store.begin("r")
    assert [item["key"] for item in store.scan("r")["items"]] == ["a", "aa", "b", "z"]


@test
def scan_uses_inclusive_start_and_exclusive_end(Store):
    store = Store()
    store.begin("w")
    for key in ["a", "b", "c", "d"]:
        store.put("w", key, key)
    store.commit("w", 1)
    store.begin("r")
    assert [item["key"] for item in store.scan("r", "b", "d")["items"]] == ["b", "c"]


@test
def scan_supports_each_unbounded_side(Store):
    store = Store()
    store.begin("w")
    for key in ["a", "b", "c"]:
        store.put("w", key, key)
    store.commit("w", 1)
    store.begin("r")
    assert [x["key"] for x in store.scan("r", end="c")["items"]] == ["a", "b"]
    assert [x["key"] for x in store.scan("r", start="b")["items"]] == ["b", "c"]


@test
def scan_empty_when_start_meets_or_exceeds_end(Store):
    store = Store()
    commit_value(store, "w", 1, "b", 1)
    store.begin("r")
    assert store.scan("r", "b", "b")["items"] == []
    assert store.scan("r", "z", "a")["items"] == []


@test
def scan_applies_limit_after_range_and_tombstone_filtering(Store):
    store = Store()
    store.begin("w")
    for key in ["a", "b", "c", "d"]:
        store.put("w", key, key)
    store.commit("w", 1)
    commit_delete(store, "del", 2, "b")
    store.begin("r")
    assert [x["key"] for x in store.scan("r", "b", None, 2)["items"]] == ["c", "d"]


@test
def scan_zero_limit_is_empty(Store):
    store = Store()
    commit_value(store, "w", 1, "a", 1)
    store.begin("r")
    assert store.scan("r", limit=0) == {"status": "ok", "items": []}


@test
def scan_places_own_insert_in_global_order(Store):
    store = Store()
    store.begin("w")
    store.put("w", "a", 1)
    store.put("w", "c", 3)
    store.commit("w", 1)
    store.begin("r")
    store.put("r", "b", 2)
    assert [x["key"] for x in store.scan("r")["items"]] == ["a", "b", "c"]


@test
def scan_overlays_own_delete_and_overwrite(Store):
    store = Store()
    store.begin("w")
    store.put("w", "a", 1)
    store.put("w", "b", 2)
    store.commit("w", 1)
    store.begin("r")
    store.delete("r", "a")
    store.put("r", "b", 20)
    assert store.scan("r")["items"] == [{"key": "b", "value": 20}]


@test
def scan_snapshot_allows_concurrent_phantom_without_visibility(Store):
    store = Store()
    commit_value(store, "seed", 1, "a", 1)
    store.begin("scanner")
    assert [x["key"] for x in store.scan("scanner")["items"]] == ["a"]
    commit_value(store, "other", 2, "b", 2)
    assert [x["key"] for x in store.scan("scanner")["items"]] == ["a"]
    store.put("scanner", "c", 3)
    assert store.commit("scanner", 3)["status"] == "committed"


@test
def scan_returns_deep_copies(Store):
    store = Store()
    commit_value(store, "w", 1, "a", {"x": [1]})
    store.begin("r")
    items = store.scan("r")["items"]
    items[0]["value"]["x"].append(2)
    assert store.scan("r")["items"] == [{"key": "a", "value": {"x": [1]}}]


@test
def scan_checks_transaction_before_range_arguments(Store):
    store = Store()
    assert store.scan("missing", "z", "a", 0) == {
        "status": "error", "error": "unknown_transaction"
    }
    store.begin("closed")
    store.abort("closed")
    assert store.scan("closed") == {
        "status": "error", "error": "transaction_closed"
    }


# ---- first-committer-wins and legal anomalies ----
@test
def blind_write_conflicts_with_newer_committed_version(Store):
    store = Store()
    store.begin("blind")
    commit_value(store, "winner", 1, "k", 1)
    store.put("blind", "k", 2)
    assert store.commit("blind", 2) == {"status": "conflict", "keys": ["k"]}


@test
def delete_conflicts_with_concurrent_update(Store):
    store = Store()
    commit_value(store, "seed", 1, "k", 1)
    store.begin("deleter")
    commit_value(store, "winner", 2, "k", 2)
    store.delete("deleter", "k")
    assert store.commit("deleter", 3)["status"] == "conflict"


@test
def put_conflicts_with_concurrent_tombstone(Store):
    store = Store()
    commit_value(store, "seed", 1, "k", 1)
    store.begin("writer")
    commit_delete(store, "deleter", 2, "k")
    store.put("writer", "k", 3)
    assert store.commit("writer", 3) == {"status": "conflict", "keys": ["k"]}


@test
def absent_delete_intent_conflicts_with_concurrent_insert(Store):
    store = Store()
    store.begin("deleter")
    assert store.delete("deleter", "k")["existed"] is False
    commit_value(store, "inserter", 1, "k", "new")
    assert store.commit("deleter", 2)["status"] == "conflict"


@test
def multi_key_conflict_list_is_complete_unique_and_sorted(Store):
    store = Store()
    store.begin("loser")
    for key in ["z", "a", "z", "m"]:
        store.put("loser", key, "L")
    store.begin("winner")
    store.put("winner", "z", 1)
    store.put("winner", "a", 1)
    store.commit("winner", 1)
    assert store.commit("loser", 2) == {"status": "conflict", "keys": ["a", "z"]}


@test
def conflict_is_atomic_for_nonconflicting_keys_too(Store):
    store = Store()
    store.begin("loser")
    store.put("loser", "hot", "lost")
    store.put("loser", "cold", "must-not-commit")
    commit_value(store, "winner", 1, "hot", "won")
    store.commit("loser", 2)
    store.begin("r")
    assert store.get("r", "hot")["value"] == "won"
    assert store.get("r", "cold") == {"status": "ok", "found": False}
    assert store.history("cold") == []


@test
def sequence_rejected_by_conflict_can_be_reused(Store):
    store = Store()
    store.begin("loser")
    store.put("loser", "k", "lost")
    commit_value(store, "winner", 5, "k", "won")
    assert store.commit("loser", 9)["status"] == "conflict"
    assert commit_value(store, "reuse", 9, "other", 1)["status"] == "committed"


@test
def disjoint_writers_from_same_snapshot_both_commit(Store):
    store = Store()
    store.begin("a")
    store.begin("b")
    store.put("a", "x", 1)
    store.put("b", "y", 2)
    assert store.commit("a", 1)["status"] == "committed"
    assert store.commit("b", 2)["status"] == "committed"


@test
def write_skew_is_allowed_under_snapshot_isolation(Store):
    store = Store()
    store.begin("seed")
    store.put("seed", "doctor-a", True)
    store.put("seed", "doctor-b", True)
    store.commit("seed", 1)
    store.begin("a")
    store.begin("b")
    assert store.get("a", "doctor-b")["value"] is True
    assert store.get("b", "doctor-a")["value"] is True
    store.put("a", "doctor-a", False)
    store.put("b", "doctor-b", False)
    assert store.commit("a", 2)["status"] == "committed"
    assert store.commit("b", 3)["status"] == "committed"


@test
def read_sets_never_create_conflicts(Store):
    store = Store()
    commit_value(store, "seed", 1, "watched", 1)
    store.begin("reader-writer")
    store.get("reader-writer", "watched")
    store.scan("reader-writer")
    commit_value(store, "updater", 2, "watched", 2)
    store.put("reader-writer", "other", 3)
    assert store.commit("reader-writer", 3)["status"] == "committed"


@test
def repeated_writes_to_one_key_count_once(Store):
    store = Store()
    store.begin("t")
    for value in range(10):
        store.put("t", "k", value)
    assert store.commit("t", 1)["writes"] == 1
    assert store.history("k")[0]["value"] == 9


@test
def rolled_back_write_is_excluded_from_conflicts_and_commit(Store):
    store = Store()
    store.begin("t")
    store.savepoint("t", "clean")
    store.put("t", "hot", "discard")
    store.put("t", "kept", 1)
    store.rollback_to("t", "clean")
    store.put("t", "kept", 2)
    commit_value(store, "other", 1, "hot", "winner")
    assert store.commit("t", 2) == {"status": "committed", "commit": 2, "writes": 1}


# ---- savepoint edge cases ----
@test
def duplicate_active_savepoint_name_is_rejected(Store):
    store = Store()
    store.begin("t")
    store.savepoint("t", "s")
    store.put("t", "k", 1)
    assert store.savepoint("t", "s") == {
        "status": "error", "error": "duplicate_savepoint"
    }
    assert store.get("t", "k")["value"] == 1


@test
def savepoint_name_can_be_reused_after_release(Store):
    store = Store()
    store.begin("t")
    store.savepoint("t", "s")
    store.release("t", "s")
    assert store.savepoint("t", "s") == {"status": "ok"}


@test
def rollback_can_restore_key_to_snapshot_absence(Store):
    store = Store()
    store.begin("t")
    store.savepoint("t", "empty")
    store.put("t", "k", 1)
    store.rollback_to("t", "empty")
    assert store.get("t", "k") == {"status": "ok", "found": False}
    assert store.commit("t", 1)["writes"] == 0


@test
def rollback_restores_captured_tombstone(Store):
    store = Store()
    commit_value(store, "seed", 1, "k", "live")
    store.begin("t")
    store.delete("t", "k")
    store.savepoint("t", "deleted")
    store.put("t", "k", "resurrected")
    store.rollback_to("t", "deleted")
    assert store.get("t", "k") == {"status": "ok", "found": False}


@test
def releasing_inner_savepoint_leaves_outer_active(Store):
    store = Store()
    store.begin("t")
    store.put("t", "k", 1)
    store.savepoint("t", "outer")
    store.put("t", "k", 2)
    store.savepoint("t", "inner")
    store.put("t", "k", 3)
    store.release("t", "inner")
    store.rollback_to("t", "outer")
    assert store.get("t", "k")["value"] == 1


@test
def savepoint_errors_follow_transaction_lookup_precedence(Store):
    store = Store()
    assert store.savepoint("none", "s")["error"] == "unknown_transaction"
    assert store.rollback_to("none", "s")["error"] == "unknown_transaction"
    store.begin("closed")
    store.abort("closed")
    assert store.release("closed", "missing")["error"] == "transaction_closed"


# ---- additional garbage-collection interactions ----
@test
def closing_old_snapshot_allows_later_collection(Store):
    store = Store()
    commit_value(store, "one", 1, "k", 1)
    store.begin("old")
    commit_value(store, "two", 2, "k", 2)
    assert store.collect_garbage(99)["cutoff"] == 1
    store.abort("old")
    assert store.collect_garbage(99) == {"status": "ok", "cutoff": 3, "removed": 1}


@test
def read_only_open_transaction_pins_collection(Store):
    store = Store()
    for tx_id, seq in [("one", 1), ("two", 2), ("three", 3)]:
        commit_value(store, tx_id, seq, "k", seq)
    store.begin("reader")
    commit_value(store, "four", 4, "k", 4)
    assert store.collect_garbage(99) == {"status": "ok", "cutoff": 3, "removed": 1}
    store.abort("reader")
    assert store.collect_garbage(99) == {"status": "ok", "cutoff": 5, "removed": 2}


@test
def garbage_collection_counts_anchors_per_key(Store):
    store = Store()
    commit_value(store, "a1", 1, "a", 1)
    commit_value(store, "b1", 2, "b", 1)
    commit_value(store, "a2", 3, "a", 2)
    commit_value(store, "b2", 4, "b", 2)
    assert store.collect_garbage(99) == {"status": "ok", "cutoff": 5, "removed": 2}
    assert [x["commit"] for x in store.history("a")] == [3]
    assert [x["commit"] for x in store.history("b")] == [4]


@test
def garbage_collection_is_idempotent_even_with_lower_request(Store):
    store = Store()
    for tx_id, seq in [("a", 1), ("b", 2), ("c", 3)]:
        commit_value(store, tx_id, seq, "k", seq)
    assert store.collect_garbage(99)["removed"] == 2
    assert store.collect_garbage(2) == {"status": "ok", "cutoff": 2, "removed": 0}
    assert store.history("k")[0]["commit"] == 3


@test
def garbage_collection_preserves_multiple_live_snapshot_answers(Store):
    store = Store()
    for tx_id, seq in [("a", 1), ("b", 2), ("c", 3)]:
        commit_value(store, tx_id, seq, "k", seq)
    store.begin("old")
    commit_value(store, "d", 4, "k", 4)
    store.begin("new")
    commit_value(store, "e", 5, "k", 5)
    assert store.collect_garbage(99) == {"status": "ok", "cutoff": 3, "removed": 1}
    assert store.get("old", "k")["value"] == 3
    assert store.get("new", "k")["value"] == 4


@test
def garbage_collection_preserves_conflict_detection(Store):
    store = Store()
    commit_value(store, "seed", 1, "k", 1)
    store.begin("stale")
    store.put("stale", "k", "stale")
    commit_value(store, "winner", 2, "k", 2)
    store.collect_garbage(99)
    assert store.commit("stale", 3) == {"status": "conflict", "keys": ["k"]}
    assert store.collect_garbage(99) == {"status": "ok", "cutoff": 3, "removed": 1}


@test
def zero_gc_boundary_removes_nothing(Store):
    store = Store()
    commit_value(store, "w", 5, "k", 1)
    assert store.collect_garbage(0) == {"status": "ok", "cutoff": 0, "removed": 0}
    assert store.history("k")[0]["commit"] == 5


# ---- audit-driven adversarial gaps ----
@test
def stored_none_is_present_and_distinct_from_tombstone(Store):
    store = Store()
    commit_value(store, "w", 1, "k", None)
    store.begin("r")
    assert store.get("r", "k") == {"status": "ok", "found": True, "value": None}
    assert store.scan("r")["items"] == [{"key": "k", "value": None}]
    assert store.history("k") == [
        {"commit": 1, "deleted": False, "value": None}
    ]


@test
def every_invalid_commit_sequence_preserves_writes_and_savepoints(Store):
    store = Store()
    store.begin("t")
    store.put("t", "k", "captured")
    store.savepoint("t", "s")
    store.put("t", "k", "later")
    for invalid in [0, -1, 1.5, "2", True]:
        assert store.commit("t", invalid) == {
            "status": "error", "error": "invalid_commit_sequence"
        }
    assert store.rollback_to("t", "s") == {"status": "ok"}
    assert store.get("t", "k")["value"] == "captured"
    assert store.commit("t", 2)["status"] == "committed"


@test
def unknown_transaction_precedes_validation_across_mutating_api(Store):
    store = Store()
    expected = {"status": "error", "error": "unknown_transaction"}
    assert store.put("none", "k", 1) == expected
    assert store.delete("none", "k") == expected
    assert store.abort("none") == expected
    assert store.commit("none", 0) == expected


@test
def closed_transaction_errors_across_mutating_and_savepoint_api(Store):
    store = Store()
    store.begin("t")
    store.abort("t")
    expected = {"status": "error", "error": "transaction_closed"}
    assert store.put("t", "k", 1) == expected
    assert store.delete("t", "k") == expected
    assert store.abort("t") == expected
    assert store.savepoint("t", "s") == expected
    assert store.rollback_to("t", "s") == expected
    assert store.release("t", "s") == expected


@test
def old_snapshot_scan_survives_later_overwrite_and_tombstone(Store):
    store = Store()
    commit_value(store, "one", 1, "k", "v1")
    store.begin("old")
    commit_value(store, "two", 2, "k", "v2")
    commit_delete(store, "three", 3, "k")
    assert store.scan("old")["items"] == [{"key": "k", "value": "v1"}]
    store.begin("new")
    assert store.scan("new")["items"] == []


@test
def savepoint_name_removed_by_rollback_can_be_reused(Store):
    store = Store()
    store.begin("t")
    store.savepoint("t", "outer")
    store.savepoint("t", "inner")
    store.rollback_to("t", "outer")
    assert store.savepoint("t", "inner") == {"status": "ok"}


@test
def transaction_ids_remain_single_use_after_abort_and_conflict(Store):
    store = Store()
    store.begin("aborted")
    store.abort("aborted")
    assert store.begin("aborted")["error"] == "duplicate_transaction"
    store.begin("conflicted")
    store.put("conflicted", "k", "lost")
    commit_value(store, "winner", 1, "k", "won")
    store.commit("conflicted", 2)
    assert store.begin("conflicted")["error"] == "duplicate_transaction"


# ---------------------------------------------------------------------------
# Differential fuzzer: run identical seeded-random operation sequences through
# the candidate and a hidden reference oracle; any divergence fails that seed.
# Probes the interacting state space far beyond the hand-written cases.
# ---------------------------------------------------------------------------
import random as _random


def _load_oracle():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "oracle.py")
    spec = importlib.util.spec_from_file_location("mvcc_oracle", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod.MVCCStore


_ORACLE = _load_oracle()
_TX = ["t0", "t1", "t2", "t3"]
_KEYS = ["k0", "k1", "k2", "k3", "k4"]
_SPN = ["s0", "s1", "s2"]
_VALS = [None, True, False, 0, 1, 7, -3, 3.5, "a", "b", [1, 2], {"a": 1}, {"n": None}]


def _gen_ops(rng, n):
    ops = []
    seq = 0
    for _ in range(n):
        m = rng.choice(
            ["begin", "put", "get", "delete", "commit", "abort", "savepoint",
             "rollback_to", "release", "scan", "history", "gc", "commit", "put", "get"]
        )
        tx = rng.choice(_TX)
        if m == "begin":
            ops.append(("begin", (tx,)))
        elif m == "put":
            ops.append(("put", (tx, rng.choice(_KEYS), rng.choice(_VALS))))
        elif m == "get":
            ops.append(("get", (tx, rng.choice(_KEYS))))
        elif m == "delete":
            ops.append(("delete", (tx, rng.choice(_KEYS))))
        elif m == "abort":
            ops.append(("abort", (tx,)))
        elif m == "savepoint":
            ops.append(("savepoint", (tx, rng.choice(_SPN))))
        elif m == "rollback_to":
            ops.append(("rollback_to", (tx, rng.choice(_SPN))))
        elif m == "release":
            ops.append(("release", (tx, rng.choice(_SPN))))
        elif m == "history":
            ops.append(("history", (rng.choice(_KEYS),)))
        elif m == "gc":
            ops.append(("collect_garbage", (rng.randint(0, seq + 2),)))
        elif m == "scan":
            start = rng.choice([None] + _KEYS)
            end = rng.choice([None] + _KEYS)
            limit = rng.choice([None, 0, 1, 2, 3])
            ops.append(("scan", (tx, start, end, limit)))
        elif m == "commit":
            if rng.random() < 0.8:
                seq += rng.randint(1, 2)
                s = seq
            else:
                s = rng.randint(0, seq)
            ops.append(("commit", (tx, s)))
    return ops


def _call(store, method, args):
    try:
        return ("ok", getattr(store, method)(*args))
    except BaseException as exc:  # a spec-compliant impl never raises here
        return ("raise", type(exc).__name__)


def _fuzz(Cand, seed, nops=250):
    rng = _random.Random(seed)
    ops = _gen_ops(rng, nops)
    cand = Cand()
    orac = _ORACLE()
    for i, (m, a) in enumerate(ops):
        rc = _call(cand, m, a)
        ro = _call(orac, m, a)
        if rc != ro:
            return "op#%d %s%r -> cand=%r oracle=%r" % (i, m, a, rc, ro)
    for k in _KEYS:
        rc = _call(cand, "history", (k,))
        ro = _call(orac, "history", (k,))
        if rc != ro:
            return "final history(%r) -> cand=%r oracle=%r" % (k, rc, ro)
    return None


def _register_fuzz(count):
    for _s in range(count):
        def make(seed):
            def t(Store):
                detail = _fuzz(Store, seed)
                assert detail is None, detail
            t.__name__ = "fuzz_%04d" % seed
            return t
        test(make(_s))


_register_fuzz(1500)


def main():
    total = len(TESTS)
    if len(sys.argv) != 2:
        sys.stderr.write("usage: harness.py <candidate_dir>\n")
        for name, _ in TESTS:
            print("FAIL %s [missing candidate directory]" % name)
        print("RESULT 0 %d" % total)
        return 1
    try:
        Store = load(sys.argv[1])
    except BaseException as exc:
        sys.stderr.write("load failed: %r\n" % (exc,))
        for name, _ in TESTS:
            print("FAIL %s [import error]" % name)
        print("RESULT 0 %d" % total)
        return 1
    passed = 0
    for name, fn in TESTS:
        try:
            fn(Store)
            print("PASS %s" % name)
            passed += 1
        except AssertionError as exc:
            reason = str(exc).replace("\n", " ")[:160] or "assertion failed"
            print("FAIL %s [%s]" % (name, reason))
        except BaseException as exc:
            reason = repr(exc).replace("\n", " ")[:160]
            print("FAIL %s [%s]" % (name, reason))
    print("RESULT %d %d" % (passed, total))
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
