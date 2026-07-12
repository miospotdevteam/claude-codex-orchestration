---
name: persistent-plans
description: Keep Codex-native orchestration state durable across compaction and session boundaries using the shipped plan.json, progress.json, masterPlan.md, and plan-utils.sh contracts. Use when starting, resuming, reporting, or archiving non-trivial planned work. Do not use for a trivial edit or a read-only question with no active plan.
---

# Codex-native persistent plans

Plan files on disk are the source of truth. Context memory, task lists, wrapper
logs, and chat summaries are caches; they never override `plan.json` or
`progress.json`.

This host runs with `claude_workers=deny`. Resume and recovery must preserve
that policy: never convert an unavailable Codex or Grok lane into a Claude
dispatch, and never mark a blocked verification complete.

## Resolve the helper

Resolve the plugin root from this selected skill's installed path, then use:

```text
${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/plan-utils.sh
```

Do not edit orchestration state with ad hoc JSON rewrites when the helper has a
matching command. Its writes are validated and atomic.

## Plan files

Each active plan lives at `.temp/plan-mode/active/<planId>/`:

- `plan.json` is the immutable definition after approval.
- `progress.json` is mutable runtime state and verifier evidence.
- `masterPlan.md` is the human-facing approved proposal.
- `logs/` is wrapper-owned diagnostic output, not conductor input.

Create `progress.json` exactly once after approval through `init-progress`.
Never infer completion from a wrapper exit or a log file; only parsed verdicts
recorded in `progress.json` count.

## Start or resume

1. Run `get-plan-dir <project-root>`.
2. If no active plan exists, return to the Codex-native `writing-plans` skill.
3. If a plan exists, run `read-plan <plan-dir>` and
   `read-progress <plan-dir>`; do not read the entire logs directory.
4. Confirm `planId` agreement, approved/frozen state, and the effective
   no-Claude policy before dispatch.
5. Recompute the runnable DAG with `compute-frontier <plan-dir>` rather than
   trusting a remembered frontier.
6. Surface in-progress, blocked, and pending steps with their recorded
   executor/model so the user can see exactly where execution stopped.

An `in_progress` step after interruption is not automatically failed or safe to
repeat. Inspect its expected files and current diff, then record a deviation
before any deliberate re-dispatch.

## Execute durably

- Before a worker starts, use
  `start-step <plan-dir> <step-id> <executor> <model> <effort>`.
- Before each independent review, use
  `record-lane-dispatch <plan-dir> <step-id> <lane> <executor> <model> <effort>`;
  after it returns, use `record-verdict` with the correct `codex` or `grok`
  lane.
- Re-run `compute-frontier` after every status transition.
- Dispatch frontier steps in parallel only when their declared files do not
  overlap; serialize possible collisions.
- A profiled implementation step becomes done only when `plan-utils.sh`
  accepts the complete verifier set frozen by `routingProfile`; manual steps
  are exempt, and unprofiled legacy plans fall back to their owner matrix.
- Record runtime facts and reroutes as deviations. Never mutate a frozen
  `plan.json` to make execution history look cleaner.

## Completion and archive

Before archive, prove that every non-skipped step is done, required Codex/Grok
verdicts are PASS, project checks passed, and no unresolved deviation changes
the approved scope. Then run:

```text
${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/plan-utils.sh archive-plan <plan-dir>
```

Do not use `--force` during normal completion. It is a recovery mechanism, not
a substitute for missing evidence.

## Safety

- Preserve unrelated dirty and untracked work; never reset, clean, checkout,
  stash, or overwrite it.
- Do not reconstruct status from raw Codex/Grok stdout.
- Do not silently replace a missing independent verifier with same-family
  approval.
- Stop for user judgment when the frozen plan needs structural change or
  repeated fix-and-verify cycles do not converge.
