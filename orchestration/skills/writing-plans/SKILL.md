---
name: writing-plans
description: Draft the three plan files (plan.json, progress.json, masterPlan.md) after discovery is complete, then drive review and approval. Use whenever the user says "write the plan", "draft a plan.json", "let's plan this", or after discovery / brainstorming has produced enough context to commit to a path. Produces a DAG of TDD-granularity steps with explicit dependsOn edges, a per-step progress[] checklist, and a tight human-facing masterPlan.md. Do NOT use when discovery is incomplete (use `brainstorming` or dispatch `Explore`), when the user says "just do it" / "no plan", or mid-execution (use `persistent-plans` to update progress instead).
allowed-tools: Read, Edit, Write, Bash, Glob
---

# writing-plans

Turn a completed discovery into the three plan files on disk. The
plan is a contract, not a script — once approved it does not change.
`progress.json` carries every deviation.

## When this fires

- Discovery (Explore / brainstorming) is complete and the user wants
  to commit to a plan.
- The user says "write the plan", "draft a plan.json", "let's plan
  this", "what's the plan".
- An existing plan was invalidated by a structural change and needs a
  fresh draft (new planId).

It does **not** fire for:

- Discovery incomplete — route to `brainstorming` or dispatch
  `Explore` first.
- The user said "just do it" / "no plan" — skip the loop.
- Mid-execution updates — use `persistent-plans` to update
  `progress.json`.

## Panel planning — automatic for high-ambiguity tasks

Before drafting solo, apply this trigger. Panel-plan when ANY of:
`brainstorming` fired during discovery; the request is a goal without
a mechanism ("decide what to do about X"); two or more plausible
architectures survived discovery with non-obvious tradeoffs; the plan
will span ≥3 domains or ≥ ~8 steps. Skip when the user said "just
do it" / "quick", or the work is single-domain clear-spec or a
mechanical sweep. The user can force either mode.

The protocol (full spec: `docs/09-routing-matrix.md`, Panel Planning
section — including the measured result it rests on: independent
drafts + convergence beat both every solo plan and a sequential
relay):

1. Write one planning brief to `<plan-dir>/panel/brief.md`.
2. Send the **identical brief, in parallel, independently** to Codex
   (`run-codex-impl.sh`, synthetic step id `panel-codex`, deliverable
   `panel/codex.plan.md`), Grok (`run-grok-impl.sh`,
   `panel/grok.plan.md`; on wrapper exit 4, continue as a two-model
   panel), and a Claude planner (`Agent`, explicit scorecard model,
   `panel/claude.plan.md`). No panelist ever sees another's draft.
3. Dispatch one Claude convergence sub-agent (Fable preferred, Opus
   floor) that reads the brief + drafts and returns the converged
   plan: a definite decision wherever drafts disagree (one-line
   reason), redundancy cut, complementary strengths kept.
4. Use the converged plan as the source for step 1 of the flow below.
   Panel drafts stay in `<plan-dir>/panel/` for audit; the conductor
   reads only the converged output.
5. **Never chain panelists sequentially on one evolving draft** — it
   measured worse than the best solo plan.

## Outputs

Three files under `.temp/plan-mode/active/<planId>/`:

- **`plan.json`** — schema in `schemas/plan.schema.json`. Required
  fields: planId, title, createdAt, createdBy, frozen, context,
  steps. Approval fields (approvedAt, approvedVia) are optional until
  approval lands.
- **`progress.json`** — schema in `schemas/progress.schema.json`.
  Initialized via `scripts/plan-utils.sh init-progress <plan-dir>`.
- **`masterPlan.md`** — start from `templates/masterPlan.template.md`
  and fill the five sections: Goal, Approach, Steps, Risks and open
  questions, Out of scope.

## Step granularity

One step = one component, one behavior, or one mechanical sweep. The
test: if a step's `progress[]` array has more than ~6 sub-items, the
step is too large — split it. Counter-test: if a step touches one
file and has one acceptance criterion, it may be too small — merge it
with an adjacent step.

For TDD steps, the `progress[]` checklist encodes the red-green
rhythm:

```
"progress": [
  "Write failing tests covering sign+verify roundtrip and tamper detection",
  "Implement sign() with HMAC-SHA256",
  "Implement verify() with constant-time comparison",
  "Run test suite; ensure type-check and lint pass",
  "Commit"
]
```

For refactors, `progress[]` encodes the stage order (additive →
migrate consumers → delete old shape).

## dependsOn DAG validity

Enforce these rules before flipping `frozen: true`:

1. Every ID in any `dependsOn` exists in `steps`.
2. The graph is acyclic (topological sort succeeds).
3. A step with empty `dependsOn` is a root — runnable from the start.
4. **Steps that touch the same file have a dependency edge between
   them.** Concurrent edits to the same file by parallel agents are a
   correctness bug. If two steps share a file but are otherwise
   independent, order them with a dep rather than letting them race.

If a step would naturally split across two owners (a Claude-only
skill on one half and a Codex implementation on the other), produce
two sequential steps linked by `dependsOn` rather than forcing one
step into a single owner.

## Routing (owner + skill)

Default routing follows the matrix in `docs/09-routing-matrix.md`.
Short form:

- **`codex-impl` (default)**: backend services, CRUD, refactors,
  migrations, test writing, config/glue/mechanical work, CI/CD
  setup, any "no other rule fires" step.
- **`claude-impl`**: steps whose `skill` is in the Claude-only set
  (`frontend-design`, `svg-art`, `immersive-frontend`,
  `brainstorming`, `writing-plans`, `doc-coauthoring`).
- **`manual`**: the user does it (auth flows that need a human
  browser, secret handling, decisions that need judgment outside the
  model).

If a step's owner is `claude-impl` for any reason other than a
Claude-only skill, write a one-line `routingJustification` in the
step description so the conductor can audit it later. A `claude-impl`
step without justification is a planning bug.

## The full draft → review → handoff flow

Planning has two integrated mechanisms that must run in order:
**Orbit review** (the user sees the plan) and **the plan-mode handoff**
(execution starts in a clean context window). Run them in this order:

### 1. Draft the three files (frozen:false)

Write `plan.json` (with `frozen: false`), `progress.json`, and
`masterPlan.md` under `.temp/plan-mode/active/<planId>/`. Don't
initialize `progress.steps[*].status` yet — initialization happens
on approval (step 4 below).

### 2. Open Orbit review on `masterPlan.md`

The plugin declares `orbit` as an MCP server. Call the Orbit tools
in this sequence:

```
orbit_await_review( file: "<plan-dir>/masterPlan.md" )
```

This presents the file to the user, blocks until they verdict it,
and returns the verdict.

While waiting (or after a verdict), the conductor may also call:

- `orbit_get_review_state` — check current review status.
- `orbit_list_threads` / `orbit_list_blocks` — read the user's
  comments and blocking remarks.
- `orbit_reply` / `orbit_resolve_thread` — respond to threads and
  mark them resolved as you address them.
- `orbit_load_artifact` — load referenced artifacts the user
  attached to the review.

### 3. Iterate on changes, or accept

**If the user requests changes** (Orbit returns a `request_changes`
verdict or non-empty blocking threads):

- Read every blocking thread via `orbit_list_threads`.
- Edit `plan.json` and/or `masterPlan.md` in place (still
  `frozen: false`).
- Reply to each addressed thread via `orbit_reply` and
  `orbit_resolve_thread`.
- Loop back to `orbit_await_review` for another round.

**If the user accepts** (Orbit returns an `approve` verdict):

- Set `plan.json.approvedAt` to now (UTC ISO-8601 with `Z`).
- Set `plan.json.approvedVia` to `"orbit"`.
- Flip `plan.json.frozen` to `true`.
- Initialize `progress.json` via
  `scripts/plan-utils.sh init-progress <plan-dir>` so every step is
  `pending` and `currentFrontier` is the set of root steps.

### 4. Plan-mode handoff (clear context before execution)

Once `frozen: true`, the conductor's window is still full of
discovery context. Clear it before dispatching:

1. `EnterPlanMode` — opens the harness's plan-mode buffer.
2. Inside plan mode, write a tiny resumption scratchpad pointing at
   the plan dir (one line is enough — the plan files on disk are
   the source of truth; this scratchpad just survives the
   compaction summary).
3. `ExitPlanMode` — harness compacts the prior context away.
4. `post-compact` hook fires automatically, re-injecting the active
   plan path and the runnable frontier as an action-oriented notice.
5. The conductor's next turn starts with a clean window: it reads
   `plan.json` + `progress.json`, mirrors progress into the
   TaskList, and begins dispatching the frontier via `codex-dispatch`.

Without this handoff, every Codex dispatch in the execute phase
inherits a context full of discovery prose and bloats unnecessarily.

### Conversational fallback (no Orbit)

If `orbit-mcp` isn't available (the user skipped the install prereq
or it's broken), the conductor degrades gracefully:

- Walk the user through `masterPlan.md` in chat. Quote the Goal +
  Approach + Steps sections inline.
- On verbal "ack" / "yes" / "go" / "looks good", treat that as
  approval.
- Set `plan.json.approvedVia` to `"conversational"`, otherwise the
  flow is identical (flip `frozen`, initialize progress, do the
  plan-mode handoff).

Record the approval mode in `plan.json.approvedVia` so a future
session can audit which path was taken.

## What stays out of plan.json

- Implementation details that belong in the step description, not in
  separate top-level fields.
- Discovery artifacts. Point at them with `context.discoveryRef` if
  helpful; do not inline them.
- Status that belongs in `progress.json` (`startedAt`, verdicts,
  findings, deviations).
- Anything from v1: receipts, HMAC sidecars, claude-review pointers,
  digester refs. None of these exist in v2.

## Re-planning

If execution reveals the plan was structurally wrong (a new step is
needed, a step must split, a dep was missed):

1. Declare the plan blocked in `progress.json`.
2. Move the directory to `archive/<oldPlanId>/`.
3. Draft a new plan with a new `planId`. Reuse what's still valid;
   replace what isn't.
4. Re-approve.

Small adjustments (a too-strict acceptance criterion) do not warrant
a replan — record them as `deviations` and continue.

## Interaction with other skills

- `engineering-discipline` — the floor under every step. Each step's
  `acceptanceCriteria` should imply post-change verification.
- `persistent-plans` — consumes the three files this skill produces.
- `codex-dispatch` — reads `step.description` + `acceptanceCriteria`
  + `files` and renders the prompt sent to Codex.
- `conductor` — invokes this skill once discovery is complete.
- `brainstorming` — runs before this skill when the problem shape is
  unclear; hands off a one-paragraph design summary.

## Failure surface

- **Steps too large** — Codex returns FINDINGS with "I did A, B, C,
  but D and E were out of scope". Split the step.
- **Missed file overlap** — two parallel steps trample each other's
  changes. Always declare dep edges between steps that share a file.
- **Plan that can't be tested** — acceptance criteria like "the code
  is cleaner" don't survive a verifier pass. Every criterion must be
  a testable assertion.
- **Approved-but-still-changing plan** — if `frozen: true` is set
  before approval, this skill is broken. The approval flow is what
  flips `frozen`.
