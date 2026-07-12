# orchestration — v2

This repository is **v2 of the `orchestration` plugin for Codex and Claude
Code**. The default install is the no-Claude Codex host; Claude remains an
explicitly selectable host and optional worker family.
It contains both the design spec (under `docs/`) and the plugin
implementation that descends from it (under `orchestration/`:
`.claude-plugin/plugin.json`, `codex-plugin/.codex-plugin/plugin.json`, `skills/`,
`codex-skills/`, `external-skills/`, `config/`, `hooks/`,
`scripts/`, `schemas/`, `templates/`, `tests/`). A routing-eval harness
lives in the top-level `eval/` directory. See the layout block below.

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
- Nine auxiliary skills the orchestrator routes to
  (`doc-coauthoring`, `frontend-design`, `svg-art`, `immersive-frontend`,
  `mcp-builder`, `react-native-mobile`, `webapp-testing`,
  `skill-review-standard`, `remote-agent-host`), auto-discovered from
  `skills/<name>/SKILL.md`.
- Six hook-event registrations: two bounded read-only notice hooks
  (`SessionStart`, `PostCompact`) plus four narrowly scoped, fail-open,
  non-decision Mini lifecycle observers backed by one private labels-only
  queue bridge. This supersedes the former exactly-two-read-only-hooks design.
- Direction-locked Codex wrappers (`run-codex-impl.sh`, `run-codex-verify.sh`)
  with a fixed Summary / Verdict / Findings prompt contract.
- A parallel Grok lane (`run-grok-impl.sh`, `run-grok-verify.sh`) sharing
  the same direction-locked contract; see `docs/10-grok-integration.md`.
- Five direction-locked model wrappers: two implementation wrappers and three
  verification wrappers (Codex, Grok, and the legacy Claude verifier).
- Sixteen plugin-root scripts covering wrappers, plan/routing helpers, the
  guarded workflow relay, and the Mini-resident registry/mirror/APNs backend.
- Four JSON Schemas for plans, progress, routing, and policy, plus a
  `masterPlan.md` template.

## Repository layout

```
claude-codex-orchestration/      ← repo root = marketplace root
├── .agents/plugins/
│   └── marketplace.json         ← Codex marketplace metadata
├── .claude-plugin/
│   └── marketplace.json         ← marketplace metadata (this repo as marketplace)
├── README.md                    ← you are here
├── AGENTS.md                    ← the three roles (conductor, sub-agents, Codex)
├── LICENSE                      ← MIT
├── install.sh                   ← --host codex|claude|both (Codex default)
├── .claude/
│   └── CLAUDE.md                ← context for any Claude session editing this repo
├── docs/                        ← the design spec (markdown only)
│   ├── 01-philosophy.md … 12-phone-control-surface.md
│
├── orchestration/               ← shared package + Claude plugin source
│   ├── .claude-plugin/
│   │   └── plugin.json          ← minimal plugin manifest (name, description)
│   ├── codex-plugin/            ← Codex marketplace source
│   │   ├── .codex-plugin/plugin.json
│   │   └── skills/              ← conventional entrypoints to canonical bodies
│   ├── skills/                  ← 9 core + 9 auxiliary skills
│   ├── codex-skills/            ← 4 Codex-host orchestration skills
│   ├── external-skills/         ← exact 13 portable Codex/Grok work skills
│   ├── config/                  ← canonical Codex/Fable routing profiles
│   ├── hooks/                   ← manifest + 2 read-only notice handlers +
│   │                               1 fail-open private-queue observer handler
│   ├── scripts/                 ← 5 wrappers + 11 plan/routing/Mini helpers
│   ├── schemas/                 ← plan, progress, routing, and policy schemas
│   ├── templates/               ← starter templates (e.g. masterPlan)
│   └── tests/                   ← hook + script tests
│
└── eval/                        ← routing-validation eval harness (non-shipped dev tool)
    ├── corpus/                  ← gold tasks per domain (tracked)
    ├── scripts/                 ← bash helpers: score/judge/aggregate (tracked)
    └── results/                 ← scorecards + raw run JSON (gitignored)
```

## Install

Prerequisites depend on the selected host:

- Default `--host codex`: authenticated `codex` and `grok` CLIs. Codex is the
  Sol xhigh root; Grok 4.5 is the independent planning, review, and verification
  counterweight. This path never requires or invokes `claude`.
- `--host claude`: authenticated Claude Code, Codex, and Grok CLIs. Fable is
  the root; Codex and Grok remain required planning and verification lanes.
- `--host both`: all three authenticated CLIs. This is the easiest setup for
  explicit host switching without reinstalling later.
- `orbit-mcp` on `PATH` — the plugin declares an `orbit` MCP server
  used to surface `masterPlan.md` for human review before execution
  and to coordinate the plan-mode handoff (`EnterPlanMode` →
  compaction → fresh execution window). On macOS: `brew install
  orbit-mcp` (or follow Orbit's own install docs).
- `jq` on `PATH` — used by the plan helpers, the contract parser, and
  the hooks.

The optional Mac Mini workflow path additionally requires local `git`, `ssh`,
and a SHA-256 implementation, plus an already provisioned Mini. The Mini must
expose the matched `workflow-registry`, supervisor, mirror worker, gateway,
APNs sender, and protocol authority generation on `PATH`; the MacBook's
`remote-agent.sh` talks only to `workflow-registry`. The supervisor launches
the installed `claude`, `codex`, or `grok` subscription TUI. Each TUI must
already be authenticated interactively on the Mini, and real worktrees must
exist at the configured project roots. Configure its SSH
host with `--host`, `REMOTE_AGENT_HOST`, or the single-line
`${XDG_STATE_HOME:-$HOME/.local/state}/orchestration-remote-host` file. The
helper neither installs this backend nor copies SSH keys, API keys, cookies,
browser profiles, shell profiles, harness authentication, or other secrets.

### One-liner install (recommended)

Clone this repo somewhere stable, then run `install.sh`:

```bash
git clone https://github.com/miospotdevteam/claude-codex-orchestration.git \
  ~/projects/claude-codex-orchestration
cd ~/projects/claude-codex-orchestration
bash install.sh                         # Codex-primary surface; no Claude invocation
# bash install.sh --host both           # prepare both hosts
# bash install.sh --host both           # install once for profile switching
```

`install.sh` is host-aware and idempotent. Every mode installs and validates the
Codex dependency; Claude modes additionally install the Claude plugin. The
selected provider's machine-readable installed artifact—not the invoking
checkout—is canonical. Before cleanup, the installer validates the exact 13
portable work skills, then syncs them into `~/.codex/skills` and
`~/.grok/skills`; host-only conductor/plan/dispatch bodies remain plugin-owned.
`--host codex` performs this without invoking Claude. Unowned skills are
preserved. Safe to re-run after upgrading.

The effective profile defaults to the shipped `codex-primary` preset when a
project has no routing file. A project override lives at
`.orchestration/routing.json` and is managed by `orchestration-routing.sh`.
Activate either profile atomically:

```bash
orchestration/scripts/orchestration-routing.sh activate codex-primary .
# later, if Fable remains available:
orchestration/scripts/orchestration-routing.sh activate fable-primary .
```

`codex-primary` requires a Sol xhigh Codex host and denies Claude workers.
`fable-primary` requires a Fable xhigh Claude host and enables the approved
Fable/Codex/Grok lanes. Activation reports the required next host but does not
launch it. Invalid routing fails closed to `deny`; legacy `policy.json` remains
a compatibility fallback only when no project routing override exists. The standalone
[model routing configurator](docs/model-routing-configurator.html) emits the
same validated, activatable profiles.

Codex model selection remains an authenticated machine preference, not an
installer mutation. For the default lane, configure `~/.codex/config.toml` with
`model = "gpt-5.6-sol"` and `model_reasoning_effort = "xhigh"`. The Grok
wrappers independently pin `grok-4.5` with high reasoning effort.

### Manual install (if you prefer)

```bash
# Codex
codex plugin marketplace add miospotdevteam/claude-codex-orchestration
codex plugin add orchestration@claude-codex-orchestration

# Add this repo as a Claude Code marketplace
claude plugin marketplace add miospotdevteam/claude-codex-orchestration

# Install the plugin from the marketplace
claude plugin install orchestration@claude-codex-orchestration
```

After install, start the selected host in any project. On Claude, the
`SessionStart` hook injects a one-line notice if an active plan
already exists; otherwise the `conductor` skill is on standby.

### Upgrade

```bash
claude plugin marketplace update claude-codex-orchestration
claude plugin update orchestration
```

Or re-run `bash install.sh --host codex|claude|both` from the clone. Host
installation and orchestration authority are separate: with both hosts
installed, switch explicitly using `orchestration-routing.sh activate
codex-primary|fable-primary`; no reinstall is required.

Restart Claude Code or run `/reload-plugins` in an open session after install
or upgrade. Do not edit the plugin cache or user Claude settings by hand; make
changes in this repository, reinstall, and reload.

### Rollback

To remove the current plugin cleanly, run:

```bash
claude plugin uninstall orchestration -y
claude plugin marketplace remove claude-codex-orchestration
```

Reinstalling with `install.sh` always selects the marketplace's current
artifact; it does not pin the invoking checkout. A historical rollback must be
published or registered as a marketplace version and then installed through
the Claude plugin CLI—never copied into Claude's cache manually.

The Mini backend has no fixed installation directory; its supervisor,
workflow registry, mirror worker, gateway, APNs sender, and protocol authority
must be deployed as one matched generation on the Mini's `PATH`. Retain the
previous matched generation before upgrading. If rollback is needed, stop
active work through the matching guarded helper and restore the generation as
a unit; never mix relay/backend versions or bypass lease, restore-journal, or
recovery-required state.

An unrelated dirty Mini worktree is not an invitation to deploy over it.
Never reset, clean, checkout, overwrite, or raw-rsync it. List, inspect, wait,
sync, and release through the guarded `remote-agent` protocol only; its lease,
snapshot, divergence, restore-journal, and recovery-required refusals are
authoritative. Mirror verified content and release ownership before changing
host or updating the matched relay/registry generation.

Claude model and effort are authenticated user preferences, not supervisor
launch arguments. For this Mini deployment, select Fable and xhigh once in the
subscription-backed Claude TUI (`/model fable`, then `/effort xhigh`) and verify
that `~/.claude/settings.json` reports `model=fable` and
`effortLevel=xhigh`. The supervisor deliberately continues to launch only
`claude --yolo`; the helper neither copies authentication nor rewrites those
machine-local preferences.

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

### Mac Mini workflows

The `remote-agent-host` skill translates natural-language Mini requests into
one stateless guarded relay:

```text
remote-agent.sh [--host HOST] list
remote-agent.sh [--host HOST] inspect WORKFLOW_ID
remote-agent.sh [--host HOST] wait WORKFLOW_ID --cursor CURSOR --timeout SECONDS
remote-agent.sh [--host HOST] start-conductor PROJECT PLAN_ID
remote-agent.sh [--host HOST] send WORKFLOW_ID --prompt-file FILE [--ack-event SEQ]
remote-agent.sh [--host HOST] interrupt|kill|release|reveal WORKFLOW_ID
remote-agent.sh [--host HOST] sync WORKFLOW_ID [--cancel MIRROR_JOB]
remote-agent.sh [--host HOST] diagnostic ACTION PROJECT HARNESS
```

Ask naturally: “list the Mini workflows”, “resume this workflow”, “check
whether it needs input”, “wait for its next event”, “reveal its Terminal”,
“synchronize and release it”, or “start a Codex diagnostic session”. The relay
never orchestrates locally and stores no workflow state. `list` discovers
opaque workflow IDs; every later resident-workflow operation uses that ID.

`start-conductor` creates the durable Mini-resident workflow. The shipped
registry currently launches the Claude subscription harness for this path.
Codex and Grok desktop sessions use the separate full-lease `diagnostic`
family and must not be described as mobile-resumable workflows.

Prompts travel only through private files. Before every send, inspect and report
at most 40 relevant lines or 4 KiB. Monitoring is event-driven: issue one
blocking `wait`, retain its restart-aware monotonic cursor, then inspect once.
Never loop on captures, screenshots, or Computer Use.

Synchronization is separate from lifecycle control. Kill makes a workflow
quiescent but does not move files or release ownership. `sync WORKFLOW_ID`
queues a mirror job whose safe direction is derived at claim time. Only after a
`mirror-done` event and aligned state may `release WORKFLOW_ID` clear the
lease last. Divergence, live-writer conflicts, CAS loss, restore failure, or
`recovery-required` always fail closed. PID, heartbeat, terminal, exit, and
timeout state never infer staleness.

The Mini and MacBook must run matching relay/registry generations. Exit 127
without a registry envelope indicates version skew, not an absent workflow.
During an upgrade, use only the previously installed matching guarded helper to
quiesce and align the old session; never fall back to raw SSH, rsync, or tmux.

## Testing

Run all 29 shipped plugin suites against installation, helpers, skills,
wrappers, Mini services, and hooks:

```bash
cd orchestration
for test_file in tests/scripts/*.test.sh tests/hooks/*.test.sh; do
  bash "$test_file"
done
```

All 29 suites use shell test harnesses, sandbox under `mktemp -d`,
and clean up after themselves. Each exits non-zero on any failure.

Syntax / lint checks for the shell scripts:

```bash
cd orchestration
bash -n scripts/*.sh hooks/*.sh tests/scripts/*.test.sh tests/hooks/*.test.sh
shellcheck scripts/*.sh hooks/*.sh    # optional but recommended
```

JSON validity (from repo root):

```bash
jq -e . .claude-plugin/marketplace.json orchestration/.claude-plugin/plugin.json orchestration/hooks/hooks.json orchestration/schemas/*.json
```

## Contributing / dev

The full design lives under `docs/`. Read in order:

1. `docs/01-philosophy.md` — the bias (what v2 keeps, drops, why).
2. `docs/02-conductor.md` — the dispatch-only contract.
3. `docs/03-plan-format.md` — the plan/progress/masterPlan schemas.
4. `docs/04-execution-loop.md` — the four-phase runtime.
5. `docs/05-skills-catalog.md` — what each skill triggers on.
6. `docs/06-codex-integration.md` — wrappers + prompt contract.
7. `docs/07-hooks.md` — the six hook events, privacy, and event limits.
8. `docs/08-plugin-layout.md` — target tree + build order.
9. `docs/09-routing-matrix.md` — model routing, panel planning, and verification lanes.
10. `docs/10-grok-integration.md` — Grok wrappers + prompt contract.
11. `docs/11-routing-eval.md` — the routing eval harness that validates the matrix.
12. `docs/12-phone-control-surface.md` — the evolving private phone-control contract.

When you're working on the plugin, your own session is itself an
exercise of the system: a non-trivial change should produce a plan
under `.temp/plan-mode/active/<planId>/`. Look at the existing
archives under `.temp/plan-mode/archive/` for examples of approved
plans and their progress records.

`.claude/CLAUDE.md` is the project-local rule set: markdown only under
`docs/`, no regressions to v1 shape, no `lib/` shared between skills, and
exactly the shipped six-event hook surface. The four lifecycle observers are
fail-open, non-decision, and labels-only; they supersede the former two-hook
rule without restoring gates.

## What v2 does **not** ship

- No signed receipts, HMAC sidecars, or `claude-review-*.md` sibling files.
- No `lbyl-digest` sub-agent.
- No forced-plan hard gates. Reminders only.
- No tool-blocking or decision-returning hooks. Lifecycle observers may append
  sanitized labels to their private queue, but never persist user/model text.
- No `lib/` shared between skills. Skills reference each other by
  name in prose, not by shared imports.
- No secret copying, continuous unguarded synchronization, public workflow
  endpoint, transcript persistence, or raw terminal streaming.

See `docs/01-philosophy.md` for the full rationale.
