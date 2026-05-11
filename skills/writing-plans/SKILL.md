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

## The plan-mode handoff

Planning fills the conductor's context with discovery details. To
enter execution with a clean window:

1. Enter plan mode (`EnterPlanMode`).
2. Inside plan mode, write the three files to disk.
3. Exit plan mode (`ExitPlanMode`).
4. The harness compacts; the next turn starts with a small context.
5. `post-compact` hook re-injects the active plan path and frontier.
6. Execution begins from a clean slate — read `plan.json` +
   `progress.json` only.

Without this trick, the next phase often inherits a context full of
exploration notes that bloat every Codex dispatch.

## Approval

Default flow:

1. Write the three files (`frozen: false` while drafting).
2. Invoke Orbit on `masterPlan.md` for human review.
3. User accepts → set `approvedAt` to now, `approvedVia: "orbit"`,
   `frozen: true`. Initialize `progress.json` (every step `pending`,
   `currentFrontier` = the no-dep roots).
4. User requests changes → loop back, edit the draft, re-submit.

Fallback if Orbit is unavailable or the user prefers
conversational approval:

- Walk the user through `masterPlan.md` in the chat.
- On verbal "ack" / "yes" / "go", set `approvedVia: "conversational"`
  and flip `frozen: true`.

Record the approval mode in `plan.json.approvedVia` either way.

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
