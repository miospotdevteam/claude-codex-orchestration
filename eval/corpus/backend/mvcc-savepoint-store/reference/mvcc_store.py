"""Gold implementation for the hidden MVCC benchmark."""
from copy import deepcopy


class MVCCStore:
    def __init__(self):
        self._last_commit = 0
        self._transactions = {}
        self._versions = {}

    def _lookup(self, tx_id):
        tx = self._transactions.get(tx_id)
        if tx is None:
            return None, {"status": "error", "error": "unknown_transaction"}
        if not tx["open"]:
            return None, {"status": "error", "error": "transaction_closed"}
        return tx, None

    def begin(self, tx_id):
        if tx_id in self._transactions:
            return {"status": "error", "error": "duplicate_transaction"}
        self._transactions[tx_id] = {
            "snapshot": self._last_commit,
            "open": True,
            "writes": {},
            "savepoints": [],
        }
        return {"status": "ok", "snapshot": self._last_commit}

    def savepoint(self, tx_id, name):
        tx, error = self._lookup(tx_id)
        if error:
            return error
        if any(saved_name == name for saved_name, _ in tx["savepoints"]):
            return {"status": "error", "error": "duplicate_savepoint"}
        tx["savepoints"].append((name, deepcopy(tx["writes"])))
        return {"status": "ok"}

    def _savepoint_index(self, tx, name):
        for index, (saved_name, _) in enumerate(tx["savepoints"]):
            if saved_name == name:
                return index
        return None

    def rollback_to(self, tx_id, name):
        tx, error = self._lookup(tx_id)
        if error:
            return error
        index = self._savepoint_index(tx, name)
        if index is None:
            return {"status": "error", "error": "unknown_savepoint"}
        tx["writes"] = deepcopy(tx["savepoints"][index][1])
        tx["savepoints"] = tx["savepoints"][: index + 1]
        return {"status": "ok"}

    def release(self, tx_id, name):
        tx, error = self._lookup(tx_id)
        if error:
            return error
        index = self._savepoint_index(tx, name)
        if index is None:
            return {"status": "error", "error": "unknown_savepoint"}
        tx["savepoints"] = tx["savepoints"][:index]
        return {"status": "ok"}

    def put(self, tx_id, key, value):
        tx, error = self._lookup(tx_id)
        if error:
            return error
        tx["writes"][key] = (False, deepcopy(value))
        return {"status": "ok"}

    def _read_raw(self, tx, key):
        if key in tx["writes"]:
            deleted, value = tx["writes"][key]
            return (not deleted), value
        visible = None
        for commit, deleted, value in self._versions.get(key, []):
            if commit <= tx["snapshot"]:
                visible = (deleted, value)
            else:
                break
        if visible is None or visible[0]:
            return False, None
        return True, visible[1]

    def get(self, tx_id, key):
        tx, error = self._lookup(tx_id)
        if error:
            return error
        found, value = self._read_raw(tx, key)
        if not found:
            return {"status": "ok", "found": False}
        return {"status": "ok", "found": True, "value": deepcopy(value)}

    def delete(self, tx_id, key):
        tx, error = self._lookup(tx_id)
        if error:
            return error
        existed, _ = self._read_raw(tx, key)
        tx["writes"][key] = (True, None)
        return {"status": "ok", "existed": existed}

    def scan(self, tx_id, start=None, end=None, limit=None):
        tx, error = self._lookup(tx_id)
        if error:
            return error
        if start is not None and end is not None and start >= end:
            return {"status": "ok", "items": []}
        keys = sorted(set(self._versions) | set(tx["writes"]))
        items = []
        for key in keys:
            if start is not None and key < start:
                continue
            if end is not None and key >= end:
                continue
            found, value = self._read_raw(tx, key)
            if not found:
                continue
            if limit is not None and len(items) >= limit:
                break
            items.append({"key": key, "value": deepcopy(value)})
        return {"status": "ok", "items": items}

    def commit(self, tx_id, commit_seq):
        tx, error = self._lookup(tx_id)
        if error:
            return error
        if (
            isinstance(commit_seq, bool)
            or not isinstance(commit_seq, int)
            or commit_seq <= 0
            or commit_seq <= self._last_commit
        ):
            return {"status": "error", "error": "invalid_commit_sequence"}
        conflicts = []
        for key in tx["writes"]:
            versions = self._versions.get(key, [])
            if versions and versions[-1][0] > tx["snapshot"]:
                conflicts.append(key)
        if conflicts:
            tx["open"] = False
            tx["writes"] = {}
            tx["savepoints"] = []
            return {"status": "conflict", "keys": sorted(conflicts)}
        write_count = len(tx["writes"])
        for key, (deleted, value) in tx["writes"].items():
            self._versions.setdefault(key, []).append(
                (commit_seq, deleted, deepcopy(value))
            )
        tx["open"] = False
        tx["writes"] = {}
        tx["savepoints"] = []
        self._last_commit = commit_seq
        return {
            "status": "committed",
            "commit": commit_seq,
            "writes": write_count,
        }

    def abort(self, tx_id):
        tx, error = self._lookup(tx_id)
        if error:
            return error
        tx["open"] = False
        tx["writes"] = {}
        tx["savepoints"] = []
        return {"status": "aborted"}

    def history(self, key):
        result = []
        for commit, deleted, value in self._versions.get(key, []):
            item = {"commit": commit, "deleted": deleted}
            if not deleted:
                item["value"] = deepcopy(value)
            result.append(item)
        return result

    def collect_garbage(self, before_seq):
        open_snapshots = [
            tx["snapshot"] for tx in self._transactions.values() if tx["open"]
        ]
        safety_boundary = min(open_snapshots) if open_snapshots else self._last_commit + 1
        cutoff = min(before_seq, safety_boundary)
        removed = 0
        for key, versions in self._versions.items():
            below = [version for version in versions if version[0] < cutoff]
            retained = [version for version in versions if version[0] >= cutoff]
            if below:
                retained.insert(0, below[-1])
                removed += len(below) - 1
            self._versions[key] = retained
        return {"status": "ok", "cutoff": cutoff, "removed": removed}
