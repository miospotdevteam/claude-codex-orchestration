---
name: refactoring
description: Multi-file restructuring — renaming across files, moving or splitting modules, extracting shared helpers, consolidating duplicates. Use whenever a change spans more than one file or rearranges code without altering behavior. Triggers include "refactor X", "extract Y", "move Z into …", or any rename that crosses file boundaries. Do NOT use for single-variable renames within one function, formatting-only changes, adding new features (use `writing-plans`), or bug fixes (use `systematic-debugging`).
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# refactoring

A refactor changes the shape of the code without changing what it
does. The bar is higher than a bug fix because every callsite must
keep working through every intermediate state, not just the final one.

## When this fires

- Renames that span more than one file.
- Moving or splitting modules.
- Extracting duplicated logic into a shared helper.
- Restructuring directory layout.
- Consolidating naming conventions across the tree.

It does **not** fire for:

- Single-variable renames within one function.
- Formatting-only changes.
- Adding new features — use `writing-plans` instead.
- Fixing a bug — use `systematic-debugging`.

## The four-phase pattern

### Phase 1 — Discover consumers

Before touching anything, identify every place the code under refactor
is used:

- Direct imports of the symbol(s) being moved.
- String-keyed references (DI containers, route registries, plugin
  manifests).
- Tests, snapshots, fixtures.
- Type re-exports (`.d.ts`, barrel files).
- Generated code (codegen output, OpenAPI specs, GraphQL SDL).

For anything beyond ~3 files, dispatch the sweep to an `Explore`
sub-agent. The conductor's read budget is too small for an open-ended
grep across the tree.

The exit criterion: you can name every consumer. If you can't, you're
not done with phase 1.

### Phase 2 — Plan the stages

A refactor that lands in one giant commit always has a window where
the code doesn't compile. Plan stages such that the **codebase
compiles and tests pass between every stage**:

- Stage A: introduce the new shape alongside the old (additive).
- Stage B: migrate consumers one batch at a time.
- Stage C: remove the old shape once nothing references it.

Stages map naturally to plan steps in `writing-plans`. Each step has
its own `acceptanceCriteria` and verifier pass.

### Phase 3 — Execute keeping green

For each stage:

1. Make the change.
2. Run type-check, lint, the test suite covering the touched files.
3. Resolve any breakage **before** moving to the next stage.
4. Commit (or save a checkpoint in `progress.json`).

If a stage's blast radius is wider than expected, split it into two
smaller stages rather than pushing through. The `engineering-discipline`
skill's "no silent scope cuts" rule applies.

### Phase 4 — Final verify

After the last stage:

- Full test suite (not just the touched-files subset).
- Type-check + lint clean.
- Grep for any stranded references to the old shape (old names,
  removed paths, comments referencing the dead structure).
- Update docs and code comments that referenced the old shape.

## Interaction with other skills

- `engineering-discipline` — the floor. Habit 1 (read consumers first)
  expands into this skill's phase 1; habit 4 (verify after every
  change) runs at every stage boundary.
- `writing-plans` — stages become plan steps. A refactor that fits in
  one plan is fine; a refactor that needs ten stages should be split
  into multiple plans.
- `systematic-debugging` — if a stage's verifier returns FAIL, this is
  a bug in the refactor approach. Hand off to systematic-debugging
  rather than retrying blindly.
- `codex-dispatch` — Codex implements each stage; the conductor reads
  only the contract block.

## Failure modes

- **Skipped consumer discovery** — the classic refactor regression.
  Some consumer indexed the symbol by string and nothing caught it
  until production. Fix: dispatch `Explore` even when "it seems
  obvious".
- **Big-bang stage** — too much change in one stage; verifier returns
  FAIL with five unrelated errors and you can't tell which one
  matters. Fix: split.
- **Old shape lingers** — a partial migration leaves both shapes
  alive, callers split, no single source of truth. Fix: never finish
  the refactor without phase 4's grep for stranded references.

## What this skill does not own

- It does not write tests for new behavior — refactors are behavior-
  preserving by definition. Tests that fail because of behavior change
  are bugs in the refactor, not features.
- It does not decide the target shape — that's a design question
  handled by `brainstorming` before this skill fires.
- It does not bypass `engineering-discipline` — even a "trivial"
  rename across files runs the discipline habits.
