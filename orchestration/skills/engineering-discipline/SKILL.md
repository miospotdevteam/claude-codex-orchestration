---
name: engineering-discipline
description: The behavioral baseline for any code change. Read imports and consumers before editing shared types or utilities, track blast radius, refuse `any` / `as any` / silent type assertions, and run type-check + lint + tests after every change. Use whenever you write, edit, refactor, port, migrate, or debug code — any language, any framework, any file count. Bug fixes (even one-line), dependency bumps, config changes, and CI fixes all count. Do NOT use for pure questions, code reading without edits, documentation-only tasks, or conversations that don't touch source files.
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# engineering-discipline

The discipline layer every other coding skill rests on. This is not a
workflow or a checklist — it is the set of habits that keep a change
from breaking builds, missing consumers, or silently shrinking its own
scope.

## When this fires

Any time the conductor (or a sub-agent acting on its behalf) is about
to modify a source file. That includes:

- Bug fixes (even one-line).
- Feature additions and refactors.
- Dependency bumps, config edits, CI tweaks.
- Migration scripts and one-off shell commands that touch the tree.

It does **not** fire for:

- Pure questions, explanations, or code reading.
- Documentation-only tasks where no source file changes.
- Conversations that produce no edits.

## The five habits

Each habit is a question to answer **before** the edit lands. If you
can't answer it, don't make the edit yet.

### 1. Read imports and consumers first

Before editing a shared type, exported function, or utility:

- Open the file, read the export list.
- Grep for consumers (the file's imports going the other way).
- For non-trivial blast radius, hand off the sweep to an `Explore`
  sub-agent and read its bounded summary.

The smaller the change feels, the more important this step is. The
classic regression is "I just renamed a field" landing on a callsite
that was indexed by string elsewhere.

### 2. Track the blast radius

Before each edit, name in one sentence what else might break:

- Same-module callers.
- Other modules that import the symbol.
- Tests (unit, integration, snapshot) that reference the name.
- Generated code, schema files, OpenAPI specs, GraphQL SDL.
- Type defs in `.d.ts` files or other re-exports.

If the answer is "I don't know," push the discovery down to an
`Explore` sub-agent before continuing.

### 3. No type shortcuts

`any`, `as any`, `// @ts-ignore`, and `// @ts-expect-error` are
banned unless every one of these is true:

- The constraint is genuinely outside the type system (e.g. a JSON
  blob from an untyped third party).
- The shortcut is paired with a runtime check that recovers the type.
- A short comment names the constraint.

The equivalents in other languages — `Object`-typed parameters in
Java, `interface{}` in Go, `**kwargs` in Python without `TypedDict`,
unchecked `unwrap()` chains in Rust — get the same treatment.

### 4. Verify after every change

Run the project's checks. Don't batch them to "the end" — batched
verification hides which edit caused the break:

- Type-check (`tsc --noEmit`, `mypy`, `cargo check`, equivalents).
- Lint (`eslint`, `ruff`, `clippy`).
- Tests (at least the suite covering the touched files; full suite
  before declaring done).

If a check is unavailable in this environment or genuinely doesn't
exist for this project, say so out loud. **Don't claim "tests pass"
when you didn't run them.** Honest "I couldn't run X because Y" beats
silent omission every time.

### 5. No silent scope cuts

A task that started as "fix the auth bug and update the docs" doesn't
quietly become "fix the auth bug." If a piece of the requested work
is dropped:

- Flag it in your reply: "I did A, deferred B because of C — okay to
  move on?"
- Update `progress.json` with a deviation if a plan is active.
- Do not finish a step by quietly redefining what "done" meant.

The opposite failure is also a discipline lapse: silently widening
scope ("while I was in here I refactored…"). If a needed cleanup
falls outside the step, flag it and propose a follow-up step.

## What this skill is not

- It is **not** a hook or a gate. By design, discipline in v2 lives in
  skills, not in tool interceptors. The user can take a shortcut at any
  moment; this skill just makes the shortcut a conscious choice rather
  than an unconscious one.
- It is **not** a substitute for `test-driven-development` or
  `refactoring`. Those are workflows with their own structure; this
  skill is the floor that runs underneath them.

## Interaction with other skills

- `test-driven-development` adds a red-green-refactor rhythm on top
  of habit 4 ("verify after every change") — the test is the
  verification, written first.
- `refactoring` adds a contract-based staged approach to a multi-file
  change; this skill ensures every stage compiles and passes checks.
- `systematic-debugging` replaces "guess-and-check" with a four-phase
  investigation; the verification step at the end is this skill's
  habit 4.
- `writing-plans` encodes habits 4 and 5 into each step's
  `acceptanceCriteria` and `progress[]` checklist.
- `codex-dispatch` injects this skill's name into every Codex
  IMPLEMENT prompt so the executor honors it even when running
  out-of-thread.

## Failure surface

The common slips this skill exists to catch:

- "I just renamed it, no consumers" — and the rename misses three
  string-keyed callsites.
- "The fix is one line" — but the one line changes a function
  signature used by 40 modules.
- `as any` to silence a stubborn type error — and the runtime
  surface drifts from the type system forever.
- "Tests will pass, I'll skip running them" — and they don't.
- "I'll come back to the documentation update" — and the doc rots.

Each of these is a discipline failure, not a tooling failure. The
remedy is to read this skill, not to add a hook.
