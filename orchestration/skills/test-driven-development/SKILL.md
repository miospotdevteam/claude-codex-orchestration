---
name: test-driven-development
description: Red-green-refactor rhythm for new behavior. Write a failing test, watch it fail for the right reason, implement the smallest change that turns it green, then refactor. Use when writing a new feature or function with testable behavior, when the user says "let's TDD this", or when a plan step's progress[] starts with "Write failing tests". Requires existing test infrastructure in the project. Do NOT use for fixing bugs in already-tested code (use `systematic-debugging`), characterization tests for legacy untested code (different workflow), refactoring without behavior change (use `refactoring`), or projects with no test runner.
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# test-driven-development

The discipline of writing the test first. Used right, TDD shapes the
design of the code being added — every public symbol has a caller (the
test) before it has an implementation, so the API is exercised by
intent rather than by accident.

## When this fires

- Adding a new feature or function with testable behavior.
- The user says "let's TDD this" / "test first" / "write the test
  before the implementation".
- A plan step's `progress[]` array starts with "Write failing
  tests…" — `writing-plans` encodes the rhythm there.
- A new pure function, parser, transformer, or any logic with clear
  inputs and outputs.

It does **not** fire for:

- Fixing a bug in already-tested code — `systematic-debugging` is
  the workflow.
- Writing characterization tests for legacy untested code — that's
  a different workflow (pin existing behavior first, no design
  feedback loop).
- Refactoring without behavior change — `refactoring`.
- Projects with no test infrastructure — suggest adding it first.
  TDD without a fast feedback loop is just slower coding.

## The red-green-refactor cycle

### Red — write a failing test

- One behavior per test, named for the behavior ("returns null on
  tampered cookies", not "test1").
- Run the test. **Verify it fails for the right reason** — the
  failure message should mention the absence of the not-yet-built
  thing, not a syntax error or an import error. If the test fails for
  the wrong reason, the test itself is broken.
- Commit (or save a checkpoint) before moving on. A clean failing
  test is a known good state.

### Green — make it pass with the smallest change

- Implement the minimum needed to flip red to green.
- Resist gold-plating. The next test will force the next behavior.
- Re-run the test. It should now pass. If it doesn't, the issue is in
  the implementation, not the test.

### Refactor — clean up with the test as safety net

- With the test green, restructure the implementation: rename for
  clarity, extract helpers, eliminate duplication.
- Re-run the test after every restructure. If it goes red, undo the
  last change.
- Stop refactoring when the code is clean enough. Refactoring is not
  the next feature.

## What "the right reason" means

A failing test can fail in many ways. Only one of them is useful:

| Failure mode | TDD-useful? |
|---|---|
| Assertion fails — "expected X, got Y" | Yes |
| Symbol not defined / import error | **No** — fix the test scaffold first |
| Compilation error in test file | **No** — the test isn't running yet |
| Throws unexpected exception | Sometimes — only if the exception is the behavior under test |
| Times out / hangs | **No** — the test is broken |
| Passes accidentally on first run | **No** — the test isn't testing anything |

A test that passes on the first run before any implementation is
written is the worst case: it gives false confidence and locks in
nothing. Re-read it; the assertion is probably trivially true.

## Encoding TDD into a plan step

When `writing-plans` produces a step with `skill:
test-driven-development`, the `progress[]` checklist encodes the
rhythm:

```
"progress": [
  "Write failing test for <behavior 1>",
  "Run; verify it fails with the expected message",
  "Implement minimum to pass",
  "Run; verify green",
  "Refactor if needed",
  "Write failing test for <behavior 2>",
  "...",
  "Run full test suite; type-check and lint pass",
  "Commit"
]
```

The conductor (or Codex via `run-codex-impl.sh`) walks the checklist
in order. Skipping ahead — implementing before the test — is the
silent scope cut this skill exists to prevent.

## Interaction with other skills

- `engineering-discipline` — habit 4 ("verify after every change") is
  the test run. Habit 5 ("no silent scope cuts") catches "I'll write
  the test later" before it ships.
- `writing-plans` — emits TDD steps when the work is new behavior in
  a tested project.
- `systematic-debugging` — when a verifier returns FAIL on a TDD
  step, that's a bug in the implementation, not the test. Hand off
  there.
- `refactoring` — the refactor phase of red-green-refactor invokes
  the same discipline (small stages, test-green between each).

## Failure surface

- **Test-after coding** — "I'll write the test once the
  implementation is done." The implementation drives the test
  instead of the test driving the implementation. The result is a
  test that mirrors the code rather than the behavior.
- **Over-broad tests** — one giant test asserting six behaviors. When
  it fails you can't tell which behavior broke. Split.
- **Mocking everything** — the test runs but exercises mocks, not
  code. If the test passes with the implementation deleted, the test
  isn't testing the implementation.
- **Refactor that breaks the test** — and then you "fix" the test.
  No. Undo the refactor and try a smaller change.
