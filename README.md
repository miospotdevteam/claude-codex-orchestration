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
- Six hook-event registrations: two bounded read-only notice hooks
  (`SessionStart`, `PostCompact`) plus four narrowly scoped, fail-open,
  non-decision Mini lifecycle observers backed by one private labels-only
  queue bridge. This supersedes the former exactly-two-read-only-hooks design.
- Direction-locked Codex wrappers (`run-codex-impl.sh`, `run-codex-verify.sh`)
  with a fixed Summary / Verdict / Findings prompt contract.
- A parallel Grok lane (`run-grok-impl.sh`, `run-grok-verify.sh`) sharing
  the same direction-locked contract; see `docs/10-grok-integration.md`.
- Nine plugin-root scripts total: those four wrappers, `plan-utils.sh`,
  `parse-contract.sh`, the guarded `remote-agent.sh` host helper, and the
  Mini-side `agent-supervisor` plus `remote-agent-v1` authority.
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
│   ├── hooks/                   ← manifest + 2 read-only notice handlers +
│   │                               1 fail-open private-queue observer handler
│   ├── scripts/                 ← four wrappers + five plan/contract/Mini helpers
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
The requested `PROJECT` selects the local checkout independently of caller cwd:
`miospot` uses `LOCAL_MIOSPOT_ROOT` or `$HOME/Projects/miospot`, and
`orchestration` uses `LOCAL_ORCHESTRATION_ROOT` or
`$HOME/Projects/orchestration`. The selected root must be the canonical,
non-symlink Git toplevel on an attached branch.
The Mini must already expose the shipped `remote-agent-v1` protocol and
`agent-supervisor` as executables on `PATH`; the supervisor launches the
installed `claude`, `codex`, or `grok` subscription TUI. Each TUI must already
be authenticated interactively on the Mini, and real worktrees must exist at
the configured project roots. Configure its SSH
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
bash install.sh
```

`install.sh` is idempotent: it uninstalls any existing `orchestration`
plugin, adds (or updates) the marketplace, and installs the latest
version. It resolves the single absolute `installPath` reported by
`claude plugin list --json` and treats that installed plugin-cache artifact—not
the invoking checkout—as canonical. Claude loads plugin skills from that cache;
the installer removes duplicate plugin-owned copies from `~/.claude/skills`
and syncs the seven injectable lane skills into `~/.codex/skills` and
`~/.grok/skills`. Unowned skills are preserved. Safe to re-run after upgrading.

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

The Mini backend has no fixed installation directory; install the shipped
`orchestration/scripts/agent-supervisor` and
`orchestration/scripts/remote-agent-v1` together on the Mini's `PATH`. Before
upgrading them, retain the previous matched pair. If backend rollback is
needed, stop active sessions through the guarded helper, restore both files
together, and start a new session; never mix backend versions or bypass lease,
restore-journal, or recovery-required state.

The V6 rollout has one known provisional MioSpot lease left by the pre-fix
failed launch. After atomically installing the new matched backend pair, and
before retrying `start`, recover only that exact record from a shell on the
Mini:

```bash
remote-agent-v1 lease-abort temp-rename miospot \
  remote-agent--miospot--claude 0 authority-root-v1
```

The `0` is the recorded lease generation, even though the project generation
is already `1` after its successful common-state CAS. Capture rollout evidence
before and after: the initial status is `relation=equal`,
`writer/lease=provisional`, project generation `1`; the successful transition
leaves `relation=equal`, `writer/lease=none`, project generation `1`, and the
final trace line exactly `lease-abort`. Do not reset common state or project
generation, and do not alter or retry the command if the session, lease
generation, authority token, or provisional state does not match: the closed
transition must refuse that state for explicit investigation.

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
commands: status, start, inspect, continue, send, interrupt, kill, wait, reveal, reclaim
projects: miospot, orchestration
harnesses: claude, codex, grok
options: --prompt-file FILE --active-plan NAME
         --include-ignored PATH --approve-ignored PATH
         --cursor EPOCH:NUMBER --timeout SECONDS
```

Ask naturally: “start Claude on the Mini for orchestration”, “wait for the Mini
Claude agent”, “check what the Mini Codex session needs”, “continue the Mini
Grok session with these instructions”, “reveal the Mini Terminal”, “interrupt
the Mini agent”, or “reclaim the Mini work locally”.
The project must be exactly `miospot` or `orchestration`; the harness defaults
to `claude` only when no family was named. Prompts go through a private file,
never command-line text. For a new session the skill runs `status`, starts
without a prompt, inspects and reports a bounded capture, then sends the first
prompt. Before any later input it also inspects and reports first.

The command lifecycle is single-writer:

| Command | Meaning |
|---|---|
| `status` | Compare the exact local transfer snapshot with the Mini and compose one bounded envelope from authority state plus exact supervisor session/bootstrap state. A running session includes a directly reusable `bootstrapCursor`; status is a preflight, not a transcript. |
| `start` | Accept only equal or local-only state, transfer if needed, launch the exact session, commit the Mini lease, and return its bounded `bootstrapCursor` envelope. Remote-only work must be reclaimed first. |
| `inspect` | Capture the bounded session state without synchronizing files. |
| `continue` | Capture, then send one required `--prompt-file`; no file synchronization. |
| `send` | Send one required prompt to an existing session; the natural-language skill performs a separate `inspect` first. |
| `interrupt` | Request an immediate interrupt; it does not release project ownership. |
| `kill` | Terminate the session and verify quiescence; it still does not reclaim files or release the project lease. |
| `wait` | Block once for a labels-only lifecycle event, tmux exit, or timeout using a retained `--cursor EPOCH:NUMBER` and a 1–300 second `--timeout`; then perform one bounded inspect. |
| `reveal` | Open Terminal on the exact existing `remote-agent--PROJECT--HARNESS` session without input, pane replacement, synchronization, or ownership changes. |
| `reclaim` | With no live writer, remote-only state uses verified inbound staging and content transfer before releasing the lease last; equal+quiescent state is release-only with zero content transfer. |

Claude `Stop`, `SubagentStop`, and `StopFailure` mean main-turn completed,
subagent completed, and main-turn failed; they are distinct. Only
`permission_prompt`, `idle_prompt`, and `elicitation_dialog` are treated as
input-needed notifications. Tmux exit and timeout are separate wakes. None of
these signals proves lease quiescence—only guarded kill/reclaim protocol checks
do. Private event-file contents contain only allowlisted `scope` and `kind`
labels; the filename carries the cursor, and the supervisor adds session,
epoch, and cursor to the wait envelope. Prompt, transcript, model, environment,
and terminal text are excluded.
Codex and Grok normally expose only exit and timeout because Claude plugin hooks
do not run in those TUIs.

Lifecycle monitoring is event-driven: issue one blocking `wait`, then one
bounded `inspect` (at most 40 lines or 4 KiB). Do not loop on inspect or
screenshots. Computer Use is reserved for an explicit exceptional interactive
problem after a wake, not a polling loop.

`wait` uses a restart-aware cursor retained from `start`, a running `status`, or
a prior wait result. `start` returns a bounded labels-only envelope after lease
commit; `status` composes authority and supervisor state after its
synchronization probe. Its `bootstrapCursor` is passed directly to the first
wait, so bounded inspect is no longer a cursor fallback. The skill never
guesses a cursor or invokes the Mini supervisor directly.

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
retrying, reclaiming, or bypassing the helper. Every writer record remains
live/active until an explicit safe protocol transition clears it; two-sided
divergence, lost generation checks, active-writer conflicts, and post-sync
mismatches likewise fail closed. No PID, heartbeat, tmux, timeout, or event
signal is used to infer process staleness. Local state under
`${XDG_STATE_HOME:-$HOME/.local/state}/orchestration/remote-agent/` is only a
private diagnostic mirror, not an authoritative backup; the protocol state
and restore journal on the Mini are authoritative.

For a human who needs interactive visibility, ask to “reveal the Mini
Terminal.” The guarded `reveal PROJECT HARNESS` route attaches Terminal to the
exact session without sending input or replacing its pane. Visibility does not
transfer files, change the lease, or replace reclaim. A live tmux session can
outlast a local chat or SSH disconnect, but this plugin does not provide
chat-transport persistence, a Mini boot service, or reboot survival.

## Testing

Run the fifteen shipped plugin test suites against installation, helpers,
skills, wrappers, and hooks:

```bash
cd orchestration
bash tests/scripts/parse-contract.test.sh    # contract-block parsing cases
bash tests/scripts/plan-utils.test.sh        # plan-file helper cases
bash tests/scripts/agent-supervisor.test.sh  # Mini session/event adapter cases
bash tests/scripts/remote-agent-protocol.test.sh # Mini authority/lease cases
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
bash tests/hooks/agent-event.test.sh         # private lifecycle observer cases
```

All fifteen suites use shell test harnesses, sandbox under `mktemp -d`,
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
- No Mini backend bootstrap, secret copying, continuous synchronization,
  chat persistence, or Mini reboot-survival guarantee.

See `docs/01-philosophy.md` for the full rationale.
