# 01 — Philosophy

v2 of the orchestration plugin is a deliberate rewrite. v1 worked, but it
worked by adding ceremony on top of every action. v2 keeps the parts that
earned their place and removes the parts that only existed to defend
against problems the model can already handle.

This document explains the bias. Every other doc in this repo descends
from these principles.

## Why rebuild

v1 grew three categories of accidental complexity:

1. **Receipt theater.** Every Codex call produced a `codex-receipt-step-N.json`
   plus an HMAC sidecar, plus a `claude-review-step-N.md` from a digester
   sub-agent. The conductor never read raw Codex output. In practice the
   receipts encoded the same information Codex already returned in its
   summary; the HMAC protected against tampering by an attacker who, if
   present, could already write to the project.
2. **Forced gates.** A hook intercepted `Edit` and `Write` and refused them
   when no active plan existed. The intent was discipline; the effect was
   friction on every two-line change. Users learned to run `/bypass` as a
   reflex.
3. **Skill sprawl.** Sub-skills for digesting, for minting sidecars, for
   verifying sidecars, for resolving plan paths. Each one made sense in
   isolation; together they buried the actual workflow.

v2 trusts the model more and the infrastructure less.

## What v2 keeps from v1

These three ideas earned their place and carry forward:

1. **Conductor mode.** The main Claude thread orchestrates and dispatches;
   it does not do the heavy reading or writing. The conductor's context is
   a scarce resource and must be protected. See `02-conductor.md`.
2. **Persistent plans on disk.** Plans live as three files under
   `.temp/plan-mode/active/<plan-name>/`: `plan.json` (immutable),
   `progress.json` (mutable), `masterPlan.md` (human-facing). Plans
   survive context compaction because they exist on disk, not in the
   model's memory. See `03-plan-format.md`.
3. **Discipline skills as the behavioral layer.** `engineering-discipline`,
   `systematic-debugging`, `refactoring`, `test-driven-development`,
   `brainstorming`, `writing-plans`. These shape *how* the model works,
   independent of *what* it's working on. See `05-skills-catalog.md`.

We also keep **Orbit review** for `masterPlan.md` before execution
begins, and the **plan-mode handoff** trick (use `EnterPlanMode` →
write a scratchpad to disk → `ExitPlanMode`) so execution starts with a
clean window.

## What v2 drops from v1

These three categories are gone:

1. **Signed-receipt machinery.** No `codex-receipt-step-N.json`, no HMAC
   sidecars, no `claude-review-*.md` siblings, no `lbyl-digest` sub-agent.
   Codex output is bounded by **prompt contract** (a fixed Summary /
   Verdict / Findings shape) and read directly. See
   `06-codex-integration.md`.
2. **Forced-plan enforcement.** No hook intercepts `Edit` / `Write`. The
   only thing pushing the model toward plans is gentle reminders from the
   discipline skills and the `session-start` notice. If the user wants to
   make a one-line change without a plan, nothing stops them.
3. **Heavy hook surface.** v1 had hooks that mutated state, invoked
   Codex, refreshed caches, and gated tools. v2 ships **exactly two**
   hooks and **both are read-only**: `session-start` and `post-compact`.
   They inject context. They do not block, mutate, or call out. See
   `07-hooks.md`.

## v2 design principles

These principles resolve future design questions. When in doubt, pick the
option that aligns with more of them.

1. **Trust the model.** Claude 4.x is competent. If the model can be
   reminded to do the right thing via a skill description, do that instead
   of building a hook to enforce it. Enforcement is for safety-critical
   invariants (no destructive git, no secret commits) — not for habits.
2. **Minimal hooks.** Hooks are the most expensive surface to maintain
   because they fire on every event. v2 ships two, both read-only. Any
   proposal to add a third hook must clear a high bar.
3. **Bounded I/O via prompt contract, not signed artifacts.** A sub-agent
   or Codex call returns at most one structured message in a known shape.
   The conductor parses the shape and trusts it. The bound is enforced by
   the prompt (and by the model's training to follow prompts), not by a
   downstream cryptographic check.
4. **Skill-driven discipline.** Behavior changes are delivered through
   skills, which the model voluntarily invokes when their triggers match.
   This keeps the discipline layer composable and inspectable; it also
   means the user can override it on a per-task basis without fighting a
   hook.
5. **Plans are documents, not enforcement.** `plan.json` is a contract
   the conductor uses to track work. It is not a gate. If the work
   diverges from the plan, the conductor updates `progress.json` with a
   deviation and continues — it does not error out.
6. **One file, one responsibility.** Skills, hooks, and docs each do one
   thing. If a skill description starts saying "and also...", split it.
7. **Resumable by construction.** Anything that can't be reconstructed
   from `plan.json` + `progress.json` after a compaction is a bug. The
   only state that matters lives on disk.

## How to read the rest of this spec

`02-conductor.md` and `03-plan-format.md` are the core. Everything else
falls out of them:

- `04-execution-loop.md` is the runtime that consumes the plan format.
- `05-skills-catalog.md` is the skills the conductor invokes.
- `06-codex-integration.md` is the bounded I/O channel.
- `07-hooks.md` is the (small) glue that keeps the conductor oriented.
- `08-plugin-layout.md` is the target shape for an implementer.
