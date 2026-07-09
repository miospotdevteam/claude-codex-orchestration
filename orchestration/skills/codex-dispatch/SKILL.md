---
name: codex-dispatch
description: Invoke Codex and Grok through the plugin's direction-locked wrappers (`${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-impl.sh` / `run-codex-verify.sh`, `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-impl.sh` / `run-grok-verify.sh`) and parse the bounded Summary / Verdict / Findings contract block. Use whenever a plan step with `owner: codex-impl` or `owner: grok-impl` is on the frontier, for every verification dispatch (cross-family policy: `codex-impl` verified by Grok when the Grok lane is configured; `grok-impl` / `claude-impl` verified by Codex), or when the conductor needs an out-of-band check. The wrapper's identity locks the direction (impl vs verify); never read raw Codex or Grok output — only the JSON emitted by `${CLAUDE_PLUGIN_ROOT}/scripts/parse-contract.sh` that the wrapper prints. Do NOT use for implementing `claude-impl` / `manual` steps (verifying finished `claude-impl` work does go through here), for free-form conversation, or for any Codex or Grok call that bypasses the wrappers.
allowed-tools: Read, Bash, Edit, Write
---

# codex-dispatch

The skill that owns every Codex and Grok interaction. v2's central rule
is that the conductor never invokes `codex exec` or `grok` directly —
it goes through one of the direction-locked wrappers whose script
identity is the source of truth for the direction (IMPLEMENT vs
VERIFY). Anything outside this contract is a correctness hazard.

## Hard rule: verification is cross-family and Claude-session-dispatched

**Every implementation step gets a Claude-session-dispatched verify
whose model family differs from the implementer's. The verifier
wrapper never calls the bridge directly.**

The cross-family policy:

- `codex-impl` steps are verified via
  `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-verify.sh` when the Grok lane
  is configured; the implementer is Codex, so the verifier is Grok.
- `grok-impl` and `claude-impl` steps are verified via
  `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh`; the implementer
  is Grok or Claude, so the verifier is Codex.
- The invariant: the verifier is always a **different model family**
  than the implementer.
- If a grok wrapper exits 4 (the grok binary is unavailable), fall
  back to `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh` and note
  the fallback in the step's `progress.json` `deviations`.

BRIDGE-DISABLED (2026-05-24): Anthropic disabled the legacy
`claude-bridge` MCP call-back tools (`verify_step`,
`frontend_implement`, `attack_plan`). The contract is:

1. The verifier (Codex or Grok) emits the bounded contract block
   parseable by `${CLAUDE_PLUGIN_ROOT}/scripts/parse-contract.sh`
   (Summary / Verdict / Findings / FilesTouched).
2. The conductor (Claude) dispatches the cross-family verify wrapper
   through this skill to verify the step.
3. The conductor reads only the parsed JSON from the wrapper; it
   never reads raw wrapper stdout, and neither Codex nor Grok reaches
   back into Claude through a bridge tool.

If a plan step, prose template, or sub-agent prompt tries to make
Codex or Grok call `verify_step`, `frontend_implement`, or
`attack_plan`, that is a bug — re-render the prompt to use the
contract-block flow instead.

## When this fires

- A plan step with `owner: "codex-impl"` reaches the runnable
  frontier → use `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-impl.sh`.
- A plan step with `owner: "grok-impl"` reaches the runnable
  frontier → use `${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-impl.sh`.
- A step (any owner) has been implemented and needs verification →
  use the cross-family verify wrapper (`run-grok-verify.sh` for
  `codex-impl` when the Grok lane is configured; otherwise
  `run-codex-verify.sh`).
- The conductor needs an out-of-band Codex check (rare; e.g. a quick
  sanity scan before approving a plan) → use the verify wrapper with
  a synthetic step block.

It does **not** fire for:

- **Implementing** steps with `owner: "claude-impl"` or `"manual"` —
  those are executed outside this skill. **Verifying** finished
  `claude-impl` work *does* fire this skill, via
  `run-codex-verify.sh` per the cross-family policy.
- Free-form chat without a plan step backing the call.
- Codex or Grok invocations that bypass the wrappers — those are bugs
  in this skill's caller.

## Wrapper selection

This skill owns **both** direction-locked wrapper lanes — Codex and
Grok. There is no tenth skill for Grok: the v2 catalog stays at nine,
and `codex-dispatch` is the single wrapper-dispatch authority for
every off-context executor and verifier.

| Step state | Wrapper | Direction |
|---|---|---|
| `owner: codex-impl`, status `pending` → `in_progress` | `run-codex-impl.sh` | IMPLEMENT |
| `owner: grok-impl`, status `pending` → `in_progress` | `run-grok-impl.sh` | IMPLEMENT |
| `codex-impl` impl needs verification, **Grok lane configured** | `run-grok-verify.sh` | VERIFY |
| `codex-impl` impl needs verification, Grok lane not configured | `run-codex-verify.sh` | VERIFY |
| `grok-impl` impl needs verification | `run-codex-verify.sh` | VERIFY |
| `owner: claude-impl` step needs verification after Claude finishes | `run-codex-verify.sh` | VERIFY |

Verification is **cross-family** (see `docs/09-routing-matrix.md`): the
verifier is a different model family than the implementer. When the
Grok lane is configured (the `grok` CLI is installed and
authenticated), `codex-impl` steps are verified via
`run-grok-verify.sh`; `grok-impl` and `claude-impl` steps are verified
via `run-codex-verify.sh`.

The wrappers are direction-locked: the prompt body cannot flip a
verifier into an implementer. Choosing the right wrapper — direction
*and* family — is this skill's only directional decision.

### Calling conventions are identical across families

The Grok wrappers take the **identical CLI shape** as the Codex ones:
`--plan-id` / `--step-id` / `--root-dir` / `--skill`, the rendered step
block on stdin, and — for verify — the diff via `--diff-file <path>`
or after a `---DIFF---` sentinel on stdin. They emit the **same** parsed
contract JSON (`summary` / `verdict` / `findings` / `filesTouched`).
Only the underlying CLI differs (`grok` vs `codex exec`); everything
above the wrapper boundary is the same. Every invocation example below
that names a `run-codex-*.sh` script applies verbatim to its
`run-grok-*.sh` counterpart — swap the script name, keep the flags.

## Rendering the step block

The wrappers read the step block from stdin (see each script's
header). The block is plain prose, not JSON. The conductor renders it
from `plan.json` fields:

```
# Step <step-id>: <step.title>

## Description
<step.description>

## Acceptance criteria
- <acceptanceCriteria[0]>
- <acceptanceCriteria[1]>
- ...

## Files (expected)
- <files[0]>
- <files[1]>

## Progress checklist
1. <progress[0]>
2. <progress[1]>
...
```

For verify calls, append the diff after a `---DIFF---` sentinel line,
or pass `--diff-file <path>` (see the `run-codex-verify.sh` /
`run-grok-verify.sh` headers — both use the same convention).

## Calling the wrappers (the exact invocation)

The conductor invokes the wrappers via the `Bash` tool. All paths
resolve through `${CLAUDE_PLUGIN_ROOT}` — Claude Code substitutes
this at runtime to the plugin's installed location (typically
`~/.claude/plugins/marketplaces/claude-codex-orchestration/orchestration`).
Do **not** hard-code an absolute path; the env var is the contract.

### IMPLEMENT call (codex-impl steps)

```bash
PLAN_DIR='.temp/plan-mode/active/<planId>'
STEP_ID='step-N'
ROOT_DIR="$(pwd)"   # the project the user is working in, not the plugin root
SKILL='test-driven-development'  # optional; only if step.skill is set

render_step_block | "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-impl.sh" \
  --plan-id "<planId>" \
  --step-id "$STEP_ID" \
  --root-dir "$ROOT_DIR" \
  --skill "$SKILL"
```

`render_step_block` is whatever produces the prose block above; in
practice the conductor builds it inline with `jq` reads from
`plan.json` and pipes the heredoc-formatted result.

The wrapper's stdout on success is **only** the parsed contract JSON.
Capture it with command substitution:

```bash
RESULT_JSON="$(render_step_block | "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-impl.sh" \
  --plan-id "<planId>" \
  --step-id "$STEP_ID" \
  --root-dir "$ROOT_DIR" \
  --skill "$SKILL")"

VERDICT="$(jq -r .verdict   <<<"$RESULT_JSON")"
SUMMARY="$(jq -r .summary   <<<"$RESULT_JSON")"
FINDINGS_JSON="$(jq -c .findings <<<"$RESULT_JSON")"
FILES_JSON="$(jq -c .filesTouched <<<"$RESULT_JSON")"
```

### VERIFY call (after any impl finishes)

Two ways to pass the diff. Pick whichever fits:

**A) diff in a file** — preferred when the diff is large or you
already have it on disk:

```bash
DIFF_FILE='/tmp/step-N.diff'   # however you produced it

render_step_block | "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh" \
  --plan-id "<planId>" \
  --step-id "$STEP_ID" \
  --root-dir "$ROOT_DIR" \
  --diff-file "$DIFF_FILE"
```

**B) diff on stdin after a `---DIFF---` sentinel** — fine when
inlining is easier:

```bash
{
  render_step_block
  printf '\n---DIFF---\n'
  cat "$DIFF_FILE"
} | "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh" \
    --plan-id "<planId>" \
    --step-id "$STEP_ID" \
    --root-dir "$ROOT_DIR"
```

### After the call — write the verdict back

Always go through `plan-utils.sh`. Atomic writes; no jq one-offs:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" record-verdict \
  "$PLAN_DIR" "$STEP_ID" \
  "$VERDICT" "$SUMMARY" "$FINDINGS_JSON" "$FILES_JSON"

# Then flip status — done on PASS/FINDINGS, in_progress/blocked on FAIL.
case "$VERDICT" in
  PASS|FINDINGS)
    "${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" \
      set-step-status "$PLAN_DIR" "$STEP_ID" done ;;
  FAIL)
    "${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" \
      set-step-status "$PLAN_DIR" "$STEP_ID" blocked ;;
esac
```

After every status change, recompute the frontier with
`plan-utils.sh compute-frontier "$PLAN_DIR"` and dispatch the next
batch.

## Parallel dispatch with the file-overlap guard

The conductor computes the runnable frontier via
`${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh compute-frontier`. The default is to dispatch
**every step on the frontier in parallel**: one assistant message
with N Bash tool calls (or N background commands), one per step.

Before dispatching in parallel, check for file overlap:

```bash
# Pseudocode the conductor runs:
for each pair of frontier steps (A, B):
    if intersection(A.files, B.files) is non-empty:
        serialize A and B (do A first, then B)
```

Overlapping edits by concurrent agents are a correctness bug. The cost
of one extra round-trip is cheap insurance. This serialization rule
covers all four wrappers — `run-codex-impl.sh`, `run-codex-verify.sh`,
`run-grok-impl.sh`, and `run-grok-verify.sh` — regardless of which
family a given step is dispatched to; two frontier steps that touch the
same file are serialized even when one runs on Codex and the other on
Grok.

Resource cap: the conductor limits parallel dispatch to ~4 steps at a
time, even if the frontier is wider. This keeps the harness responsive
and the user's mental model legible.

## Reading the result

Each wrapper emits **one** thing to stdout on success: the JSON
output of `${CLAUDE_PLUGIN_ROOT}/scripts/parse-contract.sh`, shaped
like:

```json
{
  "summary": "...",
  "verdict": "PASS" | "FINDINGS" | "FAIL",
  "findings": ["...", "..."],
  "filesTouched": ["src/foo.ts", "src/foo.test.ts"]
}
```

Read this JSON. Write it into `progress.json` via the plan-utils
helper (full bash example in "Calling the wrappers" above):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/plan-utils.sh" record-verdict \
  "$PLAN_DIR" "$STEP_ID" \
  "$VERDICT" "$SUMMARY" "$FINDINGS_JSON" "$FILES_JSON"
```

Then call `set-step-status` to flip the step to `done` (PASS /
FINDINGS) or `blocked` (FAIL after retry).

## The hard rule: never read raw stdout

The conductor does not read the executor's raw stream — Codex or Grok.
Period.

- Raw stream goes to `.temp/plan-mode/active/<planId>/logs/`, one log
  per dispatch: `codex-impl-<stepId>.log` / `codex-verify-<stepId>.log`
  for the Codex lane, `grok-impl-<stepId>.log` /
  `grok-verify-<stepId>.log` for the Grok lane.
- The log file is for human debugging after the fact.
- If the parsed JSON is missing information you need, the answer is
  to amend the step's `description` so Codex returns it next time,
  **not** to start reading the log.

The bound is the prompt contract. The contract is enforced by the
wrapper. Reading the log defeats the boundary.

## Failure handling

| Wrapper exit code | Meaning | Conductor action |
|---|---|---|
| 0 | Contract block parsed | Read JSON, record verdict |
| 1 | Bad invocation (missing args, etc.) | Bug in this skill — fix |
| 2 | `codex exec` itself failed | Step → `blocked` with reason `codex-unavailable`; surface |
| 3 | Contract block missing or malformed | **Retry exactly once** with a stricter reminder appended to the step block. Second failure → step `blocked` with reason `contract-parse-failed` |
| 4 | `grok` binary not on PATH (Grok wrapper only) | **Verify dispatch** (`run-grok-verify.sh`): re-dispatch the verification via `run-codex-verify.sh` — the pre-Grok fallback — and record the fallback in the step's `progress.json` `deviations`. **Impl dispatch** (`run-grok-impl.sh`): flip the step `blocked` with reason `grok-unavailable`; surface |

Codex verdict handling:

- **PASS** — record and mark step `done`.
- **FINDINGS** — record (with findings array), mark step `done`,
  surface findings to the user.
- **FAIL** — record, mark step `in_progress` (one retry) or
  `blocked`. **Do not auto-retry indefinitely.** Surface findings,
  ask the user how to proceed.

## What this skill explicitly does not do

- It does not invoke `codex exec` or `grok` directly. Wrappers only.
- It does not pass `--model` / `-m` to anything, on either lane.
  Callers never pass a model to either wrapper pair: the Codex wrappers
  pass no flag and run the machine default; the Grok wrappers pin
  `-m grok-build` in-script (see `docs/06-codex-integration.md` and
  the model-selection doctrine in `docs/09-routing-matrix.md`).
- It does not write its own prompts to Codex outside the rendered
  step block — the direction header is part of the wrapper, not the
  caller's responsibility.
- It does not maintain receipts, HMAC sidecars, or `claude-review-*`
  artifacts. None of those exist in v2. The contract block is the
  receipt.

## Interaction with other skills

- `engineering-discipline` — injected by name into every IMPLEMENT
  prompt. The executor honors it.
- `persistent-plans` — owns the writes back into `progress.json`;
  this skill calls its helpers (`record-verdict`, `set-step-status`).
- `writing-plans` — produces the step block this skill renders.
- `conductor` — the orchestrator that selects this skill on every
  frontier dispatch.

## Failure surface

- **Direction confusion** — picking
  `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-impl.sh` for a verification
  call would produce edits where the conductor expected a read-only
  check. The script identity prevents this from being possible if the
  wrappers are chosen by `step.owner`, not by prompt content.
- **Skipped file-overlap guard** — two parallel steps both edit
  `src/auth/session.ts`. The second commit silently overwrites the
  first. Always check overlap before parallelizing.
- **Reading the log** — the conductor opens
  `codex-impl-step-3.log` "just to see what happened". The context
  budget blows immediately and the conductor starts orchestrating
  from raw Codex prose. Don't.
- **Auto-retry on FAIL** — looping FAIL → retry → FAIL hides a real
  problem. One retry on parse failure (different cause). Zero
  automatic retries on `Verdict: FAIL`. Surface and ask.
