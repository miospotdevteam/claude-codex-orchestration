# 08 — Plugin layout

This document specifies the **target directory tree**, the
**`plugin.json` metadata**, and the **per-artifact source docs** so
anyone working on the plugin knows exactly which doc informs which
file.

The implementation lives at the root of **this repository**,
alongside `docs/`. The layout below is what should be at the repo
root.

## Directory tree

```
orchestration/
├── plugin.json                          ← plugin metadata
├── README.md                            ← usage / install
├── AGENTS.md                            ← same convention as this spec
│
├── skills/                              ← one subdirectory per skill
│   ├── conductor/                       ← core: top-level orchestrator
│   ├── engineering-discipline/          ← core: behavioral baseline
│   ├── persistent-plans/                ← core: plan I/O + resumption
│   ├── writing-plans/                   ← core: draft plan files
│   ├── codex-dispatch/                  ← core: wrapper routing
│   ├── refactoring/                     ← core: multi-file restructuring
│   ├── test-driven-development/         ← core: red-green-refactor
│   ├── systematic-debugging/            ← core: four-phase debugging
│   ├── brainstorming/                   ← core: design dialogue
│   ├── doc-coauthoring/                 ← auxiliary: prose authoring
│   ├── frontend-design/                 ← auxiliary: UI / design system
│   ├── svg-art/                         ← auxiliary: hand-coded SVG
│   ├── immersive-frontend/              ← auxiliary: WebGL / 3D / scroll
│   ├── mcp-builder/                     ← auxiliary: MCP server dev
│   ├── react-native-mobile/             ← auxiliary: RN apps (dual-install)
│   ├── webapp-testing/                  ← auxiliary: Playwright / E2E
│   └── skill-review-standard/           ← auxiliary: skill QA gate
│       (each skill dir contains SKILL.md and optional references/, scripts/)
│
├── codex-skills/                        ← Codex-side bodies for dual-install skills
│   └── react-native-mobile/
│       └── SKILL.md
│
├── hooks/                               ← exactly two hook scripts
│   ├── session-start.sh
│   └── post-compact.sh
│
├── scripts/                             ← codex wrappers + utilities
│   ├── run-codex-impl.sh
│   ├── run-codex-verify.sh
│   ├── plan-utils.sh                    ← read/write helpers for plan files
│   └── parse-contract.sh                ← extract the contract block
│
├── schemas/                             ← JSON schemas for plan files
│   ├── plan.schema.json
│   └── progress.schema.json
│
├── templates/                           ← starter templates
│   └── masterPlan.template.md
│
└── tests/                               ← hook + script tests
    ├── hooks/
    │   ├── session-start.test.sh
    │   └── post-compact.test.sh
    └── scripts/
        ├── parse-contract.test.sh
        └── plan-utils.test.sh
```

Notes on shape:

- **One directory per skill.** Each skill is self-contained in its
  own folder. `SKILL.md` is the canonical file the Claude Code
  harness loads. If a skill grows references (cheat sheets, example
  prompts), they live in that skill's folder.
- **No `lib/` for shared skill code.** v1 had a shared `lib/` that
  encouraged skills to import each other's logic and tangled them.
  v2 skills only reference each other by name in prose, not by
  shared code.
- **Two hooks, both at the top level of `hooks/`.** No
  subdirectories, no `pre-edit/` placeholder dirs. The minimum is
  the minimum.
- **`scripts/` holds the wrappers and a small set of helpers.**
  `plan-utils.sh` provides idempotent read/write of `plan.json` and
  `progress.json` so the conductor doesn't reinvent jq invocations.
  `parse-contract.sh` extracts the contract block from raw Codex
  output and is used by both Codex wrappers.

## `plugin.json` metadata

The top-level manifest the Claude Code harness loads. Shape:

```json
{
  "name": "orchestration",
  "version": "2.0.0",
  "description": "Conductor-mode orchestrator: persistent plans, bounded sub-agent dispatch, direction-locked Codex impl/verify. Read-only hooks, no gates.",
  "author": "<implementer>",
  "license": "MIT",
  "skills": [
    "skills/conductor/SKILL.md",
    "skills/engineering-discipline/SKILL.md",
    "skills/persistent-plans/SKILL.md",
    "skills/writing-plans/SKILL.md",
    "skills/codex-dispatch/SKILL.md",
    "skills/refactoring/SKILL.md",
    "skills/test-driven-development/SKILL.md",
    "skills/systematic-debugging/SKILL.md",
    "skills/brainstorming/SKILL.md"
  ],
  "hooks": {
    "session-start": "hooks/session-start.sh",
    "post-compact": "hooks/post-compact.sh"
  },
  "permissions": {
    "read": [
      ".temp/plan-mode/**",
      "scripts/**",
      "schemas/**",
      "templates/**"
    ],
    "write": [
      ".temp/plan-mode/active/**",
      ".temp/plan-mode/archive/**"
    ],
    "bash": [
      "scripts/run-codex-impl.sh",
      "scripts/run-codex-verify.sh",
      "scripts/plan-utils.sh",
      "scripts/parse-contract.sh"
    ]
  }
}
```

The exact field names depend on the harness's plugin schema at the
time of implementation; the structure above is the **intent**. Two
points the implementer must honor regardless of schema:

1. **Hooks declared as exactly the two above.** No `pre-edit`, no
   `pre-write`, no `pre-bash`. Anyone adding a hook must justify
   against `01-philosophy.md`.
2. **Write permissions scoped to `.temp/plan-mode/`.** The plugin
   does not write outside the plan area; it asks the user (or
   Codex via the wrappers) to do so.

## Per-artifact source docs

Cross-reference: which doc(s) inform which file. Implementers
should read the listed doc before writing the file.

| Artifact                                    | Read first                              |
|---------------------------------------------|-----------------------------------------|
| `README.md`                                 | This repo's `README.md`, `01-philosophy.md` |
| `AGENTS.md`                                 | This repo's `AGENTS.md`, `02-conductor.md` |
| `plugin.json`                               | `08-plugin-layout.md` (this doc), `07-hooks.md` |
| `skills/conductor/SKILL.md`                 | `02-conductor.md`, `04-execution-loop.md`, `05-skills-catalog.md` |
| `skills/engineering-discipline/SKILL.md`    | `01-philosophy.md`, `05-skills-catalog.md` |
| `skills/persistent-plans/SKILL.md`          | `03-plan-format.md`, `04-execution-loop.md`, `05-skills-catalog.md` |
| `skills/writing-plans/SKILL.md`             | `03-plan-format.md`, `04-execution-loop.md`, `05-skills-catalog.md` |
| `skills/codex-dispatch/SKILL.md`            | `06-codex-integration.md`, `05-skills-catalog.md` |
| `skills/refactoring/SKILL.md`               | `05-skills-catalog.md`, `01-philosophy.md` |
| `skills/test-driven-development/SKILL.md`   | `05-skills-catalog.md` |
| `skills/systematic-debugging/SKILL.md`      | `05-skills-catalog.md` |
| `skills/brainstorming/SKILL.md`             | `05-skills-catalog.md` |
| `hooks/session-start.sh`                    | `07-hooks.md`, `03-plan-format.md` |
| `hooks/post-compact.sh`                     | `07-hooks.md`, `04-execution-loop.md` |
| `scripts/run-codex-impl.sh`                 | `06-codex-integration.md` |
| `scripts/run-codex-verify.sh`               | `06-codex-integration.md` |
| `scripts/plan-utils.sh`                     | `03-plan-format.md` |
| `scripts/parse-contract.sh`                 | `06-codex-integration.md` |
| `schemas/plan.schema.json`                  | `03-plan-format.md` |
| `schemas/progress.schema.json`              | `03-plan-format.md` |
| `templates/masterPlan.template.md`          | `03-plan-format.md` |
| `tests/hooks/*.test.sh`                     | `07-hooks.md` |
| `tests/scripts/parse-contract.test.sh`      | `06-codex-integration.md` |
| `tests/scripts/plan-utils.test.sh`          | `03-plan-format.md` |

## Implementation order

A sensible build sequence:

1. **`schemas/*.json`** — the data shapes are the substrate. Get
   them right and the rest follows.
2. **`scripts/plan-utils.sh` + tests** — idempotent helpers for
   reading and updating plan files.
3. **`scripts/parse-contract.sh` + tests** — the Codex output
   parser. Independent of Codex itself; testable with fixtures.
4. **`scripts/run-codex-impl.sh` and `run-codex-verify.sh`** — the
   wrappers, once the parser is solid.
5. **`hooks/session-start.sh` + `post-compact.sh` + tests** — both
   thin and similar. Reuse `plan-utils.sh`.
6. **`skills/`** — write `conductor`, `persistent-plans`, and
   `codex-dispatch` first (they wire everything together), then the
   discipline skills (`engineering-discipline`, `writing-plans`,
   `refactoring`, `test-driven-development`, `systematic-debugging`,
   `brainstorming`).
7. **`plugin.json`** and **`README.md`** last, when everything else
   is testable.

## What the implementer should NOT add

To keep v2 from regressing into v1:

- **No `receipts/` directory.** No HMAC sidecars. No
  `claude-review-*.md` siblings.
- **No `digester/` skill.** Codex output is parsed directly; no
  middle layer.
- **No `pre-*` hooks.** The two hooks listed are the entirety of the
  hook surface.
- **No `lib/` shared between skills.** Skills compose via prose
  references, not shared imports.
- **No `enforcement/` mode flag.** v2 is gentle reminders only.

If any of these feel necessary mid-build, re-read
`01-philosophy.md` and reconsider. The bias is toward less, not
more.
