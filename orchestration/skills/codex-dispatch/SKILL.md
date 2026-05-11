---
name: codex-dispatch
description: Invoke Codex through the plugin's direction-locked wrappers (`${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-impl.sh`, `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh`) and parse the bounded Summary / Verdict / Findings contract block. Use whenever a plan step with `owner: codex-impl` is on the frontier, when a step's executor needs verification, or when the conductor needs an out-of-band Codex check. The wrapper's identity locks the direction (impl vs verify); never read raw Codex stdout — only the JSON emitted by `${CLAUDE_PLUGIN_ROOT}/scripts/parse-contract.sh` that the wrapper prints. Do NOT use for `claude-impl` / `manual` steps, for free-form conversation, or for any Codex call that bypasses the wrappers.
allowed-tools: Read, Bash, Edit, Write
---

# codex-dispatch

The skill that owns every Codex interaction. v2's central rule is that
the conductor never invokes `codex exec` directly — it goes through one
of two wrappers whose script identity is the source of truth for the
direction (IMPLEMENT vs VERIFY). Anything outside this contract is a
correctness hazard.

## When this fires

- A plan step with `owner: "codex-impl"` reaches the runnable
  frontier → use `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-impl.sh`.
- A step (any owner) has been implemented and needs verification →
  use `${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh`.
- The conductor needs an out-of-band Codex check (rare; e.g. a quick
  sanity scan before approving a plan) → use the verify wrapper with
  a synthetic step block.

It does **not** fire for:

- Steps with `owner: "claude-impl"` or `"manual"`.
- Free-form chat without a plan step backing the call.
- Codex invocations that bypass the wrappers — those are bugs in this
  skill's caller.

## Wrapper selection

| Step state | Wrapper | Direction |
|---|---|---|
| `owner: codex-impl`, status `pending` → `in_progress` | `run-codex-impl.sh` | IMPLEMENT |
| Any `done` impl that wants a verifier pass | `run-codex-verify.sh` | VERIFY |
| `owner: claude-impl` step needs verification after Claude finishes | `run-codex-verify.sh` | VERIFY |

The wrappers are direction-locked: the prompt body cannot flip a
verifier into an implementer. Choosing the right wrapper is this
skill's only directional decision.

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
or pass `--diff-file <path>` (see `run-codex-verify.sh` header for
the convention).

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
of one extra round-trip is cheap insurance.

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

The conductor does not read Codex's raw stream. Period.

- Raw stream goes to `.temp/plan-mode/active/<planId>/logs/`.
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

Codex verdict handling:

- **PASS** — record and mark step `done`.
- **FINDINGS** — record (with findings array), mark step `done`,
  surface findings to the user.
- **FAIL** — record, mark step `in_progress` (one retry) or
  `blocked`. **Do not auto-retry indefinitely.** Surface findings,
  ask the user how to proceed.

## What this skill explicitly does not do

- It does not invoke `codex exec` directly. Wrappers only.
- It does not pass `--model` / `-m` to anything. The wrappers do not
  accept that flag for a reason (machine defaults; see
  `docs/06-codex-integration.md`).
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
