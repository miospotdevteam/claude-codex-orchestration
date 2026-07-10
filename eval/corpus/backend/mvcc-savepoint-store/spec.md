# MVCC snapshot-isolation store with savepoints and safe version GC

Implement a deterministic in-memory multi-version key/value store. Transactions
read from fixed snapshots, buffer their own writes, may use nested savepoints,
and commit under first-committer-wins snapshot isolation. The store also exposes
version history and a garbage collector that must preserve every open
transaction's answers.

This task is self-contained. It does not require threads, locks, persistence, or
domain-specific database knowledge beyond the rules below.

## Deliverable

Create one file **`mvcc_store.py`** exposing a class **`MVCCStore`**.

## Runtime and inputs

- Python 3, standard library only.
- No I/O, logging, wall-clock reads, randomness, or global mutable state.
- Transaction IDs, commit sequence numbers, and GC boundaries are supplied by
  the caller. Identical call sequences must produce identical results.
- Keys, transaction IDs, and savepoint names are strings.
- Values are JSON-like Python values: `None`, booleans, finite integers/floats, strings,
  lists, and dictionaries whose keys are strings. The required copy semantics
  are stated below.
- `limit` is `None` or a non-negative integer other than a boolean.
  `before_seq` is a non-negative integer other than a boolean. Other arguments
  may be assumed to have the stated type.

## Model and terminology

The store starts empty with `last_commit == 0`.

Each successful commit has a caller-supplied positive integer commit sequence.
Successful commit sequences must be strictly increasing, but need not be
consecutive. Every committed write creates a version tagged with that commit
sequence. A deletion creates a tombstone version.

`begin(tx_id)` fixes that transaction's **snapshot** to the store's current
`last_commit`. A committed version is visible in that snapshot exactly when its
commit sequence is at most the snapshot, and no later visible version of the
same key supersedes it. A visible tombstone means the key is absent.

An open transaction additionally sees its own current buffered writes. Its
buffer overlays its snapshot: a buffered value replaces the snapshot value and
a buffered deletion makes the key absent. Reads never see another
transaction's uncommitted writes.

Transaction IDs are single-use for the lifetime of an `MVCCStore` instance.
A transaction is **closed** after a successful commit, an explicit abort, or a
conflict result. An invalid commit sequence does not close it.

All error returns in this specification are ordinary dictionaries; methods
must not raise for the specified error cases.

## API

### `begin(tx_id)`

Starts a transaction.

- Success: `{"status": "ok", "snapshot": <current last_commit>}`.
- If this ID has ever been used, even by a now-closed transaction:
  `{"status": "error", "error": "duplicate_transaction"}`.

### `get(tx_id, key)`

Reads through the transaction's own-write overlay and fixed snapshot.

- Present: `{"status": "ok", "found": True, "value": <value>}`.
- Absent or deleted: `{"status": "ok", "found": False}`. This shape has no
  `value` field.
- Transaction lookup errors use the precedence and shapes in
  [Transaction lookup errors](#transaction-lookup-errors).

### `put(tx_id, key, value)`

Buffers a value write, replacing any earlier buffered operation for that key.
The value must be deep-copied when this method is called.

- Success: `{"status": "ok"}`.
- Transaction lookup errors apply.

### `delete(tx_id, key)`

Buffers a tombstone, replacing any earlier buffered operation for that key.
`existed` reports whether the key was present in this transaction's current
view immediately before this delete.

- Success: `{"status": "ok", "existed": <bool>}`.

Deleting an absent key still buffers a write intent. It therefore counts as a
write at commit and participates in write/write conflict detection. Repeating
`delete` on the same key returns `existed: False` the second time.

### `scan(tx_id, start=None, end=None, limit=None)`

Returns the transaction's current visible key/value pairs after applying its
own-write overlay.

- Success: `{"status": "ok", "items": [{"key": <key>, "value": <value>}, ...]}`.
- Keys are in ascending Python string order.
- The range is `start <= key < end`. `None` means unbounded on that side.
- If `start >= end` when both are non-`None`, the result is empty.
- Apply the range and remove tombstones before applying `limit`.
- `limit == 0` returns an empty list; `limit is None` returns all matches.
- Scans are ordinary snapshot reads. They create no predicate/range locks, so a
  concurrent insertion into a scanned range does not itself cause a conflict.
- Transaction lookup errors apply.

### `savepoint(tx_id, name)`

Creates a named savepoint capturing the transaction's entire current write
buffer. Savepoints are ordered by creation and may be nested.

- Success: `{"status": "ok"}`.
- If `name` is already an active savepoint in this transaction:
  `{"status": "error", "error": "duplicate_savepoint"}`.
- Transaction lookup errors take precedence over savepoint errors.

### `rollback_to(tx_id, name)`

Restores the write buffer captured by `name`. The named savepoint remains
active; every savepoint created after it is removed. Reads performed after the
savepoint have no special effect and need no rollback.

- Success: `{"status": "ok"}`.
- If `name` is not active: `{"status": "error", "error": "unknown_savepoint"}`.
- Transaction lookup errors take precedence.

Rolling back removes discarded keys from the transaction's final write set;
those discarded writes neither create versions nor cause conflicts.

### `release(tx_id, name)`

Keeps all buffered writes unchanged, but removes `name` **and every savepoint
created after it**. This is deliberately different from `rollback_to`, which
keeps its named savepoint.

- Success: `{"status": "ok"}`.
- If `name` is not active: `{"status": "error", "error": "unknown_savepoint"}`.
- Transaction lookup errors take precedence.

A removed name may be used for a new savepoint later in the same open
transaction.

### `commit(tx_id, commit_seq)`

Attempts to atomically commit the transaction's **final buffered write set**.

Validation and conflict checks occur in this exact order:

1. Transaction lookup errors.
2. `commit_seq` must be an integer but not a boolean, must be positive, and
   must be strictly greater than `last_commit`. Otherwise return
   `{"status": "error", "error": "invalid_commit_sequence"}` and leave the
   transaction open and unchanged.
3. For every key in the final write set, find its latest committed version. A
   key conflicts exactly when that version's commit sequence is greater than
   the transaction's snapshot. Tombstones participate like values. Reads and
   scans never participate in this check.

If one or more keys conflict:

- Return `{"status": "conflict", "keys": [<key>, ...]}` with every
  conflicting key once in ascending string order.
- Close the transaction and discard all its buffered writes/savepoints.
- Do not create any version and do not advance `last_commit`; the rejected
  `commit_seq` may therefore be reused by another open transaction.

If there is no conflict:

- Atomically create one version per key in the final write set, all tagged with
  `commit_seq`, and close the transaction.
- Advance `last_commit` to `commit_seq`, including for a read-only commit.
- Return `{"status": "committed", "commit": <commit_seq>, "writes": <number
  of distinct keys in the final write set>}`.

Multiple `put`/`delete` calls for one key produce at most one version at commit.
A blind write is checked exactly like a write preceded by a read.

This is snapshot isolation, not serializability: two transactions that read
the same keys but write disjoint keys may both commit. Write skew and scan
phantoms are therefore allowed.

### `abort(tx_id)`

Closes an open transaction and discards its writes/savepoints.

- Success: `{"status": "aborted"}`.
- Transaction lookup errors apply.

### `history(key)`

Returns the physically retained committed versions for `key` in ascending
commit order. Uncommitted writes never appear.

- Value version: `{"commit": <seq>, "deleted": False, "value": <value>}`.
- Tombstone: `{"commit": <seq>, "deleted": True}` (no `value` field).

The return value is a list. An unknown key returns `[]`. Garbage collection may
remove old entries as specified next.

### `collect_garbage(before_seq)`

Compacts physical version history without changing any logical `get` or `scan`
answer available to an open transaction or to a transaction begun later.

Compute the effective `cutoff` as follows:

- If at least one transaction is open, let `oldest` be the minimum snapshot of
  all open transactions and set `cutoff = min(before_seq, oldest)`.
- If no transaction is open, set `cutoff = min(before_seq, last_commit + 1)`.

For each key independently, consider versions whose commit is **strictly less
than** `cutoff`:

- Retain the greatest such version as that key's anchor, even if it is a
  tombstone.
- Remove every other version strictly below `cutoff`.
- Retain every version whose commit is equal to or greater than `cutoff`.

Return `{"status": "ok", "cutoff": <effective cutoff>, "removed": <total
number of versions removed across all keys>}`.

Consequences worth noting:

- A version exactly at `cutoff` is not below it and is retained.
- The anchor may be older than the oldest open snapshot; it is the version that
  transaction still needs when no newer version is visible to it.
- Open transactions with no writes still constrain GC.
- Closed transactions do not constrain GC.
- Repeating a collection is idempotent once no additional version is eligible.
- GC does not change `last_commit`, transaction state, conflict rules, or the
  current logical contents.

## Transaction lookup errors

For `get`, `put`, `delete`, `scan`, `savepoint`, `rollback_to`, `release`,
`commit`, and `abort`, check transaction identity/state before method-specific
validation:

- An ID never passed successfully to `begin`:
  `{"status": "error", "error": "unknown_transaction"}`.
- A previously begun but now-closed transaction:
  `{"status": "error", "error": "transaction_closed"}`.

## Isolation, copying, and atomicity invariants

- Deep-copy a value on `put`, and deep-copy values returned by `get`, `scan`,
  and `history`. Mutating caller input or any returned object must never mutate
  stored state, buffered state, snapshots, savepoints, or later results.
- Savepoints capture values as they existed when the savepoint was created;
  later caller mutations and later buffered writes cannot alter the capture.
- A conflicting commit is all-or-nothing even when only some keys conflict.
- Transactions, versions, and savepoints are per `MVCCStore` instance. No
  state may leak between instances.
