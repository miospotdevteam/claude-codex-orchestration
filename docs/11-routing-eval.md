# 11 — Routing eval harness

The routing matrix in `docs/09-routing-matrix.md` decides who owns each
kind of task — Codex by default, a Claude tier for taste work, Grok as
the second off-context lane. Today that table rests on **reasoned
priors**: it asserts that Codex is the strongest clear-spec backend
implementer and that Claude tiers carry taste, but it has never been
measured. This document specifies the **routing eval harness** — a
local, gitignored tool that runs the *same* task through Codex, Grok,
and the Claude tiers (Opus / Fable) across a set of domains and produces
a **scorecard** showing who actually wins each one, and whether the
plugin's own wrappers help or hurt.

The harness **validates** `docs/09-routing-matrix.md`; it never edits
it. A human reads a scorecard and, if the evidence warrants, hand-edits
the routing table in a separate, deliberate step. There is no auto-PR
and no threshold that trips a routing change. The eval and the routing
decision stay decoupled so that eval noise can never drift the matrix.

The harness is **session-driven**: it cannot be a single shell script,
because two of the models it compares (the Claude tiers) and part of the
judge panel are only reachable through the `Agent` tool inside a Claude
session. So a Claude session is the driver — it dispatches the
Claude-side work via `Agent`, and shells out to `eval/scripts/*.sh` for
everything a CLI can reach (Codex, Grok, objective scoring,
aggregation). This doc is both the **design spec** for that harness and
the **operator runbook** for the session that drives a run.

---

## What the harness validates

`docs/09-routing-matrix.md` reduces every routing decision to two axes —
**intelligence** (how hard a problem a model carries unsupervised) and
**taste** (judgment about the shape of an artifact a human will read or
maintain). It then assigns each task category a default owner on those
axes. The harness asks the empirical question the matrix answers by
assertion:

- **Per domain, who wins?** On backend-from-spec tasks, does Codex
  actually beat the Claude tiers, as the table claims? On frontend and
  docs tasks, do the Claude tiers actually carry the taste premium?
- **By how much?** A one-point win on a 5-point rubric is noise; a
  consistent two-domain sweep is signal. The scorecard reports margins,
  not just winners.
- **Do our wrappers help?** The plugin wraps Codex and Grok in
  direction-locked headers and injects skills. The harness measures each
  model *with* and *without* that wrapper, so a wrapper that adds drag
  instead of lift shows up as a negative delta.

The output is evidence for a human editing `docs/09-routing-matrix.md`,
nothing more. See the **Boundaries** section for the hard line between
"the harness produced a scorecard" and "the matrix changed."

---

## The four pieces

A run is built from four pieces. The rest of this doc details each; here
is the whole shape in one place.

1. **Corpus** — a fixed set of gold tasks on disk, grouped by domain.
   Each task states a problem every model is given, and (for code
   domains) carries a hidden test suite plus a quality rubric.
2. **Scoring** — hybrid and multi-dimensional. Code domains earn an
   objective **correctness** score from hidden tests *plus* a
   judge-scored **quality** score. Taste domains are **judge-only**
   against a rubric. Judging is a **cross-family blind panel**.
3. **Invocation — two tracks.** *Track A* runs each model through the
   real production wrappers (routing truth). *Track B* runs each model
   bare, with a minimal prompt and no wrapper (capability truth). The
   per-model `delta(A, B)` is the wrapper's measured lift or drag.
4. **Output** — per-domain scorecards under `eval/results/<runId>/`,
   gitignored. A human reads them; the routing matrix is edited by hand
   later, if at all.

---

## Seed domains

The harness seeds six domains, drawn from the task categories in
`docs/09-routing-matrix.md`. Three are **code** domains — they have an
objective right answer that hidden tests can check — and three are
**taste** domains, where quality is a matter of judgment against a
rubric. The scoring mode follows directly from that split.

| Domain | Kind | Scoring mode | Drawn from (docs/09 category) |
|---|---|---|---|
| `backend` (backend-from-spec) | code | objective + judge | Backend from clear spec (CRUD, services) |
| `refactor` (refactor-across-files) | code | objective + judge | Refactor across many files |
| `bugfix` | code | objective + judge | Bug investigation / failing test |
| `frontend` (frontend UI) | taste | judge-only | Frontend UI / visual design / UX polish |
| `docs` (docs / API docs) | taste | judge-only | Documentation / API docs / specs |
| `api-design` (API / SDK surface) | taste | judge-only | Cross-domain / external API surface design |

- **Objective + judge** (code domains): a model's output must pass the
  task's hidden tests (correctness) *and* is scored by the judge panel
  on simplicity and quality. A solution that passes the tests with 200
  lines of tangle loses to one that passes with 40 clean lines.
- **Judge-only** (taste domains): there is no runnable test. The judge
  panel scores each output against the task's rubric, and that is the
  whole score.

Six domains is a **seed**, not a ceiling. Adding a domain is: create
`eval/corpus/<domain>/` with tasks in the layout below, and decide its
scoring mode (does it have a runnable right answer?). Nothing else in
the harness is domain-specific.

---

## Corpus layout on disk

The corpus lives under `eval/corpus/`, one directory per domain, one
subdirectory per task:

```
eval/corpus/
├── backend/
│   ├── url-shortener/
│   │   ├── spec.md          ← the task statement given to every model
│   │   ├── rubric.md        ← the quality dimensions the judge panel scores
│   │   └── tests/           ← hidden; never shown to the models under test
│   │       ├── run.sh       ← the scorer's entry point (exit 0 = all pass)
│   │       └── ...          ← the actual test files / fixtures
│   └── rate-limiter/
│       └── ...
├── frontend/
│   └── pricing-table/
│       ├── spec.md          ← the task statement
│       └── rubric.md        ← taste dimensions (no tests/ for taste domains)
└── ...
```

The three files, precisely:

- **`spec.md`** — the problem statement, identical for every model and
  every track. It must be unambiguous and must **not leak the reference
  solution**. This is the only corpus file a model under test ever sees.
- **`tests/`** (code domains only) — a hidden, family-neutral test
  suite. It contains a **`run.sh`** that the objective scorer invokes
  against a candidate's produced output; `run.sh` exits `0` when every
  test passes and non-zero otherwise, and prints a machine-readable
  pass/total tally the scorer can parse. The suite is "family-neutral"
  in that it checks behavior described by `spec.md`, not any one model's
  coding style — it passes or fails a correct solution regardless of who
  wrote it.
- **`rubric.md`** — the quality dimensions the judge panel scores. For
  code domains these are simplicity/quality dimensions layered *on top
  of* correctness (idiomatic, minimal, readable, edge-cases handled).
  For taste domains the rubric **is** the whole score, so it must
  enumerate 3–5 concrete, scorable dimensions with brief scoring
  guidance, so that independent judges produce comparable numbers.

Taste-domain tasks have **no `tests/` directory** — their `spec.md` +
`rubric.md` is the whole task.

### Representing "a model's produced output"

A candidate's output for a code task is a **directory of produced
files** — the files the model created or edited, rooted at a per-task
sandbox. The objective scorer copies the task's hidden `tests/` into
that sandbox and runs `tests/run.sh` against the produced files. This is
the representation the scorer expects; corpus `run.sh` scripts are
authored to that contract (they locate the candidate's files by
convention within the sandbox, not by a diff).

---

## Scoring model

Scoring is **hybrid and multi-dimensional**. The two ingredients are an
objective correctness score (code domains only) and a judge-panel
quality score (all domains).

### Objective correctness

For code domains, `eval/scripts/score-objective.sh` takes a candidate's
produced-files directory and a task's hidden `tests/` directory, runs
`tests/run.sh` in a sandbox, and emits a JSON score object:

```json
{ "taskId": "backend/url-shortener", "model": "codex", "track": "A",
  "passed": 7, "total": 8, "correctness": 0.875 }
```

`correctness` is `passed / total`, a number in `[0, 1]`. A task with
**zero tests** is reported as an explicit error, never a silent pass —
a corpus task with no runnable tests is a corpus bug, and the scorer
surfaces it rather than scoring it 1.0.

### Judge-scored quality

Correctness alone rewards a passing tangle as much as a passing clean
solution. So every code-domain output is *also* scored by the judge
panel on the task's quality rubric, and every taste-domain output is
scored by the panel alone. The judge score is a rubric number (e.g. a
0–5 mean across the rubric's dimensions).

The **combined score** per model per task is:

- **Code domain**: `correctness` gates, then rubric quality ranks — a
  model must pass the tests to compete, and among passing solutions the
  judge quality score breaks the tie. (The aggregator in
  `eval/scripts/aggregate.sh` pins the exact combination; see the
  scorecard section.)
- **Taste domain**: the rubric score is the whole combined score.

### The blind cross-family judge panel

Each task compares **three candidate outputs, one per model family** —
Codex, Grok, and a Claude tier (Opus by default; Fable when the domain
warrants the top tier). Three candidates map cleanly to the anonymized
labels `A`, `B`, `C`. Because each candidate is produced on *both*
tracks (see the next section), the panel judges **one blind bundle per
track**: an A/B/C bundle of the three Track-A outputs, and a separate
A/B/C bundle of the three Track-B outputs. That gives every model a
comparable quality score on each track, which is what makes the
`delta(A, B)` in the next section well-defined.

LLM-as-judge is noisy and carries same-family preference — an Opus judge
may quietly favor an Opus-authored answer. The harness blunts this with
a **cross-family blind panel**:

- **Three judges, three families**: Codex, Grok, and Opus each score the
  three candidate outputs. No single family's bias picks the winner.
- **Blind**: within a track's bundle, the three candidate outputs are
  anonymized to `A`, `B`, `C` before judging. A judge scores the rubric
  without knowing which model produced which output.
- **Position-swapped**: the A/B/C label assignment is permuted so that a
  judge's positional bias (favoring whichever came first) averages out
  across the panel.

Each judge emits, per task and per track, a JSON object scoring each
anonymized candidate against the rubric, with a short rationale:

```json
{ "judge": "grok", "taskId": "frontend/pricing-table", "track": "A",
  "scores": { "A": 4.2, "B": 3.1, "C": 4.8 },
  "rationale": "C handles the empty state and reads cleanest; B duplicates ..." }
```

The Codex and Grok judges are shelled out to via
`eval/scripts/judge-codex.sh` and `judge-grok.sh`. The Opus judge is
**dispatched from the driving session via `Agent`**, because the Claude
tiers are only reachable there (see the runbook's dispatch matrix).

---

## The two-track invocation

Every model runs each task **twice**, on two tracks. The delta between
them is the whole point.

- **Track A — through the real wrappers (routing truth).** Each model is
  invoked exactly as it would be in a real plan run: Codex through
  `orchestration/scripts/run-codex-impl.sh`, Grok through
  `run-grok-impl.sh`, and the Claude tiers through `Agent(model: ...)`
  with the same skill injection production uses. Track A measures the
  model *as the plugin actually uses it* — direction header, skill
  guidance, and all.
- **Track B — bare (capability truth).** Each model is invoked with a
  minimal prompt and **no wrapper header, no skill injection** —
  `eval/scripts/bare-codex.sh` / `bare-grok.sh` for the CLI models, and
  a bare `Agent` prompt for the Claude tiers. Track B measures the raw
  model.

The per-model **`delta(A, B)`** — combined score on Track A minus
combined score on Track B — is the harness's verdict on the plugin's own
wrappers:

- **Positive delta** → the wrapper adds **lift**: the direction header
  and skill injection make the model better at this domain. The wrapper
  earns its place.
- **Negative delta** → the wrapper adds **drag**: the scaffolding is
  getting in the model's way on this domain. That is a finding about the
  *wrapper*, independent of which model wins.

So a run validates two things at once: which model to route a domain to
(the winner), and whether our wrapper for that model helps (the delta).

### Track A for the CLI models reuses the real wrappers unchanged

`run-codex-impl.sh` and `run-grok-impl.sh` take `--plan-id`,
`--step-id`, `--root-dir`, and optional `--skill` as flags, and read the
**step block from stdin** — a plain-prose block (title, description,
acceptance criteria, files, progress) that the wrapper pins its
direction header and injected skill around. The identifiers are for
run identity and logging; the work the model is asked to do is the
piped step block, not a lookup into `plan.json`.

The harness does **not** reimplement the wrappers and does **not** pass
them a model flag (the wrapper's model is the wrapper's business).
Instead, for each corpus task it **renders a step block from the task's
`spec.md`** — the task statement as the description, the domain's
production skill as `--skill` — and pipes that block to the real wrapper
on stdin, with a synthetic `--plan-id`/`--step-id` naming the run and
task and a per-task sandbox as `--root-dir`. This is what makes Track A
*routing truth*: the model sees the exact direction header and skill it
would see in a real plan run, because it is the same wrapper wrapping
the same step-block shape.

---

## The scorecard output format

`eval/scripts/aggregate.sh` reads the per-task, per-model, per-track
score JSON (objective scores from `score-objective.sh` and rubric scores
from the judge panel, collected under `eval/results/<runId>/raw/`) and
emits a per-domain scorecard in two forms into
`eval/results/<runId>/`:

- **`scorecard.json`** — machine-readable. Per domain: the ranked models
  with their combined scores, the margin between #1 and #2, and each
  model's `delta(A, B)`.
- **`scorecard.md`** — the same data as a human-readable table.

```json
{
  "runId": "2026-07-09-backend-dryrun",
  "domains": {
    "backend": {
      "ranking": [
        { "model": "codex", "combined": 0.91, "correctness": 0.94, "quality": 4.3 },
        { "model": "opus",  "combined": 0.86, "correctness": 0.94, "quality": 3.9 }
      ],
      "margin": 0.05,
      "wrapperDelta": { "codex": 0.07, "grok": -0.02, "opus": 0.01 }
    }
  }
}
```

`runId` is passed to `aggregate.sh` as an argument — the harness scripts
take no wall-clock or random input, so a run is reproducible and its
output directory is named by the operator, not by the clock.

The combined-scoring rule the aggregator applies (code = correctness
gate + judge quality; taste = rubric only) is documented in-script and
matches the **Scoring model** section above; the two must not drift.

---

## Operator runbook — how to run a routing eval

### The harness is session-driven, not a single script

There is no `run-eval.sh` that does the whole thing, and there
deliberately never will be. The Claude candidate (an Opus or Fable tier)
and one of the three judges (Opus) are reachable **only through the
`Agent` tool inside a Claude session**. A pure shell script cannot
dispatch them. So the driver is a **Claude session** — typically the
conductor — that:

- **dispatches the Claude-side work via `Agent`**: the Claude candidate
  on both tracks, and the Opus judge; and
- **shells out to `eval/scripts/*.sh`** for everything a CLI reaches:
  the Codex and Grok candidates, objective scoring, the Codex and Grok
  judges, and aggregation.

### The dispatch matrix

Which piece runs how:

| Piece | How it runs | Mechanism |
|---|---|---|
| Codex candidate — Track A | bash helper | `orchestration/scripts/run-codex-impl.sh` (real wrapper) |
| Grok candidate — Track A | bash helper | `orchestration/scripts/run-grok-impl.sh` (real wrapper) |
| Claude candidate (Opus/Fable) — Track A | **Agent** | `Agent(model: "opus" \| "fable")` + production skill |
| Codex candidate — Track B | bash helper | `eval/scripts/bare-codex.sh` |
| Grok candidate — Track B | bash helper | `eval/scripts/bare-grok.sh` |
| Claude candidate (Opus/Fable) — Track B | **Agent** | bare `Agent(model:)` prompt, no skill |
| Objective scoring (code domains) | bash helper | `eval/scripts/score-objective.sh` |
| Judge — Codex | bash helper | `eval/scripts/judge-codex.sh` |
| Judge — Grok | bash helper | `eval/scripts/judge-grok.sh` |
| Judge — Opus | **Agent** | `Agent(model: "opus")` judge prompt |
| Aggregation → scorecard | bash helper | `eval/scripts/aggregate.sh` |

The pattern: **anything a CLI can reach is a bash helper the session
shells out to; anything that needs the `Agent` tool (every Claude tier —
candidate or judge) the session dispatches directly.** That split is the
whole reason the harness is session-driven rather than a script.

### Running a domain end-to-end

For a chosen `runId` and domain, the driving session:

1. **Enumerate tasks** — list `eval/corpus/<domain>/*/`.
2. **Produce candidates** — for each task, run all three candidate
   models (Codex, Grok, the Claude tier) on **both tracks** per the
   dispatch matrix. Each invocation writes its produced output into a
   per-task, per-model, per-track sandbox.
3. **Score correctness** (code domains) — run
   `eval/scripts/score-objective.sh` on each code candidate's produced
   files against the task's hidden `tests/`; write the score JSON under
   `eval/results/<runId>/raw/`.
4. **Run the judge panel** — for each task, and separately per track,
   anonymize the three candidate outputs to A/B/C (position-swapped),
   then score them with `judge-codex.sh`, `judge-grok.sh`, and an Opus
   judge via `Agent`; write the judge JSON under `raw/`.
5. **Aggregate** — run `eval/scripts/aggregate.sh <runId>` over `raw/`
   to emit `scorecard.json` + `scorecard.md`.
6. **Read and decide** — a human reads the scorecard. If the evidence
   warrants a routing change, they edit `docs/09-routing-matrix.md`
   **by hand**, as a separate step. The harness never touches it.

Every bash helper follows the project's script conventions: `set -euo
pipefail`, sandboxed under `mktemp -d`, dependencies limited to `jq`
plus the per-task `run.sh`, and deterministic (no wall-clock or random
input — `runId` is always passed in).

### Where outputs live

All run outputs land under `eval/results/<runId>/` — raw per-model score
JSON under `raw/`, and the final `scorecard.json` + `scorecard.md` at
the run root. By design **`eval/results/` is gitignored** — the ignore
rule is added when the `eval/` tree is scaffolded (the same step that
registers `eval/` in `docs/08-plugin-layout.md`) — so scorecards and raw
run JSON stay local and are read in place. The corpus (`eval/corpus/`)
and the helper scripts (`eval/scripts/`) are tracked; results are not.

---

## Boundaries — what the harness does not do

- **It never edits `docs/09-routing-matrix.md`.** No auto-PR, no
  threshold-triggered routing change. The harness produces evidence; a
  human edits the matrix by hand, in a separate deliberate step, or not
  at all. This decoupling is load-bearing: it guarantees eval noise can
  never drift the routing table.
- **It does not commit results.** `eval/results/` is gitignored;
  scorecards are evaluated locally and discarded or kept at the
  operator's discretion.
- **It does not ship with the plugin.** `eval/` is a repo-root
  developer/research tool, a sibling of `docs/` and `orchestration/`,
  and is excluded from the plugin marketplace source `./orchestration`.
  See `docs/08-plugin-layout.md`.
- **It is not a proof.** With ~5–8 tasks per domain, a scorecard is
  **directional signal**, not statistical proof. A thin margin is noise;
  widen the corpus before making a bold routing change. Treat a single
  run as a data point, not a verdict.
- **It does not run in CI.** The harness runs on demand, locally, driven
  by a session — never on a commit hook or a schedule.

---

## Eval types beyond objective correctness

Two runs (2026-07-10) established that **objective correctness does not
separate frontier models**: on two hard, precisely-specified tasks —
one with a 375,000-operation differential fuzzer — codex, grok, and
opus were unanimously perfect. Correctness-style corpora remain useful
for regression-testing the wrappers, but ranking models requires evals
of *judgment*:

- **Plan-quality eval.** Identical under-specified brief to each model;
  each writes a plan; blind cross-family panel scores against a rubric
  (framing/assumptions, tradeoffs, phasing, risks, concreteness) with
  Latin-square position rotation. Doubles as a **judge-quality**
  measurement: each judge scores its own blind-labeled plan, exposing
  self-bias. This run's findings ground the Panel Planning section of
  `docs/09-routing-matrix.md`.
- **Topology eval.** Head-to-head between multi-model protocols
  (parallel-independent + convergence vs sequential relay) judged
  against the best solo plans as in-run anchors. Grounded the
  panel-planning protocol choice.

## Backlog — future experiments

- **Seeded-defect review eval** (the direct measurement of "codex finds
  what claude misses"): take one correct implementation, seed ~10–15
  realistic defects across layers, have each model independently
  review, and score recall / precision / **unique catches** per model.
  This measures the review/verify layer — where cross-family
  complementarity actually lives — rather than implementation.
- **Widen the plan-quality corpus** (2–3 more under-specified briefs)
  before treating the solo-plan ranking as stable; the 2026-07-10 runs
  showed rank instability for close solo scores while the
  panel-vs-relay gap was consistent across all judges.
