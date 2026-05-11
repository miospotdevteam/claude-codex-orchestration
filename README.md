# orchestration — v2

This repository is **v2 of the `orchestration` plugin for Claude Code**.
It contains both the design spec (under `docs/`) and the plugin
implementation that descends from it (at the repo root: `plugin.json`,
`skills/`, `hooks/`, `scripts/`, `schemas/`, `templates/`, `tests/`).

## Why this exists

v1 of the plugin (`look-before-you-leap`) shipped a working orchestrator but
accumulated too much enforcement machinery: signed Codex receipts, HMAC
sidecars, a digester sub-agent for every artifact, forced plan-mode gates
that blocked routine edits, and a hook surface that mutated state. The good
ideas — conductor mode, persistent plans, discipline skills, Orbit review —
were buried under ceremony.

v2 is a clean rewrite. The design preserves what worked, drops what
over-enforced, and trusts the model + bounded prompt contracts in place of
receipts and signatures.

## What v2 ships

- A `conductor` skill that orchestrates work via sub-agent dispatch and
  bounded Codex calls.
- Persistent plans on disk (three-file format) that survive compaction.
- Eight discipline skills (`engineering-discipline`, `persistent-plans`,
  `writing-plans`, `codex-dispatch`, `refactoring`,
  `test-driven-development`, `systematic-debugging`, `brainstorming`).
- Exactly two hooks, both read-only: `session-start` and `post-compact`.
- Direction-locked Codex wrappers (`run-codex-impl.sh`, `run-codex-verify.sh`)
  with a fixed Summary / Verdict / Findings prompt contract.
- JSON Schemas for `plan.json` and `progress.json`, plus a `masterPlan.md`
  template.

## Repository layout

```
orchestration/
├── plugin.json            ← plugin metadata
├── README.md              ← you are here
├── AGENTS.md              ← the three roles (conductor, sub-agents, Codex)
├── .claude/
│   └── CLAUDE.md          ← context for any Claude session editing this repo
├── docs/                  ← the design spec (markdown only)
│   ├── 01-philosophy.md   ← why we rebuilt; principles
│   ├── 02-conductor.md    ← conductor-mode spec; what main thread may read
│   ├── 03-plan-format.md  ← plan.json + progress.json + masterPlan.md
│   ├── 04-execution-loop.md ← Discovery → Plan → Execute → Verify
│   ├── 05-skills-catalog.md ← the 9 core v2 skills
│   ├── 06-codex-integration.md ← codex exec, direction lock, prompt contract
│   ├── 07-hooks.md        ← session-start and post-compact (read-only)
│   └── 08-plugin-layout.md ← target directory tree + build order
├── skills/                ← 9 core + 8 auxiliary skills (see docs/05-skills-catalog.md)
├── codex-skills/          ← Codex-side bodies for dual-install skills
├── hooks/                 ← exactly two read-only hooks
├── scripts/               ← codex wrappers + plan/contract helpers
├── schemas/               ← JSON schemas for plan + progress files
├── templates/             ← starter templates (e.g. masterPlan)
└── tests/                 ← hook + script tests
```

## Install

Prerequisites:

- Claude Code CLI installed and authenticated.
- `codex` CLI (`codex exec`) installed and authenticated — the impl and
  verify wrappers shell out to it.
- `jq` on `PATH` — used by the plan helpers, the contract parser, and
  the hooks.

Install steps (Claude Code plugin):

```
# Clone this repo to a stable path
git clone https://github.com/miospotdevteam/claude-codex-orchestration.git \
  ~/projects/claude-codex-orchestration

# Install as a Claude Code plugin
#   In Claude Code, plugins are added via the /plugin command. Open any
#   Claude Code session and run:
#
#       /plugin add ~/projects/claude-codex-orchestration
#       /reload-plugins
#
#   If your version of Claude Code uses a different mechanism (e.g. a
#   `plugins` entry in settings.json), point it at the absolute path to
#   the clone. The harness loads plugin.json from the path you give it.
```

After install, start a Claude Code session in any project. The
`session-start` hook injects a one-line notice if an active plan
already exists; otherwise the `conductor` skill is on standby.

## Usage

The plugin is **gentle-reminder driven**, not gate-enforced. You can
make any edit at any time; the discipline lives in the skills.

A typical non-trivial task flows through four phases:

1. **Discovery.** Ask Claude to "look into X" or "figure out how Y
   works". The `conductor` skill dispatches `Explore` sub-agents in
   parallel and collects bounded summaries.
2. **Plan.** Once discovery is enough, say "write the plan" (or
   similar). The `writing-plans` skill produces three files under
   `.temp/plan-mode/active/<planId>/`:
   - `plan.json` — immutable definition (frozen after approval)
   - `progress.json` — mutable execution state
   - `masterPlan.md` — human-facing proposal (review this)
3. **Execute.** On approval, `plan.json.frozen` flips to `true`. The
   conductor computes the runnable frontier via
   `scripts/plan-utils.sh compute-frontier` and dispatches steps in
   parallel through `codex-dispatch`. Codex returns a bounded
   Summary / Verdict / Findings block; the parser writes the verdict
   into `progress.json`.
4. **Verify.** Each step is verified during execution; a final pass
   re-runs project-level checks (type-check, lint, tests). The plan
   directory moves to `.temp/plan-mode/archive/` when done.

A compaction at any point is fine: the `post-compact` hook re-injects
the active plan path and the runnable frontier, and the conductor
resumes from `plan.json` + `progress.json` alone — no source files
re-read, no discovery re-run.

For trivial work — a typo, a one-line config tweak — say "just do it"
and the conductor skips the plan. The discipline is gentle on
purpose.

## Testing

Run the four test suites against the helpers and hooks:

```bash
bash tests/scripts/parse-contract.test.sh    # 9 contract-block parsing cases
bash tests/scripts/plan-utils.test.sh        # 6 plan-file helper cases
bash tests/hooks/session-start.test.sh       # 5 session-start hook cases
bash tests/hooks/post-compact.test.sh        # 4 post-compact hook cases
```

All four suites use plain-bash assertions, sandbox under `mktemp -d`,
and clean up after themselves. Each exits non-zero on any failure.

Syntax / lint checks for the shell scripts:

```bash
bash -n scripts/*.sh hooks/*.sh tests/scripts/*.test.sh tests/hooks/*.test.sh
shellcheck scripts/*.sh hooks/*.sh    # optional but recommended
```

JSON validity:

```bash
jq -e . plugin.json schemas/*.json
```

## Contributing / dev

The full design lives under `docs/`. Read in order:

1. `docs/01-philosophy.md` — the bias (what v2 keeps, drops, why).
2. `docs/02-conductor.md` — the dispatch-only contract.
3. `docs/03-plan-format.md` — the plan/progress/masterPlan schemas.
4. `docs/04-execution-loop.md` — the four-phase runtime.
5. `docs/05-skills-catalog.md` — what each skill triggers on.
6. `docs/06-codex-integration.md` — wrappers + prompt contract.
7. `docs/07-hooks.md` — what the two hooks may/may-not do.
8. `docs/08-plugin-layout.md` — target tree + build order.

When you're working on the plugin, your own session is itself an
exercise of the system: a non-trivial change should produce a plan
under `.temp/plan-mode/active/<planId>/`. Look at the existing
archives under `.temp/plan-mode/archive/` for examples of approved
plans and their progress records.

`.claude/CLAUDE.md` is the project-local rule set: markdown only under
`docs/`, no regressions to v1 shape, no `lib/` shared between skills,
no third hook.

## What v2 does **not** ship

- No signed receipts, HMAC sidecars, or `claude-review-*.md` sibling files.
- No `lbyl-digest` sub-agent.
- No forced-plan hard gates. Reminders only.
- No tool-blocking or state-mutating hooks.
- No `lib/` shared between skills. Skills reference each other by
  name in prose, not by shared imports.

See `docs/01-philosophy.md` for the full rationale.
