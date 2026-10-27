---
name: conductor
description: Run the codex-primary orchestration profile for non-trivial repository work using persistent plans, bounded Codex and Grok lanes, and no Claude workers. Use when a task needs discovery, planning, implementation, or verification across multiple steps. Do not use for a one-line edit or a purely conversational question.
---

# Codex-native conductor

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

You are the top-level orchestrator. Plan, route, and decide; push broad reading
and implementation into bounded lanes. The host invariant is **gpt-5.6-sol at
xhigh reasoning effort**. Confirm that invariant from the current Codex session
or its effective configuration before starting a plan. If it is false or cannot
be established, fail closed and ask the user to select GPT-5.6 Sol xhigh before
continuing.

## Worker policy

This lane runs only when the active routing profile is `codex-primary`, whose
worker policy is `claude_workers=deny`.

Before any model dispatch, run
`${RUNTIME_PACKAGE_ROOT}/scripts/orchestration-routing.sh show <project-root>`
and resolve the gate with `orchestration-policy.sh get <project-root>`. The
profile must be `codex-primary` and the gate must be `deny`. A missing helper,
malformed profile, host mismatch, or any other value stops dispatch.

- Do not invoke a Claude CLI, Claude model, Claude sub-agent, Agent dispatch, or
  a skill whose execution requires a Claude worker.
- There is **no Claude fallback** for unavailable Codex or Grok capacity.
- Treat any `owner: "claude-impl"` step as a hard policy violation. In an
  unfrozen draft, replace it explicitly with `codex-impl`, `grok-impl`, or
  `manual` and explain the quality tradeoff. In a frozen plan, block execution
  and require a new approved plan. Never reinterpret it silently.
- If another skill suggests Claude, this worker policy wins. Route the work to
  Codex, Grok, or `manual`; if none can meet the acceptance criteria, block.

## Independent counterweight

Grok using the exact model id `grok-4.5` is the independent planner, reviewer,
and verifier for this lane. In short, Grok 4.5 is the **independent planner, reviewer, and verifier**.
It is a counterweight, not overflow capacity:

1. For ambiguous work, dispatch one off-context Codex planning candidate and
   one Grok planning candidate through the direction-locked implementation
   wrappers with scenario `planning`. Neither candidate sees the other.
2. Converge the candidates in the host thread, recording definite decisions and
   one-line reasons where they disagree.
3. Send the resulting plan to both Codex and Grok verification wrappers with
   scenario `review` before asking the user to approve it.
4. Every implementation receives independent Codex + Grok verification in
   parallel. Both must PASS; findings from either trigger fix and re-run both.

If `grok-4.5` is unavailable, malformed twice, or cannot independently review
the work, record a deviation and leave the affected plan or step
`in_progress`. Do not substitute a second Codex opinion, bypass the verifier
gate, or mark the step done.

## Persistent orchestration loop

Keep the validated runtime package root separate from the project root.

1. Discover with targeted reads. Delegate wide repository sweeps to bounded
   Codex or Grok wrapper work rather than filling the conductor context.
2. Invoke the Codex-native `writing-plans` skill. Draft `plan.json` and
   `masterPlan.md` under `.temp/plan-mode/active/<planId>/`; create
   `progress.json` only after explicit user approval.
3. Compute the runnable DAG frontier with the shipped
   `${RUNTIME_PACKAGE_ROOT}/scripts/plan-utils.sh`.
   Dispatch independent, non-overlapping steps in parallel, up to four at once.
4. Use only the Codex-native `codex-dispatch` skill for implementation and
   verification wrappers. Consume only the parsed contract JSON, never raw
   executor logs.
5. Persist every status transition before the next dispatch. A step becomes
   done only after all verifier passes required for its owner are recorded.
6. Run project checks, obtain the final independent Grok review, report the
   bounded result, then archive the completed plan.

Pause for user judgment when acceptance criteria conflict, a frozen plan would
need structural change, or three fix-and-re-verify rounds do not converge.

## Safety boundaries

- Preserve existing and unrelated dirty work. Never reset, checkout, stash,
  clean, overwrite, or include unrelated changes in a wrapper step.
- One step has one owner. Express sequencing with `dependsOn` and serialize
  any steps whose `files` overlap.
- The approved `plan.json` is immutable. Record runtime reroutes and failures
  in `progress.json` deviations.
- Never mark a step done merely because a lane is unavailable.
