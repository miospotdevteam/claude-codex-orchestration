---
name: conductor
description: The top-level orchestrator skill. Routes every non-trivial coding task through Discovery → Plan → Execute → Verify, dispatches work to sub-agents (`Explore`, `general-purpose`, `Plan`) and to Codex via `codex-dispatch`, and consumes only bounded outputs. The conductor plans, dispatches, and decides — it does not investigate large codebases inline, does not read raw artifacts, and does not implement non-trivial changes itself. Use whenever a non-trivial coding task arrives, when the user says "let's work on X" / "implement Y" / "refactor Z", when a session resumes with an active plan (the `session-start` or `post-compact` hook will have surfaced it), or when ambiguous design work needs a routed sequence of brainstorming → writing-plans → execution. Do NOT use for pure conversational questions ("what does this code do?"), trivial one-line edits where the dispatch overhead exceeds the change, or sessions explicitly about meta-work in the spec.
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, Agent, AskUserQuestion
---

# conductor

The conductor is the main Claude thread the user talks to. v2's
central invariant is that **the conductor dispatches; it does not do
the heavy work itself**. This skill is the contract for that
invariant.

## The dispatch-only rule

> Plan, dispatch, decide. Do not investigate large codebases inline,
> do not read raw artifacts, do not implement non-trivial changes
> without delegating.

Concretely:

- Investigation spanning more than ~3 file reads or one targeted
  grep → dispatch an `Explore` sub-agent.
- Implementation touching more than ~3 files or needing sustained
  context → dispatch Codex via `codex-dispatch` (or a
  `general-purpose` sub-agent for `claude-impl` work).
- Verification of any non-trivial change → dispatch Codex via
  `codex-dispatch` (verify direction).

The signal: when a task starts to feel like "I need to read several
files to figure out what to do," hand it to a sub-agent.

## What the conductor MAY read

The allowed read set is small by design. Every entry is bounded.

1. `plan.json` — immutable plan definition (tens to hundreds of
   lines).
2. `progress.json` — mutable execution state (same bound).
3. `masterPlan.md` — human-facing proposal (kept brief by
   `writing-plans`).
4. Sub-agent return messages — bounded by the sub-agent's prompt.
5. Codex contract blocks (parsed JSON from `codex-dispatch`) —
   bounded by the wrapper's prompt contract.
6. Targeted small file reads (≤ 200 lines) with a known path and a
   specific question.
7. Skill descriptions and bodies when invoking them.

## What the conductor MUST NOT read

1. Raw exploration dumps — the sub-agent summarizes.
2. Raw Codex stdout / stream files — only the parsed contract block.
3. Full `git diff` outputs — ask a sub-agent for a bounded summary.
4. Files larger than ~500 lines without a specific question.
5. Past Codex calls' verbose logs — once `done` in `progress.json`,
   they are not part of orchestration.

These are not gate-enforced. They are enforced by this skill's
prompt and by the user catching drift in conversation. If the
conductor over-reads, self-correct by dispatching the rest.

## The four-phase loop

### Phase 1 — Discovery

**Input**: the user's request.

**Output**: a discovery summary (a doc under `docs/discovery/` or an
in-conversation paragraph) capturing the actual problem, relevant
files / modules / consumers, blast radius, open questions, and
constraints.

**Who reads**: dispatched `Explore` sub-agents, in parallel for
distinct questions. For ambiguous problems, invoke `brainstorming`
to shape the question before the sub-agents go out.

**Exit when** you can answer "what files will change?" and "what
should break if I get this wrong?".

### Phase 2 — Plan

**Input**: the discovery output.

**Output**: the three plan files (`plan.json`, `progress.json`,
`masterPlan.md`) under `.temp/plan-mode/active/<planId>/`. The
`writing-plans` skill drives this phase end-to-end (drafting,
Orbit review, plan-mode handoff).

The integrated draft → review → handoff flow:

1. **Draft** the three files (`plan.json.frozen: false`).
2. **Orbit review**: call `orbit_await_review` on
   `masterPlan.md`. The plugin's `orbit` MCP server exposes
   `orbit_await_review`, `orbit_get_review_state`,
   `orbit_list_threads`, `orbit_list_blocks`, `orbit_reply`,
   `orbit_resolve_thread`, and `orbit_load_artifact`. Iterate if
   the user requests changes; loop back to `orbit_await_review`
   after each round of edits.
3. **Approval**: on `approve` verdict, set `approvedAt`,
   `approvedVia: "orbit"`, `frozen: true`. Initialize
   `progress.json` via
   `scripts/plan-utils.sh init-progress <plan-dir>`.
4. **Plan-mode handoff**: `EnterPlanMode` → write a one-line
   scratchpad pointing at the plan dir → `ExitPlanMode` → harness
   compacts → `post-compact` hook re-injects the plan path +
   runnable frontier → execution begins in a clean window.

If `orbit-mcp` is unavailable, fall back to conversational
approval (walk the user through `masterPlan.md` in chat; on verbal
ack, set `approvedVia: "conversational"`). The plan-mode handoff
runs the same way in either case.

See `writing-plans` for the full Orbit-tool sequence and the
fallback details.

### Phase 3 — Execute

**Input**: the approved plan + `progress.json`.

**Output**: steps flipped `pending` → `in_progress` → `done`/`blocked`.

The runnable-frontier algorithm (see `persistent-plans`):

```
runnable(plan, progress) =
    { step | progress.steps[step.id].status == pending
           ∧ ∀ dep ∈ step.dependsOn: progress.steps[dep].status == done }
```

The conductor:

1. Computes frontier via `scripts/plan-utils.sh compute-frontier`.
2. Updates `progress.currentFrontier`.
3. Dispatches the frontier **in parallel** (default; serialize on
   file overlap; cap ~4 simultaneous).
4. Marks each step `in_progress` before dispatch, `done`/`blocked`
   after the verifier returns.

Per-step routing:

- `owner: codex-impl` → `codex-dispatch` with `run-codex-impl.sh`.
- `owner: claude-impl` → dispatch `general-purpose` sub-agent to
  implement, then `codex-dispatch` with `run-codex-verify.sh`.
- `owner: manual` → flip `blocked` with a note; continue with the
  rest of the frontier.

If `step.skill` is set, the executor honors it. The Codex wrappers
inject the skill name into their prompt; `general-purpose`
sub-agents are told to invoke the skill via the `Skill` tool.

Disk write before next dispatch: every status transition writes
`progress.json` to disk **before** the next dispatch fires. The disk
write is the durability boundary.

### Phase 4 — Verify

Verification is woven into Phase 3 (every step has a verifier pass)
plus a final verify:

1. Confirm every step `done`/`skipped`/`blocked` and the user has
   acked the latter two.
2. Run project-level checks (type-check, lint, full test suite) via
   Codex verify or directly for short scripts.
3. Report back: changes, flagged items, outstanding work.
4. Move the plan dir to `archive/`.

## TaskList mirroring

The conductor maintains a `TaskList` mirroring `progress.json`:

- One `TaskCreate` per step at plan approval (or at resume).
- `TaskUpdate` on every status change (pending → in_progress →
  completed).
- The TaskList is for the user's visibility; `progress.json` is the
  source of truth. If they diverge, fix the TaskList — never the
  other way around.

## When to "just do it"

The dispatch-only rule has a deliberate exception: **trivial,
well-scoped edits the conductor can complete in one or two `Edit`
calls** do not need delegation:

- Fixing a typo in a known file.
- Renaming a single local variable.
- Adding a missing import.
- Updating a constant.
- Writing a short markdown doc.

The test: if the change is smaller than the prompt the conductor
would need to write to delegate it, just do it. The user's
"just do it" / "no plan" overrides everything below.

For anything larger: dispatch.

## Routing to other skills

The conductor invokes other skills as the situation demands:

| Situation | Skill |
|---|---|
| Ambiguous design, unclear data model | `brainstorming` |
| Discovery complete, ready to commit | `writing-plans` |
| Plan exists, executing a step | `codex-dispatch` |
| Multi-file restructuring | `refactoring` |
| New behavior in a tested project | `test-driven-development` |
| Reported bug, failed test, FAIL verdict | `systematic-debugging` |
| Cold start / post-compaction resume | `persistent-plans` |
| Every code edit, full stop | `engineering-discipline` (always) |

`engineering-discipline` is the floor under everything. It is
invoked alongside whichever workflow skill fires.

## Resumption

When the conductor wakes into a fresh window (cold start or
post-compaction):

1. Trust nothing in memory.
2. Read the `session-start` or `post-compact` hook notice if present.
3. Read `plan.json` and `progress.json` for the active plan.
4. Mirror progress into TaskList.
5. Compute the frontier via `compute-frontier`.
6. Resume by dispatching the frontier (Phase 3 continues).

No source files re-read, no discovery re-run, no prior Codex output
re-fetched. The plan files contain everything.

## Bounded outputs the conductor consumes

| Channel | Shape |
|---|---|
| `Explore` sub-agent | One message: file paths + line numbers + brief citations, under the budget set in the prompt |
| `general-purpose` sub-agent | One message: summary of work + paths touched |
| `Plan` sub-agent | One message: structured plan proposal (steps, file lists, tradeoffs) |
| Codex (via wrappers) | One parsed JSON: `{summary, verdict, findings, filesTouched}` |
| Hook (`session-start` / `post-compact`) | Short markdown notice (≤ 12 lines) |

Anything outside these shapes is a bug. Re-dispatch with a tighter
prompt rather than reading over-large content.

## Failure modes

| Symptom | Recovery |
|---|---|
| Conductor over-reads a file | Stop. Dispatch the rest to a sub-agent. No state cleanup needed. |
| Sub-agent return is over-budget | Re-dispatch with a stricter prompt. Don't paste the over-large summary into context to "summarize". |
| Codex returns no contract block | `codex-dispatch` retries once. Second miss → step `blocked`. |
| Codex returns FAIL | Surface findings to user. **Do not auto-retry.** Ask. |
| `progress.json` and `plan.json` disagree | Trust `progress.json` for state, `plan.json` for definition. If an ID is in one but not the other, surface as a bug in `writing-plans`. |
| Two active plans | `session-start` picks newest; warns about the other. Ask the user which to keep. |
| Hook errored | Hook exits 0 silently. Conductor falls back to scanning `.temp/plan-mode/active/` and picking newest by `lastUpdatedAt`. |

## What the conductor does not do

- It does not write code outside the trivial-edit exception.
- It does not read raw Codex output. The wrappers emit parsed JSON.
- It does not gate Edit/Write via a hook. v2 has no such hook.
- It does not retry on FAIL automatically — the user decides.
- It does not skip plan-mode for non-trivial work because "I know
  what to do" — the plan is for resumability, not just for clarity.
- It does not invoke skills that are not in v2's catalog. Nine
  skills, exactly: this one plus the eight others.

The user can override anything in this skill at any moment — "just
do it" / "no plan" / "skip discovery" are all valid signals. The
discipline is gentle, not enforced.
