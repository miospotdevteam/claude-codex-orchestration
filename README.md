# orchestration — v2

This repository is **v2 of the `orchestration` plugin for Claude Code**.
It contains both the design spec (under `docs/`) and the plugin
implementation that descends from it (under `orchestration/`:
`.claude-plugin/plugin.json`, `skills/`, `codex-skills/`, `hooks/`,
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
- Exactly two hooks, both read-only: `session-start` and `post-compact`.
- Direction-locked Codex wrappers (`run-codex-impl.sh`, `run-codex-verify.sh`)
  with a fixed Summary / Verdict / Findings prompt contract.
- A parallel Grok lane (`run-grok-impl.sh`, `run-grok-verify.sh`) sharing
  the same direction-locked contract; see `docs/10-grok-integration.md`.
- Seven plugin-root scripts total: those four wrappers plus
  `plan-utils.sh`, `parse-contract.sh`, and the guarded `remote-agent.sh` Mini
  handoff helper.
- JSON Schemas for `plan.json` and `progress.json`, plus a `masterPlan.md`
  template.

## Repository layout

```
claude-codex-orchestration/      ← repo root = marketplace root
├── .claude-plugin/
│   └── marketplace.json         ← marketplace metadata (this repo as marketplace)
├── README.md                    ← you are here
├── AGENTS.md                    ← the three roles (conductor, sub-agents, Codex)
├── LICENSE                      ← MIT
├── install.sh                   ← conditional uninstall + install via claude CLI,
│                                   plus codex/grok CLI-side skill sync
├── .claude/
│   └── CLAUDE.md                ← context for any Claude session editing this repo
├── docs/                        ← the design spec (markdown only)
│   ├── 01-philosophy.md … 11-routing-eval.md
│
├── orchestration/               ← plugin root (marketplace source: "./orchestration")
│   ├── .claude-plugin/
│   │   └── plugin.json          ← minimal plugin manifest (name, description)
│   ├── skills/                  ← 9 core + 9 auxiliary skills
│   ├── codex-skills/            ← Codex-side bodies for dual-install skills
│   ├── hooks/                   ← hooks.json + two read-only handler scripts
│   ├── scripts/                 ← four wrappers + plan/contract/remote helpers
│   ├── schemas/                 ← JSON schemas for plan + progress files
│   ├── templates/               ← starter templates (e.g. masterPlan)
│   └── tests/                   ← hook + script tests
│
└── eval/                        ← routing-validation eval harness (non-shipped dev tool)
    ├── corpus/                  ← gold tasks per domain (tracked)
    ├── scripts/                 ← bash helpers: score/judge/aggregate (tracked)
    └── results/                 ← scorecards + raw run JSON (gitignored)
```

## Install

Prerequisites:

- Claude Code CLI installed and authenticated.
- `codex` CLI (`codex exec`) installed and authenticated — the impl and
  verify wrappers shell out to it.
- `orbit-mcp` on `PATH` — the plugin declares an `orbit` MCP server
  used to surface `masterPlan.md` for human review before execution
  and to coordinate the plan-mode handoff (`EnterPlanMode` →
  compaction → fresh execution window). On macOS: `brew install
  orbit-mcp` (or follow Orbit's own install docs).
- `jq` on `PATH` — used by the plan helpers, the contract parser, and
  the hooks.

The optional Mac Mini handoff additionally requires local `git`, `ssh`,
`rsync`, and a SHA-256 implementation, plus an already provisioned Mini.
Run it from the requested project's local Git worktree on an attached branch.
The Mini must already expose the `remote-agent-v1` protocol, the
`agent-supervisor` launcher for Claude/Grok, the `mini-agent` launcher for
Codex, and real worktrees at the configured project roots. Configure its SSH
host with `--host`, `REMOTE_AGENT_HOST`, or the single-line
`${XDG_STATE_HOME:-$HOME/.local/state}/orchestration-remote-host` file. The
helper neither installs this backend nor copies SSH keys, API keys, shell
profiles, harness authentication, or other secrets.

### One-liner install (recommended)

Clone this repo somewhere stable, then run `install.sh`:

```bash
git clone https://github.com/miospotdevteam/claude-codex-orchestration.git \
  ~/projects/claude-codex-orchestration
cd ~/projects/claude-codex-orchestration
bash install.sh
```

`install.sh` is idempotent: it uninstalls any existing `orchestration`
plugin, adds (or updates) the marketplace, and installs the latest
version. Safe to re-run after upgrading.

### Manual install (if you prefer)

```bash
# Add this repo as a Claude Code marketplace
claude plugin marketplace add miospotdevteam/claude-codex-orchestration

# Install the plugin from the marketplace
claude plugin install orchestration@claude-codex-orchestration
```

After install, start a Claude Code session in any project. The
`SessionStart` hook injects a one-line notice if an active plan
already exists; otherwise the `conductor` skill is on standby.

### Upgrade

```bash
claude plugin marketplace update claude-codex-orchestration
claude plugin update orchestration
```

Or simply re-run `bash install.sh` from the clone.

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

### Mac Mini handoff

The `remote-agent-host` skill turns natural-language requests into the guarded
`${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh` interface. Its exact CLI is:

```text
remote-agent.sh [--host HOST] COMMAND PROJECT [HARNESS] [OPTIONS]
commands: status, start, inspect, continue, send, interrupt, kill, reclaim
projects: miospot, orchestration
harnesses: claude, codex, grok
options: --prompt-file FILE --active-plan NAME
         --include-ignored PATH --approve-ignored PATH
```

Ask naturally: “start Claude on the Mini for orchestration”, “check what the
Mini Codex session needs”, “continue the Mini Grok session with these
instructions”, “interrupt the Mini agent”, or “reclaim the Mini work locally”.
The project must be exactly `miospot` or `orchestration`; the harness defaults
to `claude` only when no family was named. Prompts go through a private file,
never command-line text. For a new session the skill runs `status`, starts
without a prompt, inspects and reports a bounded capture, then sends the first
prompt. Before any later input it also inspects and reports first.

The command lifecycle is single-writer:

| Command | Meaning |
|---|---|
| `status` | Compare the exact local transfer snapshot with the Mini and report its relation; it is a preflight, not a session transcript. |
| `start` | Accept only equal or local-only state, transfer if needed, launch the exact session, and commit the Mini lease. Remote-only work must be reclaimed first. |
| `inspect` | Capture the bounded session state without synchronizing files. |
| `continue` | Capture, then send one required `--prompt-file`; no file synchronization. |
| `send` | Send one required prompt to an existing session; the natural-language skill performs a separate `inspect` first. |
| `interrupt` | Request an immediate interrupt; it does not release project ownership. |
| `kill` | Terminate the session and verify quiescence; it still does not reclaim files or release the project lease. |
| `reclaim` | Only from remote-only state with no live writer: stage and verify Mini results locally, then release the lease last. |

`start` snapshots the current branch, HEAD, and content of tracked files plus
ordinary untracked regular files. Ignored files, symlinks, `.git`, and files
outside that universe are excluded. One ignored file may be added only when
the user approves one exact literal project-relative path and the identical
string is passed to both `--include-ignored` and `--approve-ignored`; globs,
directories, absolute paths, and inferred neighbors are refused. An active
plan is opt-in with `--active-plan NAME` and adds only
`plan.json`, `progress.json`, and `masterPlan.md` from that one
`.temp/plan-mode/active/NAME/` directory. A changed source snapshot aborts the
handoff. There is no continuous or bidirectional sync while the Mini owns the
lease.

Transfers use private staging and a restore journal. If destination apply
fails and restoration verifies, ownership does not advance. If restoration
also fails, the Mini retains authoritative `recovery-required` evidence and
the mutex; stop and perform explicit administrative recovery rather than
retrying, reclaiming, or bypassing the helper. Stale writers, two-sided
divergence, lost generation checks, live-writer conflicts, and post-sync
mismatches likewise fail closed. Local state under
`${XDG_STATE_HOME:-$HOME/.local/state}/orchestration/remote-agent/` is only a
private diagnostic mirror, not an authoritative backup; the protocol state
and restore journal on the Mini are authoritative.

For a human already logged into the Mini, direct interactive attachment is an
explicit escape hatch: `tmux attach -t remote-agent--PROJECT--HARNESS`, with
the same exact project and harness atoms above. This does not transfer files,
change the lease, or replace `reclaim`; detach rather than killing the tmux
session if work should continue. A live tmux session can outlast a local chat
or SSH disconnect, but this plugin does not provide chat-transport
persistence, a Mini boot service, or reboot survival.

## Testing

Run the twelve shipped plugin test suites against installation, helpers,
skills, wrappers, and hooks:

```bash
cd orchestration
bash tests/scripts/parse-contract.test.sh    # 9 contract-block parsing cases
bash tests/scripts/plan-utils.test.sh        # 6 plan-file helper cases
bash tests/scripts/remote-agent.test.sh      # guarded Mini lifecycle cases
bash tests/scripts/run-codex-impl.test.sh    # Codex impl wrapper cases
bash tests/scripts/run-codex-verify.test.sh  # Codex verify wrapper cases
bash tests/scripts/run-grok-impl.test.sh     # Grok impl wrapper cases
bash tests/scripts/run-grok-verify.test.sh   # Grok verify wrapper cases
bash tests/scripts/skill-contracts.test.sh   # cross-skill contracts
bash tests/scripts/validate-structure.test.sh # skill structure checker
bash tests/scripts/install.test.sh           # install/cache synchronization
bash tests/hooks/session-start.test.sh       # 5 session-start hook cases
bash tests/hooks/post-compact.test.sh        # 4 post-compact hook cases
```

All twelve suites use shell test harnesses, sandbox under `mktemp -d`,
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
7. `docs/07-hooks.md` — what the two hooks may/may-not do.
8. `docs/08-plugin-layout.md` — target tree + build order.
9. `docs/09-routing-matrix.md` — model routing, panel planning, and verification lanes.
10. `docs/10-grok-integration.md` — Grok wrappers + prompt contract.
11. `docs/11-routing-eval.md` — the routing eval harness that validates the matrix.

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
- No Mini backend bootstrap, secret copying, continuous synchronization,
  chat persistence, or Mini reboot-survival guarantee.

See `docs/01-philosophy.md` for the full rationale.
