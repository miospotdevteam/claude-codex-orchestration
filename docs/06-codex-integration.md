# 06 — Codex integration

Codex (`codex exec` CLI) is v2's implementation and verification
backend. The conductor never invokes `codex` directly; it goes
through one of two **direction-locked wrapper scripts** that pin the
system prompt, the invocation flags, and the response shape Codex
must return.

This document specifies the wrappers, the prompt contract, and the
parsing rules. It explicitly does **not** specify receipts, sidecars,
or digesters — v2 has none of those.

Scope note: this document specifies the Codex lane; the Grok lane is
specified in `docs/10-grok-integration.md`, and cross-family verification
policy lives in `docs/09-routing-matrix.md`.

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
  the **end** of every Codex response. The wrapper parses that block
  internally and hands the conductor only the resulting JSON; nothing
  before the block reaches the conductor.

## The two wrappers

Both wrappers live at `orchestration/scripts/run-codex-impl.sh` and
`orchestration/scripts/run-codex-verify.sh`; the short names below
refer to those paths.

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
   present) the step's specified `skill`, and embeds the **full
   contract template** verbatim so Codex has the exact block to
   reproduce.
2. Invokes `codex exec -C <root-dir> -s workspace-write
   --skip-git-repo-check -o <last-message-file>` with the prompt on
   stdin. No determinism or temperature flag is passed; `-o` is
   Codex's own output-last-message file, where the model's final
   message is written for the wrapper to parse.
3. Captures Codex's stdout and stderr in separate files and writes a
   merged copy to a log file
   (`.temp/plan-mode/active/<planId>/logs/codex-impl-<stepId>.log`)
   for post-hoc human debugging.
4. Parses the `-o` last-message file with `orchestration/scripts/parse-contract.sh`
   (falling back to the isolated stdout capture when that file is
   empty) and prints only the parsed JSON as the script's stdout —
   that is the only thing the conductor reads.
5. Exits `2` if `codex` exits non-zero, and `3` if the contract does
   not parse.

### `run-codex-verify.sh`

Invoked after any step (regardless of impl owner) to confirm
acceptance criteria.

**Inputs**: same CLI args as impl, plus the **diff** of the changes
to verify (passed via stdin or referenced by path).

**Behavior**:
1. Builds a system prompt that fixes the direction to **VERIFY**,
   forbids any code edits, embeds the step block, skill, and diff,
   and prints the contract template inline.
2. Invokes `codex exec -C <root-dir> -s read-only
   --skip-git-repo-check -o <last-message-file>` — read-only mode,
   same output-last-message file as impl, no determinism flag.
3. Captures stdout and stderr separately and writes a merged copy to
   `codex-verify-<stepId>.log`.
4. Parses the `-o` last-message file (falling back to the isolated
   stdout capture when empty) and emits only the parsed JSON.
5. Exits `2` if `codex` exits non-zero, and `3` if the contract does
   not parse.

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
  the parser (which keys on the last contract block). Codex is
  encouraged to reason out loud above the block (it improves
  quality), but only the block is authoritative.

The wrappers append a final line to the prompt enforcing this:

> Your final output **must** end with the contract block in the
> exact shape specified. Do not omit any field. Do not emit anything
> after `=== END-CONTRACT ===`.

## Parsing rules

Parsing happens **inside the wrapper**, not in the conductor. Each
wrapper feeds Codex's output-last-message file (or, when that file is
empty, its isolated stdout capture) to `orchestration/scripts/parse-contract.sh`,
which finds the sentinels, validates the fields, and emits a single
line of JSON. The conductor never regex-parses raw Codex output — it
only ever sees the JSON the wrapper printed.

`parse-contract.sh` locates the **last** `=== ORCHESTRATION-CONTRACT
===` … `=== END-CONTRACT ===` block, is forgiving on whitespace and
Markdown list markers but strict on the field labels and the verdict
token, rejects any trailing non-whitespace after the closing
sentinel, and prints exactly:

```json
{"summary":"<one paragraph>","verdict":"PASS|FINDINGS|FAIL","findings":["...","..."],"filesTouched":["...","..."]}
```

The conductor (via the `codex-dispatch` skill) reads that JSON
directly and records it into `progress.json` under the step ID.

If the parse fails the wrapper exits `3` and prints the parser's
error to stderr; the conductor treats the step as `blocked` with
reason `contract-parse-failed` and surfaces that parser error to the
user — **not** the raw Codex output.

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
  Codex wrappers pass no model flag at all; `codex exec` uses its own
  configured default. Changing the model is a wrapper change, never a
  per-call knob.

## Computer use

The Codex lane carries **computer use**, and the conductor routes tasks
Claude cannot complete with its own tool surface to Codex for that
reason.

- **The capability, and its basis.** The Codex CLI's machine config
  ships an `mcp_servers.computer-use` entry — an MCP server that gives
  Codex control of macOS desktop apps — alongside browser-use backends
  (Chrome and an in-app browser). These tools are available inside every
  `codex exec` session with **no extra flags**, including the sessions
  the plugin's wrappers spawn. No wrapper flag turns them on or off; the
  capability comes from the machine config, not from anything
  `run-codex-impl.sh` passes. Codex's own guidance prefers its Chrome
  plugin over Computer Use for browser work, so browser-only tasks are
  not what this lane is for — they stay wherever the routing matrix
  already routes them (`docs/09-routing-matrix.md`).
- **IMPL lane only.** A computer-use step is always an `owner:
  codex-impl` step. It must never be a verify dispatch. The verify
  wrapper runs `codex exec -s read-only`, whose sandbox constrains
  *file writes* — it does **not** constrain *desktop side effects*. A
  read-only verifier can still click buttons, drive Finder, or send
  messages in a native app, so asking a verifier to drive the GUI would
  produce unbounded side effects the sandbox was never designed to hold.
  Keep GUI-driving work on the implementation lane, where side effects
  are expected.
- **Graceful degradation.** If a machine lacks the computer-use MCP
  server, Codex simply has no such tools — there is nothing to enable
  and no flag to add. When Codex reports the tools are unavailable, the
  step should be **re-routed `manual`** rather than retried: retrying
  cannot conjure a server the machine does not have.
- **Explicit goal and completion criteria.** Because the conductor
  cannot observe the screen, a computer-use step's block MUST state the
  GUI goal and its completion criteria explicitly. "Open Settings and
  toggle X, then confirm the toggle reads On" is checkable from the
  contract block; "fix the desktop app" is not. The block is the only
  channel through which the conductor knows whether the GUI work
  succeeded.

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

- **Wrapper exits `3` (contract missing or malformed)** → the
  wrapper does not retry; the **conductor** retries exactly once with
  a stricter reminder. Second failure → step becomes `blocked`.
- **Wrapper exits `2` (`codex` itself exited non-zero)** → conductor
  surfaces the failure and the merged log path; step becomes
  `blocked`.
- **Codex returns FAIL** → conductor surfaces findings; does not
  auto-retry.
- **Codex returns FINDINGS** → step is `done` with the findings
  recorded; conductor surfaces them.
- **Codex edits files during verify** → bug. Conductor reports and
  refuses the verdict.

Logs (`.temp/plan-mode/active/<planId>/logs/`) are for human
debugging only. The conductor never reads them as part of
orchestration. They are pruned when the plan archives.
