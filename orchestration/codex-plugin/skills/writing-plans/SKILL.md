---
name: writing-plans
description: Draft and approve the existing orchestration plan artifacts from a Codex-native session with a Grok 4.5 independent planning and review pass. Use after discovery is sufficient for a non-trivial change. Do not use during execution or for a trivial edit.
---

# Codex-native writing plans

## Resolve the runtime package

Never infer the runtime package root from this SKILL.md, its selected skill path,
or a version-cache parent. Before using any orchestration helper, resolve the
installed source recorded by Codex:

```bash
resolve_orchestration_runtime_root() {
  local listing matches count source_path source_layout candidate directory

  listing="$(codex plugin list --json)" || {
    printf 'cannot read the Codex plugin listing\n' >&2
    return 1
  }
  matches="$(jq -ce --arg id 'orchestration@claude-codex-orchestration' '
    def installed_entries:
      if type == "array" then .[]
      elif type == "object" and (.installed? | type) == "array" then .installed[]
      elif type == "object" and (.plugins? | type) == "array" then .plugins[]
      else error("malformed Codex plugin listing")
      end;
    [installed_entries
      | select(type == "object")
      | select(
          (.pluginId? == $id or .id? == $id)
          and .enabled? == true
        )
      | if (.source? | type) != "object"
          or (.source.path? | type) != "string"
          or (.source.path | length) == 0
        then error("malformed enabled orchestration source.path")
        else .source.path
        end]
  ' <<<"$listing")" || {
    printf 'malformed Codex plugin listing\n' >&2
    return 1
  }
  count="$(jq -r 'length' <<<"$matches")"
  [[ "$count" == 1 ]] || {
    printf 'expected exactly one enabled orchestration plugin source; found %s\n' "$count" >&2
    return 1
  }
  source_path="$(jq -er '.[0]' <<<"$matches")" || return 1
  [[ "$source_path" == /* && -d "$source_path" ]] || {
    printf 'orchestration source.path is not an absolute directory\n' >&2
    return 1
  }
  source_layout="$(basename "$source_path")"
  source_path="$(cd "$source_path" && pwd -P)" || return 1
  [[ -f "$source_path/.codex-plugin/plugin.json" ]] || {
    printf 'orchestration source has no Codex manifest\n' >&2
    return 1
  }
  jq -e '.name == "orchestration" and .skills == "./skills/"'     "$source_path/.codex-plugin/plugin.json" >/dev/null || {
    printf 'orchestration source manifest is malformed\n' >&2
    return 1
  }

  if [[ "$source_layout" == codex-plugin ]]; then
    candidate="$(cd "$source_path/.." && pwd -P)" || return 1
  else
    candidate="$source_path"
  fi
  for directory in scripts schemas templates config; do
    [[ -d "$candidate/$directory" ]] || {
      printf 'orchestration runtime root is missing %s\n' "$directory" >&2
      return 1
    }
  done
  printf '%s\n' "$candidate"
}
RUNTIME_PACKAGE_ROOT="$(resolve_orchestration_runtime_root)" || exit 1
```

The conventional installed source is the `codex-plugin` subdirectory, so its
validated parent is the runtime package root. A future root-source package is
valid only when the source path itself contains `scripts`, `schemas`,
`templates`, and `config`. Missing, ambiguous, disabled, relative, or
malformed sources fail closed. `codex plugin list --json` is the only direct
provider CLI call allowed, and only for this discovery.
Never invoke `codex exec`, `grok`, or `claude` directly. Invoke model work only through the
validated wrappers under `${RUNTIME_PACKAGE_ROOT}`.

Use the plugin's existing plan contract; do not invent a second format. Use the validated runtime package root, then use:

- `schemas/plan.schema.json` for immutable `plan.json`.
- `schemas/progress.schema.json` for mutable `progress.json`.
- `templates/masterPlan.template.md` for the human-facing proposal.
- `${RUNTIME_PACKAGE_ROOT}/scripts/plan-utils.sh init-progress <plan-dir>`
  exactly once, after approval.

## Draft

Create `.temp/plan-mode/active/<planId>/plan.json` with
`routingProfile: "codex-primary"`, `frozen: false`, and a
matching `masterPlan.md`. Do not create `progress.json` yet. Each step must have
one owner from the existing enum, explicit acceptance criteria, expected files,
and dependency edges sufficient to prevent overlapping writes.

This Codex-native lane has `claude_workers=deny`. A step with
`owner: "claude-impl"` **must not be approved**. Choose `codex-impl` for the
default clear-spec implementation lane, `grok-impl` for an independent or
capacity-balanced implementation, and `manual` when neither model can satisfy
the acceptance criteria without a prohibited Claude worker. Explain any taste
tradeoff in the step description; never hide it as a fallback.

## Independent planning and review

For ambiguous work, dispatch the identical brief independently through both
direction-locked implementation wrappers with scenario `planning`: synthetic
steps `panel-codex` and `panel-grok`. The host sees neither candidate until both
exist, then converges them. Grok remains pinned to 4.5/high.

Before approval, pass the proposed `plan.json` and `masterPlan.md` through both
Codex and Grok verification wrappers with scenario `review`. Fix every FINDINGS
or FAIL result and re-run both. If either required lane is unavailable or its
contract fails twice, stop with the draft unapproved.

## Approval

Present the final `masterPlan.md` in conversation and wait for explicit user
approval. On approval, set `approvedAt`, set `approvedVia` to
`"conversational"`, set `frozen: true`, validate the JSON against the shipped
schema, and run
`${RUNTIME_PACKAGE_ROOT}/scripts/plan-utils.sh init-progress <plan-dir>`.
From that point
on, structural changes require a new plan; runtime facts belong in
`progress.json` deviations.
