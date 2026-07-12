# AGENTS.md

This file documents the agents at work in the **`orchestration` plugin
(v2.0.0)** for Claude Code. It follows the public
[AGENTS.md](https://agents.md) convention: a single file that names the
actors and their responsibilities so any session — human or model — can
pick up the system without re-deriving it.

The plugin defines **three role families**. Each has a different read
budget, a different write budget, and a different escalation path.
Confusing them is the most common source of bugs in orchestrated
systems, so they are spelled out here.

---

## 1. Conductor (the main Claude thread)

The conductor is the Claude Code session the user is talking to. It is
**dispatch-only**: it plans, it routes work to specialists, and it consumes
bounded summaries. It does not read raw artifacts, does not run long file
sweeps itself, and does not implement large changes inline.

**May read**
- `plan.json` (immutable plan definition)
- `progress.json` (mutable step state, results, deviations)
- `masterPlan.md` (human-facing proposal)
- Sub-agent return messages (already bounded by the sub-agent's prompt)
- Codex/Grok Summary / Verdict / Findings blocks (bounded by prompt contract)
- Small targeted file reads (≤ 200 lines, when surgical context is needed)

**Must not read**
- Raw exploration dumps from sub-agents (the sub-agent summarizes)
- Raw Codex/Grok `stdout` or stream files (use the parsed contract block)
- Full `git diff` outputs (ask for a bounded summary instead)
- Files larger than ~500 lines without a specific question in mind

**Tools it owns**
- `Agent` (dispatching sub-agents)
- `Skill` (invoking discipline skills)
- `TaskCreate` / `TaskList` family (tracking work)
- `Read` / `Edit` / `Write` for small, surgical edits and the plan files
- The external wrapper scripts (`run-codex-impl.sh`, `run-codex-verify.sh`,
  `run-grok-impl.sh`, `run-grok-verify.sh`)

See `docs/02-conductor.md` for the full spec.

---

## 2. Sub-agents (Explore, general-purpose, Plan)

Sub-agents are Claude instances spawned by the conductor via the `Agent`
tool. They have a fresh context, a focused prompt, and they return **one
message** to the conductor. That return message is the contract: it must
be self-contained and bounded.

**Explore** — Read-only search agent. Use for "where is X defined?",
"which files import Y?", grep-style sweeps, and codebase questions that
would otherwise blow the conductor's context. Returns: list of file paths,
line numbers, brief code citations.

**general-purpose** — Multi-step research and code-writing agent. Use when
a task needs both investigation and changes, or when the conductor wants a
sub-agent to implement a self-contained chunk. Returns: summary of what was
done plus the paths touched.

**Plan** — Architecture/design agent. Use to draft an implementation
strategy for a non-trivial change before the conductor commits to a plan.
Returns: a structured plan proposal (steps, file lists, tradeoffs).

Sub-agents may freely read raw files, run long greps, and follow many
threads — the bounding happens in their **return** message, not in their
exploration.

---

## 3. External wrapper lanes (Codex and Grok)

Codex (`codex exec` CLI) and Grok (`grok` CLI) are external execution
lanes: separate models that run under strict direction locks. The
conductor invokes each lane through wrapper scripts, never directly:

- `run-codex-impl.sh` — Codex implements a step. Reads the step
  description and acceptance criteria; writes code; returns a Summary +
  Verdict + Findings block.
- `run-codex-verify.sh` — Codex verifies a step the conductor (or a
  sub-agent) just implemented. Reads the diff and acceptance criteria;
  returns Summary + Verdict (PASS / FINDINGS / FAIL) + Findings[].
- `run-grok-impl.sh` / `run-grok-verify.sh` — Grok mirrors the same
  bounded lane; see `docs/10-grok-integration.md`.

The wrappers exist so impl and verify can never be confused at the call
site. Each script pins its direction prompt and enforces the contract
shape the lane must return; the Codex pair also captures Codex's last
message via `-o` (`--output-last-message`).

There are **no receipts, no HMAC sidecars, no digester sub-agent** in v2.
The bound on wrapper output is enforced by the prompt contract: the wrapper
asks for a fixed shape, the conductor parses that shape, anything else is
truncated or ignored. See `docs/06-codex-integration.md` for Codex,
`docs/10-grok-integration.md` for Grok, and `docs/09-routing-matrix.md`
for cross-family verification policy.

---

## Escalation and handoff

- Conductor → Sub-agent: when work would require reading too much, or
  exploring too widely, to fit in the main thread budget.
- Conductor → Codex/Grok: when a step is well-defined enough to implement
  or verify against acceptance criteria.
- Conductor → `remote-agent-host`: when natural language explicitly asks to
  list, start, continue, wait for, inspect, reveal, steer, interrupt, kill,
  synchronize, release, or run a diagnostic Mini session. This Claude-only route uses the guarded
  helper, inspects before every input and after every lifecycle wake, and is
  not dispatched as a Codex/Grok plan step.
- Sub-agent → Conductor: every sub-agent terminates with one summary
  message. No multi-turn dialogue.
- Codex/Grok → Conductor: one bounded Summary/Verdict/Findings block per
  call.

If any role exceeds its read budget, the orchestration is broken. The
remedy is always the same: push the reading down into a sub-agent or an
external wrapper lane, and keep the conductor's window clean.

---

## Implementation surfaces

The plugin's code lives under `orchestration/`, alongside the design
spec (`docs/`) and the routing-eval harness (`eval/`) at the repo root.
Each role's behavior is enforced by the corresponding files (paths
below are relative to `orchestration/` unless noted):

- **Manifests and host install** — `.agents/plugins/marketplace.json` exposes
  `./orchestration/codex-plugin` to `codex plugin marketplace add`, while
  `.claude-plugin/marketplace.json` exposes `./orchestration` to Claude Code.
  The Codex sub-root uses the required conventional `skills/` entrypoints,
  which delegate to the canonical bodies in the parent package's
  `codex-skills/`. `install.sh --host codex|claude|both` defaults to the no-Claude
  Codex host; `--host codex` must never require or invoke Claude. Use
  `--host both` once when both subscription hosts should remain available, then
  switch orchestration authority atomically with
  `scripts/orchestration-routing.sh activate codex-primary|fable-primary`.
  `orchestration/.claude-plugin/plugin.json` is the Claude manifest;
  `orchestration/codex-plugin/.codex-plugin/plugin.json` is the Codex manifest.
  Claude Code
  requires the plugin to live in a real subdirectory — `"source": "."`
  in marketplace.json is rejected as "unsupported".
- **Skills** — `skills/<skill>/SKILL.md` for the 9 core orchestration
  skills plus 9 auxiliary skills (`doc-coauthoring`, `frontend-design`,
  `svg-art`, `immersive-frontend`, `mcp-builder`, `react-native-mobile`,
  `webapp-testing`, `skill-review-standard`, `remote-agent-host`). The
  conductor invokes them via the `Skill` tool; the harness auto-discovers
  them by scanning `skills/<name>/SKILL.md` (no manifest list needed).
- **Host and portable skill bodies** — `codex-skills/<skill>/SKILL.md` contains
  the four Codex-host orchestration skills (`conductor`, `persistent-plans`,
  `writing-plans`, `codex-dispatch`). `external-skills/<skill>/SKILL.md`
  contains the exact 13 work skills copied to both Codex and Grok. Claude loads
  its host and work skills directly from `skills/`. The active routing profile
  decides which host owns orchestration and which model lanes execute each
  scenario. With no project `.orchestration/routing.json`, the shipped
  `codex-primary` preset is effective; a Fable switch is always explicit.
- **External wrappers** — `scripts/run-codex-impl.sh` and
  `scripts/run-grok-impl.sh` (IMPLEMENT-direction), plus
  `scripts/run-codex-verify.sh`, `scripts/run-grok-verify.sh`, and the legacy
  compatibility `scripts/run-claude-verify.sh` (VERIFY-direction). Each pins its direction header in-script — the
  prompt body cannot override.
- **Plan + contract utilities** — `scripts/plan-utils.sh` (read/write
  plan files atomically) and `scripts/parse-contract.sh` (extract the
  shared external-wrapper contract block).
- **Mini workflows** — `skills/remote-agent-host/SKILL.md` owns the
  natural-language route; `scripts/remote-agent.sh` is its only transport.
  Discover resident work with `list`, then use opaque workflow IDs for
  `inspect`, `wait`, `send`, `interrupt`, `kill`, `release`, `reveal`, and
  `sync`. `start-conductor PROJECT PLAN_ID` creates the resident Claude-backed
  workflow; direct Claude/Codex/Grok access uses the separate full-lease
  `diagnostic ACTION PROJECT HARNESS` family and is not mobile-resumable.
  Prompt text is private-file-backed and never placed in argv. Wait is one
  cursor-based blocking call followed by one bounded inspect. Kill proves
  quiescence but does not transfer or release; sync queues a claim-time
  direction-derived mirror job, and release clears ownership only after
  verified alignment. The Mini registry and restore evidence are authoritative;
  no role may bypass active-writer, divergence, CAS, changed-snapshot, restore,
  or recovery-required refusals with raw SSH, rsync, or tmux. Preserve unrelated
  dirty Mini work and use a previously installed matching helper only for
  bounded migration across relay/registry version skew.
- **Hooks** — six event registrations explicitly supersede the prior
  exactly-two-read-only-hooks design. `SessionStart` and `PostCompact` run the
  bounded context handlers `session-start.sh` and `post-compact.sh`. `Stop`,
  `SubagentStop`, `StopFailure`, and `Notification` share `agent-event.sh`, a
  narrowly scoped synchronous, fail-open, non-decision observer that writes
  only closed labels to a private supervisor queue. The Notification allowlist
  is exactly `permission_prompt`, `idle_prompt`, and `elicitation_dialog`; no
  handler edits user Claude settings or stores prompt/transcript/terminal text.
- **Schemas** — four schemas describe plan, progress, routing, and policy
  state.
- **Templates** — `templates/masterPlan.template.md` is the starter
  for `writing-plans`.
- **Tests** — 29 shipped plugin suites under `tests/scripts/*.test.sh` and
  `tests/hooks/*.test.sh` (26 script plus 3 hook suites). The repo-root routing
  eval adds 5 suites under `eval/tests/` but is not shipped with the plugin.

The full design spec sits under `docs/01-philosophy.md` …
`docs/11-routing-eval.md`. Read `docs/02-conductor.md` for the
conductor's full contract, `docs/06-codex-integration.md` and
`docs/10-grok-integration.md` for wrapper lane contracts,
`docs/09-routing-matrix.md` for cross-family verification policy, and
`docs/05-skills-catalog.md` for each skill's responsibilities.
