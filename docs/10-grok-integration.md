# 10 — Grok integration

Grok is v2's **second external executor**, sitting alongside Codex as
a peer implementation and verification backend. Its backend is the
**Grok Build CLI** (`grok`), and the conductor reaches it the same way
it reaches Codex: never directly, always through a pair of
**direction-locked wrapper scripts** that mirror the Codex pair
one-for-one. The wrappers pin the direction (IMPLEMENT vs VERIFY), the
invocation flags, and the same bounded Summary / Verdict / Findings
contract that Codex must return. If you have read
`docs/06-codex-integration.md`, you already know the shape of this
lane; this document records only what is specific to Grok.

## The contract

The Grok lane speaks the **identical contract** to the Codex lane. Every
Grok response must end with the same block, matched on the same exact
sentinels:

```
=== ORCHESTRATION-CONTRACT ===
Summary: <one paragraph, at most 6 sentences, plain prose>
Verdict: PASS | FINDINGS | FAIL
Findings:
- <one-line finding>
FilesTouched:
- <path>
=== END-CONTRACT ===
```

The wrappers hand the raw Grok log to the same `scripts/parse-contract.sh`
that parses Codex output. There is no Grok-specific parser and no
Grok-specific field. `Verdict` is one of `PASS`, `FINDINGS`, `FAIL`;
`Findings` is empty on `PASS`; `FilesTouched` is empty for verify. Text
before the opening sentinel is ignored. Because the contract is shared,
a Grok `ProgressEntry` and a Codex `ProgressEntry` are indistinguishable
downstream — the conductor treats a verdict as a verdict regardless of
which family produced it.

## The two wrappers

The direction is the **script's identity**, exactly as in the Codex
lane. Nothing in the per-call prompt can flip an implementer into a
verifier or vice versa.

### `run-grok-impl.sh`

Invoked when a plan step routes to the Grok implementation lane. It
takes `--plan-id`, `--step-id`, `--root-dir` (must be an absolute,
existing path), and optional `--skill`. It reads the rendered step
block from stdin, builds a system prompt whose first line pins the
direction to **IMPLEMENT** ("You are Grok Build running in IMPLEMENT
mode…"), always honors `engineering-discipline`, honors the
step-specific `--skill` when supplied, and appends the contract-block
enforcement line. The IMPLEMENT prose is pinned in the script and is
not overridable per call.

### `run-grok-verify.sh`

Invoked to confirm acceptance criteria against a diff. It takes the
same args plus an optional `--diff-file <path>`. Without `--diff-file`,
stdin carries the step block, then a line containing exactly
`---DIFF---`, then the diff. Its system prompt pins the direction to
**VERIFY** ("You are Grok Build running in VERIFY mode… You may NOT
edit files."), embeds the step block, skill, and diff, and prints the
contract template inline. The VERIFY prose is likewise pinned in-script.

## Exact invocation as shipped

The impl wrapper invokes:

```
grok --prompt-file <file> --cwd <root> \
  -m grok-build \
  --always-approve \
  --max-turns 40
```

The verify wrapper invokes:

```
grok --prompt-file <file> --cwd <root> \
  -m grok-build \
  --max-turns 40 \
  --deny 'Write' --deny 'Edit' --deny 'Bash'
```

The wrappers pin `-m grok-build`, the subscription's Grok 4.5-backed
coding model. This avoids config drift from the user-configurable CLI
default (`~/.grok/config.toml`) and avoids the API-credit hazard of
using the raw `grok-4.5` model id, which bills xAI API credits instead
of the subscription pool.

## Read-only enforcement

The verify wrapper's read-only guarantee rests on the **three `--deny`
rules**, not on the prompt and not on any permission mode. This was
established empirically against **grok 0.2.93 on 2026-07-09**:

- `--deny 'Write' --deny 'Edit' --deny 'Bash'` **does** block: a write
  attempt under these rules is refused.
- `--permission-mode plan` does **not** block writes. It must **never**
  be used as the read-only mechanism, and the wrapper does not use it.
- The VERIFY prompt's "You may NOT edit files" line is
  **defense-in-depth only** — a second layer behind the deny rules, not
  the primary guarantee.

Any file a verify call manages to touch is treated as a bug, exactly as
in the Codex lane.

## Log files

Each wrapper streams the full raw Grok run to a per-step log under the
active plan directory:

- `.temp/plan-mode/active/<planId>/logs/grok-impl-<stepId>.log`
- `.temp/plan-mode/active/<planId>/logs/grok-verify-<stepId>.log`

These logs are for human debugging only. The **only** thing written to
the wrapper's stdout is the parsed contract JSON; the conductor never
reads the log as part of orchestration.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Contract parsed and emitted. |
| `1` | Bad invocation (missing/invalid args). |
| `2` | `grok` exited non-zero. |
| `3` | Contract missing or malformed. |
| `4` | `grok` binary not on `PATH`. |

On exit `3`, the conductor retries exactly once with a stricter
contract reminder; a second failure blocks the step. On exit `4`, the
conductor **falls back to `run-codex-verify.sh`** for verification —
Codex covers for an absent Grok binary. This cross-family fallback is
policy, defined in `docs/09-routing-matrix.md`.

## Auth

Grok Build authenticates one of two ways:

- **`grok login`** subscription credentials. Verified working headless
  on 2026-07-09 with a grok.com login.
- **`XAI_API_KEY`** environment variable.

Grok Build requires a **SuperGrok Heavy** subscription.

## Install-time verification checklist

Run this checklist when installing or upgrading `grok`. Results recorded
below are from **grok 0.2.93 on 2026-07-09**; re-run on every upgrade.

- [x] Binary present and version check — `grok --version` → `0.2.93` ✓
- [x] Headless subscription auth via `grok login` (grok.com) ✓
- [x] Model inventory via `grok models` — `grok-build` (default),
      `grok-composer-2.5-fast` ✓
- [x] Deny-rule write-block probe — write under
      `--deny Write/Edit/Bash` refused ✓ (blocked)
- [x] `--permission-mode plan` probe — does **not** block writes ✗
      (documented hazard; do not use as the read-only mechanism)
- [x] Flags reconciliation — `--no-auto-update` is **absent** in
      0.2.93; do not use it
- [x] `grok --help` flag survey (2026-07-09): `--sandbox <PROFILE>`
      exists but profiles are undocumented/untested; `--permission-mode
      plan` probed and does **not** block writes; `--deny
      Write/Edit/Bash` probed and blocks confirmed.
- [ ] Run 4 parallel one-shot `grok -p` calls; confirm all complete
      without quota/429 errors; record wall time.
- [ ] Re-run this whole checklist on the next `grok` upgrade

## Fallback plan B

If Grok Build's contract compliance degrades, the recorded alternative
is **opencode with xAI OAuth**.
