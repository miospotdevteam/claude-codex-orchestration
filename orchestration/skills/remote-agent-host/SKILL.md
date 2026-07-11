---
name: remote-agent-host
description: Route natural-language requests to start, continue, inspect, wait for, reveal, control, or reclaim a supported agent session on the configured Mac Mini through the plugin's guarded helper. Use when the user asks to launch work on the Mini, check whether the Mini agent needs input, wait for lifecycle progress, show its Terminal, steer or stop it, resume it with more input, or safely bring its work back. Do NOT use for ordinary local execution, arbitrary remote hosts or projects, remote shell administration, or requests to improvise SSH, tmux, file-copy, or rsync commands.
allowed-tools: Read, Bash, AskUserQuestion
---

# remote-agent-host

Translate the user's Mini intent into the shipped guarded helper. The helper is
the only transport and session-control boundary:

```sh
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh [--host HOST] COMMAND PROJECT [HARNESS] [OPTIONS]
```

Do not substitute the following skill-local-looking path; it is not the
shipped entry point in this layout:

```text
${CLAUDE_PLUGIN_ROOT}/skills/remote-agent-host/scripts/remote-agent.sh
```

Never reconstruct, remember, suggest, or execute raw SSH, rsync, tmux, or
supervisor commands. Do not bypass a helper refusal. The helper's preflight,
mutex, lease, generation, snapshot, and quiescence checks are authoritative.
This skill is Claude-only natural-language orchestration: do not send it to an
external implementation lane and do not create a `codex-skills` copy.

## Required inputs

Resolve these from the user's request and current context:

- `PROJECT`: exactly `miospot` or `orchestration`. Ask if ambiguous.
- `HARNESS`: exactly `claude`, `codex`, or `grok`; default to `claude` only
  when the user did not name an agent family.
- Mini host: use the helper's configured `REMOTE_AGENT_HOST` or state-file
  default. Pass `--host` only when the user explicitly supplies a host.
- Prompt text: write it to a private temporary file, pass only
  `--prompt-file FILE`, and delete the file after the helper returns. Never put
  prompt content in argv or interpolate it into a shell command.
- Active plan: pass `--active-plan NAME` only for a known active plan and only
  as its single directory name.

The helper selects the local checkout from `PROJECT`, independent of caller
cwd: `miospot` uses `LOCAL_MIOSPOT_ROOT` or `$HOME/Projects/miospot`, while
`orchestration` uses `LOCAL_ORCHESTRATION_ROOT` or
`$HOME/Projects/orchestration`. If the project, harness, host, or plan cannot
be resolved without guessing, ask one narrow question instead of attempting a
transport command.

## Intent map

In the commands below, use the resolved literal `PROJECT` and `HARNESS` atoms;
add `--host HOST` immediately after `remote-agent.sh` only when the user named a
host.

| User intent | Exact guarded helper flow |
|---|---|
| Start Mini work, launch an agent on the Mini | Run the exact `status` → promptless `start` and retain its `bootstrapCursor` → `inspect` and report → private-file `send` recipe below. |
| Continue Mini work or resume it with new instructions | Run the exact `inspect` and report → private-file `continue` recipe below. |
| Inspect for input, check whether the agent is waiting, or ask what it needs | Run the exact `inspect` recipe below; summarize the bounded captured state and send nothing. |
| Wait or monitor the Mini agent for lifecycle progress | Use the retained cursor, or run one `status` to obtain its running-session `bootstrapCursor`, then run the exact single blocking `wait` recipe below; retain the returned monotonic wait cursor, run one `inspect` after any wake, and report only the bounded result. |
| Reveal or show the Mini Terminal | Run the exact `reveal` recipe below; it attaches Terminal to the existing `remote-agent--PROJECT--HARNESS` session without replacing its pane. |
| Control Mini work, steer it, or tell it something | Inspect and report first, then use the exact private-file `send` recipe below. Use the exact `interrupt` recipe for stop-now and `kill` for explicit termination. |
| Reclaim Mini work or take over locally | Follow the reclaim protocol below; only then run the exact `reclaim` recipe. |

```sh
# start
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh status PROJECT HARNESS
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh start PROJECT HARNESS
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh inspect PROJECT HARNESS
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh send PROJECT HARNESS --prompt-file FILE

# continue / inspect / wait / reveal
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh inspect PROJECT HARNESS
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh continue PROJECT HARNESS --prompt-file FILE
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh wait PROJECT HARNESS --cursor EPOCH:NUMBER --timeout SECONDS
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh reveal PROJECT HARNESS

# steer / stop / terminate / reclaim
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh send PROJECT HARNESS --prompt-file FILE
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh interrupt PROJECT HARNESS
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh kill PROJECT HARNESS
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh reclaim PROJECT HARNESS
```

`status` is a synchronization preflight, not a substitute for `inspect` when
the user asks what the agent is doing or whether it needs input. It returns
exactly one status JSON object with `authority` and `supervisor` members. The
`authority` member contains the synchronization probe, and the `supervisor`
member contains the bounded labels-only session state. For a running session,
retain `supervisor.bootstrapCursor` and reuse it directly as `--cursor`. A
successful `start` returns a distinct bootstrap envelope after its lease
commit; retain that envelope's top-level `bootstrapCursor`.

## Capture-before-input contract

Capture state before every prompt or message, including the initial prompt.
Before every prompt or message is sent to an existing or newly started Mini
session, run `inspect` and report the captured state to the user. Keep the
report bounded: at most 40 relevant terminal lines or 4 KiB, whichever is
smaller. State whether the session appears running, waiting for input,
finished, or unclear; include only the small tail needed to support that
classification. Do not paste a full transcript or raw diagnostic dump.

Only after that report may `continue` or `send` transmit the prompt. If inspect
fails or the state is unclear, send no input and report the helper failure.
This applies to initial instructions too: start the session without a prompt,
inspect it, report the capture, and then send the initial prompt.

## Lifecycle wait and Terminal reveal

Lifecycle monitoring is a blocking event wait, not repeated `inspect` calls.
Pass the most recent restart-aware cursor back to `wait`; cursors increase
monotonically; retain the monotonic wait cursor. A changed epoch identifies a
supervisor restart. Main-turn
completion and subagent completion remain distinct event scopes. `Stop` means
the Claude main turn completed, `SubagentStop` means one Claude subagent
completed, and `StopFailure` means the main turn failed. The input-needed
allowlist is exactly `permission_prompt`, `idle_prompt`, and `elicitation_dialog`;
every other notification is ignored. Timeout and tmux
session exit are normal, distinct wake results. A timeout means no supported
event or exit was observed before the deadline, and tmux exit means only that
the session is absent. Neither those results nor any Claude hook event proves
process or lease quiescence. Codex and Grok normally expose only exit and
timeout because plugin lifecycle events are emitted by Claude hooks.

Do not invent an initial cursor. Retain the top-level `bootstrapCursor` from a
successful `start`, or `supervisor.bootstrapCursor` from the one nested JSON
object returned by a running `status`, and pass that exact `EPOCH:NUMBER`
directly to the first `wait`. When no cursor is available in current context,
run `status` once as the normal bootstrap path; if its `supervisor` member
reports the exact session absent and therefore has no `bootstrapCursor`, report
that there is no running session to wait for. Never use `inspect` to synthesize
a cursor or bypass the helper by invoking the Mini supervisor directly.

After an event wake, keep a bounded `inspect` capture of at most 40 lines or 4 KiB.
The capture is ephemeral output;
event envelopes never contain or persist pane, model, or user text. A wait or
event never synchronizes the worktree, mutates ownership, or releases a lease.
Never loop on `inspect`, screenshots, or Computer Use to detect progress.
Computer Use is reserved for exceptional interactive recovery after an event
or explicit user request, not lifecycle polling.

`reveal` opens the Mini Terminal on the exact existing
`remote-agent--PROJECT--HARNESS` tmux session. Reveal prompt content is never placed in argv;
reveal sends no input and never replaces, respawns, or kills the existing pane.
It is visibility only: it does not start a session or alter lease state.

The supervisor starts the installed `claude`, `codex`, or `grok` subscription
TUI in tmux. Authentication must already exist on the Mini through that TUI's
normal interactive subscription login. Never copy API keys, browser profiles,
cookies, or local authentication material and never edit user Claude settings
to install or emulate lifecycle hooks; the plugin manifest owns its hooks.

## Synchronization safety

Never sync or synchronize files while an active writer owns the project on
the Mini. The existence of any writer record is treated as live/active until
an explicit safe protocol transition clears it; a quiescent record is eligible
only for that guarded reclaim transition, not for a new start. Never use PID or
heartbeat signals to infer a stale writer; tmux state, timeout, and lifecycle
events cannot infer one either.
Treat an active-writer, mutex, lease, CAS, divergence, changed-snapshot, or
recovery-required refusal as a hard stop. Report the bounded error and do not
retry through another command or transport.

Normal outbound start may transfer tracked and ordinary untracked files. An
ignored file or ignored path is excluded unless all of these are true:

1. The user names and approves one exact, literal, project-relative ignored
   path. General consent such as "include ignored files" is insufficient.
2. Repeat the exact path in the confirmation question and receive explicit
   approval for that same spelling.
3. Pass the identical string to both `--include-ignored PATH` and
   `--approve-ignored PATH`. Never approve a glob, directory expansion,
   absolute path, symlink, `.git` content, or inferred neighboring file.

If more than one ignored path is needed, handle each as a separate explicit
decision rather than widening the transfer universe.

## Safe reclaim protocol

Reclaim means safely returning ownership to the local host. Remote-only state
may also return content; reclaim is never permission to race the Mini writer.

1. Run `status` and `inspect`, then report their bounded state.
2. If any writer or agent is active, do not sync. Ask for explicit permission
   to terminate it unless the user already explicitly requested kill/reclaim
   with termination.
3. Run `kill PROJECT HARNESS`. A successful kill includes the helper's
   quiescence check. If kill or quiescence confirmation fails, do not reclaim.
4. Run `status` again. Proceed only when the helper reports a quiescent writer
   record and either remote-only state or equal state. Quiescence authorizes
   only the guarded reclaim transition; the writer record remains active until
   that transition clears it.
5. Run `reclaim PROJECT HARNESS` once. Remote-only is the only content-transfer
   path and uses verified inbound staging; equal+quiescent is release-only with
   zero content transfer. Report the bounded result and stop on any mismatch,
   divergence, active-writer, CAS, restore, or recovery error. Reclaim is the
   explicit safe protocol transition that clears a quiescent writer record;
   no process-age heuristic can substitute for it.

## Reporting

Return a compact result containing the intent handled, project and harness,
the bounded captured state observed before input, the helper action attempted,
and whether local or Mini ownership changed. Redact prompt bodies, host secrets,
temporary paths, and raw protocol payloads. A helper failure is the final
result unless the user changes the requested action or supplies missing exact
confirmation.

When validating edits to this skill, the structural checker is available at
`${CLAUDE_PLUGIN_ROOT}/skills/skill-review-standard/scripts/validate-structure.sh`.
