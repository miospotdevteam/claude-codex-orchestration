# 07 — Hooks

v2 registers **six Claude Code hook events**. Two context hooks keep the
conductor oriented; four narrowly scoped lifecycle observers feed sanitized
labels to the Mini session supervisor. This six-event design explicitly
supersedes the earlier exactly-two-read-only-hooks design.

None of the six entries is a tool gate. The lifecycle observers are
synchronous, fail open, emit no hook decision, and never edit user Claude
settings. They enqueue only closed labels in private supervisor state; prompt,
message, transcript, environment, model, and terminal text never enter the
queue.

## Event inventory

| Claude Code event | Handler | Purpose |
|---|---|---|
| `SessionStart` (`startup|resume|clear`) | `hooks/session-start.sh` | Inject a bounded active-plan notice. |
| `PostCompact` | `hooks/post-compact.sh` | Re-inject the active plan and runnable frontier. |
| `Stop` | `hooks/agent-event.sh` | Enqueue `main completed`. |
| `SubagentStop` | `hooks/agent-event.sh` | Enqueue `subagent completed`. |
| `StopFailure` | `hooks/agent-event.sh` | Enqueue `main failed`. |
| `Notification` | `hooks/agent-event.sh` | Enqueue `main input-needed` only for the exact allowlist below. |

The four lifecycle event registrations share one handler because their
privacy, binding, and fail-open behavior is identical. “Four observers” means
four event registrations, not four scripts.

## Context hook: `session-start`

`SessionStart` runs for `startup`, `resume`, and `clear`, before the first user
turn. It reads only `.temp/plan-mode/active/`, selects the sole active plan or
the one whose `progress.json` has the newest `lastUpdatedAt`, and emits a short
notice containing the plan ID/title, status counts, runnable frontier, and
relative plan path. With no active plan it emits a one-line standby notice.

It does not mutate plan files, inspect source, invoke another model, spawn an
agent, block a tool, or ask a question. Missing or malformed plan state is a
bounded notice or a silent zero exit; hook failure must not break startup.

## Context hook: `post-compact`

`PostCompact` runs after Claude Code compacts the conductor context. It reads
the active plan's `plan.json` and `progress.json`, recomputes the runnable
frontier through `scripts/plan-utils.sh`, and injects a bounded resumption
notice. It never reconstructs discovery, reads source files, or changes plan
state. Missing state is a short diagnostic and a zero exit.

The separate event prevents `SessionStart` from firing twice around a
compaction.

## Lifecycle observer: `agent-event`

`hooks/agent-event.sh` reads at most one bounded JSON payload from stdin and
accepts only these mappings:

- Main `Stop` → scope `main`, kind `completed`.
- `SubagentStop` → scope `subagent`, kind `completed`.
- Main `StopFailure` → scope `main`, kind `failed`.
- `Notification` with `permission_prompt`, `idle_prompt`, or
  `elicitation_dialog` → scope `main`, kind `input-needed`.

Every other event and notification subtype is ignored. In particular, the
input-needed allowlist is exactly those three values; it is not a substring or
open-ended notification matcher.

The handler requires an exact canonical project-root and tmux-pane binding to
one live `remote-agent--PROJECT--HARNESS` supervisor session. It then invokes
only:

```text
${CLAUDE_PLUGIN_ROOT}/scripts/agent-supervisor enqueue ROOT %PANE SCOPE KIND
```

The private queue lives under
`${XDG_STATE_HOME:-$HOME/.local/state}/orchestration/agent-supervisor/` with
directories mode `0700` and files mode `0600`. Records contain only scope and
kind; the supervisor adds the session atom, epoch, and monotonic cursor when a
wait wakes. The hook passes no stdin to the queue and discards all output.

Malformed input, missing dependencies, ambiguous bindings, queue failures, and
timeouts all exit zero without stdout/stderr. The observer does not return
JSON, `decision`, `continue`, or `stopReason` fields, so it cannot approve,
deny, or steer a Claude turn. Installation is plugin-scoped through
`hooks/hooks.json`; no document, installer, or hook may edit
`~/.claude/settings.json` or another user settings file.

## Event semantics and limits

Lifecycle labels are wake hints, not proofs about the writer lease:

- `Stop` says the Claude main turn completed. It does not say all child
  processes ended, the tmux session exited, or the lease is quiescent.
- `SubagentStop` says one subagent completed. It is intentionally distinct from
  main-turn completion and says nothing about other agents.
- `StopFailure` says the main turn failed. It does not imply session exit or
  safe reclaim.
- `input-needed` says Claude emitted one allowlisted notification. The caller
  must inspect the bounded terminal tail to learn what input is appropriate.
- A supervisor `exit` wake says the exact tmux session is absent.
- A supervisor `timeout` wake says no supported event or tmux exit was observed
  before the 1–300 second deadline.

No event, exit wake, or timeout proves lease quiescence. Only the guarded
`remote-agent.sh kill PROJECT HARNESS` path invokes the synchronization
protocol's quiescence check. Wait, inspect, and reveal never synchronize files,
change ownership, or release a lease.

Claude sessions can produce all three event kinds. Codex and Grok do not run
Claude plugin hooks, so their waits normally wake only on tmux exit or timeout.
An epoch change identifies a supervisor restart; callers retain and resend the
returned `epoch:cursor` so a restart or queued event is not mistaken for fresh
terminal state.

## Event-driven interaction, not visual polling

The natural-language route uses one blocking helper call:

```text
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh wait PROJECT HARNESS --cursor EPOCH:NUMBER --timeout SECONDS
```

After any `event`, `exit`, or `timeout` wake, it performs one bounded
`inspect` (at most 40 lines or 4 KiB) and reports only the relevant tail. It
does not repeatedly inspect, screenshot-poll, or use Computer Use as a watch
loop. Computer Use is exception handling for an explicit interactive problem
after a wake; `reveal` is the supported way to open Terminal on the exact
existing session.

The public helper exposes the restart-aware first-wait cursor without a
separate caller-side supervisor command. A successful `start` returns one
bounded labels-only envelope after lease commit, and `status` composes one
bounded public envelope from its authority probe and exact supervisor state.
Callers retain a running session's `bootstrapCursor` and pass it directly to
`wait`; subsequent wake envelopes replace the retained epoch and cursor.
`inspect` is used after a wake for bounded context, not as a normal first-wait
fallback, and callers never invoke `agent-supervisor` around the guarded
boundary.

The Mini supervisor launches the installed Claude, Codex, or Grok subscription
TUI. Each must already be authenticated interactively on the Mini. Hooks and
handoff never copy API keys, cookies, browser profiles, shell profiles, or
subscription credentials.

## Hook manifest

`hooks/hooks.json` is the executable source of truth. The two context hooks use
10-second bounds. Each of `Stop`, `SubagentStop`, `StopFailure`, and
`Notification` is declared synchronously with `async: false` and a 2-second
timeout so the small label is handed off before Claude exits the hook callback.
All command paths begin with `${CLAUDE_PLUGIN_ROOT}`.

## Validation

The shipped hook suites are:

```text
tests/hooks/session-start.test.sh
tests/hooks/post-compact.test.sh
tests/hooks/agent-event.test.sh
```

They cover plan notices, resumption, exact event mappings, the three-value
input allowlist, payload redaction, private queue permissions, exact session
binding, fail-open behavior, and non-mutation of user settings. See
`docs/08-plugin-layout.md` for the complete source and test inventory.
