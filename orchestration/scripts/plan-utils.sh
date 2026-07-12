#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PLAN_SCHEMA="$SCRIPT_DIR/../schemas/plan.schema.json"

usage() {
  cat >&2 <<'USAGE'
Usage: plan-utils.sh <subcommand> [args...]

Subcommands:
  get-plan-dir <project-root>
  read-plan <plan-dir>
  read-progress <plan-dir>
  init-progress [--force] <plan-dir>
  start-step <plan-dir> <step-id> <executor> <model> <effort>
  set-step-status <plan-dir> <step-id> <status>
  record-lane-dispatch <plan-dir> <step-id> <lane> <executor> <model> <effort>
  record-deviation <plan-dir> <step-id> <type> <description> <files-json-array>
  record-verdict <plan-dir> <step-id> <verdict> <summary> <findings-json-array> <files-json-array> [lane]
  set-frontier <plan-dir> <space-separated-step-ids>
  compute-frontier <plan-dir>
  archive-plan [--force] <plan-dir>
  list-plans <project-root>
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

valid_lane() {
  case "$1" in
    claude | codex | grok) return 0 ;;
    *) return 1 ;;
  esac
}

owner_is_implementation() {
  case "$1" in
    claude-impl | codex-impl | grok-impl) return 0 ;;
    *) return 1 ;;
  esac
}

lane_is_required() {
  local plan_dir=$1
  local step_id=$2
  local lane=$3
  local required_json
  required_json=$(required_lanes_json_for_step "$plan_dir" "$step_id")
  jq -e --arg lane "$lane" 'index($lane) != null' <<<"$required_json" >/dev/null
}

required_lanes_json_for_owner() {
  local owner=$1
  [[ -f "$PLAN_SCHEMA" ]] || die "missing plan schema: $PLAN_SCHEMA"
  jq -ce --arg owner "$owner" '
    .["$defs"].owner["x-requiredVerifierLanes"] as $matrix
    | if $matrix | has($owner) then
        $matrix[$owner]
      else
        error("owner is absent from x-requiredVerifierLanes")
      end
  ' "$PLAN_SCHEMA" 2>/dev/null || die "invalid step owner or verifier matrix: $owner"
}

# Routing profile from plan.json. Empty string identifies a legacy plan.
routing_profile_from_plan() {
  local plan_dir=$1
  local plan_file="$plan_dir/plan.json"
  [[ -f "$plan_file" ]] || die "missing plan.json in $plan_dir"
  jq -r '.routingProfile // empty' "$plan_file"
}

# New plans freeze their verifier lanes through routingProfile. Plans without
# the field retain the schema-backed owner matrix for backward compatibility.
required_lanes_json_for_step() {
  local plan_dir=$1
  local step_id=$2
  local profile owner
  owner=$(step_owner_from_plan "$plan_dir" "$step_id")
  [[ -n "$owner" ]] || die "unknown step id in plan.json: $step_id"
  if [[ "$owner" == "manual" ]]; then
    printf '%s\n' '[]'
    return 0
  fi
  profile=$(routing_profile_from_plan "$plan_dir")
  case "$profile" in
    codex-primary)
      printf '%s\n' '["codex","grok"]'
      ;;
    fable-primary)
      printf '%s\n' '["codex","grok","claude"]'
      ;;
    "")
      required_lanes_json_for_owner "$owner"
      ;;
    *)
      die "invalid routingProfile '$profile'"
      ;;
  esac
}

# Owner from plan.json for a step id. Empty string if missing.
step_owner_from_plan() {
  local plan_dir=$1
  local step_id=$2
  local plan_file="$plan_dir/plan.json"
  [[ -f "$plan_file" ]] || die "missing plan.json in $plan_dir"
  jq -r --arg id "$step_id" '
    (.steps // [])
    | map(select(.id == $id))
    | if length == 0 then empty else .[0].owner // empty end
  ' "$plan_file"
}

# True when lane is the authoritative verifier for owner (mirrors to top-level verdict).
lane_is_authoritative() {
  local owner=$1
  local lane=$2
  case "$owner" in
    codex-impl)
      [[ "$lane" == "grok" ]]
      ;;
    claude-impl | grok-impl)
      [[ "$lane" == "codex" ]]
      ;;
    *)
      return 1
      ;;
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
  [[ $# -eq 5 ]] || die "start-step requires <plan-dir> <step-id> <executor> <model> <effort>"

  local plan_dir step_id executor model effort now
  plan_dir=$(abs_dir "$1")
  step_id=$2
  executor=$3
  model=$4
  effort=$5
  valid_executor "$executor" || die "invalid executor: $executor"
  [[ -n "$model" ]] || die "model must not be empty"
  [[ -n "$effort" ]] || die "effort must not be empty"
  require_file_json "$plan_dir/progress.json"
  jq -e --arg id "$step_id" '.steps[$id] != null' "$plan_dir/progress.json" >/dev/null ||
    die "unknown step id: $step_id"

  now=$(utc_now)
  # The single-quoted argument is jq code; its $variables must reach jq literally.
  # shellcheck disable=SC2016
  atomic_update_progress "$plan_dir" '
    .lastUpdatedAt = $now
    | .steps[$id].status = "in_progress"
    | .steps[$id].startedAt = (.steps[$id].startedAt // $now)
    | .steps[$id].dispatch = {
        executor: $executor,
        model: $model,
        effort: $effort,
        startedAt: $now
      }
    | .steps[$id] |= del(
        .completedAt,
        .laneDispatches,
        .verdicts,
        .verdict,
        .result,
        .findings,
        .filesTouched
      )
  ' \
    --arg id "$step_id" \
    --arg executor "$executor" \
    --arg model "$model" \
    --arg effort "$effort" \
    --arg now "$now"
}

cmd_record_lane_dispatch() {
  [[ $# -eq 6 ]] ||
    die "record-lane-dispatch requires <plan-dir> <step-id> <lane> <executor> <model> <effort>"

  local plan_dir step_id lane executor model effort owner now clear_mirror
  plan_dir=$(abs_dir "$1")
  step_id=$2
  lane=$3
  executor=$4
  model=$5
  effort=$6
  valid_lane "$lane" || die "invalid lane: $lane (expected claude, codex, or grok)"
  valid_executor "$executor" || die "invalid executor: $executor"
  [[ "$lane" == "$executor" ]] || die "lane '$lane' must use executor '$lane'"
  [[ -n "$model" ]] || die "model must not be empty"
  [[ -n "$effort" ]] || die "effort must not be empty"
  require_file_json "$plan_dir/progress.json"
  jq -e --arg id "$step_id" '.steps[$id] != null' "$plan_dir/progress.json" >/dev/null ||
    die "unknown step id: $step_id"
  owner=$(step_owner_from_plan "$plan_dir" "$step_id")
  [[ -n "$owner" ]] || die "unknown step id in plan.json: $step_id"
  if ! lane_is_required "$plan_dir" "$step_id" "$lane"; then
    die "lane '$lane' may not verify $owner step '$step_id'"
  fi
  clear_mirror=false
  if lane_is_authoritative "$owner" "$lane"; then
    clear_mirror=true
  fi

  now=$(utc_now)
  # The single-quoted argument is jq code; its $variables must reach jq literally.
  # shellcheck disable=SC2016
  atomic_update_progress "$plan_dir" '
    .lastUpdatedAt = $now
    | .steps[$id].status = "in_progress"
    | .steps[$id].startedAt = (.steps[$id].startedAt // $now)
    | .steps[$id].laneDispatches = ((.steps[$id].laneDispatches // {}) + {
        ($lane): {
          lane: $lane,
          executor: $executor,
          model: $model,
          effort: $effort,
          dispatchedAt: $now
        }
      })
    | del(.steps[$id].completedAt, .steps[$id].verdicts[$lane])
    | if $clear_mirror then
        del(
          .steps[$id].verdict,
          .steps[$id].result,
          .steps[$id].findings,
          .steps[$id].filesTouched
        )
      else
        .
      end
  ' \
    --arg id "$step_id" \
    --arg lane "$lane" \
    --arg executor "$executor" \
    --arg model "$model" \
    --arg effort "$effort" \
    --argjson clear_mirror "$clear_mirror" \
    --arg now "$now"
}

cmd_record_deviation() {
  [[ $# -eq 5 ]] ||
    die "record-deviation requires <plan-dir> <step-id> <type> <description> <files-json-array>"

  local plan_dir step_id deviation_type description files_json now
  plan_dir=$(abs_dir "$1")
  step_id=$2
  deviation_type=$3
  description=$4
  files_json=$5
  [[ -n "$deviation_type" ]] || die "deviation type must not be empty"
  [[ -n "$description" ]] || die "deviation description must not be empty"
  jq -e 'type == "array" and all(.[]; type == "string" and length > 0)' \
    <<<"$files_json" >/dev/null || die "deviation files must be a JSON array of nonempty strings"
  require_file_json "$plan_dir/progress.json"
  jq -e --arg id "$step_id" '.steps[$id] != null' "$plan_dir/progress.json" >/dev/null ||
    die "unknown step id: $step_id"

  now=$(utc_now)
  # The single-quoted argument is jq code; its $variables must reach jq literally.
  # shellcheck disable=SC2016
  atomic_update_progress "$plan_dir" '
    .lastUpdatedAt = $now
    | .steps[$id].status = "in_progress"
    | .steps[$id].startedAt = (.steps[$id].startedAt // $now)
    | .steps[$id].deviations = ((.steps[$id].deviations // []) + [{
        type: $type,
        description: $description,
        files: $files
      }])
    | del(.steps[$id].completedAt)
  ' \
    --arg id "$step_id" \
    --arg type "$deviation_type" \
    --arg description "$description" \
    --argjson files "$files_json" \
    --arg now "$now"
}

# Profile-or-owner verifier done gate. Reads progress.json + plan.json; does not write.
check_done_gate() {
  local plan_dir=$1
  local step_id=$2

  local owner progress_file
  progress_file="$plan_dir/progress.json"
  owner=$(step_owner_from_plan "$plan_dir" "$step_id")
  [[ -n "$owner" ]] || die "unknown step id in plan.json: $step_id"

  local required_json lane lane_verdict
  required_json=$(required_lanes_json_for_step "$plan_dir" "$step_id")
  while IFS= read -r lane; do
    [[ -n "$lane" ]] || continue
    lane_verdict=$(jq -r --arg id "$step_id" --arg lane "$lane" \
      '.steps[$id].verdicts[$lane].verdict // empty' "$progress_file")
    [[ "$lane_verdict" == "PASS" ]] ||
      die "cannot mark step '$step_id' done: $owner requires $lane-lane PASS; got '${lane_verdict:-none}'"
  done < <(jq -r '.[]' <<<"$required_json")
}

cmd_set_step_status() {
  local arg
  for arg in "$@"; do
    [[ "$arg" != "--degraded" ]] ||
      die "--degraded has been removed; required verifier lanes must all record PASS"
  done
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

  if [[ "$status" == "done" ]]; then
    check_done_gate "$plan_dir" "$step_id"
  fi

  # The single-quoted argument is jq code; its $variables must reach jq literally.
  # shellcheck disable=SC2016
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
  [[ $# -eq 6 || $# -eq 7 ]] ||
    die "record-verdict requires <plan-dir> <step-id> <verdict> <summary> <findings-json-array> <files-json-array> [lane]"

  local plan_dir step_id verdict summary findings_json files_json lane now owner
  plan_dir=$(abs_dir "$1")
  step_id=$2
  verdict=$3
  summary=$4
  findings_json=$5
  files_json=$6
  lane=""
  if [[ $# -eq 7 ]]; then
    lane=$7
    valid_lane "$lane" || die "invalid lane: $lane (expected claude, codex, or grok)"
  fi
  valid_verdict "$verdict" || die "invalid verdict: $verdict"
  require_file_json "$plan_dir/progress.json"
  jq -e 'type == "array"' <<<"$findings_json" >/dev/null || die "findings must be a JSON array"
  jq -e 'type == "array"' <<<"$files_json" >/dev/null || die "filesTouched must be a JSON array"
  jq -e --arg id "$step_id" '.steps[$id] != null' "$plan_dir/progress.json" >/dev/null ||
    die "unknown step id: $step_id"

  now=$(utc_now)

  if [[ -z "$lane" ]]; then
    # Legacy path: top-level fields only.
    # The single-quoted argument is jq code; its $variables must reach jq literally.
    # shellcheck disable=SC2016
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
    return 0
  fi

  owner=$(step_owner_from_plan "$plan_dir" "$step_id")
  [[ -n "$owner" ]] || die "unknown step id in plan.json: $step_id"
  if ! lane_is_required "$plan_dir" "$step_id" "$lane"; then
    die "lane '$lane' may not verify $owner step '$step_id'"
  fi

  local mirror=false invalidate=false required_json
  if lane_is_authoritative "$owner" "$lane"; then
    mirror=true
  fi
  required_json=$(required_lanes_json_for_step "$plan_dir" "$step_id")
  if [[ "$verdict" != "PASS" ]] && jq -e 'length > 0' <<<"$required_json" >/dev/null; then
    invalidate=true
  fi

  # The single-quoted argument is jq code; its $variables must reach jq literally.
  # shellcheck disable=SC2016
  atomic_update_progress "$plan_dir" '
    .lastUpdatedAt = $now
    | if $invalidate then
        .steps[$id] |= (
          .status = "in_progress"
          | .startedAt = (.startedAt // $now)
          | .laneDispatches = (
            (.laneDispatches // {})
            | with_entries(select(.key == $lane))
          )
          | if (.laneDispatches | length) == 0 then
              del(.laneDispatches)
            else
              .
            end
          | del(.completedAt, .verdicts, .verdict, .result, .findings, .filesTouched)
        )
      else
        .
      end
    | .steps[$id].verdicts = ((.steps[$id].verdicts // {}) + {
        ($lane): {
          verdict: $verdict,
          summary: $summary,
          findings: $findings,
          filesTouched: $files,
          timestamp: $now
        }
      })
    | if $mirror then
        .steps[$id].verdict = $verdict
        | .steps[$id].result = $summary
        | .steps[$id].findings = $findings
        | .steps[$id].filesTouched = $files
      else
        .
      end
  ' \
    --arg id "$step_id" \
    --arg lane "$lane" \
    --arg verdict "$verdict" \
    --arg summary "$summary" \
    --argjson findings "$findings_json" \
    --argjson files "$files_json" \
    --argjson mirror "$mirror" \
    --argjson invalidate "$invalidate" \
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
  # The single-quoted argument is jq code; its $variables must reach jq literally.
  # shellcheck disable=SC2016
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

# Parse ISO-8601 Z timestamps to epoch seconds (BSD date then GNU date).
iso_to_epoch() {
  local ts=$1
  local epoch
  if epoch=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null); then
    printf '%s\n' "$epoch"
    return 0
  fi
  if epoch=$(date -u -d "$ts" '+%s' 2>/dev/null); then
    printf '%s\n' "$epoch"
    return 0
  fi
  return 1
}

# True when lastUpdatedAt is older than 7 days.
is_stale_timestamp() {
  local ts=$1
  local epoch now age
  [[ -n "$ts" ]] || return 1
  epoch=$(iso_to_epoch "$ts") || return 1
  now=$(date -u '+%s')
  age=$((now - epoch))
  [[ "$age" -gt $((7 * 24 * 60 * 60)) ]]
}

cmd_archive_plan() {
  local force=false
  if [[ $# -gt 0 && "$1" == "--force" ]]; then
    force=true
    shift
  fi
  if [[ $# -gt 0 && "${!#}" == "--force" ]]; then
    force=true
    set -- "${@:1:$(($# - 1))}"
  fi
  [[ $# -eq 1 ]] || die "archive-plan requires [--force] <plan-dir>"

  local plan_dir plan_file progress_file name parent archive_root dest in_progress_count
  plan_dir=$(abs_dir "$1")
  plan_file="$plan_dir/plan.json"
  progress_file="$plan_dir/progress.json"
  [[ -f "$plan_file" ]] || die "missing plan.json in $plan_dir; refusing to archive debris"

  if [[ -f "$progress_file" ]]; then
    in_progress_count=$(jq -r '
      [(.steps // {}) | to_entries[] | select(.value.status == "in_progress")] | length
    ' "$progress_file" 2>/dev/null || printf '0')
    if [[ "$in_progress_count" -gt 0 && "$force" != true ]]; then
      die "refusing to archive: $in_progress_count step(s) in_progress (pass --force to override)"
    fi
  fi

  name=$(basename "$plan_dir")
  parent=$(dirname "$plan_dir")
  # Scope guard: only immediate children of .temp/plan-mode/active are
  # archivable — never an arbitrary directory that happens to contain a
  # plan.json.
  case "$parent" in
    */.temp/plan-mode/active) ;;
    *) die "refusing to archive: $plan_dir is not an immediate child of .temp/plan-mode/active" ;;
  esac
  archive_root="$(dirname "$parent")/archive"
  dest="$archive_root/$name"

  [[ ! -e "$dest" ]] || die "archive destination already exists: $dest"

  mkdir -p "$archive_root"
  mv "$plan_dir" "$dest"
  abs_dir "$dest"
}

cmd_list_plans() {
  [[ $# -eq 1 ]] || die "list-plans requires <project-root>"

  local project_root active_dir
  project_root=$(abs_dir "$1")
  active_dir="$project_root/.temp/plan-mode/active"
  [[ -d "$active_dir" ]] || return 0

  local plan_dir name kind last_updated counts stale_marker
  # Sort by basename for stable output.
  while IFS= read -r plan_dir; do
    [[ -n "$plan_dir" ]] || continue
    name=$(basename "$plan_dir")
    last_updated="-"
    counts="-"
    stale_marker=""
    if [[ -f "$plan_dir/plan.json" ]]; then
      kind="real"
      if [[ -f "$plan_dir/progress.json" ]]; then
        last_updated=$(jq -r '.lastUpdatedAt // "-"' "$plan_dir/progress.json" 2>/dev/null || printf '-')
        counts=$(jq -r '
          .steps // {}
          | {
              done: ([to_entries[] | select(.value.status == "done")] | length),
              in_progress: ([to_entries[] | select(.value.status == "in_progress")] | length),
              pending: ([to_entries[] | select(.value.status == "pending")] | length),
              blocked: ([to_entries[] | select(.value.status == "blocked")] | length),
              skipped: ([to_entries[] | select(.value.status == "skipped")] | length)
            }
          | "done=\(.done) in_progress=\(.in_progress) pending=\(.pending) blocked=\(.blocked) skipped=\(.skipped)"
        ' "$plan_dir/progress.json" 2>/dev/null || printf '-')
        if [[ "$last_updated" != "-" ]] && is_stale_timestamp "$last_updated"; then
          stale_marker="STALE"
        fi
      fi
    else
      kind="debris"
    fi

    if [[ -n "$stale_marker" ]]; then
      printf '%s  %s  lastUpdatedAt=%s  %s  %s\n' "$name" "$kind" "$last_updated" "$counts" "$stale_marker"
    else
      printf '%s  %s  lastUpdatedAt=%s  %s\n' "$name" "$kind" "$last_updated" "$counts"
    fi
  done < <(find "$active_dir" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort)
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
    record-lane-dispatch) cmd_record_lane_dispatch "$@" ;;
    record-deviation) cmd_record_deviation "$@" ;;
    set-step-status) cmd_set_step_status "$@" ;;
    record-verdict) cmd_record_verdict "$@" ;;
    set-frontier) cmd_set_frontier "$@" ;;
    compute-frontier) cmd_compute_frontier "$@" ;;
    archive-plan) cmd_archive_plan "$@" ;;
    list-plans) cmd_list_plans "$@" ;;
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
