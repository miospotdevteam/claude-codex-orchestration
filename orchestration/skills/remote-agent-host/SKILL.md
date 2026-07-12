---
name: remote-agent-host
description: Route natural-language requests to discover, start, continue, inspect, wait for, reveal, control, synchronize, or release supported Mac Mini workflows through the guarded workflow-ID helper. Use when the user asks to manage resident Mini work or a bounded diagnostic harness. Do not use for ordinary local execution, arbitrary hosts or projects, or improvised SSH, tmux, rsync, file-copy, or shell administration.
allowed-tools: Read, Bash, AskUserQuestion
---

# remote-agent-host

Translate the user's Mini intent into the stateless guarded relay:

```text
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh [--host HOST] VERB [ARGUMENTS]
```

This helper is the only transport boundary. Never reconstruct or execute raw
SSH, rsync, tmux, supervisor, workflow-registry, or mirror-worker commands.
Never bypass a refusal. The Mini registry owns workflow identity, lifecycle,
input latches, request replay, mirror jobs, leases, and recovery decisions.
The MacBook relay owns no durable orchestration state.

## Required inputs

- Host: use `REMOTE_AGENT_HOST`, the guarded state-file default, or a literal
  `--host HOST` the user already supplied.
- Project: exactly `miospot` or `orchestration` when starting a workflow.
- Plan selector: one exact plan ID for `start-conductor PROJECT PLAN_ID`.
- Workflow: discover its opaque `WORKFLOW_ID` with `list`; never synthesize it.
- Prompt: place bytes in a private regular file, pass `--prompt-file FILE`,
  then delete the file. Prompt text never belongs in argv, logs, state, or a
  request ID.

If one of these cannot be resolved without guessing, ask one narrow question.

## Closed command set

```text
remote-agent.sh [--host HOST] list
remote-agent.sh [--host HOST] inspect WORKFLOW_ID
remote-agent.sh [--host HOST] wait WORKFLOW_ID --cursor CURSOR --timeout SECONDS
remote-agent.sh [--host HOST] start-conductor PROJECT PLAN_ID
remote-agent.sh [--host HOST] send WORKFLOW_ID --prompt-file FILE [--ack-event SEQ]
remote-agent.sh [--host HOST] send WORKFLOW_ID --cancel-pending
remote-agent.sh [--host HOST] interrupt WORKFLOW_ID
remote-agent.sh [--host HOST] kill WORKFLOW_ID
remote-agent.sh [--host HOST] release WORKFLOW_ID
remote-agent.sh [--host HOST] reveal WORKFLOW_ID
remote-agent.sh [--host HOST] sync WORKFLOW_ID
remote-agent.sh [--host HOST] sync WORKFLOW_ID --cancel MIRROR_JOB
remote-agent.sh [--host HOST] diagnostic ACTION PROJECT HARNESS --prompt-file FILE
```

Every mutation accepts `--request-id ID`. Retain and reuse the printed ID when
replaying the exact same mutation after an ambiguous transport result. Never
reuse it for different prompt bytes or another action.

`start-conductor` is the durable Mini-resident workflow path. The currently
shipped registry launches the Claude subscription harness for that path.
Codex or Grok desktop work uses the separate full-lease diagnostic family:
`diagnostic start|inspect|send|interrupt|kill|release PROJECT HARNESS`, where
`HARNESS` is `claude`, `codex`, or `grok`. A diagnostic session is not a
workflow, does not receive a workflow ID, and must never be presented as
mobile-resumable conductor persistence.

## Intent map

| User intent | Guarded flow |
|---|---|
| List open Mini work or ask which sessions exist | `list`; report workflow IDs, project, phase, input latch, pending message, and mirror labels from the bounded result. |
| Start durable Mini work | `list` first, then `start-conductor PROJECT PLAN_ID`; retain the returned workflow ID and cursor. Start is currently Claude-only. |
| Continue or resume a workflow | `inspect WORKFLOW_ID`, report the bounded state, then `send WORKFLOW_ID --prompt-file FILE`. |
| Check whether input is needed | `inspect WORKFLOW_ID`; send nothing unless the user supplied an answer or instruction. |
| Wait or monitor | One blocking `wait WORKFLOW_ID --cursor CURSOR --timeout SECONDS`, then one `inspect`. Retain the returned cursor. |
| Reveal Terminal | `reveal WORKFLOW_ID`; this sends no input and changes no ownership. |
| Steer, stop, or terminate | Inspect first; then `send`, `interrupt`, or explicit `kill`. |
| Synchronize or reclaim Mini work | Follow the mirror-and-release protocol below. `sync` and `release` are separate operations. |
| Run Codex/Grok/Claude outside a resident workflow | Use the exact `diagnostic ACTION PROJECT HARNESS` family and label it diagnostic. |

For `reveal WORKFLOW_ID`, prompt content is never placed in argv; the action sends no input and never replaces or respawns the existing pane.

## Capture before prompting or messaging

Before every `send`, run `inspect` and report a bounded capture: at most 40
relevant lines or 4 KiB. Classify the workflow as running, waiting for input,
finished, or unclear. Do not paste a transcript. If inspection fails or the
state is unclear, send nothing.

When `inspect` exposes a current input-needed sequence, acknowledge that exact
event with `--ack-event SEQ` on the answer. If the conductor is busy, the
registry may queue one message. A second queued message fails closed with
`queue-full`; do not overwrite it. Use `--cancel-pending` only when the user
explicitly cancels the queued input.

## Event-driven wait

Lifecycle monitoring is one blocking wait, not repeated inspection, Terminal
capture, screenshots, or Computer Use. Use the cursor returned by `list`,
`inspect`, `start-conductor`, or the previous wait. Cursors are monotonic within
their restart-aware epoch; never invent one. Timeout and session exit are wake
results, not proof of process or lease quiescence.

Claude main completion, subagent completion, and failure stay distinct. The
input-needed allowlist is exactly `permission_prompt`, `idle_prompt`, and `elicitation_dialog`.
After any wake, run one bounded `inspect`. Computer Use
is reserved for explicit exceptional interaction after a wake, never polling.

## Safe reclaim: mirror-and-release protocol

Never synchronize while an active writer is still changing the project. Every
writer record remains live/active until an explicit guarded transition clears
it. Never use PID or heartbeat state to infer staleness; tmux, timeout, and lifecycle events cannot infer it either.

1. Run `list` and `inspect WORKFLOW_ID`; report the bounded state.
2. If the workflow is active, request termination authority unless the user
   already explicitly asked to kill/reclaim it.
3. Run `kill WORKFLOW_ID`. A successful kill makes the workflow quiescent but
   does not transfer content or release the lease.
4. Run `sync WORKFLOW_ID`. The registry queues one mirror job; claim-time
   authority derives the safe direction. Never supply or infer a direction.
5. Wait for the labels-only `mirror-done` or `mirror-failed` event. Inspect the
   workflow after the wake. Divergence, live-writer, CAS loss, changed
   snapshots, restore failure, or `recovery-required` is a hard stop.
6. Run `release WORKFLOW_ID` only after the registry proves quiescence and
   aligned content. Release clears ownership last; it is not a file transfer.

An initial seed may use `sync WORKFLOW_ID --seed`. Ignored content is excluded
unless the user approves one exact literal project-relative ignored path and
the identical value is passed to both `--include-ignored PATH` and
`--approve-ignored PATH`. Never approve globs, absolute paths, symlinks,
directories, `.git`, or inferred neighbors.

## Diagnostic full-lease path

Diagnostic sessions exist for direct desktop harness access. Start with
`diagnostic start PROJECT HARNESS`, inspect before input, and use
`diagnostic send PROJECT HARNESS --prompt-file FILE`. The exact harness launch
remains subscription-backed (`claude --yolo`, `codex --yolo`, or
`grok --yolo`). On the provisioned Mini, Claude defaults to `model=fable` and
`effortLevel=xhigh`—the Mini Claude default is Fable xhigh. Those preferences
are provisioning invariants, not as launch flags or launch arguments.

A diagnostic full lease blocks a resident workflow for the same project.
Terminate with `diagnostic kill`, verify through `diagnostic inspect`, then use
`diagnostic release`. Do not claim diagnostic work is visible in the workflow
list or recoverable by the phone app.

## Version-skew refusal

Exit 127 with no registry envelope means the remote `workflow-registry` is not
installed at the expected version. Treat this as deployment version skew. Do
not fall back to raw SSH or reinterpret local diagnostic mirrors as authority.
Use the previously installed, matching guarded helper only for the bounded
migration needed to quiesce and align the old session; then upgrade both sides
before using workflow-ID commands.

## Reporting

Return the user intent, workflow ID or diagnostic project/harness, bounded
observed state, helper action, request ID for mutations, mirror state when
relevant, and whether ownership changed. Redact prompt bodies, raw protocol
payloads, temporary paths, hosts, transcripts, and secrets. A helper refusal is
the final result unless the user changes the request or supplies missing exact
input.
