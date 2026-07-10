# Project context — orchestration v2 (plugin repo)

You are working inside the repository for **v2 of the `orchestration`
plugin for Claude Code**. This repo holds both the design spec (under
`docs/`) and the plugin implementation that descends from it (under
`orchestration/`: `.claude-plugin/plugin.json`, `skills/`,
`codex-skills/`, `hooks/`, `scripts/`, `schemas/`, `templates/`,
`tests/`).

## What this repo is

- The v2 design spec, in `docs/01-philosophy.md` … `docs/11-routing-eval.md`.
- The v2 implementation that the spec describes, living under
  `orchestration/`. The target shape is in `docs/08-plugin-layout.md`
  and the suggested build order is at the bottom of that doc.
- The routing-eval harness under `eval/` (a top-level directory with
  `corpus/`, `scripts/`, `results/`, `tests/`) that validates the
  routing matrix; see `docs/11-routing-eval.md`.
- A clean rewrite of v1 (`look-before-you-leap`). Do not import,
  reference, or port v1 implementation files. The spec already
  encodes what survives from v1 and what does not.

## What this repo is not

- Not a sandbox. Changes here are the artifact.
- Not the place for a parallel `v1/` directory or compatibility shims.
  v2 stands alone.

## Editing rules

- **`docs/` stays markdown-only.** Specs there describe the design;
  they do not contain runnable code. If you need to add or amend
  design, fill the gap with more spec — not with code in `docs/`.
- **Code lives outside `docs/`.** Skill files, hook scripts, shell
  helpers, JSON schemas, and tests go in the directories specified by
  `docs/08-plugin-layout.md`. Do not invent new top-level directories
  without amending that doc first.
- **No regressions to v1 shape.** No `receipts/`, no HMAC sidecars, no
  `claude-review-*.md`, no `lbyl-digest` sub-agent, no shared `lib/`,
  no third hook, no `pre-*` hooks, no Edit/Write gating, no
  `--direction` flag (direction is the wrapper script's identity).
- **Cross-reference by relative path.** Docs refer to each other as
  e.g. `docs/02-conductor.md`. Code may cite the doc that informs it
  in a single header comment, but skill prose should reference *skills
  by name*, not by path.
- **Stand-alone docs.** Each `docs/*.md` is useful on its own. Assume
  a reader who has never seen the rest of the repo.

## Style

- Docs: H1 per file, then H2/H3 sections. No YAML frontmatter on docs
  (they are not skills). Concrete over abstract: show JSON when
  describing a schema, show a message shape when describing a
  protocol.
- Skills: each `SKILL.md` has the frontmatter the Claude Code harness
  expects (`name`, `description`, optionally `triggers`/`anti-triggers`)
  matching the catalog in `docs/05-skills-catalog.md`.
- Shell scripts: bash + jq, `set -euo pipefail`, deps minimal. Each
  script is testable and tested under `tests/`.
- Skip v1 archaeology in user-facing artifacts (README, skill prose).
  v1 may be named in commit messages or design discussion, but the
  shipping surface describes v2 as if it were the only design that
  ever existed.

## Build order

Follow the implementation order at the bottom of
`docs/08-plugin-layout.md`. Test each script/hook before moving to the
next. Fixtures for `parse-contract.sh` must include: well-formed
block, missing sentinel, malformed verdict, extra text after
`END-CONTRACT`.

## When asked to add a new doc

Add it under `docs/` with a numbered prefix that fits the existing
order. Update `README.md`'s layout block to list it. If the new doc
implies an artifact, also update the per-artifact source map at the
bottom of `docs/08-plugin-layout.md`.
