---
name: codex-dispatch
description: >-
  Invoke Codex and Grok through the plugin's direction-locked wrappers and parse the bounded Summary / Verdict / Findings contract. Use for Codex/Grok implementation and for the wrapper portion of the active profile's all-pass verifier gate. Under fable-primary the conductor adds an independent Fable verifier; under codex-primary the Codex-native dispatch body applies. Never read raw wrapper output or bypass the wrappers.
allowed-tools: Read, Bash, Edit, Write
---

# codex-dispatch

This skill owns every external implementation dispatch and every
direction-locked verification dispatch. The conductor never invokes
`codex exec`, `grok`, or a headless Claude verifier directly; it invokes
the plugin wrappers and reads only the parsed Summary / Verdict /
Findings / FilesTouched JSON.

## Hard rule: the frozen routing profile determines verification

For every profiled implementation step, dispatch the complete verifier set
over the same fixed diff:

| Routing profile | Required verifier lanes |
|---|---|
| `codex-primary` | Codex wrapper + Grok wrapper |
| `fable-primary` | Codex wrapper + Grok wrapper + independent `Agent(model: "fable")` |

Manual steps are verifier-exempt. Unprofiled legacy plans retain the schema's
owner matrix: `claude-impl` requires Codex+Grok, `codex-impl` requires
Claude+Grok, and `grok-impl` requires Codex only.

- A step reaches `done` only after every profile-required lane (or every lane
  in its legacy owner row) has a current `PASS`.
- A `FINDINGS` or `FAIL` from any required lane invalidates the other
  lanes' earlier PASS records. Fix the implementation, then dispatch
  and record every required verifier again. Never
  reuse a sibling PASS from before the fix.
- The former `--degraded` completion flag is removed. Passing it is an
  error, and there is no fallback verifier or single-lane done path for
  an implementation step.

The immutable profile, not conversational state, is the gate source of truth.

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
implementation volume does not change the frozen profile gate.

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
  verifier required by its profile or legacy owner row.
- The conductor needs a bounded out-of-band review or a G3 milestone
  message draft: use the appropriate read-only verify wrapper with a
  synthetic plan and step id.

It does not fire for implementing `claude-impl` or `manual` steps,
free-form chat, or calls that bypass the wrappers.

## Wrapper inventory and direction lock

This skill owns two IMPLEMENT wrappers and three VERIFY wrappers:

| Wrapper | Direction | Mutation policy |
|---|---|---|
| `run-codex-impl.sh` | IMPLEMENT | may edit |
| `run-grok-impl.sh` | IMPLEMENT | may edit |
| `run-codex-verify.sh` | VERIFY | read-only Codex sandbox |
| `run-grok-verify.sh` | VERIFY | write, edit, and shell denied |
| `run-claude-verify.sh` | VERIFY | legacy owner-matrix compatibility; write and command tools denied |

The Fable conductor adds the third `Agent(model: "fable")` verifier. The step
is done only when Codex, Grok, and Fable have all returned PASS.

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

For example, a legacy `codex-impl` verification persists and launches its
Claude and Grok lanes. Profiled plans use the same sequence for every lane in
their frozen verifier set:

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

Always go through `plan-utils.sh`. Atomic writes; no jq one-offs.
Every verify verdict is recorded with its lane (`codex`, `grok`, or `claude`)
so the profile gate has per-lane records to check:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" record-verdict \
  "$PLAN_DIR" "$STEP_ID" \
  "$CODEX_VERDICT" "$CODEX_SUMMARY" "$CODEX_FINDINGS_JSON" "$CODEX_FILES_JSON" codex
"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" record-verdict \
  "$PLAN_DIR" "$STEP_ID" \
  "$GROK_VERDICT" "$GROK_SUMMARY" "$GROK_FINDINGS_JSON" "$GROK_FILES_JSON" grok
"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" record-verdict \
  "$PLAN_DIR" "$STEP_ID" \
  "$FABLE_VERDICT" "$FABLE_SUMMARY" "$FABLE_FINDINGS_JSON" "$FABLE_FILES_JSON" claude

# The conductor also records the Fable result with lane `claude`.
# Then flip status — the done gate enforces the plan's routingProfile.
# FINDINGS or FAIL from ANY lane keeps the step in_progress and triggers fix +
# re-verify of all profile-required reviewers; pause only after
# three non-converging iterations or a genuine design question.
if [[ "$ALL_REQUIRED_VERDICTS_PASS" == true ]]; then
  "${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" \
    set-step-status "$PLAN_DIR" "$STEP_ID" done
fi
# On FINDINGS/FAIL: the step is already in_progress from its
# dispatch-time start-step; re-dispatch the fix-up through start-step
# (fresh dispatch record) — never a bare set-step-status flip.
```

Only after every profile-required lane, or every lane in a legacy owner row,
has a current PASS may the
conductor attempt:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" set-step-status \
  "$PLAN_DIR" "$STEP_ID" done
```

The helper reads `routingProfile` from the immutable plan and falls back to
the schema's machine-readable owner matrix only for unprofiled legacy plans.
It refuses an incomplete gate. A required lane outage remains `in_progress`
with a deviation; it never becomes a degraded completion.

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
| 0 | Contract block parsed | Read JSON, record verdict |
| 1 | Bad invocation (missing args, etc.) | Bug in this skill — fix |
| 2 | executor CLI invocation failed (`codex exec` or `grok`) | Step → `blocked` with reason `executor-unavailable`; surface. Exit 4 (the `grok` binary not on PATH) is a distinct case — see the next row. |
| 3 | Contract block missing or malformed | Retry exactly once with a stricter reminder. A second failure blocks the step/profile gate with reason `contract-parse-failed`; never shrink the reviewer set. |
| 4 | `grok` binary not on PATH (Grok wrapper only) | Block with reason `grok-unavailable`; Grok is required by both profiles. |

Verdict handling is family-independent:

- `PASS`: persist it; attempt `done` only if the full required set passes.
- `FINDINGS`: persist it, fix every finding, and re-run the full required set.
- `FAIL`: persist it, fix the failure, and re-run the full required set.

After three non-converging fix-and-reverify rounds, or immediately when
a finding exposes a genuine design decision, pause and surface the
state. This convergence guard is distinct from the one malformed-output
retry.

- It does not invoke `codex exec` or `grok` directly. Wrappers only.
- It does not pass `--model` / `-m` to anything, on either lane.
  Callers never pass a model to either wrapper pair. They pass a bounded
  scenario enum; Codex maps it to the allowed effort internally and Grok pins
  `-m grok-4.5` in-script. The model is the wrapper's identity, never
  the caller's choice.
- It does not write its own prompts to Codex outside the rendered
  step block — the direction header is part of the wrapper, not the
  caller's responsibility.
- It does not maintain receipts or HMAC sidecars. The bounded contract and
  durable lane record are the receipt.

## Interaction with other skills

- `engineering-discipline` is injected into every implementation
  prompt.
- `persistent-plans` owns schema-valid `progress.json` state;
  this skill uses `start-step`, `record-lane-dispatch`,
  `record-verdict`, and `set-step-status`.
- `writing-plans` produces the immutable step block.
- `conductor` selects the owner, launches the required verifier set, and
  applies the frozen profile or legacy matrix without exceptions.
