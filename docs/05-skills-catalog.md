# 05 — Skills catalog

v2 ships **nine core skills**. They split into one orchestrator
(`conductor`), one infrastructure skill (`persistent-plans`), one
dispatch skill (`codex-dispatch`), and six discipline skills that
shape *how* work is done independent of *what* is being done.

This document is the catalog. For each skill: one-line description,
triggers (when the skill should fire), anti-triggers (when it should
not), and the responsibilities the skill owns.

The full skill prompts live in the implementation repo (see
`08-plugin-layout.md`). This doc is the contract.

---

## 1. `conductor`

**One-line**: The top-level orchestrator skill. Reminds the main
Claude thread that it is in dispatch-only mode and routes work to
sub-agents, Codex, or other skills.

**Triggers**
- Any non-trivial coding task arrives in the main thread.
- The session starts and a plan is active (the `session-start` hook
  surfaces this, and the conductor skill picks it up).
- The user says "let's work on X", "implement Y", "refactor Z", or
  similar.

**Anti-triggers**
- Pure conversational questions ("what does this code do?").
- Trivial one-line edits where the conductor skill's overhead beats
  the change.
- Sessions that are explicitly about meta-work (writing docs in this
  spec repo, for example).

**Responsibilities**
- Enforce the dispatch-only rule from `02-conductor.md`.
- Choose the right skill for each phase: `brainstorming` for
  ambiguous design, `writing-plans` for plan drafting, `refactoring`
  for restructuring, etc.
- Drive the four-phase loop from `04-execution-loop.md`.
- Maintain the TaskList that mirrors `progress.json`.

---

## 2. `engineering-discipline`

**One-line**: The behavioral baseline for any code change — read
imports before editing, track blast radius, no type shortcuts, verify
after every change.

**Triggers**
- Any task that writes, edits, refactors, ports, or migrates code.
- Bug fixes, even one-line ones.
- Dependency bumps and config changes.

**Anti-triggers**
- Pure questions, explanations, or code reading without edits.
- Pure documentation tasks with no source-file changes.
- Conversations that don't touch code.

**Responsibilities**
- Force the executor (Codex or sub-agent) to identify consumers
  before editing shared types/utilities.
- Forbid `any` / `as any` / silent type assertions.
- Require post-change verification (type-check, lint, tests) and
  surface any skipped checks explicitly.
- Catch silent scope cuts ("I'll do X" → only does part of X).

---

## 3. `persistent-plans`

**One-line**: The infrastructure skill that owns the plan files on
disk and the resumption protocol.

**Triggers**
- About to start any non-trivial task (creates a plan).
- Resuming after a compaction (reads the active plan).
- The user says "continue", "where were we", or similar.

**Anti-triggers**
- Pure read-only questions.
- Tasks the user has explicitly tagged "no plan" / "just do it".

**Responsibilities**
- Locate / create the plan directory at
  `.temp/plan-mode/active/<planId>/`.
- Read `plan.json` + `progress.json` at the top of every resumed
  session.
- Recreate the TaskList from `progress.json`.
- Apply the resumption protocol from `04-execution-loop.md`.
- Move completed plans to `archive/`.

---

## 4. `writing-plans`

**One-line**: Draft `plan.json` and `masterPlan.md` from a completed
discovery, drive the Orbit review, then initialize `progress.json`
exactly once at approval via `init-progress`.

**Triggers**
- Discovery is complete and the user wants to commit to a plan.
- The user says "write the plan", "let's plan this", "draft a
  plan.json".
- An existing plan has been invalidated and needs a re-draft.

**Anti-triggers**
- Discovery is incomplete (route to `brainstorming` or `Explore`).
- The user says "just do it" / "no plan".
- Mid-execution (use `persistent-plans` to update progress instead).

**Responsibilities**
- Apply the panel-planning trigger first: high-ambiguity tasks get
  parallel independent drafts (Codex / Grok / Claude) converged by a
  Claude sub-agent before drafting — see `09-routing-matrix.md`,
  Panel Planning.
- Enforce TDD-granularity steps (one component / one behavior).
- Set `dependsOn` correctly to form a valid DAG.
- Generate the `progress[]` checklist on each step.
- Write a tight, human-readable `masterPlan.md`.
- Drive Orbit review and flip `frozen` to true on approval.

---

## 5. `codex-dispatch`

**One-line**: The single wrapper-dispatch authority — owns **both** the
Codex and Grok direction-locked wrapper lanes, invoking each executor
through its wrappers and parsing the bounded Summary / Verdict /
Findings contract block. (No tenth skill: Grok is dispatched from here;
the catalog stays at nine.)

**Triggers**
- A plan step with `owner: codex-impl` or `owner: grok-impl` is on the
  frontier.
- A step's executor needs verification — per the dual mandate in
  `docs/09-routing-matrix.md`: at least one cross-family verifier, and
  Grok always among the verifiers when its lane is available
  (`run-grok-verify.sh` alone for `codex-impl`; BOTH
  `run-codex-verify.sh` and `run-grok-verify.sh` for `grok-impl` /
  `claude-impl`, `done` requiring both PASS; `run-codex-verify.sh` as
  the degraded fallback when the Grok lane is down).
- The conductor needs an out-of-band Codex or Grok check (rare).

**Anti-triggers**
- Implementing a step whose `owner` is `claude-impl` or `manual` —
  verifying finished `claude-impl` work still fires this skill (both
  `run-codex-verify.sh` and `run-grok-verify.sh` per the dual-verify
  policy).
- Tasks that don't go through the plan system (free-form
  conversation).

**Responsibilities**
- Choose the wrapper by direction *and* family: `run-codex-impl.sh` /
  `run-grok-impl.sh` for IMPLEMENT, `run-codex-verify.sh` /
  `run-grok-verify.sh` for VERIFY — never mix. The Grok wrappers take
  the identical CLI shape and emit the same parsed JSON as the Codex
  ones; only the underlying CLI differs.
- Build the prompt from `step.description`, `step.acceptanceCriteria`,
  and `step.files`.
- Parse the contract block out of stdout. Reject and retry once if
  the block is missing.
- On Grok exit 4 (`grok` not on PATH): fall verification back to
  `run-codex-verify.sh` and record the deviation; flip a `grok-impl`
  step `blocked` with reason `grok-unavailable`.
- Write the parsed verdict, findings, and files-touched into
  `progress.json`.
- Never read raw Codex or Grok stream output or treat unparsed text as
  authoritative.

---

## 6. `refactoring`

**One-line**: Multi-file restructuring, renaming across files,
extracting helpers, splitting modules.

**Triggers**
- Renames that span more than one file.
- Moving / splitting modules.
- Extracting shared logic from duplicates.
- The user says "refactor X", "extract Y", "move Z into ...".

**Anti-triggers**
- Single-variable renames within one function.
- Formatting-only changes.
- Adding new features (use `writing-plans` instead).
- Bug fixes (use `systematic-debugging`).

**Responsibilities**
- Discover all consumers before editing (delegated to `Explore`).
- Plan the change in stages so the codebase compiles between
  stages.
- Run type-check / lint / tests after each stage, not just at the
  end.
- Flag any code paths that the refactor leaves stranded.

---

## 7. `test-driven-development`

**One-line**: Enforce a red-green-refactor rhythm for new behavior.

**Triggers**
- Writing a new feature or function with testable behavior.
- The user asks "let's TDD this" or invokes a step whose
  `progress[]` starts with "Write failing tests".
- New behavior in a project that already has test infrastructure.

**Anti-triggers**
- Fixing a bug in already-tested code (use `systematic-debugging`).
- Writing characterization tests for legacy untested code.
- Refactoring without behavior change.
- Projects with no test infrastructure (suggest adding it first).

**Responsibilities**
- Block writing implementation before a failing test exists.
- Verify the test fails for the right reason (red).
- Verify the test passes after implementation (green).
- Recommend a refactor pass after green.
- Encode this rhythm into the step's `progress[]` items.

---

## 8. `systematic-debugging`

**One-line**: Four-phase debugging — investigate, identify pattern,
form hypotheses, fix — to prevent guess-and-check thrashing.

**Triggers**
- A reported bug, test failure, or unexpected behavior.
- The user says "this doesn't work", "X is broken", "fix the bug
  where ...".
- A verifier returns FAIL with concrete findings.

**Anti-triggers**
- Learning a new API (use exploration).
- Refactoring for clarity (use `refactoring`).
- Performance optimization without a regression to investigate.
- New-feature work (use `test-driven-development` /
  `writing-plans`).

**Responsibilities**
- Phase 1 — Investigate: reproduce, narrow inputs, identify the
  smallest failing case.
- Phase 2 — Pattern: explain the symptom in terms of code paths.
- Phase 3 — Hypotheses: list candidate root causes; pick the most
  likely.
- Phase 4 — Fix: change the code; verify the fix; verify no
  regressions.

---

## 9. `brainstorming`

**One-line**: Collaborative dialogue to turn a vague design question
into a concrete proposal before any code is written.

**Triggers**
- Ambiguous user requests ("how should we approach X?", "what's the
  best way to ...?").
- Multiple plausible designs with non-obvious tradeoffs.
- New features where the data model is unclear.
- Pre-discovery, when the conductor isn't sure what to explore.

**Anti-triggers**
- Implementation planning of an already-decided design (use
  `writing-plans`).
- Debugging (use `systematic-debugging`).
- Refactoring of code whose target shape is clear.
- Pure codebase questions ("where is X defined?").

**Responsibilities**
- Ask one question at a time, multiple choice where possible.
- Surface tradeoffs honestly; offer a recommendation but accept
  redirection.
- Converge on a single approach the user has bought into.
- Hand off to `writing-plans` (or directly to execution for small
  changes) with a one-paragraph design summary.

---

## Auxiliary skills

In addition to the nine core skills above, v2 ships nine auxiliary
skills covering the craft-specific work the orchestrator routes to.
Each lives in `skills/<name>/SKILL.md` and follows the same harness
frontmatter convention (`name`, `description`); the harness
auto-discovers them by scanning `skills/<name>/SKILL.md` — no list in
`plugin.json` is needed (the manifest carries only `name`,
`description`, and the `orbit` MCP server).

| Skill | One-line | Routing |
|---|---|---|
| `doc-coauthoring` | Collaborative authoring of RFCs, ADRs, runbooks, API docs, and other prose artifacts | Claude-only (Claude-only skill set in the routing matrix) |
| `frontend-design` | Distinctive production-grade frontend interfaces — landing pages, dashboards, design-system work | Claude-only |
| `svg-art` | Hand-coded SVG artwork — patterns, illustrations, decorative backgrounds, filter effects | Claude-only |
| `immersive-frontend` | Award-winning WebGL / Three.js / scroll-driven 3D experiences | Claude-only |
| `mcp-builder` | Building production-quality MCP servers that expose APIs/databases/services as LLM tools | Codex-default with Claude-side design |
| `react-native-mobile` | Premium native-feeling React Native mobile apps; dual-installable (Claude for UI/UX, Codex for code-heavy) | Conditional — see RN-mobile Routing Directive in `docs/09-routing-matrix.md` |
| `webapp-testing` | End-to-end webapp testing with Playwright; visual regression and accessibility passes | Codex-default with Claude design for test plans |
| `skill-review-standard` | Post-creation quality gate for skills — structural validation, with/without test, trigger overlap | Claude-only (meta) |
| `remote-agent-host` | Guarded natural-language start, continue, wait, inspect, reveal, interrupt, kill, and reclaim lifecycle for supported Mac Mini sessions | Claude-only (host orchestration) |

### `remote-agent-host` lifecycle contract

This skill triggers only when the user asks to start, continue, wait for,
inspect, reveal, control, interrupt, kill, or reclaim work on the configured
Mini. It does not trigger for ordinary local execution, arbitrary remote
administration, or unsupported projects and hosts. Its sole executable
boundary is:

```text
${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh [--host HOST] COMMAND PROJECT [HARNESS] [OPTIONS]
```

The closed command set is `status`, `start`, `inspect`, `continue`, `send`,
`interrupt`, `kill`, `wait`, `reveal`, and `reclaim`; projects are exactly
`miospot` and `orchestration`; harnesses are exactly `claude`, `codex`, and
`grok`. The skill uses only `--host`, `--prompt-file`, `--active-plan`,
`--include-ignored`, `--approve-ignored`, `--cursor`, and `--timeout`. It maps
natural language to that interface. `PROJECT` also selects the local checkout
independently of caller cwd: `LOCAL_MIOSPOT_ROOT` or `$HOME/Projects/miospot`,
and `LOCAL_ORCHESTRATION_ROOT` or `$HOME/Projects/orchestration`. It
defaults the harness to Claude only
when no family was named, puts prompts in private temporary files, and reports
a bounded `inspect` capture before every input. A launch is therefore
`status` → promptless `start` and retain `bootstrapCursor` → `inspect` and
report → `send`, even though the lower-level helper permits an optional prompt
on `start`.

Wait is `${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh wait PROJECT HARNESS
--cursor EPOCH:NUMBER --timeout SECONDS`, with a retained monotonic cursor and
a 1–300 second bound. It is one blocking call, followed by one bounded
`inspect`, never repeated inspection or screenshot polling. `reveal` opens
Terminal on the exact existing `remote-agent--PROJECT--HARNESS` session and
does not send input, replace its pane, synchronize files, or alter ownership.
The first wait uses the bounded labels-only top-level `bootstrapCursor`
returned by a successful `start`, or `supervisor.bootstrapCursor` from the one
nested JSON object returned by a running `status`; later waits retain the most
recent returned epoch and cursor, including across supervisor restarts.

Claude `Stop`, `SubagentStop`, and `StopFailure` map respectively to main
completed, subagent completed, and main failed; the scopes stay distinct. Only
`permission_prompt`, `idle_prompt`, and `elicitation_dialog` are accepted as
input-needed notifications. Tmux exit and timeout are separate wake results.
No event, exit, or timeout proves the writer lease is quiescent; only guarded
kill/reclaim protocol checks do. Event records contain closed labels only, in
private state; prompt, transcript, model, environment, and terminal text are
never queued. Codex and Grok normally produce only exit/timeout wakes because
the lifecycle observers are Claude plugin hooks.

Ownership is a lease, not continuous synchronization. `start` accepts equal
or local-only state and makes the Mini the single writer. `inspect`,
`continue`, `send`, `interrupt`, and `kill` do not synchronize project files;
even a quiescent `kill` does not reclaim them or release the lease. Safe
reclaim checks `status` and `inspect`, obtains termination permission when
needed, and kills and verifies quiescence. Remote-only state then pulls through
private verified staging and releases ownership last; equal+quiescent state is
post-verified and released with zero content transfer. Every writer record is
treated as live/active until an explicit safe protocol transition clears it;
quiescent reclaim is that transition, and PID or heartbeat state never creates
an inferred stale class.

The normal transfer universe is tracked and ordinary untracked regular files.
Ignored content requires exact per-path consent and identical literal values
for `--include-ignored` and `--approve-ignored`; globs, absolute paths,
symlinks, `.git`, directory expansion, and inferred neighbors are excluded.
`--active-plan NAME` adds exactly the selected plan's `plan.json`,
`progress.json`, and `masterPlan.md`, with snapshot-change detection.
Destination apply uses a private restore journal: verified restore leaves
ownership unchanged; failed restore retains authoritative recovery evidence
and the mutex. The local state mirror is diagnostic only. The helper assumes
the Mini protocol, launchers, worktrees, authentication, and transport are
already provisioned. The supervisor launches the installed subscription TUI
for Claude, Codex, or Grok, which must already be authenticated interactively
on the Mini; it promises no backend bootstrap, implicit secret copy,
continuous sync, chat persistence, or reboot survival. A human may attach on
the Mini only through the guarded `reveal` intent; visibility neither changes
ownership nor substitutes for reclaim. The skill never improvises raw tmux or
transport commands, never edits user Claude settings, and uses Computer Use
only for exceptional explicit interaction after a wake—not as a polling loop.

The skill also routes the two cession intents, `cede` and `uncede`, that arm and
cancel a phone-originated Mini-content start. `cede` runs the same canonical
worktree gate under the Mini mutex and issues a single-use, MacBook-issued
cession only from a clean, equal, writer-none relation; `uncede` cancels an
unconsumed one. A phone-started session carries an explicit `origin=phone` writer
record and is live/active exactly like any other lease, and every guarded MacBook
operation fails closed if local content has drifted from an active cession's
baseline. The phone control surface — an installable app served tailnet-only from
the Mini that re-calls the host-independent verbs and queues the two
ownership-changing ones — is specified in full in
`12-phone-control-surface.md`; this catalog is updated to the shipped contract
once that surface lands.

### Codex-side skill bodies (`codex-skills/`)

For the dual-install pattern (currently `react-native-mobile`), Codex
also gets its own copy of the skill body at
`codex-skills/<name>/SKILL.md`. The routing matrix at
`docs/09-routing-matrix.md` decides which side gets which step:
UI/UX/animation work goes to Claude; data-flow / native modules /
code-heavy work goes to Codex. The two SKILL.md files keep the same
wording about the split so both sides see the same rule.

`codex-skills/` is loaded by `codex exec` separately from the Claude
Code plugin manifest; it is not discovered by the Claude Code harness
at all. The wrappers and the user read these bodies directly from the
`codex-skills/` tree.
