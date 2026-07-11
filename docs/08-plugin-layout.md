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

`install.sh` resolves exactly one absolute `installPath` from `claude plugin
list --json`, validates that cached artifact, and uses it as the canonical
source. Claude loads its skills from the plugin cache; same-named plugin-owned
directories are removed from `~/.claude/skills` rather than copied there. The
seven injectable external-lane skills are copied from the installed artifact
to `~/.codex/skills` and `~/.grok/skills`, while unowned skills remain intact.
After install, restart Claude Code or run `/reload-plugins`. Never patch the
cache or user Claude settings directly.

Clean rollback removes `orchestration` and its marketplace with the Claude
plugin CLI. `install.sh` always reinstalls the marketplace's current artifact,
not the invoking checkout, so a historical rollback must be exposed as a
marketplace version. The Mini-side `agent-supervisor` and `remote-agent-v1`
have no fixed destination but must be installed together on the Mini's `PATH`;
retain and restore them as a matched pair. Transfer rollback itself is owned by
the private restore journal: verified restore leaves ownership unchanged, and
failed restore preserves recovery-required evidence and the mutex.

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
│   ├── 01-philosophy.md … 12-phone-control-surface.md
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
    │   ├── skill-review-standard/       ← auxiliary: skill QA gate
    │   └── remote-agent-host/           ← auxiliary: guarded Mini handoff
    │       (each skill dir contains SKILL.md and optional references/, scripts/)
    │
    ├── codex-skills/                    ← Codex-side bodies for dual-install skills
    │   └── react-native-mobile/
    │       └── SKILL.md
    │
    ├── hooks/                           ← event handlers + manifest
    │   ├── hooks.json                   ← maps event names → handler scripts
    │   ├── session-start.sh             ← read-only SessionStart notice handler
    │   ├── post-compact.sh              ← read-only PostCompact notice handler
    │   └── agent-event.sh               ← fail-open private-queue lifecycle observer
    │
    ├── scripts/                         ← codex wrappers + utilities
    │   ├── run-codex-impl.sh
    │   ├── run-codex-verify.sh
    │   ├── run-grok-impl.sh
    │   ├── run-grok-verify.sh
    │   ├── plan-utils.sh                ← read/write helpers for plan files
    │   ├── parse-contract.sh            ← extract the contract block
    │   ├── remote-agent.sh              ← guarded host-side Mini boundary
    │   ├── agent-supervisor             ← Mini session/event adapter
    │   ├── remote-agent-v1              ← Mini synchronization authority
    │   ├── agent-control                ← Mini-local guarded-verb authority (phone surface)
    │   ├── phone-control-gateway        ← loopback HTTP+SSE daemon (Python 3 stdlib)
    │   ├── phone-control-bridge         ← MacBook SSH long-poll ownership worker
    │   └── phone-control-install-check  ← read-only install/hardening validator
    │
    ├── schemas/                         ← JSON schemas for plan files
    │   ├── plan.schema.json
    │   └── progress.schema.json
    │
    ├── templates/                       ← starter templates
    │   ├── masterPlan.template.md
    │   └── phone-control/               ← installable PWA shell + LaunchAgent plists
    │       ├── index.html
    │       ├── app.js
    │       ├── style.css
    │       ├── manifest.webmanifest
    │       ├── sw.js
    │       ├── icon.svg
    │       ├── com.orchestration.phone-control-gateway.plist
    │       └── com.orchestration.phone-control-bridge.plist
    │
    └── tests/                           ← hook + script tests
        ├── hooks/
        │   ├── agent-event.test.sh
        │   ├── session-start.test.sh
        │   └── post-compact.test.sh
        └── scripts/
            ├── agent-supervisor.test.sh
            ├── install.test.sh
            ├── parse-contract.test.sh
            ├── plan-utils.test.sh
            ├── remote-agent-protocol.test.sh
            ├── remote-agent.test.sh
            ├── run-codex-impl.test.sh
            ├── run-codex-verify.test.sh
            ├── run-grok-impl.test.sh
            ├── run-grok-verify.test.sh
            ├── skill-contracts.test.sh
            ├── validate-structure.test.sh
            ├── agent-control.test.sh
            ├── phone-control-gateway.test.sh
            ├── phone-control-bridge.test.sh
            ├── phone-control-install.test.sh
            └── phone-control-e2e.test.sh
```

Notes on shape:

The core plugin subtree contains 18 Claude-side skills (9 core and 9
auxiliary), 1 Codex-side skill body, 2 read-only notice handlers and 1 fail-open
private-queue observer with a six-event manifest, 9 scripts (4 model wrappers
and 5 helpers), 2 schemas, 1 template, and 15 test suites (12 script suites and
3 hook suites). The phone-from-anywhere control surface described in
`12-phone-control-surface.md` extends this with 4 more scripts (`agent-control`,
`phone-control-gateway`, `phone-control-bridge`, `phone-control-install-check`),
the `templates/phone-control/` asset set (six PWA shell files plus two
LaunchAgent plists), and 5 more test suites, and adds new verbs to the existing
Mini authorities (`remote-agent-v1` gains `peek`, `git-align`, and the cession
transitions; `remote-agent.sh` gains `cede` and `uncede`) — bringing the totals
to 13 scripts and 20 test suites. The non-shipped routing eval adds 7 scripts
and 5 test suites at the repo root.

- **`.claude-plugin/` holds each manifest.** Claude Code's plugin
  schema places metadata under `.claude-plugin/` rather than at the
  repo root. This repo has two such directories: the repo-root
  `.claude-plugin/marketplace.json` and the plugin's own
  `orchestration/.claude-plugin/plugin.json`. Even in a single-plugin
  repo the marketplace `source` must point at a real subdirectory
  (`./orchestration`) — Claude Code does **not** accept `"."` as a
  same-dir marker — which is why the plugin lives in its own subdir
  rather than sharing the root `.claude-plugin/` directory.
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
- **Hooks declared in `hooks/hooks.json`.** Three `.sh` files implement six
  event registrations. `SessionStart` and `PostCompact` provide bounded
  read-only plan notices. `Stop`, `SubagentStop`, `StopFailure`, and
  `Notification` share one synchronous, fail-open, non-decision bridge into a
  private labels-only queue. This explicitly supersedes the former
  exactly-two-read-only-hooks design; it does not restore tool gates or permit
  user-settings edits. See `07-hooks.md` for the event semantics and privacy
  contract.
- **`scripts/` holds the wrappers and a small set of helpers.**
  `plan-utils.sh` provides idempotent read/write of `plan.json` and
  `progress.json` so the conductor doesn't reinvent jq invocations.
  `parse-contract.sh` extracts the contract block from raw Codex
  output and is used by both Codex wrappers. The four direction-locked
  wrappers remain `run-{codex,grok}-{impl,verify}.sh`; `remote-agent.sh` is a
  separate guarded transport/session helper, not a fifth model wrapper.
- **Mini handoff has four artifacts.** `skills/remote-agent-host/SKILL.md`
  translates natural language and enforces capture-before-input;
  `scripts/remote-agent.sh` exposes the closed help surface (`status`, `start`,
  `inspect`, `continue`, `send`, `interrupt`, `kill`, `wait`, `reveal`,
  `reclaim`; projects
  `miospot` / `orchestration`; harnesses `claude` / `codex` / `grok`). The
  only options are `--host`, `--prompt-file`, `--active-plan`,
  `--include-ignored`, `--approve-ignored`, `--cursor`, and `--timeout`;
  `PROJECT` selects the canonical local Git toplevel through the independent
  `LOCAL_MIOSPOT_ROOT` / `LOCAL_ORCHESTRATION_ROOT` mappings (defaulting under
  `$HOME/Projects`) rather than caller cwd;
  prompt content is read from the
  named file and never placed in argv, and ignored paths require identical
  literal include/approval values. Successful `start` and running `status`
  expose a bounded labels-only `bootstrapCursor` for the first direct `wait`.
  `scripts/agent-supervisor` owns tmux,
  bounded capture, private event queues, blocking wait, and Terminal reveal;
  `scripts/remote-agent-v1` owns synchronization and lease proofs. Both
  Mini-side executables must be installed together on the Mini's `PATH`; no
  fixed destination directory is defined. The installed Claude/Codex/Grok
  subscription TUIs must already be interactively authenticated. Local state
  is diagnostic, while the Mini lease,
  generation, restore journal, and recovery evidence are authoritative. It
  provides one start/reclaim ownership handoff, not continuous sync, secret
  copying, chat persistence, backend bootstrap, or reboot survival.
- **`eval/` is a repo-root, non-shipped developer tool.** The routing
  eval harness lives in an `eval/` directory at the repo root — a
  sibling of `docs/` and `orchestration/`, **not** a subdirectory of
  `orchestration/`. Because the plugin's marketplace source is
  `./orchestration`, everything under `eval/` is excluded from what
  ships; it is a local developer/research tool, never installed with
  the plugin. It is deliberately absent from the `orchestration/`
  subtree above; if drawn, it belongs at the repo-root level alongside
  `docs/`. Read `docs/11-routing-eval.md` before touching any `eval/`
  artifact.

## `.claude-plugin/plugin.json` (plugin manifest)

The minimum the harness needs:

```json
{
  "name": "orchestration",
  "description": "Conductor-mode orchestrator: persistent plans, bounded sub-agent dispatch, direction-locked Codex impl/verify. Read-only plan notices, fail-open private-queue lifecycle observers, no gates."
}
```

Optional fields the schema allows:

- `mcpServers` — map of MCP server name → invocation. v2 declares
  one entry, `orbit`, invoked via the `orbit-mcp` command (assumed
  on `PATH`). Orbit surfaces `masterPlan.md` for human review before
  the conductor flips `plan.json.frozen` to `true`, and provides the
  review-state primitives the conductor uses during the plan-mode
  handoff. Shape:

  ```json
  "mcpServers": {
    "orbit": {
      "command": "orbit-mcp"
    }
  }
  ```

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
  "description": "Conductor-mode orchestrator for Claude Code: persistent plans, direction-locked Codex impl/verify, bounded prompt-contract I/O, read-only plan notices and fail-open lifecycle observers.",
  "owner": {
    "name": "Miospot Dev Team"
  },
  "plugins": [
    {
      "name": "orchestration",
      "description": "Conductor-mode orchestrator: persistent plans, bounded sub-agent dispatch, direction-locked Codex impl/verify. Read-only plan notices, fail-open private-queue lifecycle observers, no gates.",
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

The manifest has exactly six keys:

| Event | Matcher | Handler | Timeout |
|---|---|---|---|
| `SessionStart` | `startup|resume|clear` | `session-start.sh` | 10 s, synchronous |
| `PostCompact` | none | `post-compact.sh` | 10 s |
| `Stop` | none | `agent-event.sh` | 2 s, synchronous |
| `SubagentStop` | none | `agent-event.sh` | 2 s, synchronous |
| `StopFailure` | none | `agent-event.sh` | 2 s, synchronous |
| `Notification` | none | `agent-event.sh` | 2 s, synchronous |

`SessionStart` excludes `compact` because `PostCompact` owns that lifecycle.
The four lifecycle observers perform their exact allowlisting inside the
shared handler, emit no decision, and fail open. Their only mutation is an
atomic append of closed scope/kind labels to private mode-`0700`/`0600`
supervisor state; they do not retain hook payload text or edit user Claude
settings. Full executable JSON lives in `orchestration/hooks/hooks.json`, and
`docs/07-hooks.md` defines the semantic limits: main stop, subagent stop,
failure, input-needed, tmux exit, and timeout are distinct wakes and none
proves lease quiescence.

## Per-artifact source docs

Cross-reference: which doc(s) inform which file.

| Artifact                                       | Read first                                                |
|------------------------------------------------|-----------------------------------------------------------|
| `README.md`                                    | This repo's `README.md`, `01-philosophy.md`               |
| `AGENTS.md`                                    | This repo's `AGENTS.md`, `02-conductor.md`                |
| `docs/12-phone-control-surface.md`             | `12-phone-control-surface.md` (this artifact), `05-skills-catalog.md`, `08-plugin-layout.md` |
| `.claude-plugin/plugin.json`                   | `08-plugin-layout.md` (this doc)                          |
| `.claude-plugin/marketplace.json`              | `08-plugin-layout.md` (this doc)                          |
| `install.sh`                                   | `08-plugin-layout.md` (this doc), the `claude plugin` CLI |
| `hooks/hooks.json`                             | `07-hooks.md`, `08-plugin-layout.md`                      |
| `hooks/session-start.sh`                       | `07-hooks.md`, `03-plan-format.md`                        |
| `hooks/post-compact.sh`                        | `07-hooks.md`, `04-execution-loop.md`                     |
| `hooks/agent-event.sh`                         | `07-hooks.md`, `05-skills-catalog.md`                     |
| `skills/conductor/SKILL.md`                    | `02-conductor.md`, `04-execution-loop.md`, `05-skills-catalog.md` |
| `skills/engineering-discipline/SKILL.md`       | `01-philosophy.md`, `05-skills-catalog.md`                |
| `skills/persistent-plans/SKILL.md`             | `03-plan-format.md`, `04-execution-loop.md`, `05-skills-catalog.md` |
| `skills/writing-plans/SKILL.md`                | `03-plan-format.md`, `04-execution-loop.md`, `05-skills-catalog.md`, `09-routing-matrix.md` |
| `skills/codex-dispatch/SKILL.md`               | `06-codex-integration.md`, `05-skills-catalog.md`         |
| `skills/remote-agent-host/SKILL.md`             | `05-skills-catalog.md`, `08-plugin-layout.md`              |
| Other `skills/*/SKILL.md` (core and auxiliary) | `05-skills-catalog.md` (+ skill-specific docs)            |
| `scripts/run-codex-impl.sh`                    | `06-codex-integration.md`                                 |
| `scripts/run-codex-verify.sh`                  | `06-codex-integration.md`                                 |
| `scripts/run-grok-impl.sh`                     | `10-grok-integration.md`                                  |
| `scripts/run-grok-verify.sh`                   | `10-grok-integration.md`                                  |
| `scripts/plan-utils.sh`                        | `03-plan-format.md`                                       |
| `scripts/parse-contract.sh`                    | `06-codex-integration.md`                                 |
| `scripts/remote-agent.sh`                      | `05-skills-catalog.md`, `08-plugin-layout.md`, `12-phone-control-surface.md` |
| `scripts/agent-supervisor`                     | `05-skills-catalog.md`, `07-hooks.md`, `08-plugin-layout.md` |
| `scripts/remote-agent-v1`                      | `05-skills-catalog.md`, `08-plugin-layout.md`, `12-phone-control-surface.md` |
| `scripts/agent-control`                        | `12-phone-control-surface.md`                             |
| `scripts/phone-control-gateway`                | `12-phone-control-surface.md`                             |
| `scripts/phone-control-bridge`                 | `12-phone-control-surface.md`                             |
| `scripts/phone-control-install-check`          | `12-phone-control-surface.md`, `08-plugin-layout.md`      |
| `templates/phone-control/index.html`           | `12-phone-control-surface.md`                             |
| `templates/phone-control/app.js`               | `12-phone-control-surface.md`                             |
| `templates/phone-control/style.css`            | `12-phone-control-surface.md`                             |
| `templates/phone-control/manifest.webmanifest` | `12-phone-control-surface.md`                             |
| `templates/phone-control/sw.js`                | `12-phone-control-surface.md`                             |
| `templates/phone-control/icon.svg`             | `12-phone-control-surface.md`                             |
| `templates/phone-control/com.orchestration.phone-control-gateway.plist` | `12-phone-control-surface.md`, `08-plugin-layout.md` |
| `templates/phone-control/com.orchestration.phone-control-bridge.plist`  | `12-phone-control-surface.md`, `08-plugin-layout.md` |
| `schemas/plan.schema.json`                     | `03-plan-format.md`                                       |
| `schemas/progress.schema.json`                 | `03-plan-format.md`                                       |
| `templates/masterPlan.template.md`             | `03-plan-format.md`                                       |
| `tests/hooks/*.test.sh`                        | `07-hooks.md`                                             |
| `tests/hooks/agent-event.test.sh`              | `07-hooks.md`, `05-skills-catalog.md`                     |
| `tests/scripts/parse-contract.test.sh`         | `06-codex-integration.md`                                 |
| `tests/scripts/plan-utils.test.sh`             | `03-plan-format.md`                                       |
| `tests/scripts/agent-supervisor.test.sh`       | `05-skills-catalog.md`, `07-hooks.md`                     |
| `tests/scripts/remote-agent-protocol.test.sh`  | `05-skills-catalog.md`, `08-plugin-layout.md`             |
| `tests/scripts/remote-agent.test.sh`           | `05-skills-catalog.md`, `08-plugin-layout.md`             |
| `tests/scripts/run-codex-impl.test.sh`         | `06-codex-integration.md`                                 |
| `tests/scripts/run-codex-verify.test.sh`       | `06-codex-integration.md`                                 |
| `tests/scripts/run-grok-impl.test.sh`          | `10-grok-integration.md`                                  |
| `tests/scripts/run-grok-verify.test.sh`        | `10-grok-integration.md`                                  |
| `tests/scripts/skill-contracts.test.sh`        | `05-skills-catalog.md`                                    |
| `tests/scripts/validate-structure.test.sh`     | `05-skills-catalog.md`, `12-phone-control-surface.md`     |
| `tests/scripts/install.test.sh` (repo root `install.sh`) | `08-plugin-layout.md`                           |
| `tests/scripts/agent-control.test.sh`          | `12-phone-control-surface.md`                             |
| `tests/scripts/phone-control-gateway.test.sh`  | `12-phone-control-surface.md`                             |
| `tests/scripts/phone-control-bridge.test.sh`   | `12-phone-control-surface.md`                             |
| `tests/scripts/phone-control-install.test.sh`  | `12-phone-control-surface.md`, `08-plugin-layout.md`      |
| `tests/scripts/phone-control-e2e.test.sh`      | `12-phone-control-surface.md`                             |
| `eval/corpus/`                                 | `11-routing-eval.md`                                      |
| `eval/scripts/`                                | `11-routing-eval.md`                                      |
| `eval/results/`                                | `11-routing-eval.md`                                      |
| `eval/tests/`                                  | `11-routing-eval.md`                                      |
| `eval/tests/aggregate.test.sh`                 | `11-routing-eval.md`                                      |
| `eval/tests/extract-judge-json.test.sh`        | `11-routing-eval.md`                                      |
| `eval/tests/helpers.test.sh`                   | `11-routing-eval.md`                                      |
| `eval/tests/score-objective.test.sh`           | `11-routing-eval.md`                                      |
| `eval/tests/corpus-harnesses.test.sh`          | `11-routing-eval.md`                                      |

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
5. **`scripts/run-grok-impl.sh` and `run-grok-verify.sh`** — the
   Grok wrappers, mirroring the Codex wrapper shape once the parser
   is solid.
6. **`scripts/remote-agent-v1` + `agent-supervisor` + `remote-agent.sh` +
   `skills/remote-agent-host/SKILL.md` + tests** — keep synchronization,
   lifecycle events, executable help, and natural intent aligned.
7. **`hooks/session-start.sh` + `post-compact.sh` + `agent-event.sh` + tests**
   — keep context injection separate from the private labels-only lifecycle
   bridge.
8. **`skills/`** — write `conductor`, `persistent-plans`, and
   `codex-dispatch` first (they wire everything together), then the
   discipline skills.
9. **`.claude-plugin/plugin.json`**, **`hooks/hooks.json`**, and
   **`.claude-plugin/marketplace.json`** — the manifests. Trivial
   once the rest is solid.
10. **`README.md`**, **`AGENTS.md`**, **`install.sh`** — last, when
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
- **No `pre-*` hooks or extra lifecycle events.** The six manifest entries are
  the entirety of the hook surface. The four Mini observers must remain
  fail-open, non-decision, private-queue bridges and must never edit user
  Claude settings.
- **No `lib/` shared between skills.** Skills compose via prose
  references, not shared imports.
- **No `enforcement/` mode flag.** v2 is gentle reminders only.

If any of these feel necessary mid-build, re-read
`01-philosophy.md` and reconsider. The bias is toward less, not
more.
