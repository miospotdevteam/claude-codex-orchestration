# 02 — Conductor mode

The conductor is the main Claude thread the user talks to. v2's central
invariant is that **the conductor dispatches; it does not do the heavy
work itself**.

This document is the spec for that invariant. It defines the dispatch
rule, the allowed read set, the forbidden read set, and the bounded
outputs the conductor consumes.

See also: `AGENTS.md` (the roles), `04-execution-loop.md` (how the
conductor drives the runtime), `06-codex-integration.md` (the bounded
Codex lane), `10-grok-integration.md` (the Grok lane), and
`09-routing-matrix.md` (cross-family verification policy).

## The dispatch-only rule

> The conductor's job is to plan, dispatch, and decide. The conductor
> does not investigate large codebases inline, does not read raw artifacts,
> and does not implement non-trivial changes without delegating.

Concretely:

- **Investigation that spans more than ~3 file reads or one targeted grep**
  goes to an `Explore` sub-agent. The sub-agent returns one summary
  message.
- **Implementation that touches more than ~3 files or requires sustained
  context** goes to Codex (`run-codex-impl.sh`), Grok
  (`run-grok-impl.sh`; see `10-grok-integration.md`), or to a
  `general-purpose` sub-agent.
- **Verification of a non-trivial change** follows the cross-family policy
  in `09-routing-matrix.md`. The conductor reads the parsed Verdict.

Surgical operations the conductor *does* handle directly:

- Reading `plan.json`, `progress.json`, `masterPlan.md`.
- Reading a known file at a known path for a known reason (≤ 200 lines).
- Editing a known file with a precise old/new string (one or two edits).
- Writing a small new file (a scratchpad, a short doc, a config).
- Invoking skills via the `Skill` tool.
- Running short read-only shell commands (`ls`, `git status`, `git log`,
  `git diff --stat`).

When a task starts to feel like "I need to read several files to figure
out what to do," that is the dispatch signal: hand it to a sub-agent.

## What the conductor MAY read

The allowed read set is small and intentional. Every entry on this list
exists because it is **bounded by construction**.

1. **`plan.json`** — Immutable plan definition. Size bounded by the
   number of steps (typically tens of lines, hundreds at most).
2. **`progress.json`** — Mutable execution state. Same size bound as
   `plan.json`.
3. **`masterPlan.md`** — Human-facing proposal. Bounded by author
   discipline (kept brief by `writing-plans`).
4. **Sub-agent return messages.** The sub-agent's prompt instructs it
   to return a single bounded summary. The conductor reads that
   summary, not the sub-agent's intermediate work.
5. **Codex/Grok Summary / Verdict / Findings blocks.** Bounded by the
   wrapper's prompt contract — see `06-codex-integration.md` and
   `10-grok-integration.md`. The conductor parses the contract block
   and ignores anything else.
6. **Targeted small file reads (≤ 200 lines)** when the conductor has a
   specific question and knows the path. Reading a config, a type
   definition, or a single function is fine.
7. **Skill descriptions and skill bodies** when invoking them.

## What the conductor MUST NOT read

These categories blow the context budget and should always be pushed
down to a sub-agent or an external wrapper lane.

1. **Raw exploration dumps.** If a sub-agent's prompt would naturally
   produce a long list of grep matches, that lives inside the sub-agent.
   The conductor reads only the synthesized summary.
2. **Raw Codex/Grok `stdout` / stream files.** External wrappers may
   emit verbose reasoning, tool traces, or partial drafts. The conductor
   reads only the parsed Summary / Verdict / Findings block (see
   contract below).
   The raw stream may be written to disk for debugging but is not part
   of the conductor's read set.
3. **Full `git diff` output** for non-trivial changes. The conductor
   either trusts the external verifier's Verdict, or asks a sub-agent for
   a bounded summary of the diff (e.g., "describe the changes to
   `src/auth/*` in 10 bullets"). It does not page through diff hunks.
4. **Files larger than ~500 lines** without a specific question in
   mind. Open-ended reads of large files are a sub-agent's job.
5. **Past external-wrapper calls' verbose logs.** Once a step is marked
   done in `progress.json`, its logs are archived. The conductor does
   not re-read them.

These prohibitions are not enforced by a hook. They are enforced by
the conductor skill's prompt and by the user catching drift in
conversation. v2 trusts the model to honor them; if it doesn't, the
fix is to tighten the skill description, not add a gate.

## Bounded outputs the conductor consumes

Every channel into the conductor has a known shape:

### From sub-agents (Explore, general-purpose, Plan)

A single message whose form is set by the sub-agent's prompt. The
conductor's `Agent` call always specifies:

- The deliverable (what the summary should contain)
- A length cap ("under 200 words" or "at most 15 bullet points")
- The forbidden content ("do not paste full file contents")

The sub-agent runs whatever queries it needs internally; the conductor
sees only the final message.

### From external wrappers (Codex and Grok)

A fixed block in the response:

```
Summary: <one paragraph, ≤ 6 sentences>
Verdict: PASS | FINDINGS | FAIL
Findings:
  - <one-line finding>
  - <one-line finding>
  ...
```

The conductor parses these three fields and ignores everything else the
wrapper emitted. There is no receipt to validate, no signature to
check, no digester to invoke. The bound is the prompt contract; the
contract is enforced by the wrapper. See `06-codex-integration.md` and
`10-grok-integration.md` for the exact prompt and parsing rules.

### From hooks

Only `SessionStart` and `PostCompact` inject bounded read-only notices. The
four lifecycle observers emit no notice or decision and enqueue only
allowlisted labels in private state. See `07-hooks.md`; no hook injects full
file contents or raw artifacts.

## When the conductor is allowed to "just do it"

The dispatch-only rule has a small exception: **trivial, well-scoped
edits the conductor can complete in one or two `Edit` calls** do not
need delegation. Examples:

- Fixing a typo in a known file
- Renaming a single local variable
- Adding a missing import line
- Updating a constant
- Writing a short markdown doc

The test: if the change is smaller than the prompt the conductor would
need to write to delegate it, just do it. This exception exists so v2
does not feel like every keystroke requires a sub-agent.

For anything larger, dispatch.

## Failure modes and recovery

- **Conductor over-reads a file.** Self-correct: stop, dispatch the
  rest of the investigation to a sub-agent. No persistent state to
  clean up.
- **Sub-agent returns more than its budget.** Re-dispatch with a
  tighter prompt. Do not paste the over-large summary into context to
  "summarize it" — that defeats the boundary.
- **External wrapper returns no contract block.** The wrapper exits 3;
  it does not retry. The conductor re-dispatches exactly once with a
  stricter format reminder appended to the step block. If the retry
  also fails, the conductor reports the failure to the user and asks
  how to proceed; it does not guess.
- **Plan and progress disagree.** `progress.json` is the source of
  truth for state. If `plan.json` is missing a step that
  `progress.json` references, that's a bug in `writing-plans` and
  should be surfaced.
