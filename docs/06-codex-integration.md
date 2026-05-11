# 06 — Codex integration

Codex (`codex exec` CLI) is v2's implementation and verification
backend. The conductor never invokes `codex` directly; it goes
through one of two **direction-locked wrapper scripts** that pin the
system prompt, the deterministic-output flag, and the response
shape Codex must return.

This document specifies the wrappers, the prompt contract, and the
parsing rules. It explicitly does **not** specify receipts, sidecars,
or digesters — v2 has none of those.

## Why wrappers, not direct invocation

v1 let the conductor build Codex prompts ad-hoc. Two failure modes
followed:

1. The conductor occasionally asked Codex to *verify* a step that
   was supposed to be *implemented*, and vice versa. Codex would
   comply with whichever instruction landed last in the prompt,
   producing a step that looked done but wasn't.
2. Codex's output shape drifted across calls, so the conductor had
   to read raw stdout (or invoke a digester) to figure out what
   happened.

v2 fixes both by:

- Splitting impl and verify into two separate scripts. The script
  name is the source of truth for direction; nothing in the prompt
  body can override it.
- Pinning a single Summary / Verdict / Findings contract block at
  the **end** of every Codex response. The conductor parses that
  block and ignores anything before it.

## The two wrappers

### `run-codex-impl.sh`

Invoked when a plan step has `owner: codex-impl`.

**Inputs** (CLI args + stdin):
- `--plan-id <planId>` — for log filenames.
- `--step-id <stepId>` — for log filenames.
- `--root-dir <path>` — project root Codex should operate in.
- Stdin: the rendered step block (description, acceptance criteria,
  file list, progress checklist).

**Behavior**:
1. Builds a system prompt that fixes the direction to
   **IMPLEMENT**, references `engineering-discipline` and (if
   present) the step's specified `skill`, and ends with the contract
   block specification.
2. Invokes `codex exec` with `-o <deterministic-output-flag>` so the
   model is run in low-temperature, single-response mode.
3. Streams stdout to a log file (`.temp/plan-mode/active/<planId>/logs/codex-impl-<stepId>.log`)
   for post-hoc debugging.
4. Extracts the trailing contract block (see parsing below) and
   prints it as the script's stdout — that is the only thing the
   conductor reads.
5. Exits non-zero if no contract block is present.

### `run-codex-verify.sh`

Invoked after any step (regardless of impl owner) to confirm
acceptance criteria.

**Inputs**: same CLI args as impl, plus the **diff** of the changes
to verify (passed via stdin or referenced by path).

**Behavior**:
1. Builds a system prompt that fixes the direction to **VERIFY**,
   forbids any code edits, and references the step's acceptance
   criteria.
2. Invokes `codex exec` with `-o` as above.
3. Streams stdout to `codex-verify-<stepId>.log`.
4. Extracts and emits the contract block.
5. Exits non-zero on missing contract block.

The verify wrapper has **no `--root-dir`** write permissions in
mind — even though Codex is technically capable of editing files, the
verify prompt instructs it not to, and any diff produced by a verify
call is treated as a bug.

## The prompt contract

Every Codex response must end with this block (exact shape):

```
=== ORCHESTRATION-CONTRACT ===
Summary: <one paragraph, at most 6 sentences, plain prose>
Verdict: PASS | FINDINGS | FAIL
Findings:
- <one-line finding>
- <one-line finding>
FilesTouched:
- <path>
- <path>
=== END-CONTRACT ===
```

Rules:

- The sentinel lines `=== ORCHESTRATION-CONTRACT ===` and
  `=== END-CONTRACT ===` are exact. The parser matches on them
  literally.
- **Verdict** is one of three tokens: `PASS`, `FINDINGS`, `FAIL`.
- **Findings** is omitted-or-empty on `PASS`. On `FINDINGS` it lists
  non-blocking concerns. On `FAIL` it lists what's missing.
- **FilesTouched** lists every file written by the impl wrapper (and
  is empty for verify).
- Any text Codex emits **before** the opening sentinel is ignored by
  the conductor. Codex is encouraged to reason out loud above the
  block (it improves quality), but only the block is authoritative.

The wrappers append a final line to the prompt enforcing this:

> Your final output **must** end with the contract block in the
> exact shape specified. Do not omit any field. Do not emit anything
> after `=== END-CONTRACT ===`.

## Parsing rules

The conductor (via the `codex-dispatch` skill) parses Codex output
as follows:

1. Read script stdout (already trimmed by the wrapper to just the
   contract block; the wrapper handles the find-the-sentinels step).
2. Match the contract block. If absent, the wrapper has exited
   non-zero; the conductor surfaces the failure.
3. Parse the four fields with a simple regex per field. The parser
   is forgiving on whitespace and Markdown list markers but strict
   on the field labels and the verdict token.
4. Construct a `ProgressEntry`:
   ```json
   {
     "verdict": "PASS|FINDINGS|FAIL",
     "summary": "<one paragraph>",
     "findings": ["...", "..."],
     "filesTouched": ["..."]
   }
   ```
5. Write it into `progress.json` under the step ID.

If parsing fails (malformed verdict, missing sentinel after the
wrapper passed it through), the conductor treats the step as
`blocked` with reason `contract-parse-failed` and surfaces the raw
parser error to the user — **not** the raw Codex output.

## What v2 explicitly does NOT do

- **No `codex-receipt-step-N.json`.** The contract block is the
  receipt.
- **No HMAC sidecars.** There is no adversary in the threat model
  who can tamper with Codex output but not with `progress.json`
  itself; signing one without the other is theater.
- **No `claude-review-step-N.md`.** If the conductor wants a human
  review of a step's diff, it dispatches a sub-agent to summarize the
  diff into a bounded message. That message is not persisted as a
  named artifact.
- **No `lbyl-digest` sub-agent.** Codex output is already bounded by
  the contract; the digester existed to bound it twice.
- **No `--model` flag plumbed through user-visible config.** The
  wrappers pin the model. Changing it is a wrapper change.

## Direction lock in detail

Inside each wrapper, the system prompt opens with a literal direction
header that cannot be overridden by the per-call prompt:

```
You are Codex running in IMPLEMENT mode for the
orchestration plugin. You will edit files in <root-dir> to satisfy
the step described below. You may not change tests in a way that
hides failures. You must finish with the contract block.
```

or:

```
You are Codex running in VERIFY mode for the orchestration
plugin. You may read files and the provided diff. You may NOT edit
files. You must finish with the contract block. Your verdict is
PASS only if every acceptance criterion is met by the diff.
```

The conductor cannot, by passing extra prompt text, flip an
implementer into a verifier or vice versa. The script's identity is
the direction.

## Failure handling

- **Wrapper exits non-zero (no contract block)** → conductor retries
  exactly once with a stricter reminder. Second failure → step
  becomes `blocked`.
- **Codex returns FAIL** → conductor surfaces findings; does not
  auto-retry.
- **Codex returns FINDINGS** → step is `done` with the findings
  recorded; conductor surfaces them.
- **Codex edits files during verify** → bug. Conductor reports and
  refuses the verdict.

Logs (`.temp/plan-mode/active/<planId>/logs/`) are for human
debugging only. The conductor never reads them as part of
orchestration. They are pruned when the plan archives.
