#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: plan-utils.sh <subcommand> [args...]

Subcommands:
  get-plan-dir <project-root>
  read-plan <plan-dir>
  read-progress <plan-dir>
  init-progress [--force] <plan-dir>
  start-step <plan-dir> <step-id> <executor> <model>
  set-step-status <plan-dir> <step-id> <status>
  record-verdict <plan-dir> <step-id> <verdict> <summary> <findings-json-array> <files-json-array>
  set-frontier <plan-dir> <space-separated-step-ids>
  compute-frontier <plan-dir>
USAGE
}

die() {
  printf 'plan-utils: %s\n' "$*" >&2
  exit 1
}

need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'plan-utils: jq is required but was not found in PATH\n' >&2
    exit 2
  fi
}

utc_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

abs_dir() {
  local dir=$1
  (cd "$dir" 2>/dev/null && pwd -P) || die "directory not found: $dir"
}

require_file_json() {
  local file=$1
  [[ -f "$file" ]] || die "missing file: $file"
  jq -e . "$file" >/dev/null
}

atomic_update_progress() {
  local plan_dir=$1
  local filter=$2
  shift 2

  local progress_file tmp
  progress_file="$plan_dir/progress.json"
  [[ -f "$progress_file" ]] || die "missing progress.json in $plan_dir"
  tmp=$(mktemp "$plan_dir/.progress.json.tmp.XXXXXX")

  if jq "$@" "$filter" "$progress_file" >"$tmp"; then
    mv "$tmp" "$progress_file"
  else
    rm -f "$tmp"
    return 1
  fi
}

valid_status() {
  case "$1" in
    pending | in_progress | done | blocked | skipped) return 0 ;;
    *) return 1 ;;
  esac
}

valid_verdict() {
  case "$1" in
    PASS | FINDINGS | FAIL) return 0 ;;
    *) return 1 ;;
  esac
}

valid_executor() {
  case "$1" in
    codex | grok | claude) return 0 ;;
    *) return 1 ;;
  esac
}

cmd_get_plan_dir() {
  [[ $# -eq 1 ]] || die "get-plan-dir requires <project-root>"

  local project_root active_dir
  project_root=$(abs_dir "$1")
  active_dir="$project_root/.temp/plan-mode/active"
  [[ -d "$active_dir" ]] || die "no active plan directory found under $active_dir"

  local selected
  selected=$(
    find "$active_dir" -mindepth 1 -maxdepth 1 -type d -print |
      while IFS= read -r dir; do
        local updated name
        updated=""
        if [[ -f "$dir/progress.json" ]]; then
          updated=$(jq -r '.lastUpdatedAt // ""' "$dir/progress.json" 2>/dev/null || printf '')
        fi
        name=$(basename "$dir")
        printf '%s\t%s\t%s\n' "$updated" "$name" "$dir"
      done |
      sort -t "$(printf '\t')" -k1,1r -k2,2 |
      awk -F '\t' 'NR == 1 { print $3 }'
  )

  [[ -n "$selected" ]] || die "no active plan directory found under $active_dir"
  abs_dir "$selected"
}

cmd_read_plan() {
  [[ $# -eq 1 ]] || die "read-plan requires <plan-dir>"
  local plan_dir plan_file
  plan_dir=$(abs_dir "$1")
  plan_file="$plan_dir/plan.json"
  require_file_json "$plan_file"
  cat "$plan_file"
}

cmd_read_progress() {
  [[ $# -eq 1 ]] || die "read-progress requires <plan-dir>"
  local plan_dir progress_file
  plan_dir=$(abs_dir "$1")
  progress_file="$plan_dir/progress.json"
  require_file_json "$progress_file"
  cat "$progress_file"
}

cmd_init_progress() {
  local force=false
  if [[ $# -gt 0 && "$1" == "--force" ]]; then
    force=true
    shift
  fi
  if [[ $# -gt 0 && "${!#}" == "--force" ]]; then
    force=true
    set -- "${@:1:$(($# - 1))}"
  fi
  [[ $# -eq 1 ]] || die "init-progress requires <plan-dir>"

  local plan_dir plan_file progress_file now tmp
  plan_dir=$(abs_dir "$1")
  plan_file="$plan_dir/plan.json"
  progress_file="$plan_dir/progress.json"
  require_file_json "$plan_file"

  if [[ -f "$progress_file" && "$force" != true ]]; then
    die "progress.json already exists in $plan_dir; pass --force to overwrite"
  fi

  now=$(utc_now)
  tmp=$(mktemp "$plan_dir/.progress.json.tmp.XXXXXX")
  if jq --arg now "$now" '
    {
      planId: .planId,
      startedAt: $now,
      lastUpdatedAt: $now,
      currentFrontier: [
        .steps[]
        | select((.dependsOn | length) == 0)
        | .id
      ],
      steps: (
        .steps
        | map({key: .id, value: {status: "pending"}})
        | from_entries
      )
    }
  ' "$plan_file" >"$tmp"; then
    mv "$tmp" "$progress_file"
  else
    rm -f "$tmp"
    return 1
  fi
}

cmd_start_step() {
  [[ $# -eq 4 ]] || die "start-step requires <plan-dir> <step-id> <executor> <model>"

  local plan_dir step_id executor model now
  plan_dir=$(abs_dir "$1")
  step_id=$2
  executor=$3
  model=$4
  valid_executor "$executor" || die "invalid executor: $executor"
  [[ -n "$model" ]] || die "model must not be empty"
  require_file_json "$plan_dir/progress.json"
  jq -e --arg id "$step_id" '.steps[$id] != null' "$plan_dir/progress.json" >/dev/null ||
    die "unknown step id: $step_id"

  now=$(utc_now)
  atomic_update_progress "$plan_dir" '
    .lastUpdatedAt = $now
    | .steps[$id].status = "in_progress"
    | .steps[$id].startedAt = (.steps[$id].startedAt // $now)
    | .steps[$id].dispatch = {
        executor: $executor,
        model: $model,
        startedAt: $now
      }
    | del(.steps[$id].completedAt)
  ' \
    --arg id "$step_id" \
    --arg executor "$executor" \
    --arg model "$model" \
    --arg now "$now"
}

cmd_set_step_status() {
  [[ $# -eq 3 ]] || die "set-step-status requires <plan-dir> <step-id> <status>"

  local plan_dir step_id status now
  plan_dir=$(abs_dir "$1")
  step_id=$2
  status=$3
  valid_status "$status" || die "invalid status: $status"
  require_file_json "$plan_dir/progress.json"
  jq -e --arg id "$step_id" '.steps[$id] != null' "$plan_dir/progress.json" >/dev/null ||
    die "unknown step id: $step_id"

  now=$(utc_now)
  atomic_update_progress "$plan_dir" '
    .lastUpdatedAt = $now
    | .steps[$id].status = $status
    | if $status == "pending" then
        del(.steps[$id].startedAt, .steps[$id].completedAt)
      elif $status == "in_progress" then
        .steps[$id].startedAt = (.steps[$id].startedAt // $now)
        | del(.steps[$id].completedAt)
      elif ($status == "done" or $status == "blocked" or $status == "skipped") then
        .steps[$id].completedAt = $now
      else
        .
      end
  ' --arg id "$step_id" --arg status "$status" --arg now "$now"
}

cmd_record_verdict() {
  [[ $# -eq 6 ]] || die "record-verdict requires <plan-dir> <step-id> <verdict> <summary> <findings-json-array> <files-json-array>"

  local plan_dir step_id verdict summary findings_json files_json now
  plan_dir=$(abs_dir "$1")
  step_id=$2
  verdict=$3
  summary=$4
  findings_json=$5
  files_json=$6
  valid_verdict "$verdict" || die "invalid verdict: $verdict"
  require_file_json "$plan_dir/progress.json"
  jq -e 'type == "array"' <<<"$findings_json" >/dev/null || die "findings must be a JSON array"
  jq -e 'type == "array"' <<<"$files_json" >/dev/null || die "filesTouched must be a JSON array"
  jq -e --arg id "$step_id" '.steps[$id] != null' "$plan_dir/progress.json" >/dev/null ||
    die "unknown step id: $step_id"

  now=$(utc_now)
  atomic_update_progress "$plan_dir" '
    .lastUpdatedAt = $now
    | .steps[$id].verdict = $verdict
    | .steps[$id].result = $summary
    | .steps[$id].findings = $findings
    | .steps[$id].filesTouched = $files
  ' \
    --arg id "$step_id" \
    --arg verdict "$verdict" \
    --arg summary "$summary" \
    --argjson findings "$findings_json" \
    --argjson files "$files_json" \
    --arg now "$now"
}

cmd_set_frontier() {
  [[ $# -ge 1 ]] || die "set-frontier requires <plan-dir> <space-separated-step-ids>"

  local plan_dir now frontier_json
  plan_dir=$(abs_dir "$1")
  shift
  require_file_json "$plan_dir/progress.json"

  frontier_json=$(printf '%s\n' "$@" | tr ' ' '\n' | awk 'NF > 0' | jq -R . | jq -s .)
  now=$(utc_now)
  atomic_update_progress "$plan_dir" '
    .lastUpdatedAt = $now
    | .currentFrontier = $frontier
  ' --argjson frontier "$frontier_json" --arg now "$now"
}

cmd_compute_frontier() {
  [[ $# -eq 1 ]] || die "compute-frontier requires <plan-dir>"

  local plan_dir
  plan_dir=$(abs_dir "$1")
  require_file_json "$plan_dir/plan.json"
  require_file_json "$plan_dir/progress.json"

  jq -r --slurpfile progress "$plan_dir/progress.json" '
    $progress[0] as $p
    | .steps[]
    | select(($p.steps[.id].status // null) == "pending")
    | select(all(.dependsOn[]; $p.steps[.].status == "done"))
    | .id
  ' "$plan_dir/plan.json"
}

main() {
  need_jq
  [[ $# -ge 1 ]] || {
    usage
    exit 1
  }

  local subcommand=$1
  shift
  case "$subcommand" in
    get-plan-dir) cmd_get_plan_dir "$@" ;;
    read-plan) cmd_read_plan "$@" ;;
    read-progress) cmd_read_progress "$@" ;;
    init-progress) cmd_init_progress "$@" ;;
    start-step) cmd_start_step "$@" ;;
    set-step-status) cmd_set_step_status "$@" ;;
    record-verdict) cmd_record_verdict "$@" ;;
    set-frontier) cmd_set_frontier "$@" ;;
    compute-frontier) cmd_compute_frontier "$@" ;;
    -h | --help | help)
      usage
      ;;
    *)
      usage
      die "unknown subcommand: $subcommand"
      ;;
  esac
}

main "$@"
