---
name: codex-dispatch
description: Dispatch Codex and Grok implementation or verification work through the existing direction-locked wrappers from a Codex-native conductor, then persist only parsed contract results. Use for every runnable implementation step and every independent verifier pass. Do not use for free-form calls or direct model CLI invocation.
---

# Codex-native dispatch

Resolve the plugin root from this selected skill's installed path and invoke
only these shipped wrapper contracts:

- `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/run-codex-impl.sh` for
  `owner: "codex-impl"` implementation.
- `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/run-codex-verify.sh` for read-only
  Codex verification.
- `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/run-grok-impl.sh` for
  `owner: "grok-impl"` implementation.
- `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/run-grok-verify.sh` for read-only
  Grok verification.
- `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/parse-contract.sh` inside the
  wrappers for bounded JSON output.
- `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/plan-utils.sh` for progress
  transitions and verdict recording.

Never invoke `codex exec`, `grok`, or `claude` directly. Never pass a model
argument to a wrapper. Pass only the route's scenario enum; Codex wrappers map
that enum to an internal effort, while Grok stays pinned to 4.5/high.

## Dispatch protocol

1. Inspect `git status` and the step's expected files. Preserve unrelated dirty
   work and serialize any overlapping step or wrapper self-edit.
2. Render the existing step block from `plan.json`: title, description,
   acceptance criteria, files, and progress checklist.
3. Before implementation, run
   `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/plan-utils.sh start-step` with
   executor, model, and effort so `progress.json` durably records the dispatch.
4. Invoke the owner-specific implementation wrapper. Read only its parsed JSON
   stdout; raw logs remain human-debugging artifacts.
5. For every profiled implementation step, persist each verifier first with
   `record-lane-dispatch`, then dispatch
     `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/run-codex-verify.sh` and
     `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/run-grok-verify.sh` in
   parallel with scenario `review`; both must PASS under `codex-primary`.
   An implementation step owned by `claude-impl` remains a policy violation
   under `claude_workers=deny` and blocks without fallback. Manual steps are
   verifier-exempt. Unprofiled legacy plans retain their owner matrix.
6. Record each lane verdict with
   `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/plan-utils.sh record-verdict`.
   Only after the required PASS set exists may that helper mark the step done.

FINDINGS and FAIL both become the bounded fix specification. Re-dispatch the
owner lane for a fix, then re-run every required verifier. After three
non-converging rounds, stop for user judgment.

## Fail closed

If Codex is unavailable, the implementation or cross-family gate stays blocked.
If Grok 4.5 is unavailable, every affected implementation, plan review, or
verification stays blocked. Contract parse failures get one strict retry; a
second failure blocks the operation. There is no Claude fallback, no degraded
same-family PASS, and no `--degraded` completion for this lane.
