# 04 — Execution loop

The orchestration plugin runs every non-trivial task through four
phases: **Discovery → Plan → Execute → Verify**. Each phase has a
well-defined input, a well-defined output, and a clear handoff.

This document specifies the runtime: how the conductor moves through
the phases, how parallel work is dispatched, and how a session
resumes after compaction.

See `02-conductor.md` for the dispatch rules, `03-plan-format.md` for
the plan/progress schemas, `06-codex-integration.md` for the Codex lane,
`10-grok-integration.md` for the Grok lane, and `09-routing-matrix.md`
for cross-family verification policy.

## Phase 1 — Discovery

**Input**: the user's request.

**Output**: a discovery document (`docs/discovery/<topic>.md` or an
in-conversation summary) capturing:

- The actual problem (sometimes different from the user's wording)
- Relevant files, modules, and consumers
- Blast radius (what changes when X changes)
- Open questions and assumptions
- Constraints (deps that can't change, public APIs to preserve)

**Who does the reading**: not the conductor. Discovery is the most
read-heavy phase. The conductor dispatches `Explore` sub-agents in
parallel for distinct questions ("where is auth implemented?",
"which routes use the session middleware?", "what tests cover
cookies?") and collects their bounded summaries.

For ambiguous problems, the conductor may also invoke the
`brainstorming` skill (see `05-skills-catalog.md`) to shape the
problem before sub-agents are dispatched.

**Exit criterion**: enough information to draft a plan. If the
conductor cannot answer "what files will change?" and "what should
break if I get this wrong?", discovery is not done.

## Phase 2 — Plan

**Input**: the discovery output.

**Output**: the three plan files (`plan.json`, `progress.json`,
`masterPlan.md`) in `.temp/plan-mode/active/<planId>/`.

**Who drafts**: the conductor, with the `writing-plans` skill. The
skill enforces TDD-granularity steps (one component / one behavior
per step), explicit `dependsOn` for the DAG, and the `progress[]`
checklist on each step.

**Approval**: `masterPlan.md` goes through Orbit review (or
conversational approval if Orbit is unavailable). On approval,
`plan.json.frozen` flips to `true` and `progress.json` is initialized
with every step set to `pending`.

The **plan-mode handoff** trick is critical here: planning often
fills the conductor's context with discovery details. To enter the
execution phase with a clean window:

1. The conductor enters plan mode (`EnterPlanMode`).
2. Inside plan mode it writes the three plan files to disk.
3. It exits plan mode (`ExitPlanMode`).
4. The harness compacts; the next turn starts with a small context.
5. The `post-compact` hook re-injects the active plan path and
   current frontier (see `07-hooks.md`).
6. Execution begins from a clean slate, reading only `plan.json`
   and `progress.json`.

**Exit criterion**: `plan.json.frozen == true` and `progress.json`
exists.

## Phase 3 — Execute

**Input**: the approved plan and the current `progress.json`.

**Output**: one or more steps in `progress.json` flipped from
`pending` → `in_progress` → `done` (or `blocked`).

### The runnable-frontier algorithm

At any moment, define:

```
runnable(plan, progress) =
    { step ∈ plan.steps
      | progress.steps[step.id].status == pending
      ∧ ∀ dep ∈ step.dependsOn: progress.steps[dep].status == done }
```

This is the **frontier**. The conductor:

1. Computes `runnable(plan, progress)` after every step completes.
2. Updates `progress.currentFrontier`.
3. Dispatches every step in the frontier **in parallel** by default.
4. Marks each as `in_progress` before dispatch and `done` after the
   verifier returns PASS (fixing and re-verifying any FAIL/FINDINGS
   first, per the policy below).

Parallel dispatch uses the harness's ability to call multiple `Agent`
or wrapper scripts in one assistant message. The conductor sends one
message containing N tool calls — one per frontier step — and the
harness runs them concurrently.

### Size-1 frontier: serial execution

If `|runnable| == 1`, the conductor dispatches the single step,
awaits the verdict, updates `progress.json`, recomputes the frontier,
and continues. No parallelism overhead.

### Larger frontier: parallel dispatch

If `|runnable| > 1`, all runnable steps are dispatched together.
This is the common case when steps are independent (e.g., updating
three unrelated modules).

Constraints:

- **File overlap guard.** If two runnable steps declare overlapping
  `files`, the conductor warns and serializes them. Overlapping
  edits by concurrent agents are a correctness hazard; the cost of
  one extra round trip is cheap insurance.
- **Resource limits.** The conductor caps parallel dispatch at a
  small number (default 4) to keep the harness responsive and the
  user's mental model legible.

### Per-step execution

For each dispatched step, the conductor chooses the executor based
on `step.owner`:

- **`codex-impl`** (default) → invoke `run-codex-impl.sh` with the
  step description and acceptance criteria. The wrapper returns a
  Summary / Verdict / Findings block (see `06-codex-integration.md`).
- **`claude-impl`** → dispatch a `general-purpose` sub-agent to
  implement; then dispatch verification per `09-routing-matrix.md`.
- **`grok-impl`** → invoke `run-grok-impl.sh` with the step description
  and acceptance criteria. See `10-grok-integration.md`; verification
  follows `09-routing-matrix.md`.
- **`manual`** → flip `progress` to `blocked` with a note for the
  user, and continue with the rest of the frontier.

The executor honors `step.skill` if set, invoking that skill at the
top of its prompt.

### Updating progress

After every step transition the conductor:

1. Writes `progress.json` to disk **before** dispatching the next
   frontier. The disk write is the durability boundary.
2. Records the verdict, findings, files touched, and any
   deviations.
3. Recomputes the frontier and continues.

If a step's verdict is `FAIL` or `FINDINGS`, the conductor fixes the
findings and re-verifies. The loop is: dispatch → verify → if not
PASS, fix + re-verify → repeat until PASS. It does **not** mark the
step `done` with findings, and does **not** defer them to a follow-up
step. The conductor surfaces one-line progress to the user between
iterations, but pauses to ask how to proceed only after three
non-converging iterations or when a finding raises a genuine design
question that needs the user's judgment.

## Phase 4 — Verify

Verification is woven into Phase 3 — every step is verified according
to the cross-family policy in `09-routing-matrix.md` as part of its
dispatch — but there is also a **final verify** at the end:

**Input**: `progress.json` with every step `done` or accounted for.

**Output**: a closing summary to the user, plus the plan moved from
`active/` to `archive/`.

The conductor:

1. Confirms every step is `done` / `skipped` / `blocked` and that the
   user has acknowledged the latter two.
2. Runs project-level checks if defined (type-check, lint, test
   suite). These are run via the applicable verifier wrapper from
   `09-routing-matrix.md` or directly by the conductor for short
   scripts.
3. Reports back: what changed, what's flagged, what's outstanding.
4. Moves the plan directory to `archive/`.

## Resumption protocol (after compaction)

The most failure-prone moment in v1 was the resumption after a
context compaction. v2 makes resumption a first-class case.

When the conductor wakes into a fresh context window:

1. **Trust nothing in memory.** Anything not on disk is gone.
2. **Read the `post-compact` notice** (if present) — it points at the
   active plan path and current frontier. See `07-hooks.md`.
3. **Read `plan.json`** (immutable, full read OK — small).
4. **Read `progress.json`** (mutable, full read OK — small).
5. **Recreate the TaskList** from the plan: one `TaskCreate` per
   step, with status mirrored from `progress.json`.
6. **Compute the frontier** using the runnable-frontier algorithm.
7. **Resume** by dispatching the frontier as in Phase 3.

No code is re-read, no exploration is re-run, no external-wrapper
output from prior steps is re-fetched. Everything needed to continue is
in the three plan files.

If the `post-compact` hook is missing or the user invoked the session
fresh, the conductor falls back to scanning
`.temp/plan-mode/active/` and picking the most recently updated
plan, then warns the user before proceeding.

## When to skip the loop

Not every task earns a plan. Trivial changes — a typo fix, a one-line
config tweak, a short shell command, an explanatory answer — go
straight to action. The signal is: if writing `plan.json` would take
longer than doing the work, skip the loop.

This is the **gentle reminder** model from `01-philosophy.md`. The
discipline skills nudge the conductor toward a plan for non-trivial
work; nothing prevents the conductor from skipping the loop when
skipping is the right call.

## Failure handling

- **Transient provider capacity or overload** → keep the step
  `in_progress`, announce the pause, wait 10 minutes, and repeat the
  identical dispatch on the same model and provider. Permit at most two
  delayed retries (three attempts total). After exhaustion, use an
  already-defined lane fallback; if none exists, mark the step `blocked`
  and surface the capacity failure. Do not apply this loop to auth or
  configuration errors, missing binaries, invalid invocations, or
  malformed contracts.
- **External wrapper unreachable** → step is `blocked` with a
  lane-specific unavailable reason. Conductor surfaces to user.
- **Verifier does not converge** → FAIL/FINDINGS drives the
  fix-and-re-verify loop, not a `blocked` state. Only after three
  non-converging iterations (or a finding that needs a design
  decision) does the conductor pause and ask the user how to proceed.
  This is distinct from the transport-level retry-once rule for an
  unreachable wrapper or a missing contract block.
- **Plan invariant violated** (cyclic deps, missing dep ID) → this is
  a `writing-plans` bug; the conductor reports it and refuses to
  execute the plan.
- **Progress and plan disagree** → the conductor trusts
  `progress.json` for state and `plan.json` for definition. If a
  `progress.json` entry references a step ID not in `plan.json`,
  surface as a bug.
