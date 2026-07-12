---
name: persistent-plans
description: Keep Codex-native orchestration state durable across compaction and session boundaries using plan.json, progress.json, masterPlan.md, and plan-utils.sh. Use when starting, resuming, reporting, or archiving non-trivial planned work.
---

# Codex host entrypoint

This conventional Codex plugin entrypoint delegates to the canonical host body
at `../../../codex-skills/persistent-plans/SKILL.md`, relative to this
`SKILL.md`. Read that file completely before handling plan state, and follow it as
this skill's authoritative instructions. If it is missing or unreadable, stop
fail-closed rather than inventing a second plan contract.
