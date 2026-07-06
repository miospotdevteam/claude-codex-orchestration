# 09 — Routing Matrix

Canonical task-type routing table for assigning `owner` and (in v2's
plan vocabulary) `owner` value `claude-impl` / `codex-impl` / `manual`
to each plan step. Consumed by the `writing-plans` skill during plan
creation and by the `codex-dispatch` skill during execution.

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
subscription (the plugin's expected setup), **GPT-5.5 via the Codex
wrappers is effectively free at the margin** and runs *off the
conductor's context*. That is why Codex is the default implementer —
not because it has the most taste, but because it is intelligent,
cheap, and off-context. Reach for it liberally on bulk mechanical work.

---

## Model Scorecard

The conductor reaches five models. Route by the axis the step is
*bottlenecked* on, then escalate per the policy below.

| Model | Reached via | Intelligence | Taste | Route here for |
|---|---|---|---|---|
| **Fable 5** | `Agent(model: "fable")` | highest | highest | The hardest *and* most user-facing implementation; end-to-end multi-step work that needs both axes at once — the "steer everything" tier. |
| **Opus 4.8** | `Agent(model: "opus")` | high | high | Default Claude-side implementation floor; strong all-rounder when a step needs real taste but is not the top of the pile. |
| **Sonnet 5** | `Agent(model: "sonnet")` | mid | mid | Cheap, read-heavy scouting and mechanical Claude-side work where taste does not ship. Never the default for code that lands. |
| **Codex / GPT-5.5** | `run-codex-impl.sh` / `run-codex-verify.sh` | high | low | Bulk mechanical work, clear-spec backend, migrations, and off-context implementation. Also the independent second perspective on verify. |
| **Haiku** | — | low | low | **Never for real work.** Not an execution or verification tier. |

The Claude tiers (Fable / Opus / Sonnet) are selected via the `model`
field on the `Agent` tool. Codex is reached only through the
direction-locked wrappers, which never take a `-m` flag (see *Machine
defaults* at the bottom of this doc).

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
   Claude taste-pass after Codex. This is the `dual-pass` and "Claude
   reviews Codex integration impact" rows made explicit.
3. **Tiebreak for anything that ships: intelligence > taste > cost.**
   Cost decides only when intelligence and taste do not. It never
   blocks the right model for work that lands.
4. **Never route real work to Haiku**, and never let Sonnet own code
   that ships — Sonnet is for cheap read-heavy scouting only.

---

## How to Use This Table

When creating a plan, classify each step by its **task category** (left
column). The table gives the default `owner`, `mode`, and conditions under
which the default should be overridden. Steps may span multiple categories
— use the category that best describes the step's *primary* work.

If a step would naturally span both Claude-suitable and Codex-suitable
work (mixed ownership), **split it into two sequential steps with
`dependsOn`**. The plan schema does not support per-step mixed
ownership: every step has exactly one `owner` and one `mode`.

---

## Task-Type Routing Table

| Task Category | Default Owner | Default Mode | Override Conditions |
|---|---|---|---|
| **Frontend UI / visual design / UX polish** | `claude` | `claude-impl` | Skill must be in Claude-only set (`frontend-design`, `svg-art`, `immersive-frontend`). |
| **Product copy / UX text / content** | `claude` | `claude-impl` | Skill `doc-coauthoring`. |
| **Creative / landing page / marketing** | `claude` | `claude-impl` | Skill `frontend-design` / `immersive-frontend` / `svg-art`. |
| **Brainstorming / requirements shaping** | `claude` | `claude-impl` | Skill `brainstorming`. Codex co-explores in parallel and reviews `design.md` before `writing-plans`. |
| **Plan writing** | `claude` | `claude-impl` | Skill `writing-plans`. Codex participates in plan consensus. |
| **Documentation / API docs / specs** | `claude` | `claude-impl` | Skill `doc-coauthoring`. Codex verifies technical accuracy via `run-codex-verify.sh` contract block. |
| **MCP / DB / API / external integration** | `codex` | `codex-impl` | If the step is purely external-facing design (no code), it may be `claude-impl` with explicit justification. Otherwise split into design step (`claude-impl`, `doc-coauthoring`) and impl step (`codex-impl`) with `dependsOn`. |
| **Cross-domain integration** | `codex` | `codex-impl` | Split mixed work into sequential steps: design (`claude-impl`) → backend impl (`codex-impl`) → frontend impl (`claude-impl`) with `dependsOn`. |
| **Backend from clear spec (CRUD, services)** | `codex` | `codex-impl` | — |
| **API route / service implementation** | `codex` | `codex-impl` | — |
| **Refactor across many files** | `codex` | `codex-impl` | Claude reviews integration impact via verification subagent. |
| **Framework / library migration** | `codex` | `codex-impl` | Add a leading design step (`claude-impl`, `doc-coauthoring`) with `dependsOn` if strategy needs human framing. |
| **Dependency upgrade** | `codex` | `codex-impl` | Same as migration: optional leading design step for breaking-change discussion. |
| **i18n string extraction sweep** | `codex` | `codex-impl` | Add a leading convention-defining step (`claude-impl`) with `dependsOn` if convention is ambiguous. |
| **Bug investigation / root cause analysis** | `codex` | `codex-impl` | Skill `systematic-debugging`. |
| **Failing test / CI failure** | `codex` | `codex-impl` | Skill `systematic-debugging`. |
| **Performance optimization** | `codex` | `codex-impl` | Investigation step is `codex-impl`. Fix steps assigned after via Dynamic Routing: backend → `codex-impl`, frontend → `claude-impl`. |
| **Security review / audit** | both | `dual-pass` | Claude: design-level. Codex: implementation-level. Both passes independent. |
| **Security-sensitive design** | `claude` | `claude-impl` | Skill `brainstorming` / `doc-coauthoring`. Codex does adversarial challenge pass via `run-codex-verify.sh`. |
| **CI/CD pipeline setup** | `codex` | `codex-impl` | — |
| **Test writing** | `codex` | `codex-impl` | Gets TDD skill injected. |
| **PR review** | both | `dual-pass` | Claude: design/architecture. Codex: correctness/security. |
| **Post-step verification** | `codex` | (verification dispatch — not a step mode) | Codex's verification of `claude-impl` runs via `run-codex-verify.sh` and emits a Summary / Verdict / Findings contract block. Verification is structural, not a step. |
| **Design system update (tokens)** | varies | sequential | Step A: design tokens + core primitives (`claude-impl`, `frontend-design`). Step B: sweep components to use tokens (`codex-impl`, `dependsOn: [A]`). |
| **Dark mode / theming** | varies | sequential | Step A: theme system + ThemeProvider (`claude-impl`, `frontend-design`). Step B: sweep components (`codex-impl`, `dependsOn: [A]`). |
| **Dashboard with charts** | varies | sequential | Step A: layout shell (`claude-impl`, `frontend-design`). Step B: data hooks (`codex-impl`, TDD). Step C: wire charts (`claude-impl`, `dependsOn: [A, B]`). |
| **Real-time / collaborative features** | varies | sequential | Step A: architecture decision (`claude-impl`, `brainstorming`). Step B: backend (`codex-impl`). Step C: frontend (`claude-impl`, `frontend-design`). `dependsOn` chain or fan-in as appropriate. |
| **Stripe / payment integration** | varies | sequential | Step A: external API surface design (`claude-impl`, `doc-coauthoring`). Step B: internal services + DB models (`codex-impl`, `dependsOn: [A]`). Step C: webhooks/checkout UI (`claude-impl`, `dependsOn: [B]`). |
| **Plugin / MCP development** | varies | sequential | Step A: skills + MCP surface (`claude-impl`, `mcp-builder` or `doc-coauthoring`). Step B: hooks + scripts + manifest (`codex-impl`, `dependsOn: [A]`). |
| **React Native (mobile) UI/UX** | `claude` | `claude-impl` | Skill `react-native-mobile`, **conditional** per the RN Routing Directive (see RN section below). |
| **React Native (mobile) code-heavy** | `codex` | `codex-impl` | Skill `react-native-mobile`, **conditional** per the RN Routing Directive (see RN section below). |
| **Vague / ambiguous request** | `claude` | `claude-impl` | Clarification step is `claude-impl`. Once concrete, subsequent steps assigned normally via this table — most will land on `codex-impl`. |
| **Anything not above (config, glue, wiring, mechanical work)** | `codex` | `codex-impl` | Codex default. |

---

## Hard Boundaries

These rules override the table above:

1. **Codex is the default implementer.** Under conductor mode, every step
   is presumed `codex-impl` unless one of three conditions holds: (a) the
   step's `skill` is in the Claude-only set below, (b) the RN-mobile
   Routing Directive sends it to Claude, or (c) a documented routing-matrix
   override applies (e.g., security-sensitive design, MCP/external-tool
   reasoning). Claude-impl steps without a written `routingJustification`
   citing one of these reasons are a planning bug.

2. **Claude-only skill set (exact, exhaustive — six skills).** A step's
   `skill` field forces `owner: "claude"` if and only if the skill is one
   of EXACTLY:

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
   exactly one `owner` and one `mode`.

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
   user may change any step's `owner` and `mode`. The routing matrix
   provides defaults, not mandates.

8. **Wrapper-modification serialization.** A step that edits
   `run-codex-impl.sh`, `run-codex-verify.sh`, or any other
   actively-used dispatch script (or a hook lib those wrappers source)
   MUST be dispatched ALONE — never in a parallel batch alongside other
   dispatches that use those scripts. This rule is enforced by the
   `codex-dispatch` skill ("Parallel Step Execution" section).

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

`routingJustification` examples:
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

## Skill Injection Rules

When `owner: "codex"`, the step's `skill` field determines what guidance
Codex receives in its developer-instructions:

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
- `writing-plans` — Claude leads, Codex participates in plan consensus
- `doc-coauthoring` — Claude writes, Codex verifies accuracy

`react-native-mobile` is dual-installable — both Claude and Codex have
their own copies, and routing per step follows the Routing Directive
above.

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
  caller adds it.
- **Claude-side implementation sub-agents — scorecard, not lock.** The
  conductor selects each implementation sub-agent's model via the
  `Agent` tool's `model` field per the Model Scorecard above (Opus
  floor, Fable escalation, Sonnet for cheap read-heavy). This is
  deliberate *tier selection*, not a downgrade — the "never downgrade"
  rule governs the Codex wrappers and the conductor's own thread, never
  the choice of Claude tier for a dispatched sub-agent.
