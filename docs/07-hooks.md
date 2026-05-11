# 07 — Hooks

v2 ships **exactly two hooks**, and both are **read-only**. They
inject short status notices into the conductor's context. They do
not block tool calls, do not mutate files, do not invoke Codex, and
do not enforce gates.

This is a direct reaction to v1, where the hook surface grew to a
dozen gates and mutators that became the primary source of bugs and
friction. v2's principle (`01-philosophy.md`): hooks are the most
expensive surface to maintain because they fire on every event. Keep
the surface minimal.

The two hooks:

1. **`session-start`** — runs once when a Claude Code session
   starts. Looks for an active plan; injects a short notice.
2. **`post-compact`** — runs after the conductor's context is
   compacted. Re-injects the active plan path and current frontier.

This document specifies each in full.

---

## Hook 1: `session-start`

### Trigger event

The Claude Code harness fires `session-start` when:

- A new session is opened in the working directory.
- A session is resumed and the working directory has not changed.

It fires before the user's first prompt is processed.

### Inputs (event payload)

The harness invokes the hook with an environment payload
(canonical form, JSON on stdin or env vars; the implementer chooses
the form that matches the harness API). Fields used:

```json
{
  "cwd": "/abs/path/to/project",
  "sessionId": "<uuid>",
  "ts": "2026-05-11T15:00:00Z"
}
```

### Behavior (read-only)

1. **Locate the active plan.** Scan
   `<cwd>/.temp/plan-mode/active/` for plan directories.
   - Zero directories: no plan active. Emit a one-line notice
     telling the conductor that orchestration is installed but no
     plan is active.
   - One directory: that is the active plan.
   - Two or more: pick the directory whose `progress.json` has the
     latest `lastUpdatedAt`. Emit a notice naming the chosen plan
     and warning that others exist.
2. **Read `plan.json` and `progress.json`** for the chosen plan.
   These are bounded files; the hook reads them fully.
3. **Compute a short summary**:
   - Plan title and ID.
   - Step counts by status (e.g., `2 done · 1 in_progress · 5
     pending`).
   - The current runnable frontier (step IDs and titles).
4. **Emit a notice** in the format below. The hook writes it to its
   stdout (or whatever channel the harness uses for context
   injection).

### Output (injected notice format)

A short markdown block, at most ~12 lines:

```markdown
## Orchestration: active plan

- **Plan**: `auth-refactor-2026-05-11` — Refactor auth to use signed cookies
- **Status**: 2 done · 1 in_progress · 5 pending
- **Frontier**: step-3 (Introduce SignedCookie type), step-4 (Update middleware)
- **Path**: `.temp/plan-mode/active/auth-refactor-2026-05-11/`

The `conductor` skill will pick this up. Read `plan.json` and
`progress.json` before dispatching the frontier.
```

If no plan is active, the notice degrades to:

```markdown
## Orchestration

No active plan in `.temp/plan-mode/active/`. The `conductor` skill
will create one when you start a non-trivial task.
```

### What `session-start` does NOT do

- Does **not** block any tool.
- Does **not** mutate `plan.json` or `progress.json`.
- Does **not** invoke Codex.
- Does **not** read source files outside `.temp/plan-mode/active/`.
- Does **not** spawn sub-agents.
- Does **not** ask the user questions.

If `.temp/plan-mode/active/` is unreadable (permissions, missing),
the hook fails silently — it emits no notice and exits zero. A
broken hook must not break the session.

---

## Hook 2: `post-compact`

### Trigger event

The Claude Code harness fires `post-compact` after it summarizes the
conductor's prior context. By the time this hook runs, the
conductor has lost most in-memory state and is about to receive its
next user turn (or auto-resume turn).

### Inputs (event payload)

```json
{
  "cwd": "/abs/path/to/project",
  "sessionId": "<uuid>",
  "ts": "2026-05-11T16:00:00Z",
  "compactionId": "<uuid>"
}
```

### Behavior (read-only)

The `post-compact` hook's job is the same as `session-start`'s, but
the notice it emits is **action-oriented**, not informational. The
conductor needs to resume execution; the notice should make that
trivial.

1. **Locate the active plan** (same logic as `session-start`).
2. **Read `plan.json` and `progress.json`**.
3. **Compute the runnable frontier** using the algorithm in
   `04-execution-loop.md`.
4. **Emit the resumption notice** below.

If no active plan exists, the hook emits a short note saying so and
does nothing else. (After a compaction with no plan, the conductor
has no orchestration work to resume.)

### Output (injected notice format)

```markdown
## Orchestration: resuming after compaction

- **Plan**: `auth-refactor-2026-05-11` — Refactor auth to use signed cookies
- **Path**: `.temp/plan-mode/active/auth-refactor-2026-05-11/`
- **Status**: 2 done · 1 in_progress · 5 pending
- **Runnable frontier**: step-3, step-4

Resumption protocol (from `docs/04-execution-loop.md`):

1. Read `plan.json` (immutable) and `progress.json` (mutable).
2. Recreate the TaskList from `progress.json`.
3. Compute the frontier — already shown above.
4. Dispatch the frontier in parallel via `codex-dispatch`.

Do not re-read source files or re-run discovery; the plan is your
source of truth.
```

This shape is opinionated on purpose: the conductor wakes into a
clean window and needs explicit, actionable steps. The notice is the
last context-injected message before the conductor's next turn.

### What `post-compact` does NOT do

Same prohibitions as `session-start`:

- Does **not** block any tool.
- Does **not** mutate `plan.json` or `progress.json`.
- Does **not** invoke Codex.
- Does **not** read source files.
- Does **not** spawn sub-agents.

Additionally:

- Does **not** modify the harness's compaction summary itself. The
  hook produces a sibling notice that the harness presents after
  compaction; it does not edit the compaction text.

### Failure mode

If the hook errors (corrupted `progress.json`, missing files), it
emits a single line:

```
## Orchestration: post-compact hook failed; check .temp/plan-mode/active/ manually
```

and exits zero. A broken hook must not break resumption.

---

## What we explicitly did **not** add

For the record, the following hooks were considered and rejected:

- **`pre-edit` / `pre-write`** — would intercept every file edit to
  enforce plan presence. This was the v1 gate; it created the
  /bypass-as-reflex anti-pattern. Replaced by the conductor skill's
  prompt and gentle reminders.
- **`pre-codex`** — would intercept Codex calls to mint receipts.
  No receipts in v2; no need.
- **`pre-bash`** — would gate destructive commands. Out of scope:
  destructive-command policy is the user's, not the plugin's.
- **`post-step`** — would re-verify progress.json after every step.
  The conductor already writes progress.json; double-checking it
  via hook adds nothing.

The bar for adding a third hook in v2 is: it must do something that
cannot be done by a skill or wrapper, it must be read-only, and it
must be cheap to maintain. We expect to clear that bar rarely.

---

## Implementer notes

- Both hooks should be single-file scripts (the implementation
  language is the implementer's choice — Bash, Python, Node — but
  Bash + `jq` keeps deps minimal).
- Both hooks must exit zero. Non-zero exits would risk breaking the
  session.
- Both hooks should run in well under 200ms in the common case.
  Reading two small JSON files and emitting a markdown block is the
  total work.
- Tests for the hooks live in the implementation repo and cover:
  no plan, one plan, two plans (newest wins), corrupted
  `progress.json`, missing `plan.json`.

See `08-plugin-layout.md` for where the hook scripts live in the
plugin tree.

---

## Hook declaration (`hooks/hooks.json`)

Claude Code learns which scripts to fire on which events from
`hooks/hooks.json`. The schema is event-keyed: each top-level key is
a Claude Code event name (e.g. `SessionStart`, `PostCompact`,
`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`) and the
value is an array of handler-group objects. Each handler-group may
include a `matcher` (regex-style filter on event sub-types or tool
names) and a `hooks` array of command entries.

v2's `hooks/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh",
            "async": false,
            "timeout": 10
          }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/post-compact.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Three things to note:

1. **`${CLAUDE_PLUGIN_ROOT}`** is the path Claude Code resolves at
   runtime to the plugin's installation directory. Use it for every
   in-plugin command path; never hard-code absolute paths.
2. **The `SessionStart` matcher is `startup|resume|clear`** — and
   intentionally **not** `compact`. Compaction is handled by the
   `PostCompact` event below, so the session-start notice doesn't
   fire twice on a compaction event.
3. **`async: false` on `SessionStart`** ensures the notice is
   injected before the user's first turn. The `PostCompact` handler
   can run async (default); the resumption notice arrives ahead of
   the conductor's next message either way.

If a third event is ever proposed, the bar from earlier in this doc
applies: it must do something a skill or wrapper cannot, it must be
read-only, and it must be cheap to maintain.
