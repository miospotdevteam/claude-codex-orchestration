# 09 — Routing Matrix

Canonical task-type routing table for assigning each plan step's
`owner` — one of `claude-impl` / `codex-impl` / `grok-impl` /
`manual`, the exact enum in `schemas/plan.schema.json`. Consumed by the
`writing-plans` skill during plan creation and by the `codex-dispatch`
skill during execution.

See also: `docs/05-skills-catalog.md` for the v2 skill catalog,
`docs/06-codex-integration.md` for the bounded Codex contract,
`docs/02-conductor.md` for the dispatch-only rule.

**Conductor mode is the default**, but the conductor family is selected by an
explicit routing profile rather than assumed to be Claude. The active profile
is one of:

- **`codex-primary`** — GPT-5.6 Sol xhigh is the host and convergence owner;
  `claude_workers=deny`; Claude is never invoked. Codex and Grok provide the
  independent planning, exploration, implementation, and verification lanes.
- **`fable-primary`** — Claude Code running Fable xhigh is the host and
  convergence owner; `claude_workers=allow`; Codex and Grok remain mandatory
  external counterweights. If Fable is unavailable, this profile fails closed
  and the user explicitly activates `codex-primary`; there is no silent
  Opus/Sonnet orchestrator fallback.

With no project override, the effective profile is the shipped
`codex-primary` preset. An explicit profile is stored in
`.orchestration/routing.json` and validated against
`schemas/routing.schema.json`. A profile cannot change the application hosting
an already-running thread: activate `codex-primary` and start Codex, or activate
`fable-primary` and start Claude Code with Fable xhigh selected. Installing
`--host both` provisions both surfaces once so switching does not require a
reinstall.

In both profiles the conductor dispatches every non-trivial implementation step
and reads only bounded return contracts. **Codex is the default implementer.**
Taste-led work is Fable-preferred only in `fable-primary`; the same domain
skills route to Sol in `codex-primary`.

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

**Orchestrator economics.** The `fable-primary` seat uses Fable because
orchestration is *few-tokens* work when delegation holds: the conductor reads
only bounded contract blocks and sub-agent summaries, never raw artifacts, so
its tier price is a small share of total spend. `codex-primary` uses Sol xhigh
when Anthropic is unavailable or intentionally disabled and preserves the same
dispatch-only context discipline. Bad routing decisions are the expensive
failure mode, not the conductor's per-token rate. Empirical grounding:
Anthropic's multi-agent research system — an Opus lead orchestrating
Sonnet subagents — outperformed single-agent Opus by 90.2%, and the
orchestrator's token share of the run was small. A lean, cache-stable
conductor context bills mostly *cached* input, cheapening the seat
further. Those historical tiers are evaluation context only; neither Opus nor
Sonnet participates in either canonical profile.

---

## Model Scorecard

The historical inventory contains six model tiers, but the canonical profiles
activate only their named lanes. Route by the axis the step is *bottlenecked*
on, then apply the profile policy below.

| Model | Reached via | Intelligence | Taste | Route here for |
|---|---|---|---|---|
| **Fable 5** | `Agent(model: "fable")` | highest | highest | Every Claude planning, exploration, implementation, design, and review lane in `fable-primary`. |
| **Opus 4.8** | inactive in canonical profiles | high | high | Historical comparison tier only; never a silent substitute for Fable. |
| **Sonnet 5** | inactive in canonical profiles | mid | mid | Historical comparison tier only; never a silent substitute for Fable. |
| **Codex / gpt-5.6-sol** | `run-codex-impl.sh` / `run-codex-verify.sh` | high | low | Bulk mechanical work, clear-spec backend, migrations, and off-context implementation. Also the independent second perspective on verify. |
| **Grok 4.5** | `run-grok-impl.sh` / `run-grok-verify.sh` | high | low-mid | Bulk mechanical work, clear-spec backend, migrations, independent planning/exploration, and a required member of every profile's all-pass verifier gate. |
| **Haiku** | — | low | low | **Never for real work.** Not an execution or verification tier. |

The Fable profile explicitly selects `model: "fable"` on every Claude `Agent`
dispatch. Codex and Grok are each reached only through
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

### grok-impl vs codex-impl vs claude-impl (Fable)

The implementation lanes rank by quota economics, measured, not
assumed. **Measured 2026-07-10:** a full day of heavy orchestration —
a 20-step fix plan, panels, dual verification — consumed ~2% of the
weekly Grok quota while exhausting both the Claude and Codex quotas.
Grok is the slack resource; the routing must spend it.

The implementation preference order:

1. **`codex-impl` remains the default external implementer**
   (off-context, effectively free at the margin on the subscription).
2. **`grok-impl` is preferred over a Fable implementation
   sub-agent for any implementation step that does not need the active
   profile's taste owner.** If a step would land on
   `claude-impl` merely because the Codex lane is busy, or because "an
   Fable agent can do it", route it `grok-impl` instead. Grok is also
   the second lane when Codex is saturated, and the second half of
   bulk sweeps split across both lanes.
3. **`claude-impl` exists only in `fable-primary` and is reserved for
   taste-led work.** The same step routes to Sol under `codex-primary`.

A `claude-impl` step that isn't taste-led or Claude-skill-gated is a
routing bug twice over: it burns the scarce quota and leaves the slack
lane idle.

---

## Escalation & Tiebreak Policy

The scorecard gives defaults, not limits. The conductor applies four
rules on top of it:

1. **Profiles are hard limits.** A weak result is fixed and re-run through the
   same required lanes. It is never silently re-dispatched to a model absent
   from the active profile.
2. **Taste routing is a first-class move.** Codex is the default implementer,
   but when the artifact is user-facing (SDK, public API, UI, copy), route the
   design through the active taste owner: Sol xhigh in `codex-primary`, Fable
   xhigh in `fable-primary`.
3. **Tiebreak for anything that ships: intelligence > taste > cost.**
   Cost decides only when intelligence and taste do not. It never
   blocks the right model for work that lands.
4. **Never route real work to Haiku, Opus, or Sonnet in either canonical
   profile.** Adding another model requires a new named, validated profile.

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

In this table, a `claude-impl` taste/design cell applies only to
`fable-primary`; `codex-primary` substitutes `codex-impl` at Sol with the same
portable skill and keeps the dependency graph unchanged.

| Task Category | Default Owner | Override Conditions |
|---|---|---|
| **Frontend UI / visual design / UX polish** | active taste owner | Sol + `frontend-design`/`svg-art`/`immersive-frontend` in `codex-primary`; Fable in `fable-primary`. |
| **Product copy / UX text / content** | active taste owner | Skill `doc-coauthoring`; Sol or Fable by profile. |
| **Creative / landing page / marketing** | active taste owner | Sol or Fable by profile, with the named portable skill. |
| **Brainstorming / requirements shaping** | active orchestrator | Host-native `brainstorming`; parallel Codex/Grok exploration remains independent. |
| **Plan writing** | active orchestrator | Host-native `writing-plans`; automatic profile panel for high ambiguity. |
| **Documentation / API docs / specs** | active taste owner | Skill `doc-coauthoring`; profile all-pass verification. |
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

1. **Codex is the default implementer in both profiles.** A step is presumed
   `codex-impl` unless a documented override applies. In `fable-primary`, a
   taste-led or prose-led step may route to `claude-impl`. In
   `codex-primary`, `owner: "claude-impl"` is invalid and the equivalent Sol
   lane owns the work; never smuggle a Claude fallback into a denied profile.

2. **Taste/planning skills are profile-dependent, not Claude-only.** The
   profile-dependent set is:

   ```
   frontend-design, svg-art, immersive-frontend,
   brainstorming, writing-plans, doc-coauthoring
   ```

   Under `fable-primary`, these prefer Fable and may use `claude-impl`. Under
   `codex-primary`, `writing-plans` and `brainstorming` are conductor-owned
   Codex-native workflows, while design/prose implementation routes to
   `codex-impl` at Sol. The portable domain bodies are installed for Codex and
   Grok so implementation and independent review see the same contract.
   `react-native-mobile` remains conditional (see below). `remote-agent-host`
   remains the one explicit Claude-host-only skill and is never copied into
   Codex/Grok worker skill directories.

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

6. **In-thread `claude-impl` threshold (Fable profile only).**
   A `claude-impl` step MAY run inside the main thread iff BOTH:
   - the step's `files` array has **≤1 file**, AND
   - the step's `skill` is one of `{brainstorming, writing-plans,
     doc-coauthoring}`.

   This exception exists only in `fable-primary`; `codex-primary` forbids
   `claude-impl`. Every other `claude-impl` step dispatches to a Claude
   subagent with explicit `model: "fable"`. Opus and Sonnet are not fallback
   workers for the named profile. Every `codex-impl` step dispatches via
   `run-codex-impl.sh`.

7. **User can override profile-valid assignments.** During Orbit plan review,
   the user may change a step's `owner` to any owner allowed by the active
   profile. Selecting `claude-impl` while `codex-primary` is active requires an
   explicit switch to `fable-primary`; the routing matrix never bypasses the
   profile's worker policy.

8. **Wrapper-modification serialization.** A step that edits
   `run-codex-impl.sh`, `run-codex-verify.sh`, or any other
   actively-used dispatch script (or a hook lib those wrappers source)
   MUST be dispatched ALONE — never in a parallel batch alongside other
   dispatches that use those scripts. This rule is enforced by the
   `codex-dispatch` skill ("Parallel dispatch with the file-overlap
   guard" section).

9. **Every dispatch carries an explicit model and announces itself.**
   In `fable-primary`, every `Agent` tool dispatch — implementation, scouting, verification
   — MUST carry an explicit `model` chosen per the Model Scorecard;
   inheriting the session model is a routing bug. Scouts (`Explore` /
   `Plan`) use `fable` *explicitly*, never implicitly. Each
   dispatch also emits a one-line user-visible announcement of the form:

   ```
   → <step-id> · <owner> · <model> · <skill>
   ```

   In addition, the `Agent` tool's `description` parameter MUST embed
   the step id and model, format `<step-id> · <model> · <short title>`
   (e.g. `step-01 · fable · docs/09 routing`): the harness's task panel
   below the user's input field renders the description, so embedding
   the model there is what makes the fleet's model composition visible
   live. This complements the `→` announcement line; it does not
   replace it.

10. **Quality arbitration follows the active profile.**
    Arbitration — ranking candidate artifacts, breaking a tie between
    approaches, scoring output quality — is distinct from step
    verification (which follows the cross-family rule above). The
    `codex-primary` dispatches Codex + Grok and requires consensus.
    `fable-primary` dispatches Fable + Codex + Grok and requires all three
    bounded judgments before convergence. **Self-bias guard** (measured:
    codex +0.30, fable +0.47 on their own blind-labeled work; grok/opus ≈
    0): an arbiter's score of its own-family artifact counts only when a
    different family independently concurs. Blind artifacts whenever practical.

---

## RN-mobile conditional routing

`react-native-mobile` has profile-dependent taste routing. Apply this rule whenever a step's `skill` is
`react-native-mobile`:

- **UI/UX (animations, haptics, gestures, visual polish) → active taste
  owner:** Fable in `fable-primary`, Sol in `codex-primary`.
- **Code-heavy (data flow, networking, native modules, non-visual logic) → codex.**

The Routing Directive section in
`skills/react-native-mobile/SKILL.md` is the Claude-side body; the portable
external-lane body under `external-skills/react-native-mobile/SKILL.md` carries
the profile-aware version for Codex and Grok. If a step blends both kinds of work, split
it into two sequential steps with `dependsOn` rather than forcing a
single owner.

Routing-justification examples (write these into the step description,
not a separate field):
- `"react-native-mobile UI/UX per Routing Directive → active taste owner"`
- `"react-native-mobile code-heavy per Routing Directive → codex-impl"`

---

## Dynamic Routing

Some steps cannot determine their owner at plan time:

| Pattern | How It Works |
|---|---|
| **Performance optimization** | Codex investigates bottlenecks first (`codex-impl`). Backend fixes stay Codex; frontend fixes use the active taste owner (Sol or Fable). |
| **Vague requests** | The active orchestrator clarifies first using its host-native brainstorming/doc workflow. Once concrete, subsequent steps are assigned normally. |

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
2. The identical brief goes to the active profile's lanes **in parallel,
   independently** — no panelist ever sees another's draft:
   - **Codex** via `run-codex-impl.sh` (synthetic step id
     `panel-codex`, brief on stdin); deliverable
     `<plan-dir>/panel/codex.plan.md`.
   - **Grok** via `run-grok-impl.sh`, same shape, writing
     `panel/grok.plan.md`. An unavailable required lane blocks the selected
     profile rather than shrinking the panel.
   - **Fable planner (`fable-primary` only)** via `Agent(model: "fable")`.
     There is no Opus/Sonnet substitution for the named Fable profile. Writes
     `panel/claude.plan.md`.
3. **Convergence.** The active orchestrator (Sol for `codex-primary`, Fable
   for `fable-primary`)
   reads the brief plus all bounded drafts and produces the converged plan:
   a definite decision wherever the drafts disagree (with a one-line
   reason — never "either works"), redundancy cut, complementary
   strengths kept. The converged output feeds the normal
   `writing-plans` three-file draft. Panel drafts stay in
   `<plan-dir>/panel/` as the audit trail; the conductor reads only
   the converged output, never the raw drafts.
4. `codex-primary` therefore has two independent candidates (Codex + Grok);
   `fable-primary` has three (Codex + Grok + Fable). A missing required lane
   blocks convergence; it does not silently shrink the selected profile.
5. **Never chain panelists on one evolving draft.** Sequential
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

The portable worker inventory is exact and shared by Codex and Grok:

```
engineering-discipline, test-driven-development, refactoring,
systematic-debugging, brainstorming, doc-coauthoring, frontend-design,
svg-art, immersive-frontend, mcp-builder, react-native-mobile,
webapp-testing, skill-review-standard
```

Host-only orchestration bodies never enter Grok's worker directory. Codex gets
its native `conductor`, `persistent-plans`, `writing-plans`, and
`codex-dispatch` bodies from the Codex plugin. Claude gets its existing host
bodies from the Claude plugin. `remote-agent-host` stays Claude-host-only.

**CLI-side installation.** The repo-root `install.sh` validates the complete
portable inventory from the installed marketplace artifact before removing
anything, then synchronizes it into `~/.codex/skills/` and
`~/.grok/skills/` for every selected host path. Provider-specific overrides
under `external-skills/` win over shared `skills/` bodies. The installer
enforces one canonical copy per lane, preserves unowned user skills, and never
uses the invoking checkout as the install source. `--host codex` performs this
sync without invoking Claude; `--host both` provisions both conductor surfaces
for immediate profile switching.

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
**Verification is an all-pass profile gate.** All required reviewers run
independently over the same fixed diff and acceptance criteria:

- `codex-primary` → Codex + Grok in parallel. Both must PASS. Grok is the
  cross-family gate for Codex-authored work; Codex is the cross-family gate for
  Grok-authored work.
- `fable-primary` → Codex + Grok + Fable in parallel. All three must PASS.
  At least two reviewers are cross-family for any single-family implementer.

Findings from any reviewer enter the fix-and-re-verify loop, and **every**
profile-required reviewer re-runs after a fix. Missing binaries, unavailable
models, or two contract-parse failures block the step; the selected profile is
never silently degraded to a smaller verifier set. After three non-converging
rounds, pause for user judgment with the step still `in_progress`.

There are **no signed receipts, no HMAC sidecars, no digester
subagent** in v2. See `docs/01-philosophy.md` for the rationale.

---

## Direction-locked model and effort selection

Two model-selection regimes coexist, and they must not be confused:

- **The active conductor is profile-locked.** `codex-primary` requires Sol
  xhigh; `fable-primary` requires Fable xhigh. A mismatch blocks dispatch.
- **Codex wrapper model stays machine-selected; effort is scenario-locked.**
  The Codex wrappers MUST NOT pass `--model` / `-m`. Callers pass only a
  scenario enum and the wrapper maps it internally: planning/design → xhigh;
  exploration/implementation/review → high; bulk → medium. This is a bounded
  direction parameter, not arbitrary model selection.
- **Grok is fully pinned.** The Grok wrappers pin `-m grok-4.5` and
  `--reasoning-effort high` in-script —
  the subscription's current default coding model per `grok models` —
  because the CLI default is user-configurable (`~/.grok/config.toml`)
  and an unpinned wrapper would silently follow whatever that config
  says. When xAI renames the subscription model id (as happened when
  `grok-build` was retired for `grok-4.5`), the pin is the single
  place to update, and a stale pin fails loudly with "unknown model
  id" (wrapper exit 2) rather than silently running a different model. The verify wrapper additionally enforces read-only via
  `--deny 'Write' --deny 'Edit' --deny 'Bash'`. The invariant is the
  same for both pairs: **callers never supply a model**; model identity and
  allowed effort mapping are the wrapper's business.
- **Claude-side sub-agents are Fable-locked by profile.** Under
  `fable-primary`, every Claude planning, exploration, implementation, and
  verification dispatch explicitly uses `model: "fable"`. If Fable cannot run,
  the profile blocks and the user activates `codex-primary`; no smaller Claude
  tier is substituted.
