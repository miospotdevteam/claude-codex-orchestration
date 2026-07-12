---
name: writing-plans
description: Draft and approve the existing orchestration plan artifacts from a Codex-native session with a Grok 4.5 independent planning and review pass. Use after discovery is sufficient for a non-trivial change. Do not use during execution or for a trivial edit.
---

# Codex-native writing plans

Use the plugin's existing plan contract; do not invent a second format. Resolve
the plugin root as the directory two levels above this skill directory, then use:

- `schemas/plan.schema.json` for immutable `plan.json`.
- `schemas/progress.schema.json` for mutable `progress.json`.
- `templates/masterPlan.template.md` for the human-facing proposal.
- `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/plan-utils.sh init-progress <plan-dir>`
  exactly once, after approval.

## Draft

Create `.temp/plan-mode/active/<planId>/plan.json` with
`routingProfile: "codex-primary"`, `frozen: false`, and a
matching `masterPlan.md`. Do not create `progress.json` yet. Each step must have
one owner from the existing enum, explicit acceptance criteria, expected files,
and dependency edges sufficient to prevent overlapping writes.

This Codex-native lane has `claude_workers=deny`. A step with
`owner: "claude-impl"` **must not be approved**. Choose `codex-impl` for the
default clear-spec implementation lane, `grok-impl` for an independent or
capacity-balanced implementation, and `manual` when neither model can satisfy
the acceptance criteria without a prohibited Claude worker. Explain any taste
tradeoff in the step description; never hide it as a fallback.

## Independent planning and review

For ambiguous work, dispatch the identical brief independently through both
direction-locked implementation wrappers with scenario `planning`: synthetic
steps `panel-codex` and `panel-grok`. The host sees neither candidate until both
exist, then converges them. Grok remains pinned to 4.5/high.

Before approval, pass the proposed `plan.json` and `masterPlan.md` through both
Codex and Grok verification wrappers with scenario `review`. Fix every FINDINGS
or FAIL result and re-run both. If either required lane is unavailable or its
contract fails twice, stop with the draft unapproved.

## Approval

Present the final `masterPlan.md` in conversation and wait for explicit user
approval. On approval, set `approvedAt`, set `approvedVia` to
`"conversational"`, set `frozen: true`, validate the JSON against the shipped
schema, and run
`${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/plan-utils.sh init-progress <plan-dir>`.
From that point
on, structural changes require a new plan; runtime facts belong in
`progress.json` deviations.
