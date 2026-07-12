---
name: conductor
description: Run the codex-primary orchestration profile for non-trivial repository work using persistent plans, bounded Codex and Grok lanes, and no Claude workers. Use when a task needs discovery, planning, implementation, or verification across multiple steps. Do not use for a one-line edit or a purely conversational question.
---

# Codex host entrypoint

This conventional Codex plugin entrypoint delegates to the canonical host body
at `../../../codex-skills/conductor/SKILL.md`, relative to this `SKILL.md`.
Read that file completely before taking any orchestration action, and follow it
as this skill's authoritative instructions. If the canonical body is missing or
cannot be read, stop fail-closed instead of improvising a fallback conductor.
