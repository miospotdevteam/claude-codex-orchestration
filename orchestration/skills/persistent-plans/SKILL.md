---
name: persistent-plans
description: Plan files on disk are the source of truth — not context memory. Use whenever you start non-trivial coding work, resume after a context compaction, or the user says "continue" / "where were we". Locates the active plan dir under `.temp/plan-mode/active/<planId>/`, reads `plan.json` (immutable) and `progress.json` (mutable), mirrors progress into a TaskList, and applies the resumption protocol from docs/04-execution-loop.md. Do NOT use for pure read-only questions, conversations that don't touch code, or tasks the user has explicitly tagged "just do it" / "no plan".
allowed-tools: Read, Edit, Write, Bash, Glob
---

# persistent-plans

The infrastructure skill that owns the plan files on disk and the
resumption protocol. v2's central durability claim is that **anything
not on disk after a compaction is gone**. This skill is the contract
that makes that claim hold.

## When this fires

- About to start a non-trivial task (create a plan).
- Resuming after a harness compaction (read the active plan).
- The user asks "continue", "where were we", "what's the status".
- The `session-start` or `post-compact` hook announced an active plan.

It does **not** fire for:

- Pure questions, code reading without edits.
- Tasks the user has tagged "no plan" / "just do it".
- Trivial one-line edits where the plan would be longer than the diff.

## The three files

Every plan lives in a single directory at:

```
.temp/plan-mode/active/<planId>/
├── plan.json         ← immutable definition (frozen: true after approval)
├── progress.json     ← mutable execution state
├── masterPlan.md     ← human-facing proposal (the doc the user reviews)
└── logs/             ← Codex impl/verify logs (debugging only; conductor never reads)
```

Boundaries:

- **`plan.json` is read-only after approval.** Once `frozen: true`, the
  definition does not change. Field reference: `schemas/plan.schema.json`.
- **`progress.json` is the only file the conductor mutates during
  execution.** Field reference: `schemas/progress.schema.json`.
- **`masterPlan.md` is for humans.** Not consumed by any tool; not part
  of the resumption protocol.
- **`logs/` is opaque.** Wrappers write Codex streams there. The
  conductor never reads logs as part of orchestration.

## The canonical helper

All reads, writes, and frontier computations go through
`scripts/plan-utils.sh`. Subcommands:

- `get-plan-dir <project-root>` — locate the active plan dir.
- `read-plan <plan-dir>` / `read-progress <plan-dir>` — validated reads.
- `init-progress <plan-dir>` — initialize progress.json from plan.json.
- `set-step-status <plan-dir> <step-id> <status>` — atomic status update.
- `record-verdict <plan-dir> <step-id> <verdict> <summary> <findings-json> <files-json>` — write the verifier's result.
- `set-frontier <plan-dir> <ids…>` / `compute-frontier <plan-dir>` — manage the runnable frontier.

Mutations are atomic (tmp file + rename). If a write fails mid-run,
`progress.json` is either the old state or the new state — never a
half-written file.

Reach for `jq` directly only when `plan-utils.sh` doesn't cover the
case, and consider adding the helper if the case will recur.

## The runnable-frontier algorithm

A step is **runnable** iff:

1. Its current status is `pending` (not `in_progress`, `done`,
   `blocked`, or `skipped`).
2. Every step ID in its `dependsOn` array has status `done` in
   `progress.json`.

After every status change, recompute the frontier and write it to
`progress.currentFrontier`. The conductor dispatches the frontier (in
parallel by default, serialized when two runnable steps overlap on
files — see `codex-dispatch`).

Flipping a step to `in_progress` records a `dispatch` object —
`{executor, model, startedAt}`, with `executor` one of
`codex` | `grok` | `claude` — alongside the step's `startedAt`. It is
overwritten on re-dispatch, so it always names the model behind the
recorded verdict. On resumption, the conductor surfaces in-flight
steps' dispatch info in its status line, so the user can see which
models were mid-flight when the prior session ended.

## Resumption protocol

When a fresh context window starts (cold start or post-compaction):

1. **Trust nothing in memory.** Anything not in `plan.json` /
   `progress.json` is gone.
2. **Read the hook notice** from `session-start` or `post-compact` if
   present — it points at the active plan path and the frontier.
3. **Read `plan.json`** (full read; bounded by step count).
4. **Read `progress.json`** (full read; same bound).
5. **Mirror progress into a TaskList.** One `TaskCreate` per step.
   Mark each task's status from `progress.steps[id].status`.
6. **Recompute the frontier** via `compute-frontier`.
7. **Resume execution.** Dispatch the frontier per the
   `codex-dispatch` skill.

No source files are re-read. No discovery is re-run. No Codex output
from prior steps is re-fetched. The plan files contain everything
needed to continue.

If `session-start` reports no active plan, this skill does nothing
until the user starts a non-trivial task; then it creates a new plan
via `writing-plans`.

## Plan lifecycle

- **Active**: `active/<planId>/`. One active plan per project at a
  time. If `session-start` finds two, it picks the newer by
  `lastUpdatedAt` and warns about the other.
- **Done**: when every step is `done` / `skipped` / `blocked` and the
  user has acknowledged the latter two, move the directory to
  `archive/<planId>/`.
- **Abandoned**: same destination. `progress.json` records why.

Archive is a directory rename — keep it; future questions about "what
happened in that plan" benefit from having the artifact.

## Deviations, not errors

Execution rarely matches the plan exactly. When it doesn't, record a
deviation in `progress.steps[id].deviations` rather than rewriting
the plan:

```json
{
  "type": "extra-file",
  "description": "Also updated src/types/auth.d.ts because the new type was re-exported there",
  "files": ["src/types/auth.d.ts"]
}
```

Deviations are informational. The conductor does not error on them.
The `engineering-discipline` skill's "no silent scope cuts" rule
says: if you made the deviation, write it down.

If the plan is structurally wrong (a new step is needed, a step must
split), the conductor declares the plan blocked, drafts an addendum,
and asks the user to approve a replan. The new plan gets a new
`planId`; the old one moves to `archive/`.

## Interaction with other skills

- `engineering-discipline` — the discipline floor under every step's
  execution. Deviations get recorded here, no scope cuts go silent.
- `writing-plans` — creates the three files. This skill consumes
  them.
- `codex-dispatch` — reads the step block from `plan.json` and writes
  the verdict back via `record-verdict`.
- `conductor` — orchestrator that invokes this skill on every cold
  start / compaction.

## Failure handling

- **`.temp/plan-mode/active/` unreadable** — fall back to creating a
  fresh plan via `writing-plans`. Surface to the user that the prior
  state is gone.
- **`progress.json` corrupt** — refuse to mutate. Ask the user
  whether to restore from `archive/` or restart the plan.
- **`progress.json` references a step ID not in `plan.json`** — bug
  in `writing-plans` or a manual edit gone wrong. Surface and refuse
  to dispatch until reconciled.
- **Two active plans** — newer by `lastUpdatedAt` wins; warn about
  the other.

A broken plan never silently disappears. Either the user fixes it,
explicitly archives it, or replans from scratch — but the state on
disk is the source of truth until the user decides otherwise.
