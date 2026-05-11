---
name: systematic-debugging
description: Four-phase debugging — investigate, identify pattern, form hypotheses, fix — to prevent guess-and-check thrashing. Use whenever a bug is reported, a test fails unexpectedly, a verifier returns FAIL, or the user says "this doesn't work" / "X is broken" / "fix the bug where …". The discipline is: never change code before you can name the root cause. Do NOT use for learning a new API (that's exploration), refactoring for clarity (use `refactoring`), performance optimization without a concrete regression, or new-feature work (use `test-driven-development` / `writing-plans`).
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Agent
---

# systematic-debugging

The discipline that replaces "let me try this" with "let me find out
why this is happening". Most debugging time is spent trying random
fixes against an unidentified root cause. The four phases below front-
load the investigation so the fix lands once.

## When this fires

- A bug is reported with a concrete symptom.
- A test fails unexpectedly during execution.
- A `run-codex-verify.sh` call returns `Verdict: FAIL`.
- The user says "this doesn't work", "X is broken", "Y stopped
  working", "fix the bug where …".

It does **not** fire for:

- Learning a new API — that's exploration, not debugging.
- Refactoring for clarity — use `refactoring`.
- Performance optimization without a regression to investigate.
- Building new behavior — use `test-driven-development`.

## Phase 1 — Investigate

Goal: a minimal reproduction. You can't fix what you can't reproduce.

- Get the exact failing input. "It crashes sometimes" → "it crashes
  when the user payload includes a unicode null byte in the email
  field".
- Narrow the input. Strip everything that doesn't change the
  behavior. The smaller the repro, the more it tells you.
- Identify the smallest failing case: shortest input, fewest steps,
  least state.
- For wide investigations (which file? which module? which version?),
  dispatch an `Explore` sub-agent. The conductor's read budget should
  not be spent on grep sweeps.

Exit when you can say: "Running X produces Y. Expected Z."

## Phase 2 — Identify the pattern

Goal: connect the symptom to a code path. Without this step you'll
fix something adjacent to the bug instead of the bug itself.

- Trace the failing input through the code from entry point to
  symptom.
- At each step, ask: is the data what I expect here? Is the state
  what I expect here?
- Note the place where the answer flips from "yes" to "no". That is
  the pattern boundary; the root cause is on or near that line.

If the trace requires reading many files, hand the trace request to a
sub-agent ("trace the path of `req.body.email` through `src/api/auth/*`
and report where the value first diverges from expected").

## Phase 3 — Form hypotheses

Goal: a ranked list of candidate root causes.

- List every plausible explanation for the pattern observed in phase
  2, even ones that seem unlikely. Three to five is typical.
- For each, predict what the code would have to look like for that
  hypothesis to be true.
- Read those locations. Confirm or eliminate each hypothesis. Most
  fall on first inspection; the survivor is the root cause.

If two hypotheses survive inspection, design a quick experiment that
discriminates between them (a print, a temporary assertion, a
targeted unit test). Run it. Eliminate one.

Do **not** start editing yet. The fix comes after the root cause is
named.

## Phase 4 — Fix

Goal: a minimal change that addresses the root cause, with a
regression test that would have caught the bug.

- Write a failing test that reproduces the bug (Phase 1's minimal
  repro becomes the test).
- Make the smallest code change that turns the test green.
- Run the full test suite. The new test passes; no others regress.
- Re-run lint and type-check.
- Update `progress.json` with what was fixed and why; record any
  related code paths you noticed that need follow-up as deviations.

If the fix is bigger than ~3 files, consider whether the bug is a
symptom of a design issue. A small bug fix in many places often
points at an abstraction that should change. Surface that observation
to the user; don't expand scope silently.

## Interaction with other skills

- `engineering-discipline` — the floor. Habit 1 (read consumers
  first) applies to the fix; habit 4 (verify after every change)
  applies to the regression test.
- `test-driven-development` — phase 4 writes the failing test first;
  same red-green-refactor cadence.
- `refactoring` — if the root cause is structural, the fix may
  trigger a follow-up refactor. Keep them as separate steps;
  refactoring while debugging hides which change fixed the bug.
- `writing-plans` — for non-trivial fixes, write a small plan first
  rather than landing the fix freehand.

## Anti-patterns

- **Guess-and-check.** Edit, run, edit again, run again. After three
  rounds, stop and go back to phase 1. The bug is not where you
  think it is.
- **Fix the symptom, not the cause.** Patching the place where the
  bad value lands instead of where it originates. The next caller
  hits the same bug.
- **Silence the messenger.** Disabling the failing test, catching and
  swallowing the exception, lowering the assertion threshold. These
  hide the bug; they don't fix it.
- **Scope creep into "while I'm in here".** Note the side observation
  as a deviation or a follow-up step; don't expand the bug fix into
  a refactor.

## Failure handling

- **Can't reproduce** — investigation isn't done. Don't move to phase
  3. Ask the user for more details, or instrument the failing path
  with logging and wait.
- **Two hypotheses both survive** — design the discriminating
  experiment. Don't pick one by gut feel.
- **Fix doesn't stick** (regression returns) — the root cause was
  not what you thought. Restart at phase 2 with the new evidence.
- **`run-codex-verify.sh` returns FAIL after the fix** — the
  verifier saw something you didn't. Read its `findings` and treat
  them as new evidence; don't argue with the verdict.
