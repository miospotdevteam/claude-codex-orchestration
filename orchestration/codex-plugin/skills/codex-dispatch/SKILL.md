---
name: codex-dispatch
description: Dispatch Codex and Grok implementation or verification work through the existing direction-locked wrappers from a Codex-native conductor, then persist only parsed contract results. Use for every runnable implementation step and every independent verifier pass. Do not use for free-form calls or direct model CLI invocation.
---

# Codex-native dispatch

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

Use the validated runtime package root and invoke only these shipped wrapper contracts:

- `${RUNTIME_PACKAGE_ROOT}/scripts/run-codex-impl.sh` for
  `owner: "codex-impl"` implementation.
- `${RUNTIME_PACKAGE_ROOT}/scripts/run-codex-verify.sh` for read-only
  Codex verification.
- `${RUNTIME_PACKAGE_ROOT}/scripts/run-grok-impl.sh` for
  `owner: "grok-impl"` implementation.
- `${RUNTIME_PACKAGE_ROOT}/scripts/run-grok-verify.sh` for read-only
  Grok verification.
- `${RUNTIME_PACKAGE_ROOT}/scripts/parse-contract.sh` inside the
  wrappers for bounded JSON output.
- `${RUNTIME_PACKAGE_ROOT}/scripts/plan-utils.sh` for progress
  transitions and verdict recording.

Never invoke `codex exec`, `grok`, or `claude` directly. Never pass a model
argument to a wrapper. Pass only the route's scenario enum; Codex wrappers map
that enum to an internal effort, while Grok stays pinned to 4.5/high.

## Dispatch protocol

1. Inspect `git status` and the step's expected files. Preserve unrelated dirty
   work and serialize any overlapping step or wrapper self-edit.
2. Render the existing step block from `plan.json`: title, description,
   acceptance criteria, files, and progress checklist.
3. Before implementation, run
   `${RUNTIME_PACKAGE_ROOT}/scripts/plan-utils.sh start-step` with
   executor, model, and effort so `progress.json` durably records the dispatch.
4. Invoke the owner-specific implementation wrapper. Read only its parsed JSON
   stdout; raw logs remain human-debugging artifacts.
5. For every profiled implementation step, persist each verifier first with
   `record-lane-dispatch`, then dispatch
     `${RUNTIME_PACKAGE_ROOT}/scripts/run-codex-verify.sh` and
     `${RUNTIME_PACKAGE_ROOT}/scripts/run-grok-verify.sh` in
   parallel with scenario `review`; both must PASS under `codex-primary`.
   An implementation step owned by `claude-impl` remains a policy violation
   under `claude_workers=deny` and blocks without fallback. Manual steps are
   verifier-exempt. Unprofiled legacy plans retain their owner matrix.
6. Record each lane verdict with
   `${RUNTIME_PACKAGE_ROOT}/scripts/plan-utils.sh record-verdict`.
   Only after the required PASS set exists may that helper mark the step done.

FINDINGS and FAIL both become the bounded fix specification. Re-dispatch the
owner lane for a fix, then re-run every required verifier. After three
non-converging rounds, stop for user judgment.

## Fail closed

If Codex is unavailable, the implementation or cross-family gate stays blocked.
If Grok 4.5 is unavailable, every affected implementation, plan review, or
verification stays blocked. Contract parse failures get one strict retry; a
second failure blocks the operation. There is no Claude fallback, no degraded
same-family PASS, and no `--degraded` completion for this lane.
