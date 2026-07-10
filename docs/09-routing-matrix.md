# 09 — Routing Matrix

Canonical task-type routing table for assigning each plan step's
`owner` — one of `claude-impl` / `codex-impl` / `grok-impl` /
`manual`, the exact enum in `schemas/plan.schema.json`. Consumed by the
`writing-plans` skill during plan creation and by the `codex-dispatch`
skill during execution.

See also: `docs/05-skills-catalog.md` for the v2 skill catalog,
`docs/06-codex-integration.md` for the bounded Codex contract,
`docs/02-conductor.md` for the dispatch-only rule.

**Conductor mode is the default**. The main Claude thread does not
write code directly — it dispatches every non-trivial step to a
subagent (`general-purpose` for `claude-impl`, Codex via
`run-codex-impl.sh` for `codex-impl`) and reads only the parsed Codex
contract block (`{summary, verdict, findings, filesTouched}`) or a
sub-agent's bounded return message. **Codex is the default
implementer.** Claude-impl is the narrow exception, gated on the
Claude-only skill list (or the RN-mobile Routing Directive).

---

## Decision Axes

Every routing decision reduces to two axes. Name them; the scorecard
and the conductor's escalation both read from them.

- **Intelligence** — how hard a problem the model carries
  *unsupervised*: depth of reasoning, holding a spec in one pass,
  tracking blast radius across many files. Drives backend logic,
  migrations, debugging, and large refactors.
- **Taste** — judgment about the shape of the artifact a human will
  read or maintain: API / SDK surface, UI / UX, naming, copy, and
  writing code that is idiomatic *for its language* (not
  TypeScript-as-Python or Rust-as-paranoid-C++). Drives frontend,
  public interfaces, docs, and product copy.

**Cost** is not a third selection axis — it is the tiebreak (see the
policy below). One fact about cost is load-bearing, though: on a Codex
subscription (the plugin's expected setup), **gpt-5.6-sol via the Codex
wrappers is effectively free at the margin** and runs *off the
conductor's context*. That is why Codex is the default implementer —
not because it has the most taste, but because it is intelligent,
cheap, and off-context. Reach for it liberally on bulk mechanical work.

**Orchestrator economics.** The conductor seat gets the strongest
available model (Fable) because orchestration is *few-tokens* work when
delegation holds: the conductor reads only bounded contract blocks and
sub-agent summaries, never raw artifacts, so its tier price is a small
share of total spend. Bad routing decisions are the expensive failure
mode, not the conductor's per-token rate. Empirical grounding:
Anthropic's multi-agent research system — an Opus lead orchestrating
Sonnet subagents — outperformed single-agent Opus by 90.2%, and the
orchestrator's token share of the run was small. A lean, cache-stable
conductor context bills mostly *cached* input, cheapening the seat
further. **Sonnet 5 is the sanctioned economy conductor** for routine
sessions where the strongest seat is not warranted.

---

## Model Scorecard

The conductor reaches six models. Route by the axis the step is
*bottlenecked* on, then escalate per the policy below.

| Model | Reached via | Intelligence | Taste | Route here for |
|---|---|---|---|---|
| **Fable 5** | `Agent(model: "fable")` | highest | highest | Plan drafting and convergence (the Claude panel seat is always Fable when available); the hardest *and* most user-facing implementation; end-to-end multi-step work that needs both axes at once — the "steer everything" tier. |
| **Opus 4.8** | `Agent(model: "opus")` | high | high | Default Claude-side implementation floor; strong all-rounder when a step needs real taste but is not the top of the pile. |
| **Sonnet 5** | `Agent(model: "sonnet")` | mid | mid | Cheap, read-heavy scouting and mechanical Claude-side work where taste does not ship. Never the default for code that lands. |
| **Codex / gpt-5.6-sol** | `run-codex-impl.sh` / `run-codex-verify.sh` | high | low | Bulk mechanical work, clear-spec backend, migrations, and off-context implementation. Also the independent second perspective on verify. |
| **Grok 4.5** | `run-grok-impl.sh` / `run-grok-verify.sh` | high | low-mid | Bulk mechanical work, clear-spec backend, migrations — the *second* off-context implementer; also the independent cross-family verifier for `codex-impl` steps. |
| **Haiku** | — | low | low | **Never for real work.** Not an execution or verification tier. |

The Claude tiers (Fable / Opus / Sonnet) are selected via the `model`
field on the `Agent` tool. Codex and Grok are each reached only through
their direction-locked wrappers; callers never supply a model to either
wrapper pair (see *Machine defaults* at the bottom of this doc).

### Measured evidence (2026-07 routing eval)

The scorecard above is priors plus measurement. What the eval runs
(`docs/11-routing-eval.md`; results stay local under `eval/results/`)
actually established:

- **Correctness parity on clear specs.** codex/sol, grok, and opus
  were unanimously perfect across two hard adversarial tasks and a
  375,000-operation differential fuzzer. At frontier tier, correctness
  cannot rank implementers — so clear-spec implementation routing is
  an **economics** decision (marginal cost, off-context execution,
  parallel lanes), which is exactly the Codex-default policy. The
  policy stands on measurement now, not on an intelligence prior.
- **Codex taste is task-dependent; rating unchanged.** Measured at
  parity with Opus on data-model-heavy design (4.89 vs 4.97 blind
  panel) but far below on business-logic / tool-surface design
  (3.65 vs 5.00). The scorecard keeps `taste: low` until a wider
  corpus confirms the split; the taste-escalation rule stays as-is.
- **Judge honesty differs by family.** Blind self-scoring
  (harshness-adjusted): codex **+0.30**, fable **+0.47**; grok
  **−0.04**, opus **−0.06**. This grounds the cross-family
  verification rule and the arbitration guard in Hard Boundary 10.
- **Panel planning beats solo and relay** — see the Panel Planning
  section below.

### grok-impl vs codex-impl

Both are off-context external implementers; the routing question is
*which lane*. **Codex remains the default external implementer.** A step
is routed `grok-impl` in three cases:

- **Parallel capacity** — the Codex lane is saturated and a step is
  otherwise runnable; Grok is the second lane.
- **Bulk sweeps** — mechanical work where a second lane doubles
  throughput (splitting a large sweep across both lanes).
- **Explicit routing** — the plan author routes the step `grok-impl`
  outright.

Absent one of these, `codex-impl` is the default.

---

## Escalation & Tiebreak Policy

The scorecard gives defaults, not limits. The conductor applies four
rules on top of it:

1. **Defaults, not limits.** A lower tier's output that does not meet
   the bar is re-dispatched to a higher tier *without asking*. Judge
   the output, not the price tag — escalating costs less than shipping
   mediocre work.
2. **Taste escalation is a first-class move.** Codex is the default
   implementer, but when the artifact is user-facing (SDK, public API,
   UI, copy), route the *design* to a Claude tier first, or add a
   Claude taste-pass after Codex. This is the dual-pass review and the
   "Claude reviews Codex integration impact" rows made explicit.
3. **Tiebreak for anything that ships: intelligence > taste > cost.**
   Cost decides only when intelligence and taste do not. It never
   blocks the right model for work that lands.
4. **Never route real work to Haiku**, and never let Sonnet own code
   that ships — Sonnet is for cheap read-heavy scouting only.

---

## How to Use This Table

When creating a plan, classify each step by its **task category** (left
column). The table gives the default `owner` and the conditions under
which the default should be overridden. Steps may span multiple categories
— use the category that best describes the step's *primary* work.

If a step would naturally span both Claude-suitable and Codex-suitable
work (mixed ownership), **split it into two sequential steps with
`dependsOn`**. The plan schema does not support per-step mixed
ownership: every step has exactly one `owner`. A category whose owner
cell lists more than one owner (e.g. `claude-impl` → `codex-impl`) is a
*decomposition hint* — it produces that many `dependsOn`-ordered steps,
not one multi-owner step.

---

## Task-Type Routing Table

| Task Category | Default Owner | Override Conditions |
|---|---|---|
| **Frontend UI / visual design / UX polish** | `claude-impl` | Skill must be in Claude-only set (`frontend-design`, `svg-art`, `immersive-frontend`). |
| **Product copy / UX text / content** | `claude-impl` | Skill `doc-coauthoring`. |
| **Creative / landing page / marketing** | `claude-impl` | Skill `frontend-design` / `immersive-frontend` / `svg-art`. |
| **Brainstorming / requirements shaping** | `claude-impl` | Skill `brainstorming`. Codex co-explores in parallel and reviews `design.md` before `writing-plans`. |
| **Plan writing** | `claude-impl` | Skill `writing-plans`. High-ambiguity tasks trigger **automatic panel planning** (see the Panel Planning section below). |
| **Documentation / API docs / specs** | `claude-impl` | Skill `doc-coauthoring`. Codex verifies technical accuracy via `run-codex-verify.sh` contract block. |
| **MCP / DB / API / external integration** | `codex-impl` | If the step is purely external-facing design (no code), it may be `claude-impl` with a one-line routing justification in the step description. Otherwise split into design step (`claude-impl`, `doc-coauthoring`) and impl step (`codex-impl`) with `dependsOn`. |
| **Cross-domain integration** | `codex-impl` | Split mixed work into sequential steps: design (`claude-impl`) → backend impl (`codex-impl`) → frontend impl (`claude-impl`) with `dependsOn`. |
| **Backend from clear spec (CRUD, services)** | `codex-impl` | — |
| **API route / service implementation** | `codex-impl` | — |
| **Refactor across many files** | `codex-impl` | Claude reviews integration impact via verification subagent. |
| **Framework / library migration** | `codex-impl` | Add a leading design step (`claude-impl`, `doc-coauthoring`) with `dependsOn` if strategy needs human framing. |
| **Dependency upgrade** | `codex-impl` | Same as migration: optional leading design step for breaking-change discussion. |
| **i18n string extraction sweep** | `codex-impl` | Add a leading convention-defining step (`claude-impl`) with `dependsOn` if convention is ambiguous. |
| **Bug investigation / root cause analysis** | `codex-impl` | Skill `systematic-debugging`. |
| **Failing test / CI failure** | `codex-impl` | Skill `systematic-debugging`. |
| **Performance optimization** | `codex-impl` | Investigation step is `codex-impl`. Fix steps assigned after via Dynamic Routing: backend → `codex-impl`, frontend → `claude-impl`. |
| **Security review / audit** | `codex-impl` + `claude-impl` | Dual-pass verification, both passes independent: a `codex-impl` step for the implementation-level audit and a separate `claude-impl` step for the design-level review. Split into two independent single-owner steps. |
| **Security-sensitive design** | `claude-impl` | Skill `brainstorming` / `doc-coauthoring`. Codex does adversarial challenge pass via `run-codex-verify.sh`. |
| **CI/CD pipeline setup** | `codex-impl` | — |
| **Test writing** | `codex-impl` | Gets TDD skill injected. |
| **PR review** | `codex-impl` + `claude-impl` | Dual-pass, both passes independent: a `codex-impl` step for correctness/security and a separate `claude-impl` step for design/architecture. Split into two independent single-owner steps. |
| **Post-step verification** | `codex-impl` | Not a plan step — a verification dispatch. Codex's verification of `claude-impl` runs via `run-codex-verify.sh` and emits a Summary / Verdict / Findings contract block. Verification is structural, not a step. |
| **Design system update (tokens)** | `claude-impl` → `codex-impl` | Sequential `dependsOn` steps. Step A: design tokens + core primitives (`claude-impl`, `frontend-design`). Step B: sweep components to use tokens (`codex-impl`, `dependsOn: [A]`). |
| **Dark mode / theming** | `claude-impl` → `codex-impl` | Sequential `dependsOn` steps. Step A: theme system + ThemeProvider (`claude-impl`, `frontend-design`). Step B: sweep components (`codex-impl`, `dependsOn: [A]`). |
| **Dashboard with charts** | `claude-impl` → `codex-impl` → `claude-impl` | Sequential `dependsOn` steps. Step A: layout shell (`claude-impl`, `frontend-design`). Step B: data hooks (`codex-impl`, TDD). Step C: wire charts (`claude-impl`, `dependsOn: [A, B]`). |
| **Real-time / collaborative features** | `claude-impl` → `codex-impl` → `claude-impl` | Sequential `dependsOn` steps. Step A: architecture decision (`claude-impl`, `brainstorming`). Step B: backend (`codex-impl`). Step C: frontend (`claude-impl`, `frontend-design`). `dependsOn` chain or fan-in as appropriate. |
| **Stripe / payment integration** | `claude-impl` → `codex-impl` → `claude-impl` | Sequential `dependsOn` steps. Step A: external API surface design (`claude-impl`, `doc-coauthoring`). Step B: internal services + DB models (`codex-impl`, `dependsOn: [A]`). Step C: webhooks/checkout UI (`claude-impl`, `dependsOn: [B]`). |
| **Plugin / MCP development** | `claude-impl` → `codex-impl` | Sequential `dependsOn` steps. Step A: skills + MCP surface (`claude-impl`, `mcp-builder` or `doc-coauthoring`). Step B: hooks + scripts + manifest (`codex-impl`, `dependsOn: [A]`). |
| **React Native (mobile) UI/UX** | `claude-impl` | Skill `react-native-mobile`, **conditional** per the RN Routing Directive (see RN section below). |
| **React Native (mobile) code-heavy** | `codex-impl` | Skill `react-native-mobile`, **conditional** per the RN Routing Directive (see RN section below). |
| **Desktop-GUI / computer-use (drive a desktop app, an OS dialog, a GUI-only workflow, visual verification of a native app)** | `codex-impl` | Codex's computer-use lane; **IMPL only — never route to the verify lane**. Browser-only work is not this row: Claude automates Chrome natively, so it stays wherever the matrix already routes it. See the *Computer-use routing* note below. |
| **Vague / ambiguous request** | `claude-impl` | Clarification step is `claude-impl`. Once concrete, subsequent steps assigned normally via this table — most will land on `codex-impl`. |
| **Anything not above (config, glue, wiring, mechanical work)** | `codex-impl` | Codex default. |

---

## Computer-use routing

The Codex lane carries **computer use**: the Codex CLI's machine config
ships an `mcp_servers.computer-use` entry — an MCP server that lets
Codex drive macOS desktop apps — plus browser-use backends (Chrome and
an in-app browser). Those tools are present in every `codex exec`
session with no extra flags, including the sessions the plugin's
wrappers start, so they are the capability's basis (not a per-machine
quirk). This is why desktop-GUI work routes to `codex-impl`: it reaches
what Claude's own tool surface cannot.

- **Browser-only work is not computer-use work.** Claude's harness
  automates Chrome natively, so anything that is purely a web page stays
  wherever the matrix already routes it. Codex's own guidance likewise
  prefers its Chrome plugin over Computer Use for browser tasks. The
  computer-use route exists for driving a native desktop app, an OS
  dialog, or a GUI-only workflow — the things Claude's tools cannot
  reach.
- **Safety boundary — IMPL lane only.** Computer-use tasks ride the
  `codex-impl` lane and never the verify lane. The verify wrapper's
  read-only sandbox constrains *file writes*, not *desktop side
  effects*: a read-only verifier can still click buttons, move files
  through Finder, or send messages in a native app. A verifier must
  therefore never be asked to drive the GUI. Keep computer-use work on
  the implementation lane, where the side effects are expected.

See `docs/06-codex-integration.md` for the capability's mechanics
(machine-config MCP server, wrapper-spawned availability,
graceful degradation when the server is absent).

---

## Hard Boundaries

These rules override the table above:

1. **Codex is the default implementer.** Under conductor mode, every step
   is presumed `codex-impl` unless one of three conditions holds: (a) the
   step's `skill` is in the Claude-only set below, (b) the RN-mobile
   Routing Directive routes it to `claude-impl`, or (c) a documented
   routing-matrix override applies (e.g., security-sensitive design,
   MCP/external-tool reasoning). A `claude-impl` step whose description
   does not carry a one-line routing justification citing one of these
   reasons is a planning bug.

2. **Claude-only skill set (exact, exhaustive — six skills).** A step's
   `skill` field forces `owner: "claude-impl"` if and only if the skill is
   one of EXACTLY:

   ```
   frontend-design, svg-art, immersive-frontend,
   brainstorming, writing-plans, doc-coauthoring
   ```

   `react-native-mobile` is NOT in this set — it is conditional (see RN
   section). v2 does not ship a `digest` skill; raw artifacts are
   bounded by the wrapper prompt contract, not by a downstream
   digester.

3. **One step has one owner.** Mixed-ownership work is split into two
   sequential single-owner steps linked by `dependsOn`. The plan schema
   does not support per-file or per-group ownership; each step carries
   exactly one `owner`.

4. **Conductor mode is the default.** The main thread dispatches every
   step to a subagent and reads only the parsed Codex contract block
   or a sub-agent's bounded return message. No raw artifact reads
   from the main thread.

5. **Parallel dispatch is the default.** The conductor's execution loop
   uses `runnable-steps` and dispatches the entire DAG frontier
   concurrently on every tick. Sequencing is expressed via `dependsOn`,
   not via main-thread serialization.

6. **In-thread `claude-impl` threshold (the only exception to dispatch).**
   A `claude-impl` step MAY run inside the main thread iff BOTH:
   - the step's `files` array has **≤1 file**, AND
   - the step's `skill` is one of `{brainstorming, writing-plans,
     doc-coauthoring}`.

   Every other `claude-impl` step dispatches to a Claude subagent whose
   model is chosen per the Model Scorecard above (Opus is the floor;
   Fable for the hardest / highest-taste work; Sonnet only for cheap
   read-heavy scouting). Every `codex-impl` step dispatches via
   `run-codex-impl.sh`.

7. **User can override any assignment.** During Orbit plan review, the
   user may change any step's `owner`. The routing matrix
   provides defaults, not mandates.

8. **Wrapper-modification serialization.** A step that edits
   `run-codex-impl.sh`, `run-codex-verify.sh`, or any other
   actively-used dispatch script (or a hook lib those wrappers source)
   MUST be dispatched ALONE — never in a parallel batch alongside other
   dispatches that use those scripts. This rule is enforced by the
   `codex-dispatch` skill ("Parallel dispatch with the file-overlap
   guard" section).

9. **Every dispatch carries an explicit model and announces itself.**
   Every `Agent` tool dispatch — implementation, scouting, verification
   — MUST carry an explicit `model` chosen per the Model Scorecard;
   inheriting the session model is a routing bug. Scouts (`Explore` /
   `Plan`) default to `sonnet` *explicitly*, never implicitly. Each
   dispatch also emits a one-line user-visible announcement of the form:

   ```
   → <step-id> · <owner> · <model> · <skill>
   ```

   In addition, the `Agent` tool's `description` parameter MUST embed
   the step id and model, format `<step-id> · <model> · <short title>`
   (e.g. `step-01 · opus · docs/09 routing`): the harness's task panel
   below the user's input field renders the description, so embedding
   the model there is what makes the fleet's model composition visible
   live. This complements the `→` announcement line; it does not
   replace it.

10. **Quality arbitration routes to the Fable + Codex judge pair.**
    Arbitration — ranking candidate artifacts, breaking a tie between
    approaches, scoring output quality — is distinct from step
    verification (which follows the cross-family rule above). The
    conductor dispatches BOTH arbiters: **Fable** via
    `Agent(model: "fable")` and **Codex** via `run-codex-verify.sh`
    (read-only; machine-default model — expected gpt-5.6-sol; the
    no-`--model`-flag invariant still holds), and consumes their
    consensus. **Self-bias guard** (measured: codex +0.30, fable +0.47
    on their own blind-labeled work; grok/opus ≈ 0): an arbiter's
    score of an artifact produced by its *own model family* counts
    only when the other arbiter independently concurs; on a split over
    an own-family artifact, add a grok or opus tiebreak vote. Blind
    the artifacts (strip authorship) whenever practical.

---

## RN-mobile conditional routing

`react-native-mobile` is the only skill that is neither Claude-only nor
Codex-default. Apply this rule whenever a step's `skill` is
`react-native-mobile`:

- **UI/UX (animations, haptics, gestures, visual polish) → claude.**
- **Code-heavy (data flow, networking, native modules, non-visual logic) → codex.**

The Routing Directive section in
`skills/react-native-mobile/SKILL.md` is the source of truth for the
Claude-side breakdown; the same wording lives in
`codex-skills/react-native-mobile/SKILL.md` so Codex sees the same
routing rule. If a step blends both kinds of work, split
it into two sequential steps with `dependsOn` rather than forcing a
single owner.

Routing-justification examples (write these into the step description,
not a separate field):
- `"react-native-mobile UI/UX per Routing Directive → claude-impl"`
- `"react-native-mobile code-heavy per Routing Directive → codex-impl"`

---

## Dynamic Routing

Some steps cannot determine their owner at plan time:

| Pattern | How It Works |
|---|---|
| **Performance optimization** | Codex investigates bottlenecks first (`codex-impl`). Based on findings, fix steps are assigned: backend → `codex-impl`, frontend → `claude-impl`. |
| **Vague requests** | Claude clarifies with user first (`claude-impl`, `brainstorming` or `doc-coauthoring`). Once requirements are concrete, subsequent steps are assigned normally — most will land on `codex-impl`. |

For these, `writing-plans` creates an investigation/clarification step
and follows it with placeholder steps whose `owner` is reassigned after
that step completes. The placeholders carry `dependsOn` edges back to
the investigation step.

---

## Panel Planning — automatic for high-ambiguity tasks

For high-ambiguity tasks, the plan itself is the artifact where model
diversity pays. The conductor then runs a **plan panel** instead of a
solo draft: independent plans generated in parallel from the identical
brief, then a single convergence pass. This is **automatic** — the
conductor applies the trigger below without being asked.

**Empirical grounding** (2026-07-10 local eval runs,
`eval/results/2026-07-10-plan-eval*`; blind cross-family judging,
unbiased-judge consensus on a 0–5 rubric):

- Solo plans from codex, grok, opus, and fable clustered tightly
  (4.44–4.67) — no single model dominates planning.
- **Parallel-independent drafts + one convergence pass beat every solo
  plan (4.88)** and led four of five rubric dimensions in the judge
  consensus — codex-solo edged it on the risks dimension (4.92 vs 4.90).
- **A sequential relay (draft → revise → finalize) scored below the
  best solo plan (4.56)** — later models anchor on the first draft and
  polish it instead of reopening decisions.

### Trigger

Panel-plan when ANY of:

- `brainstorming` fired during Discovery (the design ambiguity was
  real), or
- the request is a goal without a mechanism ("decide what we should do
  about X"), or
- after discovery, two or more plausible architectures remain with
  non-obvious tradeoffs, or
- the plan will span ≥3 domains (e.g. mobile + API + backend) or
  ≥ ~8 steps.

**The trigger is binding, not advisory.** When any condition above
matches, the conductor runs the panel — it does not weigh whether the
panel "seems worth it" for this particular task; that judgment call is
exactly how panels get skipped on the tasks that need them (observed
in practice: a conductor explicitly declined a matching panel until
the user intervened). The ONLY things that skip a matching trigger
are the user's own words: "just do it" / "quick" / "no plan" /
"solo plan is fine". Conversely, work that matches no trigger plans
solo (single-domain clear-spec work, mechanical sweeps), and the user
can force a panel anytime with "panel plan this". Cost: a panel is
~3–4× a solo plan draft — the selective trigger is what keeps it
affordable; wall-clock cost is low because generation is parallel.

### Protocol (never sequential)

1. The conductor writes one planning brief (task statement, discovery
   summary, constraints) to `<plan-dir>/panel/brief.md`.
2. The identical brief goes to three lanes **in parallel,
   independently** — no panelist ever sees another's draft:
   - **Codex** via `run-codex-impl.sh` (synthetic step id
     `panel-codex`, brief on stdin); deliverable
     `<plan-dir>/panel/codex.plan.md`.
   - **Grok** via `run-grok-impl.sh`, same shape, writing
     `panel/grok.plan.md`. If the grok lane is unavailable (wrapper
     exit 4), proceed as a two-model panel and note it in
     `progress.json` `deviations` once progress exists.
   - **Claude planner** via `Agent` with an explicit model: **Fable
     whenever available, otherwise Opus** — the plan is the
     highest-leverage artifact in the loop, so the strongest model
     drafts it; Opus is the implementation tier, not the planning
     tier. Writes `panel/claude.plan.md`.
3. **Convergence.** One Claude sub-agent (same rule: Fable whenever
   available, otherwise Opus)
   reads the brief plus all drafts and produces the converged plan:
   a definite decision wherever the drafts disagree (with a one-line
   reason — never "either works"), redundancy cut, complementary
   strengths kept. The converged output feeds the normal
   `writing-plans` three-file draft. Panel drafts stay in
   `<plan-dir>/panel/` as the audit trail; the conductor reads only
   the converged output, never the raw drafts.
4. **Never chain panelists on one evolving draft.** Sequential
   collaboration anchors on the first draft and measured *worse* than
   the best solo plan. Independence before convergence is the entire
   point of the panel.

---

## Skill Injection Rules

When `owner: "codex-impl"`, the step's `skill` field determines what
guidance Codex receives in its developer-instructions:

| Step skill | Codex gets |
|---|---|
| `test-driven-development` | TDD: RED-GREEN-REFACTOR cycles |
| `refactoring` | Refactoring contract + execution order |
| `systematic-debugging` | Four-phase investigation |
| `webapp-testing` | Playwright/E2E testing guidance |
| `mcp-builder` | MCP server development |
| `"none"` | Engineering-discipline only |

Skills that stay Claude-only (never injected into Codex):
- `frontend-design` — visual taste
- `svg-art` — creative direction
- `immersive-frontend` — experiential judgment
- `brainstorming` — Claude leads dialogue, Codex co-explores and reviews
- `writing-plans` — Claude leads; under Panel Planning, Codex and Grok
  contribute *independent* panel drafts (they never see each other's)
- `doc-coauthoring` — Claude writes, Codex verifies accuracy

`react-native-mobile` is dual-installable — both Claude and Codex have
their own copies, and routing per step follows the Routing Directive
above.

**CLI-side installation.** The repo-root `install.sh` syncs exactly the
injectable set — `engineering-discipline`, the five injectable workflow
skills above, and the external-lane `react-native-mobile` body — into
`~/.codex/skills/` **and** `~/.grok/skills/` on every (re)install. It
also enforces **one canonical copy per lane**: every plugin-managed
skill name (plus v1 leftovers) is cleared from `~/.claude/skills/`,
`~/.codex/skills/`, and `~/.grok/skills/` before the sync — Claude
loads the plugin's skills from the plugin cache only, so a user-level
copy would double-install. Skills the plugin does not own are never
touched. Both external lanes carry the same skill set; Claude-only
skills are never installed CLI-side (panel-planning briefs and
arbitration instructions travel in the wrapper prompt).

v2 does not ship a `digest` skill. Raw Codex output is bounded by the
wrapper's prompt contract (the Summary / Verdict / Findings block at
the end of every response). See `docs/06-codex-integration.md` for
the contract shape and parsing rules.

---

## Contract-block verification

Verification is not a free-form text exchange. Both directions of
work produce a bounded contract block parsed by
`scripts/parse-contract.sh`:

- **`codex-impl` step**: `run-codex-impl.sh` invokes Codex with the
  IMPLEMENT direction header pinned in-script and the step block on
  stdin. Codex's raw stream is captured to
  `.temp/plan-mode/active/<planId>/logs/codex-impl-<stepId>.log` for
  human debugging only. The wrapper emits the parsed JSON
  (`{summary, verdict, findings, filesTouched}`) on stdout — that
  is the only thing the conductor reads.
- **`claude-impl` step**: after the Claude subagent finishes,
  `run-codex-verify.sh` runs with the VERIFY direction header pinned
  in-script and `-s read-only`. Same contract-block emission; same
  conductor read pattern. The conductor never reads raw Codex
  prose.

**Cross-family verification.** The verifier should be a *different*
model family than the implementer. Empirical grounding: in the
2026-07-10 blind plan eval (`eval/results/2026-07-10-plan-eval/`),
codex and fable judges favored their own blind-labeled work by +0.30
and +0.47 (harshness-adjusted) while grok and opus showed none —
same-family review measurably overrates its own output. Corroborating
observation (2026-07-10): on identical input the Grok verifier (then
backed by Grok 4.3) returned PASS with 0 findings where the Codex
verifier returned FAIL with 18. After the backend moved to Grok 4.5
later the same day, the same verify prompt on the same material
returned FINDINGS with 6 substantive items — verifier strictness is
model-version-dependent, so leniency observations must be re-measured
after upstream model changes. Both observations are further evidence
*for* cross-family verification, not a routing or model change.
When the Grok lane is configured
(the `grok` CLI is installed and authenticated), `codex-impl` steps are
verified via `run-grok-verify.sh`, while `grok-impl` and `claude-impl`
steps are verified via `run-codex-verify.sh`. **Fallback:** whenever the
`grok` binary is unavailable (wrapper exit code 4), verification falls
back to `run-codex-verify.sh` — the pre-Grok behavior.

There are **no signed receipts, no HMAC sidecars, no digester
subagent** in v2. See `docs/01-philosophy.md` for the rationale.

---

## Machine defaults — Codex side; scorecard governs the Claude side

Two model-selection regimes coexist, and they must not be confused:

- **Conductor + Codex — machine defaults, never downgrade.** The
  conductor's own thread runs the user's configured model, and `codex`
  runs its machine default on the impl/verify side. The Codex wrappers
  MUST NOT pass `--model` / `-m`: `scripts/run-codex-impl.sh` and
  `scripts/run-codex-verify.sh` invoke `codex exec` without one, and no
  caller adds it. The Grok wrappers pin `-m grok-4.5` in-script —
  the subscription's current default coding model per `grok models` —
  because the CLI default is user-configurable (`~/.grok/config.toml`)
  and an unpinned wrapper would silently follow whatever that config
  says. When xAI renames the subscription model id (as happened when
  `grok-build` was retired for `grok-4.5`), the pin is the single
  place to update, and a stale pin fails loudly with "unknown model
  id" (wrapper exit 2) rather than silently running a different model. The verify wrapper additionally enforces read-only via
  `--deny 'Write' --deny 'Edit' --deny 'Bash'`. The invariant is the
  same for both pairs:
  **callers never supply a model to either wrapper pair**; the model is
  the wrapper's business, not the conductor's.
- **Claude-side implementation sub-agents — scorecard, not lock.** The
  conductor selects each implementation sub-agent's model via the
  `Agent` tool's `model` field per the Model Scorecard above (Opus
  floor, Fable escalation, Sonnet for cheap read-heavy). This is
  deliberate *tier selection*, not a downgrade — the "never downgrade"
  rule governs the Codex wrappers and the conductor's own thread, never
  the choice of Claude tier for a dispatched sub-agent.
