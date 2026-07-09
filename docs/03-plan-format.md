# 03 — Plan format

v2 plans live on disk as **three files** under a per-plan directory:

```
.temp/plan-mode/active/<plan-name>/
├── plan.json        ← immutable definition (frozen after approval)
├── progress.json    ← mutable execution state
└── masterPlan.md    ← human-facing proposal
```

The split is deliberate. `plan.json` is the contract; once the user
approves it (via Orbit or otherwise), it does not change. `progress.json`
is the only file the conductor mutates during execution. `masterPlan.md`
is for humans — it is the proposal the user reviews, not a runtime
artifact.

This separation means a compaction can wipe the conductor's memory and
the next session can reconstruct everything from these three files.

## plan.json

### Top-level shape

```json
{
  "planId": "auth-refactor-2026-05-11",
  "title": "Refactor auth to use signed cookies",
  "createdAt": "2026-05-11T14:23:00Z",
  "createdBy": "writing-plans",
  "approvedAt": "2026-05-11T14:45:00Z",
  "approvedVia": "orbit",
  "frozen": true,
  "context": {
    "rootDir": "/Users/x/Projects/myapp",
    "branch": "main",
    "discoveryRef": "docs/discovery/auth-refactor.md"
  },
  "steps": [
    { /* step object — see below */ },
    { /* step object */ }
  ]
}
```

### Step object

```json
{
  "id": "step-3",
  "title": "Introduce SignedCookie type and helpers",
  "description": "Create src/auth/signed-cookie.ts exporting SignedCookie type, sign(), verify(). Use HMAC-SHA256 with COOKIE_SECRET from env.",
  "acceptanceCriteria": [
    "src/auth/signed-cookie.ts exports SignedCookie, sign, verify",
    "sign() returns base64url string under 4KB for typical payloads",
    "verify() returns null on tampered cookies and the payload on valid ones",
    "Unit tests in src/auth/signed-cookie.test.ts pass"
  ],
  "files": [
    "src/auth/signed-cookie.ts",
    "src/auth/signed-cookie.test.ts"
  ],
  "dependsOn": ["step-1", "step-2"],
  "owner": "codex-impl",
  "skill": "test-driven-development",
  "estimateMinutes": 20,
  "progress": [
    "Write failing tests covering sign+verify roundtrip and tamper detection",
    "Implement sign() with HMAC-SHA256",
    "Implement verify() with constant-time comparison",
    "Run test suite; ensure type-check and lint pass",
    "Commit"
  ]
}
```

Field reference:

- **`id`** — unique within the plan. Used in `dependsOn` and
  `progress.json`. Convention: `step-<n>`.
- **`title`** — one-line label for status displays.
- **`description`** — full prose description of the step. This is what
  Codex (or a sub-agent) reads when implementing.
- **`acceptanceCriteria`** — array of testable assertions. The verifier
  (Codex via `run-codex-verify.sh`) checks each one. If any criterion
  cannot be checked from the diff alone, mark it `manual` in the prose.
- **`files`** — paths the step is expected to touch. Used by the
  runnable-frontier algorithm to detect overlapping steps and by
  hooks for status display. Not a hard constraint — deviations land
  in `progress.json`.
- **`dependsOn`** — array of step IDs that must be `done` before this
  step is runnable. Defines the DAG (see below).
- **`owner`** — who executes: `codex-impl` (default), `claude-impl`
  (the conductor implements via a sub-agent), `grok-impl` (implemented
  by Grok 4.5 via the direction-locked Grok Build wrappers — see
  `docs/10-grok-integration.md`; routing rules in
  `docs/09-routing-matrix.md`), or `manual` (the user).
- **`skill`** — the discipline skill the executor should invoke for
  this step. From `05-skills-catalog.md`. Optional.
- **`estimateMinutes`** — wall-clock estimate. Optional, advisory.
- **`progress`** — an ordered checklist of sub-tasks the executor
  should work through. For TDD steps this encodes the red-green
  rhythm; for refactors it encodes the safety order. Optional but
  recommended.

### DAG via dependsOn

`dependsOn` defines a directed acyclic graph over steps. The execution
loop (see `04-execution-loop.md`) uses it to compute the **runnable
frontier**: the set of steps whose dependencies are all `done` and
which are not themselves `done` or `in_progress`.

Validity rules `writing-plans` enforces:

1. Every ID in `dependsOn` must exist in `steps`.
2. The graph must be acyclic.
3. A step with empty `dependsOn` is a root and runnable from start.
4. Steps that touch the same file should declare a dependency between
   them — concurrent edits to the same file by parallel agents are a
   correctness bug, not a perf concern.

### Immutability

Once `frozen: true`, `plan.json` does not change. If execution reveals
the plan was wrong:

- For a small adjustment (a step's acceptance criterion is too strict),
  record a **deviation** in `progress.json` and continue.
- For a structural change (a new step is needed, or a step must split),
  the conductor declares the plan blocked, drafts an addendum, and
  asks the user to approve a re-plan. The new `plan.json` gets a
  new `planId`; the old one is moved to
  `.temp/plan-mode/archive/<planId>/`.

## progress.json

This is the only runtime-mutable file. Schema:

```json
{
  "planId": "auth-refactor-2026-05-11",
  "startedAt": "2026-05-11T15:01:00Z",
  "lastUpdatedAt": "2026-05-11T15:42:00Z",
  "currentFrontier": ["step-3", "step-4"],
  "steps": {
    "step-1": {
      "status": "done",
      "startedAt": "2026-05-11T15:01:00Z",
      "completedAt": "2026-05-11T15:08:00Z",
      "owner": "codex-impl",
      "verdict": "PASS",
      "result": "Renamed AuthSession -> Session across 14 files. Type-check clean.",
      "deviations": [],
      "filesTouched": ["src/auth/session.ts", "src/auth/index.ts", "..."]
    },
    "step-2": {
      "status": "done",
      "verdict": "FINDINGS",
      "findings": [
        "Test src/auth/session.test.ts:42 was skipped; not in acceptance criteria but worth flagging."
      ],
      "result": "...",
      "filesTouched": ["..."]
    },
    "step-3": {
      "status": "in_progress",
      "owner": "grok-impl",
      "startedAt": "2026-05-11T15:30:00Z",
      "dispatch": {
        "executor": "grok",
        "model": "grok-build",
        "startedAt": "2026-05-11T15:30:00Z"
      }
    },
    "step-4": {
      "status": "pending"
    }
  }
}
```

### Dispatch record

When a step flips to `in_progress`, the conductor writes an optional
`dispatch` object alongside `startedAt`:

```json
"step-5": {
  "status": "in_progress",
  "owner": "claude-impl",
  "startedAt": "2026-05-11T15:44:00Z",
  "dispatch": {
    "executor": "claude",
    "model": "opus",
    "startedAt": "2026-05-11T15:44:00Z"
  }
}
```

- **`executor`** — one of `codex` | `grok` | `claude`.
- **`model`** — the model identifier that ran the step (e.g. `opus`,
  `gpt-5-codex`, `grok-build`).
- **`startedAt`** — ISO-8601 UTC timestamp of the dispatch.

`dispatch` is the durable record of *which* model did the work, pairing
with the conductor's user-visible dispatch announcement. It is
overwritten on re-dispatch, so it always reflects the dispatch that
produced the recorded verdict.

### Status values

- **`pending`** — not yet runnable, or runnable but not picked.
- **`in_progress`** — dispatched, awaiting result.
- **`done`** — completed with a verdict of PASS or FINDINGS.
- **`blocked`** — could not complete; needs human input. The
  `result` field carries the reason.
- **`skipped`** — explicitly skipped by user decision; `result`
  carries the reason.

### Verdict values

These mirror the Codex verifier's contract (see
`06-codex-integration.md`):

- **`PASS`** — all acceptance criteria met.
- **`FINDINGS`** — criteria met but the verifier noted concerns. The
  conductor surfaces findings to the user; the step is still `done`.
- **`FAIL`** — criteria not met. The step goes back to `in_progress`
  or `blocked` depending on whether a retry is sensible.

### Deviations

`deviations` is an array of `{type, description, files}` objects
recording where execution diverged from `plan.json`. Examples:

- `{type: "extra-file", description: "Also updated src/types/auth.d.ts because the new type was re-exported there", files: ["src/types/auth.d.ts"]}`
- `{type: "missing-criterion", description: "Acceptance criterion 3 could not be tested in this step; deferred to step-7", files: []}`

Deviations are informational, not errors. They give the user (and a
future session) a clear picture of what actually happened.

## masterPlan.md

Human-facing. Lives next to `plan.json`. This is the document the user
reviews and approves (typically in Orbit before execution starts).

### Template

```markdown
# <Plan title>

## Goal

<One paragraph: what changes, why, and the success criterion the user
will judge by.>

## Approach

<2–5 paragraphs: the strategy. Why this shape, what alternatives were
considered and rejected, what the blast radius is.>

## Steps

1. **<step-1 title>** — <one-line summary>
2. **<step-2 title>** — <one-line summary>
3. ...

## Risks and open questions

- <risk or question>
- <risk or question>

## Out of scope

- <what we are explicitly not doing in this plan>
```

The conductor (via `writing-plans`) generates this from `plan.json`
and the discovery output. It is kept short — long enough to be a
faithful proposal, short enough to read in five minutes.

### Approval

Default flow:

1. Conductor writes the three files.
2. Conductor invokes Orbit on `masterPlan.md` for review.
3. User accepts, or requests changes (which loop back to
   `writing-plans` with the comments).
4. On accept, `plan.json` flips `frozen: true` and execution can begin.

If Orbit is not available or the user prefers, approval can be a
plain conversational ack. The conductor records the approval mode in
`plan.json.approvedVia`.

## File lifecycle

- **Active**: under `.temp/plan-mode/active/<planId>/`.
- **Done**: when every step is `done`/`skipped`/`blocked` and the
  user confirms, the plan directory moves to
  `.temp/plan-mode/archive/<planId>/`.
- **Abandoned**: same destination as Done. The `progress.json`
  records why.

Only one plan should be active at a time per project. If two are
active, the `session-start` hook picks the most recently updated and
warns the conductor that the other exists.

See `04-execution-loop.md` for how the conductor consumes these files
at runtime.
