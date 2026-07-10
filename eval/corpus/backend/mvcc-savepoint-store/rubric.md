# Rubric — MVCC snapshot-isolation store

Score each dimension from **0 to 5**. Correctness is measured by the hidden
suite; this rubric distinguishes implementation quality among similarly
correct submissions.

## 1. Snapshot and transaction semantics

- **5:** Fixed snapshots, read-your-writes, tombstones, lifecycle/error
  precedence, read-only commits, and defensive copies all match the spec.
- **3:** Core snapshots work, with one or two boundary/lifecycle mistakes.
- **1:** Behaves mainly like a mutable current-value map or leaks aliases.
- **0:** The required transaction API is absent or unusable.

## 2. Commit atomicity and conflict correctness

- **5:** Implements final-write-set first-committer-wins exactly, including
  blind writes, tombstones, sorted multi-key conflicts, reusable rejected
  sequences, and legal write skew.
- **3:** Detects common same-key conflicts but mishandles an interaction or
  mutates state on failure.
- **1:** Uses read conflicts/serializable behavior, last-writer-wins, or partial
  commits.
- **0:** Commits cannot reliably preserve isolation.

## 3. Savepoint behavior

- **5:** Nested capture, rollback retention, later-savepoint removal, release
  semantics, name reuse, and deep-copy isolation are all correct.
- **3:** Basic rollback works but nesting or name lifecycle has gaps.
- **1:** Savepoints are shallow snapshots or only track operation counts.
- **0:** Savepoint methods are missing.

## 4. Version GC and history integrity

- **5:** Computes the live-snapshot cutoff, retains exactly one per-key anchor,
  respects the strict boundary/tombstones, reports exact removals, and preserves
  reads/conflicts.
- **3:** Safe in ordinary cases but over-retains or mishandles a boundary.
- **1:** Drops versions needed by live snapshots or treats GC as deleting old
  keys.
- **0:** GC/history is absent or corrupts current state.

## 5. Clarity and maintainability

- **5:** Cohesive data model, small helpers for visibility/copy/lifecycle,
  descriptive naming, and no needless complexity or side effects.
- **3:** Readable overall with some duplication or tangled branching.
- **1:** Hard-coded test behavior, pervasive shared mutation, or opaque control
  flow.
- **0:** Non-deterministic, dependency-heavy, or substantially non-functional.
