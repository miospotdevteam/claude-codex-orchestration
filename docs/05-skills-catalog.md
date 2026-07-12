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
- A step's executor needs verification. `codex-primary` always requires final
  PASS verdicts from Codex and Grok; `fable-primary` always requires final PASS
  verdicts from Codex, Grok, and Fable. The requirement is independent of the
  implementation owner and missing lanes block completion.
- The conductor needs an out-of-band Codex or Grok check (rare).

**Anti-triggers**
- Implementing a step whose `owner` is `claude-impl` or `manual` — the skill
  still fires for the Codex and Grok portions of the active profile's review
  gate after implementation finishes.
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
- On Grok exit 4 (`grok` not on PATH), block the step with reason
  `grok-unavailable`; never weaken the active profile's required verifier set.
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
| `doc-coauthoring` | Collaborative authoring of RFCs, ADRs, runbooks, API docs, and other prose artifacts | Portable; active profile selects the model lane |
| `frontend-design` | Distinctive production-grade frontend interfaces — landing pages, dashboards, design-system work | Portable; Fable taste lane in `fable-primary`, Sol taste lane in `codex-primary` |
| `svg-art` | Hand-coded SVG artwork — patterns, illustrations, decorative backgrounds, filter effects | Portable; active profile selects the model lane |
| `immersive-frontend` | Award-winning WebGL / Three.js / scroll-driven 3D experiences | Portable; active profile selects the model lane |
| `mcp-builder` | Building production-quality MCP servers that expose APIs/databases/services as LLM tools | Portable; active profile selects design and implementation lanes |
| `react-native-mobile` | Premium native-feeling React Native mobile apps | Portable; active profile's design-taste route handles UI/UX and frontier route handles code-heavy work |
| `webapp-testing` | End-to-end webapp testing with Playwright; visual regression and accessibility passes | Portable; active profile selects test planning and implementation lanes |
| `skill-review-standard` | Post-creation quality gate for skills — structural validation, with/without test, trigger overlap | Portable meta-skill; active profile selects the reviewer lanes |
| `remote-agent-host` | Guarded natural-language discovery, workflow-ID lifecycle, mirror sync/release, and full-lease diagnostic control for the Mac Mini | Claude-only (host orchestration) |

### `remote-agent-host` lifecycle contract

This Claude-host skill maps user intent to the stateless
`${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh` relay. The current closed
interface discovers durable workflows with `list`, then addresses them by
opaque `WORKFLOW_ID`: `inspect`, `wait`, `send`, `interrupt`, `kill`,
`release`, `reveal`, and `sync`. `start-conductor PROJECT PLAN_ID`
creates a resident workflow. Prompt bytes use a private `--prompt-file`; every
mutation carries a replayable request ID.

The Mini registry—not the caller—owns lifecycle, input latches, queued messages,
mirror jobs, leases, and recovery. Monitoring uses one cursor-based blocking
wait followed by one bounded inspect; screenshots and Computer Use are never a
polling loop. A prompt is sent only after inspection and a bounded report.

File alignment is an explicit mirror operation. Kill establishes quiescence but
does not transfer content or release ownership. `sync WORKFLOW_ID` queues a
job whose direction is derived from claim-time authority; release is permitted
only after verified alignment and clears ownership last. Active-writer,
divergence, CAS, restore, or recovery refusals are final. No PID, heartbeat,
terminal, exit, or timeout signal implies staleness.

The resident `start-conductor` path is currently Claude-subscription-backed.
Direct Claude, Codex, or Grok TUIs use
`diagnostic ACTION PROJECT HARNESS`, which holds a full project lease but is
not a workflow and is not mobile-resumable. The supervisor launches the
subscription harness with its exact `--yolo` command; Mini Claude provisioning
defaults to Fable xhigh without turning that preference into launch flags.

The relay is version-coupled to the Mini registry. Exit 127 without a registry
envelope is deployment skew. Migration may use only the previously installed
matching guarded helper to quiesce and align the old session before both sides
upgrade; raw SSH, rsync, tmux, and local diagnostic mirrors never substitute
for authority.

### Codex host and portable skill bodies

`codex-skills/` contains exactly the four canonical Codex-host orchestration
bodies: `conductor`, `persistent-plans`, `writing-plans`, and
`codex-dispatch`. Codex plugin ingestion requires a conventional `skills/`
directory, so `codex-plugin/skills/` exposes four small entrypoints that load
those canonical bodies from the parent package. The entrypoints are the plugin
discovery surface; `codex-skills/` remains the single source of behavioral
truth.

`external-skills/` contains the exact 13 portable work-skill packages copied
identically into `~/.codex/skills` and `~/.grok/skills` by `install.sh`. It
includes the external-lane React Native body; UI/UX taste routes through the
active profile's design owner, while code-heavy work routes through the
frontier. Claude continues to discover its own bodies from `skills/`.
