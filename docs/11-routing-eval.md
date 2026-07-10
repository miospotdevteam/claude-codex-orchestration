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
produced-files directory (`--candidate-dir`) and a task's hidden `tests/`
directory (`--tests-dir`), plus `--task-id`, `--model`, and `--track` for
identity. It copies **both** the candidate's produced files and the hidden
tests into a fresh `mktemp` sandbox and runs `tests/run.sh <candidate_dir>`
against the staged copy, then emits a JSON score object:

```json
{ "taskId": "backend/url-shortener", "model": "codex", "track": "A",
  "passed": 7, "total": 8, "correctness": 0.875 }
```

`correctness` is `passed / total`, a number in `[0, 1]`. The contract with
`tests/run.sh` is exact: its final stdout line must be `RESULT <passed>
<total>` with non-negative integers and `total > 0`, and its exit status
must be `0` exactly when `passed == total`. The scorer **fails closed** on
any incoherence — a missing `RESULT` line, a `total` of zero, `passed >
total`, or an exit status that contradicts the tally (a full-pass tally
with a non-zero exit, or a partial tally with exit `0`) is a hard error,
not a silent score. A task with **zero tests** is therefore reported as an
explicit error, never a silent pass: a corpus task with no runnable tests
is a corpus bug the scorer surfaces rather than scoring it 1.0.

### Judge-scored quality

Correctness alone rewards a passing tangle as much as a passing clean
solution. So every code-domain output is *also* scored by the judge
panel on the task's quality rubric, and every taste-domain output is
scored by the panel alone. Each judge returns a **single holistic 0–5
quality number per candidate** — one overall rubric score, not a
per-dimension sum or mean — and the harness validates that every score is
a finite number within `[0, 5]` before it is used.

The **combined score** per model per task, exactly as
`eval/scripts/aggregate.sh` computes it, is:

- **Code domain**: the combined score **equals the raw 0–5 judge quality
  score, hard-gated to `0` whenever correctness is below `1.0`**. A model
  must pass *every* test on a task to score at all; a single failing test
  gates that task's combined score to `0`, and at the domain level any
  code task below full correctness gates that model's whole domain
  combined to `0`. Among fully-correct solutions the raw quality score
  ranks them.
- **Taste domain**: there is no objective gate; the raw 0–5 quality score
  is the whole combined score.

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

The blind labels are resolved through one canonical, per-run map at
`eval/results/<runId>/raw/de-anonymization-map.json`. The **eval-runner
session produces this file** while constructing the blind bundles and
before it dispatches any judge. Its schema is:

```json
{
  "mappings": [
    {
      "taskId": "frontend/pricing-table",
      "track": "A",
      "candidateModels": {
        "A": "codex",
        "B": "opus",
        "C": "grok"
      }
    }
  ]
}
```

There is exactly one mapping per task and track, every task included in the
run has both Track A and Track B mappings (a task absent from the run needs
neither), and each `candidateModels` object has exactly the three
blind labels `A`, `B`, and `C` mapped to three distinct model names. Label
assignments are per task and per track, not global. `aggregate.sh` rejects a
missing, malformed, duplicate, incomplete, or panel-inconsistent map instead
of filtering unmapped judge records; legacy panel-local `candidateModels`
fields may be present only when they exactly match the canonical map.

The Codex and Grok judges are shelled out to via
`eval/scripts/judge-codex.sh` and `judge-grok.sh`. Each runs its judge
model **read-only in an isolated `mktemp` sandbox** — never the caller's
cwd — with the candidate bundle and rubric copied in as sandbox-local
files (Codex under `-s read-only`, Grok under `--deny Write --deny Edit
--deny Bash`), so a judge can read its inputs but cannot write files or
mutate the tree it judges from. Both wrappers robustly extract the score
object from the model's stdout via `extract-judge-json.py` — which accepts
only finite numbers in `[0, 5]` for `A`/`B`/`C` — retry once on
unparseable output, and re-validate the `{scores:{A,B,C}, rationale}`
shape before emitting it. The Opus judge is **dispatched from the driving
session via `Agent`**, because the Claude tiers are only reachable there
(see the runbook's dispatch matrix).

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

  The two bare wrappers run at **parity**: both prepend the identical
  minimal preamble (`Complete the following task.`) to the task's spec
  and nothing else, and both execute the model in an isolated workdir
  (`--workdir`, or an ephemeral `mktemp` dir) so produced files are
  captured for scoring instead of polluting the caller. The only flags
  either passes are *execution-environment* flags, never prompt
  scaffolding: `bare-codex.sh` uses `codex exec -s workspace-write
  --skip-git-repo-check` so the model can write into the non-git workdir;
  `bare-grok.sh` pins the model with **`-m grok-4.5`** and runs
  `--always-approve --max-turns 80`. Each emits `{ "model": …, "track":
  "bare", "taskId": …, "output": "<raw stdout>" }`.

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

- **`scorecard.json`** — machine-readable. Per domain: the Track-A
  ranking (models with their `combined`, `correctness`, and `quality`),
  the `margin` between #1 and #2, and each model's `delta(A, B)` as
  `wrapperDelta`. `combined` is the raw 0–5 quality gated by correctness
  (above); `correctness` is present for code domains and `null` for
  taste; the ranking is **Track A only**, because Track A is the
  production wrapper path routing is decided on.
- **`scorecard.md`** — the same data as a human-readable table.

```json
{
  "runId": "2026-07-09-backend-dryrun",
  "domains": {
    "backend": {
      "ranking": [
        { "model": "codex", "combined": 4.3, "correctness": 1,    "quality": 4.3 },
        { "model": "opus",  "combined": 3.9, "correctness": 1,    "quality": 3.9 },
        { "model": "grok",  "combined": 0,   "correctness": 0.88, "quality": 3.4 }
      ],
      "margin": 0.4,
      "wrapperDelta": { "codex": 0.2, "opus": 0.1, "grok": 0 }
    }
  }
}
```

Read the example off the formula. On Track A, codex and opus pass every
backend test (`correctness` `1.0`), so each one's `combined` is simply
its raw quality — `4.3` and `3.9`. grok fails a test somewhere in the
domain (`correctness` `0.88 < 1.0`), so its `combined` is **gated to `0`**
even though its quality is `3.4`; a non-passing solution cannot outrank a
passing one. The `margin` is `#1 − #2` on `combined`: `4.3 − 3.9 = 0.4`.
Each `wrapperDelta` is that model's Track-A `combined` minus its Track-B
`combined` — codex scores `4.1` bare, so `4.3 − 4.1 = 0.2` of wrapper
lift; opus `3.8` bare gives `3.9 − 3.8 = 0.1`; grok is gated to `0` on
both tracks, so its delta is `0`. There is **no normalization** of quality: every quality and
`combined` number on the card is on the raw 0–5 scale, or a
difference of two such numbers, never rescaled. The only 0–1 figure
is `correctness` itself, which is a pass ratio (`passed/total`) by
definition, consumed only by the hard gate.

`runId` is passed to `aggregate.sh` as an argument — the harness scripts
take no wall-clock or random input, so a run is reproducible and its
output directory is named by the operator, not by the clock.

**Task identity and kind come from the corpus tree, not the score
records.** `aggregate.sh` walks `eval/corpus/*/*`, deriving each task's
domain from its path and its kind from disk: a task with a `tests/`
directory is `code`, one without is `taste`. Score records are matched
against that manifest, and a record naming a task outside the corpus is
an error.

`aggregate.sh` is **fail-closed**: before it ranks anything it runs a
whole-dataset preflight and dies on any inconsistency rather than
silently dropping records. It rejects an empty `raw/` (no JSON at all, or
JSON but no score files) and a missing / malformed / duplicate /
incomplete de-anonymization map; it requires the **full three-family
judge panel (codex, grok, opus) on both tracks** for every judged task, a
valid objective record for **every** code candidate on both tracks (and
none for a taste task), rejects malformed judge or objective records
(scores outside `[0, 5]`, non-integer or incoherent `passed` / `total`),
and rejects any duplicate judge or objective identity. A partial or
inconsistent run produces **no scorecard**, not a misleading one.

The combined-scoring rule the aggregator applies (code = correctness
gate over raw 0–5 quality; taste = raw quality only) is documented
in-script and matches the **Scoring model** section above; the two must
not drift.

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
   write the canonical `raw/de-anonymization-map.json`, then score the
   bundles with `judge-codex.sh`, `judge-grok.sh`, and an Opus judge via
   `Agent`; write the judge JSON under `raw/`.
5. **Aggregate** — run `eval/scripts/aggregate.sh <runId>` over `raw/`
   to emit `scorecard.json` + `scorecard.md`. It fails closed: an
   incomplete or inconsistent dataset produces no scorecard, not a
   misleading one.
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
