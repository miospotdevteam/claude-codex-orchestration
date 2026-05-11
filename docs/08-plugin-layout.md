# 08 — Plugin layout

This document specifies the **target directory tree**, the
**plugin and marketplace manifests**, and the **per-artifact source
docs** so anyone working on the plugin knows exactly which doc
informs which file.

The repository is a **one-plugin marketplace**: the marketplace
manifest lives at the repo root under `.claude-plugin/`, and the
plugin itself lives in the `orchestration/` subdirectory. This split
matches Claude Code's plugin-source convention — the marketplace's
`plugins[].source` is a relative path to a subdirectory (Claude Code
does **not** accept `.` as a same-dir marker; it must be a real
subdir like `./orchestration`).

`claude plugin marketplace add miospotdevteam/claude-codex-orchestration`
clones this repo into Claude Code's marketplace cache;
`claude plugin install orchestration@claude-codex-orchestration`
then installs the plugin from the `orchestration/` subdir.

## Directory tree

```
claude-codex-orchestration/              ← repo root = marketplace root
├── .claude-plugin/
│   └── marketplace.json                 ← marketplace metadata
├── README.md                            ← usage / install
├── AGENTS.md                            ← three-role contract
├── LICENSE                              ← MIT
├── install.sh                           ← conditional uninstall + install via claude CLI
├── docs/                                ← design spec (markdown only)
│   ├── 01-philosophy.md … 09-routing-matrix.md
│
└── orchestration/                       ← plugin root (source: "./orchestration")
    ├── .claude-plugin/
    │   └── plugin.json                  ← minimal plugin manifest (name, description)
    │
    ├── skills/                          ← one subdirectory per skill
    │   ├── conductor/                   ← core: top-level orchestrator
    │   ├── engineering-discipline/      ← core: behavioral baseline
    │   ├── persistent-plans/            ← core: plan I/O + resumption
    │   ├── writing-plans/               ← core: draft plan files
    │   ├── codex-dispatch/              ← core: wrapper routing
    │   ├── refactoring/                 ← core: multi-file restructuring
    │   ├── test-driven-development/     ← core: red-green-refactor
    │   ├── systematic-debugging/        ← core: four-phase debugging
    │   ├── brainstorming/               ← core: design dialogue
    │   ├── doc-coauthoring/             ← auxiliary: prose authoring
    │   ├── frontend-design/             ← auxiliary: UI / design system
    │   ├── svg-art/                     ← auxiliary: hand-coded SVG
    │   ├── immersive-frontend/          ← auxiliary: WebGL / 3D / scroll
    │   ├── mcp-builder/                 ← auxiliary: MCP server dev
    │   ├── react-native-mobile/         ← auxiliary: RN apps (dual-install)
    │   ├── webapp-testing/              ← auxiliary: Playwright / E2E
    │   └── skill-review-standard/       ← auxiliary: skill QA gate
    │       (each skill dir contains SKILL.md and optional references/, scripts/)
    │
    ├── codex-skills/                    ← Codex-side bodies for dual-install skills
    │   └── react-native-mobile/
    │       └── SKILL.md
    │
    ├── hooks/                           ← event handlers + manifest
    │   ├── hooks.json                   ← maps event names → handler scripts
    │   ├── session-start.sh             ← SessionStart handler (read-only)
    │   └── post-compact.sh              ← PostCompact handler (read-only)
    │
    ├── scripts/                         ← codex wrappers + utilities
    │   ├── run-codex-impl.sh
    │   ├── run-codex-verify.sh
    │   ├── plan-utils.sh                ← read/write helpers for plan files
    │   └── parse-contract.sh            ← extract the contract block
    │
    ├── schemas/                         ← JSON schemas for plan files
    │   ├── plan.schema.json
    │   └── progress.schema.json
    │
    ├── templates/                       ← starter templates
    │   └── masterPlan.template.md
    │
    └── tests/                           ← hook + script tests
        ├── hooks/
        │   ├── session-start.test.sh
        │   └── post-compact.test.sh
        └── scripts/
            ├── parse-contract.test.sh
            └── plan-utils.test.sh
```

Notes on shape:

- **`.claude-plugin/` holds both manifests.** Claude Code's plugin
  schema places metadata under `.claude-plugin/` rather than at the
  repo root. A single-plugin repo can declare both the marketplace
  and the plugin in the same `.claude-plugin/` directory by setting
  the plugin's `source` to `"."`.
- **Skills are auto-discovered.** There is no `skills` array in
  `plugin.json`. The harness scans `skills/<name>/SKILL.md` from the
  plugin root and loads whatever it finds.
- **One directory per skill.** Each skill is self-contained in its
  own folder. `SKILL.md` is the canonical file. References, scripts,
  and other supporting files live alongside it.
- **No `lib/` for shared skill code.** v1 had a shared `lib/` that
  encouraged skills to import each other's logic and tangled them.
  v2 skills only reference each other by name in prose, not by
  shared code.
- **Hooks declared in `hooks/hooks.json`.** The two `.sh` files are
  the actual handlers; the JSON file is how Claude Code learns which
  events to fire them on. See `07-hooks.md` for the full event-mapping
  contract.
- **`scripts/` holds the wrappers and a small set of helpers.**
  `plan-utils.sh` provides idempotent read/write of `plan.json` and
  `progress.json` so the conductor doesn't reinvent jq invocations.
  `parse-contract.sh` extracts the contract block from raw Codex
  output and is used by both Codex wrappers.

## `.claude-plugin/plugin.json` (plugin manifest)

The minimum the harness needs:

```json
{
  "name": "orchestration",
  "description": "Conductor-mode orchestrator: persistent plans, bounded sub-agent dispatch, direction-locked Codex impl/verify. Read-only hooks, no gates."
}
```

Optional fields the schema allows:

- `mcpServers` — map of MCP server name → invocation. v2 does not
  ship an MCP server; this stays omitted.

Fields the harness does **not** read from `plugin.json`:

- `skills` — auto-discovered from `skills/<name>/SKILL.md`.
- `hooks` — declared in `hooks/hooks.json` (see below).
- `permissions` — handled by Claude Code's settings system, not the
  plugin manifest.
- `version`, `author`, `license` — repo-level metadata, expressed in
  `LICENSE` and (for git workflows) git tags.

## `.claude-plugin/marketplace.json` (marketplace manifest)

The marketplace metadata. For this repo (a one-plugin marketplace):

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "claude-codex-orchestration",
  "description": "Conductor-mode orchestrator for Claude Code: persistent plans, direction-locked Codex impl/verify, bounded prompt-contract I/O, read-only hooks.",
  "owner": {
    "name": "Miospot Dev Team"
  },
  "plugins": [
    {
      "name": "orchestration",
      "description": "Conductor-mode orchestrator: persistent plans, bounded sub-agent dispatch, direction-locked Codex impl/verify. Read-only hooks, no gates.",
      "source": "./orchestration",
      "category": "development"
    }
  ]
}
```

`source` is a **relative path to a real subdirectory** containing the
plugin (with its own `.claude-plugin/plugin.json` inside). Claude
Code does not accept `"."` or `""` as the source — it must be a
proper subdir like `./orchestration`. If you only have one plugin in
the repo, that's why this layout has both a repo-root
`.claude-plugin/` (marketplace) and a subdir `.claude-plugin/`
(plugin).

## `hooks/hooks.json` (hook manifest)

Maps Claude Code event names to handler scripts via the
`${CLAUDE_PLUGIN_ROOT}` variable Claude Code resolves at runtime:

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

Two points of nuance:

1. **The `SessionStart` matcher excludes `compact`** — `PostCompact`
   handles that case. (v1 used a single `SessionStart` handler with
   `compact` in its matcher; v2 splits them so each script has a
   single clear responsibility.)
2. **No `pre-*` hooks.** v2 ships exactly two events. Anyone proposing
   a third hook (especially `PreToolUse`, `PostToolUse`, `Stop`)
   must justify against `01-philosophy.md` first.

## Per-artifact source docs

Cross-reference: which doc(s) inform which file.

| Artifact                                       | Read first                                                |
|------------------------------------------------|-----------------------------------------------------------|
| `README.md`                                    | This repo's `README.md`, `01-philosophy.md`               |
| `AGENTS.md`                                    | This repo's `AGENTS.md`, `02-conductor.md`                |
| `.claude-plugin/plugin.json`                   | `08-plugin-layout.md` (this doc)                          |
| `.claude-plugin/marketplace.json`              | `08-plugin-layout.md` (this doc)                          |
| `install.sh`                                   | `08-plugin-layout.md` (this doc), the `claude plugin` CLI |
| `hooks/hooks.json`                             | `07-hooks.md`, `08-plugin-layout.md`                      |
| `hooks/session-start.sh`                       | `07-hooks.md`, `03-plan-format.md`                        |
| `hooks/post-compact.sh`                        | `07-hooks.md`, `04-execution-loop.md`                     |
| `skills/conductor/SKILL.md`                    | `02-conductor.md`, `04-execution-loop.md`, `05-skills-catalog.md` |
| `skills/engineering-discipline/SKILL.md`       | `01-philosophy.md`, `05-skills-catalog.md`                |
| `skills/persistent-plans/SKILL.md`             | `03-plan-format.md`, `04-execution-loop.md`, `05-skills-catalog.md` |
| `skills/writing-plans/SKILL.md`                | `03-plan-format.md`, `04-execution-loop.md`, `05-skills-catalog.md`, `09-routing-matrix.md` |
| `skills/codex-dispatch/SKILL.md`               | `06-codex-integration.md`, `05-skills-catalog.md`         |
| Other `skills/*/SKILL.md` (core and auxiliary) | `05-skills-catalog.md` (+ skill-specific docs)            |
| `scripts/run-codex-impl.sh`                    | `06-codex-integration.md`                                 |
| `scripts/run-codex-verify.sh`                  | `06-codex-integration.md`                                 |
| `scripts/plan-utils.sh`                        | `03-plan-format.md`                                       |
| `scripts/parse-contract.sh`                    | `06-codex-integration.md`                                 |
| `schemas/plan.schema.json`                     | `03-plan-format.md`                                       |
| `schemas/progress.schema.json`                 | `03-plan-format.md`                                       |
| `templates/masterPlan.template.md`             | `03-plan-format.md`                                       |
| `tests/hooks/*.test.sh`                        | `07-hooks.md`                                             |
| `tests/scripts/parse-contract.test.sh`         | `06-codex-integration.md`                                 |
| `tests/scripts/plan-utils.test.sh`             | `03-plan-format.md`                                       |

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
   discipline skills.
7. **`.claude-plugin/plugin.json`**, **`hooks/hooks.json`**, and
   **`.claude-plugin/marketplace.json`** — the manifests. Trivial
   once the rest is solid.
8. **`README.md`**, **`AGENTS.md`**, **`install.sh`** — last, when
   everything else is testable.

## What the implementer should NOT add

To keep v2 from regressing into v1:

- **No `skills` array in `plugin.json`.** Skills are auto-discovered.
- **No fabricated `permissions` block in `plugin.json`.** The schema
  doesn't read it; permissions are a Claude Code settings concern.
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
