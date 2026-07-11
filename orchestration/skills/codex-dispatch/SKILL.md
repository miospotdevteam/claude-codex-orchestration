---
name: codex-dispatch
description: >-
  Dispatch Codex and Grok implementation work and Claude, Codex, and Grok verification through the plugin's direction-locked wrappers, then consume only the bounded contract JSON. Use for `codex-impl` or `grok-impl` frontier steps, every implementation-step verification, and synthetic read-only checks such as a Codex-drafted message for a predominantly Grok-authored milestone. The owner matrix is exact: `claude-impl` requires Codex plus Grok, `codex-impl` requires Claude plus Grok, and `grok-impl` requires Codex only. Do NOT use for implementing `claude-impl` or `manual` steps, for bypassing a wrapper, for Grok self-verification, or for degraded single-lane completion.
allowed-tools: Read, Bash, Edit, Write
---

# codex-dispatch

This skill owns every external implementation dispatch and every
direction-locked verification dispatch. The conductor never invokes
`codex exec`, `grok`, or a headless Claude verifier directly; it invokes
the plugin wrappers and reads only the parsed Summary / Verdict /
Findings / FilesTouched JSON.

## Hard rule: the owner determines every required verifier

The matrix is settled and exact:

| Step owner | Required verifier lanes | Verify wrappers |
|---|---|---|
| `claude-impl` | `codex`, `grok` | `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh` and `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-verify.sh` |
| `codex-impl` | `claude`, `grok` | `${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-verify.sh` and `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-verify.sh` |
| `grok-impl` | `codex` only | `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh` |
| `manual` | none | none |

Consequences:

- A step reaches `done` only after every lane in its row has a current
  `PASS`. An unrecorded, unavailable, or non-PASS required lane always
  leaves the step `in_progress`.
- Grok never verifies `grok-impl` work. Codex is Grok's sole verifier,
  and no Claude-family verifier runs on a Grok-owned step.
- Codex never self-verifies `codex-impl` work, and Claude never
  self-verifies `claude-impl` work. `plan-utils.sh` refuses verdicts and
  lane dispatches that are outside the owner's row.
- A `FINDINGS` or `FAIL` from any required lane invalidates the other
  lanes' earlier PASS records. Fix the implementation, then dispatch
  and record every required verifier in the owner's row again. Never
  reuse a sibling PASS from before the fix.
- The former `--degraded` completion flag is removed. Passing it is an
  error, and there is no fallback verifier or single-lane done path for
  an implementation step.

This policy's own bootstrap step is not exempt: when the matrix is
introduced by a `codex-impl` step, the conductor manually applies its
new done gate and requires both Claude and Grok PASS before completing
that step.

## Required-lane outages and the 10-minute capacity rule

If a required verifier is down, unauthenticated, quota-limited, or
otherwise unavailable, record a schema-valid deviation and keep the
step `in_progress`; do not substitute another family. For a recognizable
transient provider-capacity or overload response, announce the pause,
wait 10 minutes, and retry the same lane. This rule applies equally to
the Claude, Codex, and Grok verifier lanes.

Permit at most two delayed retries (three attempts total), and retry only
while the response remains a recognizable capacity condition.
Authentication, configuration, malformed-contract, and missing-binary
failures use their bounded failure paths below; they do not enter the
capacity loop. None of those paths can mark an unverified implementation
step `done`.

## Routing directive and milestone messages

Use Grok materially more for general implementation work; it is the
measured slack lane. Reserve `claude-impl` for taste-led or Claude-only
work, and use `codex-impl` when the plan assigns Codex. Increased Grok
implementation volume does not change the verification matrix: Codex is
always Grok's sole verifier, and Grok never reviews its own work.

G3 commit-message rule: when a milestone diff is predominantly
Grok-authored, draft its commit message either through an out-of-band
synthetic `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh` dispatch
over the staged diff or in the conductor. Never ask Grok to summarize
or name a predominantly Grok-authored diff. The synthetic contract's
`Summary` carries the subject (at most 72 characters) and optional body;
its verdict is ignored for this out-of-band use.

## When this fires

- `owner: codex-impl` reaches the frontier: dispatch
  `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-impl.sh`.
- `owner: grok-impl` reaches the frontier: dispatch
  `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-impl.sh`.
- Any implementation step is ready for verification: dispatch every
  verifier wrapper in its matrix row.
- The conductor needs a bounded out-of-band review or a G3 milestone
  message draft: use the appropriate read-only verify wrapper with a
  synthetic plan and step id.

It does not fire for implementing `claude-impl` or `manual` steps,
free-form chat, or calls that bypass the wrappers.

## Wrapper inventory and direction lock

This skill owns two IMPLEMENT wrappers and three VERIFY wrappers:

| Wrapper | Direction | Mutation policy |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-impl.sh` | IMPLEMENT | may edit |
| `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-impl.sh` | IMPLEMENT | may edit |
| `${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-verify.sh` | VERIFY | headless `-p`; write and command tools denied |
| `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh` | VERIFY | Codex read-only sandbox |
| `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-verify.sh` | VERIFY | Write, Edit, and Bash denied |

The script identity pins the direction; prompt text cannot turn a
verifier into an implementer. All verify wrappers accept
`--plan-id`, `--step-id`, `--root-dir`, optional `--skill`, and either
`--diff-file` or a `---DIFF---` stdin sentinel. All emit the same parsed
contract JSON. Grok's wrappers create and pass a distinct internal
`--leader-socket` on every invocation; callers do not supply or reuse it.

The legacy Claude bridge tools are disabled. Never instruct Codex or
Grok to call `verify_step`, `frontend_implement`, or `attack_plan`.
Verification returns through the bounded contract only.

## Rendered step block

Render the immutable plan fields as bounded prose:

```text
# Step <step-id>: <title>

## Description
<description>

## Acceptance criteria
- <criterion>

## Files (expected)
- <path>

## Progress checklist
1. <item>
```

For verification, append the diff after an exact `---DIFF---` line or
pass it via `--diff-file`.

## Persist dispatch before execution

Before every implementation dispatch, atomically start the step with
the actual executor, model, and effort:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" start-step \
  "$PLAN_DIR" "$STEP_ID" "$EXECUTOR" "$MODEL" "$EFFORT"
```

This writes:

```json
{"executor":"codex|grok|claude","model":"...","effort":"...","startedAt":"..."}
```

Before each verifier wrapper is launched, persist that lane's dispatch:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" record-lane-dispatch \
  "$PLAN_DIR" "$STEP_ID" "$LANE" "$EXECUTOR" "$MODEL" "$EFFORT"
```

The per-lane record is
`{lane, executor, model, effort, dispatchedAt}`. It is deliberately
separate from `record-verdict`: after resume or compaction, a required
`laneDispatches.<lane>` record with no current
`verdicts.<lane>` record means the step is `verifying`. Derive that
state from `progress.json`, never from conversational memory.

For example, a `codex-impl` verification persists and launches both
required lanes:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" record-lane-dispatch \
  "$PLAN_DIR" "$STEP_ID" claude claude "$CLAUDE_MODEL" "$CLAUDE_EFFORT"
render_step_and_diff | "${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-verify.sh" \
  --plan-id "$PLAN_ID" --step-id "$STEP_ID" --root-dir "$ROOT_DIR"

"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" record-lane-dispatch \
  "$PLAN_DIR" "$STEP_ID" grok grok grok-4.5 "$GROK_EFFORT"
render_step_and_diff | "${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-verify.sh" \
  --plan-id "$PLAN_ID" --step-id "$STEP_ID" --root-dir "$ROOT_DIR"
```

## Persist verdicts and apply the done gate

Record one bounded result per dispatched lane. The lane vocabulary is
`claude`, `codex`, and `grok`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" record-verdict \
  "$PLAN_DIR" "$STEP_ID" \
  "$VERDICT" "$SUMMARY" "$FINDINGS_JSON" "$FILES_JSON" "$LANE"
```

Only after every lane in the owner's row has a current PASS may the
conductor attempt:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" set-step-status \
  "$PLAN_DIR" "$STEP_ID" done
```

The helper reads the machine-readable matrix in
`${CLAUDE_PLUGIN_ROOT}/schemas/plan.schema.json` and refuses an
incomplete gate. A required lane outage remains `in_progress` with a
deviation; it never becomes a degraded completion.

On `FINDINGS` or `FAIL`, keep the step `in_progress`, dispatch the fix
through a fresh `start-step` call, then persist and run every required
lane again. `start-step` clears stale dispatch and verdict state, and a
non-PASS lane record invalidates sibling PASS records as an additional
guard.

After a successful done transition, recompute the frontier with
`${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh compute-frontier
"$PLAN_DIR"`.

## Parallelism and overlap

Dispatch independent frontier steps in parallel up to the conductor's
resource cap. Serialize any pair whose `files` arrays overlap. Apply
the same overlap guard to both implementation wrappers and all three
verification wrappers.

If a step edits a wrapper that is currently executing, first snapshot
that wrapper and `${CLAUDE_PLUGIN_ROOT}/scripts/parse-contract.sh` to a
scratch directory and invoke the snapshot. Bash can reread shifted
bytes from a script modified during execution.

## Read only the parsed contract

Successful wrappers emit only this JSON shape:

```json
{
  "summary": "...",
  "verdict": "PASS",
  "findings": [],
  "filesTouched": ["..."]
}
```

Never open raw wrapper output. Diagnostic streams belong in:

- `codex-impl-<stepId>.log` and `codex-verify-<stepId>.log`;
- `grok-impl-<stepId>.log` and `grok-verify-<stepId>.log`;
- `claude-verify-<stepId>.log`.

The logs are for a human debugging after the fact. If the bounded
contract lacks needed information, improve the step block and
re-dispatch.

## Failure handling

| Exit | Meaning | Action |
|---|---|---|
| 0 | Contract parsed | Persist the lane verdict |
| 1 | Bad wrapper invocation | Fix the caller; do not mutate step completion |
| 2 | Executor invocation failed | For recognizable capacity, apply the 10-minute retry. Otherwise record a deviation; a required verifier stays `in_progress`. An implementation executor failure may block its step. |
| 3 | Contract missing or malformed | The Claude wrapper has already retried exactly once. For Codex or Grok, retry once with a strict contract reminder. If the bounded retry still fails, record the deviation and keep any required verification lane `in_progress`. |
| 4 | Grok binary absent | A Grok implementation dispatch is unavailable. A required Grok verify lane remains `in_progress` with a deviation; never replace it with Claude or Codex. |

Verdict handling is family-independent:

- `PASS`: persist it; attempt `done` only if the full owner row passes.
- `FINDINGS`: persist it, fix every finding, and re-run the full row.
- `FAIL`: persist it, fix the failure, and re-run the full row.

After three non-converging fix-and-reverify rounds, or immediately when
a finding exposes a genuine design decision, pause and surface the
state. This convergence guard is distinct from the one malformed-output
retry.

## Explicit non-goals

- Never invoke an executor CLI directly; wrappers only.
- Callers do not pass model-selection flags to wrappers. They persist
  the actual model and effort in dispatch state; wrapper internals own
  their CLI model flags.
- Never accept a same-family self-verdict outside the owner matrix.
- Never maintain HMAC receipts, sidecars, or digest agents. The parsed
  contract and durable progress records are the boundary.
- Never infer `verifying` from memory when disk dispatch state exists.

## Interaction with other skills

- `engineering-discipline` is injected into every implementation
  prompt.
- `persistent-plans` owns schema-valid `progress.json` state;
  this skill uses `start-step`, `record-lane-dispatch`,
  `record-verdict`, and `set-step-status`.
- `writing-plans` produces the immutable step block.
- `conductor` selects the owner, launches the wrappers, and applies the
  matrix without exceptions.
