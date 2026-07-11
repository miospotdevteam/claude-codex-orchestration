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

## Hard rule: verification follows the exact owner matrix

The verification policy, per owner:

- `claude-impl` steps → verified via
  `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh` (cross-family)
  and `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-verify.sh`; both must PASS.
- `codex-impl` steps → verified via
  `${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-verify.sh` and
  `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-verify.sh`; both must PASS.
- `grok-impl` steps → verified via
  `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh` only. Grok never
  self-verifies, and no Claude-family verifier runs on Grok-owned work.
- Findings from any required lane invalidate sibling PASS records;
  after the fix, every verifier in the owner's row re-runs.
- The degraded single-lane completion path is removed. If any required
  lane is down, record a deviation and keep the step `in_progress`.
  Recognizable capacity failures use the 10-minute retry rule below,
  including the Claude verifier lane. An unverified step never flips
  `done` and never rides a milestone commit.

BRIDGE-DISABLED (2026-05-24): Anthropic disabled the legacy
`claude-bridge` MCP call-back tools (`verify_step`,
`frontend_implement`, `attack_plan`). The conductor MUST NOT instruct
Codex or Grok to call any of those tools. The contract is:

1. The verifier emits the bounded contract block defined by
   `${CLAUDE_PLUGIN_ROOT}/scripts/parse-contract.sh`.
2. The conductor (this Claude session) dispatches the cross-family
   verify wrapper via the `codex-dispatch` skill to verify the step.
3. The conductor reads only the parsed JSON from the wrapper; it
   never reads raw wrapper stdout.

This rule applies to every implementation step. Any prose, plan
template, or sub-agent prompt that asks Codex or Grok to call a bridge
MCP tool is a bug — re-dispatch with the contract-block instruction
instead.

## Hard rule: quality arbitration is the Fable + Codex judge pair

When the conductor needs to **rank candidate artifacts, break a tie
between approaches, or score output quality** (distinct from step
verification, which stays cross-family), it dispatches BOTH arbiters —
Fable via `Agent(model: "fable")` and Codex via
`${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh` (read-only,
machine-default model) — and consumes their consensus. Self-bias guard
(measured): an arbiter's score of its *own family's* artifact counts
only if the other arbiter concurs; on a split over an own-family
artifact, add a grok or opus tiebreak vote. Blind the artifacts when
practical. This arbitration pair is distinct from step verification:
verification follows the exact owner matrix above; quality arbitration
runs both arbiters and consumes their consensus.

## Hard rule: always fix findings and re-verify

**On every FAIL or FINDINGS verdict from Codex (or any verifier), the
conductor MUST fix the findings and re-run the verifier. Do not
accept findings, do not "mark done with findings", do not defer to a
follow-up step.** The loop is: dispatch → verify → if not PASS, fix
+ re-verify → repeat until PASS.

Concretely:

- **FINDINGS verdict** → dispatch a fix-up sub-agent (at the scorecard
  tier, per the rule below), then re-dispatch **every verifier the
   step's owner requires** (claude-impl: Codex+Grok; codex-impl:
   Claude+Grok; grok-impl: Codex only) on the same step. Do not record the step as `done`
  with FINDINGS.
- **FAIL verdict** → same loop. The findings array is the spec for
  the fix-up sub-agent.
- **Surface progress to the user between iterations** (one-sentence
  status), but do not stop to ask "should I fix?" — fixing is the
  default. Only pause if the user pre-empted the loop, the findings
  reveal a design question that needs their judgment, or three
  iterations have not converged.
- A step's `progress.json` verdict is overwritten on each re-verify;
  only the final PASS verdict is the durable record.

Ask the user only when the loop fails to converge or the findings
require judgment beyond mechanical fixing. Routine findings are the
conductor's job, not the user's.

## Hard rule: milestone commits and Grok-authored diffs

The conductor commits **autonomously at milestones** on `main`: when a
step (or coherent group) reaches `done` with every required verifier
at PASS, and at the end of a work session. Never commit unverified
work or failing tests. Git stays append-only: `add`, `commit`, `push`,
`fetch`, fast-forward-only `pull` — no rebase, reset, checkout, stash,
branch, or force-push, ever; divergence between machines is surfaced,
never auto-merged.

When a milestone diff is predominantly Grok-authored, draft its commit
message through an out-of-band read-only
`${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh` synthetic step or
write it in the conductor. Grok never summarizes its own diff. The
returned `Summary` may carry the subject (≤72 chars) and body. Before starting NEW work in a
repo shared with the second machine, run the sync protocol first:
check `git status` on both machines (SSH), bring the working copy to
par with HEAD via commit+push / `pull --ff-only`, and only then begin.

## Hard rule: implementation sub-agent model follows the scorecard

**Every Claude sub-agent the conductor dispatches MUST carry an
explicit `model` on the `Agent` tool — including read-only scouts —
chosen per the routing matrix's Model Scorecard.** No silent defaults,
anywhere. The conductor's own model is whatever the user is running;
the tiers below govern *dispatched* sub-agents.

The tiers:

- **Before any Claude implementation dispatch, check the lane.** A
  `claude-impl` step must be taste-led or gated on a Claude-only
  skill; general implementation that merely *could* run on Opus
  belongs on `grok-impl` (the Grok lane is the measured slack quota;
  the Claude quota is a binding constraint). Re-route rather than
  dispatch when the step doesn't justify the Claude lane.
- **Opus is the floor and the default *within* the Claude lane.**
  A justified `owner: claude-impl` step →
  `Agent(subagent_type: "general-purpose", model: "opus", ...)` unless a
  rule below moves it. Taste-led refactoring, multi-file edit, and TDD
  implementation sub-agents default here too.
- **Escalate to Fable** (`model: "fable"`) for the hardest *and* most
  user-facing implementation — work that needs top intelligence and top
  taste at once (public SDK/API surface, the flagship UI, an end-to-end
  multi-step build). Escalate without asking when a lower tier's output
  does not meet the bar: judge the output, not the price tag.
- **Sonnet** (`model: "sonnet"`) is permitted ONLY for cheap,
  read-heavy scouting or mechanical Claude-side work where taste does
  not ship. It is never the owner of code that lands.
- **Never Haiku** for execution or verification.
- Read-only scouts (`Explore`, `Plan`) MUST carry an explicit
  `model: "sonnet"` — cheap read-heavy scouting is exactly Sonnet's
  lane. They never inherit the agent definition's default silently.
- Codex dispatches (`codex-impl` / verify) are unaffected — Codex is a
  separate model under `codex-dispatch`'s wrappers, not a Claude
  sub-agent, and its wrappers never take a `-m` flag.

Any dispatch that omits an explicit `model`, uses Haiku, or defaults to
Sonnet for shipping code is a bug. Silent session-model inheritance is
a bug anywhere — scouts included. Self-correct by re-dispatching at the
right tier before consuming the result.

## Hard rule: retry transient provider capacity after 10 minutes

When a dispatch returns a recognizable transient provider-capacity or
overload condition (for example, "Selected model is at capacity"), keep
the step `in_progress`, announce the pause, wait 10 minutes, then repeat
the identical dispatch on the same model and provider. Permit at most two
delayed retries (three attempts total).

After the delayed retries are exhausted, a required verifier remains
`in_progress` with a deviation; it is never replaced by another lane.
An implementation executor may follow its defined blocked/reroute path.
This rule applies only to recognizable transient
capacity or overload responses. Authentication and configuration errors,
missing binaries, invalid invocations, and malformed contracts follow
their existing failure paths and must not enter the capacity retry loop.
Do not read forbidden raw wrapper output merely to infer a capacity
condition.

## Hard rule: announce every dispatch

**Every dispatch — an `Agent` tool call OR a wrapper script — emits one
user-visible line before it fires.** Exact format:

```
→ <step-id> · <owner> · <model> · <skill>
```

- Omit the `· <skill>` segment when the step has no `skill`.
- For `Agent` dispatches, `<model>` is the explicit `model` from the
  scorecard rule above.
- For wrapper dispatches (`run-codex-*.sh`, `run-grok-*.sh`, and
  `run-claude-verify.sh`), `<model>` is owned by the wrapper/runtime;
  callers persist the actual model and effort but pass no model flag.

For `Agent` dispatches, the tool's `description` parameter MUST also
embed the step id and model, format `<step-id> · <model> · <short
title>` (e.g. `step-02 · opus · conductor skill`). The harness task
panel renders the description under the user's input field, so this is
what makes each sub-agent's model visible live — it complements the
`→` announcement line and the durable `progress.json` dispatch record.

The line is for the user's live visibility only. The **durable**
record is the `dispatch` object written into `progress.json` when the
step flips to `in_progress`: `{executor, model, effort, startedAt}`. The
announcement line is transient; the `dispatch` object is the audit
trail.

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
- Verification of any non-trivial change → dispatch every required lane
  via `codex-dispatch` (verify direction).

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

**Output**: the plan on disk under `.temp/plan-mode/active/<planId>/` —
`plan.json` and `masterPlan.md` drafted, then `progress.json` created
once at approval via `init-progress`. The `writing-plans` skill drives
this phase end-to-end (drafting, Orbit review, plan-mode handoff).

**Panel planning is automatic for high-ambiguity tasks — and the
trigger is binding.** On entering this phase, apply the trigger in
`writing-plans` (brainstorming fired / goal-without-mechanism request /
≥2 surviving architectures / ≥3 domains or ≥ ~8 steps). When any
condition matches, run the panel — do NOT decide on your own judgment
that a panel is unnecessary for a matching task; only the user's
explicit words ("just do it" / "quick" / "no plan" / "solo plan is
fine") skip it. The panel protocol runs before drafting: the identical
brief goes **in parallel, independently** to Codex
(`${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-impl.sh`, step id `panel-codex`),
Grok (`${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-impl.sh`, `panel-grok`; two-model panel on exit 4),
and a Claude planner (`Agent`, model Fable whenever available,
otherwise Opus — the strongest model drafts the plan; Opus is the
implementation tier) — then one Claude convergence sub-agent (same
rule: Fable if available, else Opus) merges the drafts with
definite decisions where they disagree. Announce each panel dispatch
with the standard `→` line. Never chain panelists on one evolving
draft, and never read the raw drafts from the conductor thread — only
the converged output. The `writing-plans` skill owns the full panel
protocol and its trigger.

The integrated draft → review → handoff flow:

1. **Draft** `plan.json` and `masterPlan.md` (`plan.json.frozen: false`);
   `progress.json` is not written yet.
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
   `${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh init-progress <plan-dir>`.
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

1. Computes frontier via `${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh compute-frontier`.
2. Updates `progress.currentFrontier`.
3. Dispatches the frontier **in parallel** (default; serialize on
   file overlap; cap ~4 simultaneous).
4. Flips each step to `in_progress` before dispatch via
   `${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh start-step <plan-dir>
   <step-id> <executor> <model> <effort>` — one atomic update of status plus the
   `{executor, model, effort, startedAt}` dispatch record (see `persistent-plans`
   for the canonical description). Marks `done`/`blocked` after the
   verifier returns.

Per-step routing:

- `owner: codex-impl` → `codex-dispatch` with `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-impl.sh`;
  verified via `${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-verify.sh` and
  `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-verify.sh`; both must PASS.
- `owner: grok-impl` → `codex-dispatch` with `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-impl.sh` (the
  `codex-dispatch` skill owns both wrapper lanes); verified via
  `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh` only.
- `owner: claude-impl` → dispatch `general-purpose` sub-agent to
  implement, then BOTH `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh`
  and `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-verify.sh`; `done` requires
  both PASS.
- `owner: manual` → flip `blocked` with a note; continue with the
  rest of the frontier.

When a step requires interacting with a desktop application, an OS
dialog, or anything outside Claude's own tool surface, route it
`owner: codex-impl` and say in the step description that the work needs
Codex's computer use — that capability rides the Codex machine config,
not a wrapper flag. **Never route such work to the verify lane:** the
verifier's read-only sandbox constrains file writes, not desktop side
effects, so a verifier asked to drive the GUI would act with unbounded
effect. Browser-only work is the exception — Claude automates Chrome
natively, so it stays on its normal owner.

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
| Discovery complete, ready to commit | `writing-plans` (panel planning auto-triggers for high-ambiguity tasks) |
| Plan exists, executing a step | `codex-dispatch` |
| Multi-file restructuring | `refactoring` |
| New behavior in a tested project | `test-driven-development` |
| Reported bug, failed test, FAIL verdict | `systematic-debugging` |
| Cold start / post-compaction resume | `persistent-plans` |
| Start or launch Mini work; continue or resume Mini work; inspect or check whether it needs input; wait for or monitor a Mini agent; reveal or show its Mini Terminal; control, steer, interrupt, kill, or send instructions to Mini; reclaim or take over Mini work | `remote-agent-host` |
| Every code edit, full stop | `engineering-discipline` (always) |

`engineering-discipline` is the floor under everything. It is
invoked alongside whichever workflow skill fires.

The `remote-agent-host` route is an intent route, not a plan-step owner or an
external wrapper lane. When a user asks to start, continue, inspect for input,
wait for or monitor a Mini agent, reveal or show its Mini Terminal, control,
interrupt, kill, or reclaim a supported Mini session, invoke that skill and let it own the guarded
helper interaction and safety checks. The conductor consumes only its bounded
captured-state report; it never improvises SSH or rsync commands.

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
| Grok (via wrappers) | One parsed JSON: `{summary, verdict, findings, filesTouched}` |
| Hook (`session-start` / `post-compact`) | Short markdown notice (≤ 12 lines) |
| Mini lifecycle wait | Labels-only envelope `{epoch, cursor, session, wake, scope?, kind?}` followed by one bounded `inspect` capture (≤ 40 lines or 4 KiB) |

Anything outside these shapes is a bug. Re-dispatch with a tighter
prompt rather than reading over-large content.

## Failure modes

| Symptom | Recovery |
|---|---|
| Conductor over-reads a file | Stop. Dispatch the rest to a sub-agent. No state cleanup needed. |
| Sub-agent return is over-budget | Re-dispatch with a stricter prompt. Don't paste the over-large summary into context to "summarize". |
| Codex returns no contract block | `codex-dispatch` retries once. Second miss → step `blocked`. |
| Codex returns FAIL or FINDINGS | Fix the findings and re-verify; loop until PASS. Pause only after three non-converging iterations or a genuine design question that needs user judgment. |
| `progress.json` and `plan.json` disagree | Trust `progress.json` for state, `plan.json` for definition. If an ID is in one but not the other, surface as a bug in `writing-plans`. |
| Two active plans | `session-start` picks newest; warns about the other. Ask the user which to keep. |
| Hook errored | Hook exits 0 silently. Conductor falls back to scanning `.temp/plan-mode/active/` and picking newest by `lastUpdatedAt`. |

## What the conductor does not do

- It does not write code outside the trivial-edit exception.
- It does not read raw Codex output. The wrappers emit parsed JSON.
- It does not gate Edit/Write via a hook. v2 has no such hook.
- It does not accept a FAIL or FINDINGS verdict as final — it fixes
  the findings and re-verifies until PASS, pausing only on
  non-convergence or a design question that needs user judgment.
- It does not skip plan-mode for non-trivial work because "I know
  what to do" — the plan is for resumability, not just for clarity.
- It does not invoke skills that are not in v2's catalog: the core
  orchestration skills (this conductor plus its planning, dispatch,
  and discipline peers) and the auxiliary craft skills the
  orchestrator routes to. The catalog is exactly the skills shipped
  under this plugin's `skills/` directory — it invents no others.

The user can override anything in this skill at any moment — "just
do it" / "no plan" / "skip discovery" are all valid signals. The
discipline is gentle, not enforced.
