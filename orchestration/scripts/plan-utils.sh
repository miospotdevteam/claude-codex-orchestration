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
  set-step-status <plan-dir> <step-id> <status> [--degraded <reason>]
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
    codex | grok) return 0 ;;
    *) return 1 ;;
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
  # The single-quoted argument is jq code; its $variables must reach jq literally.
  # shellcheck disable=SC2016
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

# Parse optional --degraded <reason> from argv; remaining positionals go to stdout
# as lines (bash 3.2 safe — no nameref).
parse_degraded_flag() {
  degraded_reason=""
  _parse_pos=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --degraded)
        [[ $# -ge 2 ]] || die "--degraded requires a reason"
        [[ -n "$2" ]] || die "--degraded reason must not be empty"
        degraded_reason=$2
        shift 2
        ;;
      *)
        _parse_pos+=("$1")
        shift
        ;;
    esac
  done
}

# Dual-verifier done gate. Sets gate_use_degraded=true/false or exits on refusal.
# Reads progress.json + plan.json; does not write.
check_done_gate() {
  local plan_dir=$1
  local step_id=$2
  local degraded=$3

  local owner progress_file
  progress_file="$plan_dir/progress.json"
  owner=$(step_owner_from_plan "$plan_dir" "$step_id")
  [[ -n "$owner" ]] || die "unknown step id in plan.json: $step_id"

  local codex_v grok_v top_v has_lane
  codex_v=$(jq -r --arg id "$step_id" '.steps[$id].verdicts.codex.verdict // empty' "$progress_file")
  grok_v=$(jq -r --arg id "$step_id" '.steps[$id].verdicts.grok.verdict // empty' "$progress_file")
  top_v=$(jq -r --arg id "$step_id" '.steps[$id].verdict // empty' "$progress_file")
  has_lane=false
  if [[ -n "$codex_v" || -n "$grok_v" ]]; then
    has_lane=true
  fi

  local codex_pass=false grok_pass=false top_pass=false any_pass=false
  [[ "$codex_v" == "PASS" ]] && codex_pass=true
  [[ "$grok_v" == "PASS" ]] && grok_pass=true
  [[ "$top_v" == "PASS" ]] && top_pass=true
  # any_pass gates --degraded: it requires a real per-lane PASS. The
  # legacy top-level verdict never satisfies a degraded completion —
  # degraded means "one of the two required lanes is down", not "no
  # lane ever ran".
  if [[ "$codex_pass" == true || "$grok_pass" == true ]]; then
    any_pass=true
  fi

  gate_use_degraded=false

  case "$owner" in
    codex-impl)
      if [[ "$grok_pass" == true ]]; then
        :
      elif [[ "$has_lane" == false && "$top_pass" == true ]]; then
        # Legacy path: no per-lane data, top-level PASS is enough.
        :
      elif [[ -n "$degraded" && "$any_pass" == true ]]; then
        gate_use_degraded=true
      else
        die "cannot mark step '$step_id' done: codex-impl requires grok-lane PASS (or legacy top-level PASS when no lane data); got grok='${grok_v:-none}' top='${top_v:-none}'"
      fi
      ;;
    claude-impl | grok-impl)
      if [[ "$codex_pass" == true && "$grok_pass" == true ]]; then
        :
      elif [[ -n "$degraded" && "$any_pass" == true ]]; then
        gate_use_degraded=true
      else
        die "cannot mark step '$step_id' done: $owner requires PASS in both verdicts.codex and verdicts.grok (or --degraded <reason> with a single-lane PASS); got codex='${codex_v:-none}' grok='${grok_v:-none}'"
      fi
      ;;
    *)
      # manual / unknown: no dual mandate
      :
      ;;
  esac
}

cmd_set_step_status() {
  parse_degraded_flag "$@"
  set -- "${_parse_pos[@]}"
  [[ $# -eq 3 ]] || die "set-step-status requires <plan-dir> <step-id> <status> [--degraded <reason>]"

  local plan_dir step_id status now
  plan_dir=$(abs_dir "$1")
  step_id=$2
  status=$3
  valid_status "$status" || die "invalid status: $status"
  if [[ -n "$degraded_reason" && "$status" != "done" ]]; then
    die "--degraded is only valid when setting status to done"
  fi
  require_file_json "$plan_dir/progress.json"
  jq -e --arg id "$step_id" '.steps[$id] != null' "$plan_dir/progress.json" >/dev/null ||
    die "unknown step id: $step_id"

  now=$(utc_now)

  if [[ "$status" == "done" ]]; then
    check_done_gate "$plan_dir" "$step_id" "$degraded_reason"
    if [[ "$gate_use_degraded" == true ]]; then
      # The single-quoted argument is jq code; its $variables must reach jq literally.
      # shellcheck disable=SC2016
      atomic_update_progress "$plan_dir" '
        .lastUpdatedAt = $now
        | .steps[$id].status = "done"
        | .steps[$id].completedAt = $now
        | .deviations = ((.deviations // []) + [{at: $now, note: $note}])
      ' --arg id "$step_id" --arg now "$now" --arg note "$degraded_reason"
      return 0
    fi
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
    valid_lane "$lane" || die "invalid lane: $lane (expected codex or grok)"
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

  local mirror=false
  if lane_is_authoritative "$owner" "$lane"; then
    mirror=true
  fi

  if [[ "$mirror" == true ]]; then
    # The single-quoted argument is jq code; its $variables must reach jq literally.
    # shellcheck disable=SC2016
    atomic_update_progress "$plan_dir" '
      .lastUpdatedAt = $now
      | .steps[$id].verdicts = ((.steps[$id].verdicts // {}) + {
          ($lane): {
            verdict: $verdict,
            summary: $summary,
            findings: $findings,
            filesTouched: $files,
            timestamp: $now
          }
        })
      | .steps[$id].verdict = $verdict
      | .steps[$id].result = $summary
      | .steps[$id].findings = $findings
      | .steps[$id].filesTouched = $files
    ' \
      --arg id "$step_id" \
      --arg lane "$lane" \
      --arg verdict "$verdict" \
      --arg summary "$summary" \
      --argjson findings "$findings_json" \
      --argjson files "$files_json" \
      --arg now "$now"
  else
    # The single-quoted argument is jq code; its $variables must reach jq literally.
    # shellcheck disable=SC2016
    atomic_update_progress "$plan_dir" '
      .lastUpdatedAt = $now
      | .steps[$id].verdicts = ((.steps[$id].verdicts // {}) + {
          ($lane): {
            verdict: $verdict,
            summary: $summary,
            findings: $findings,
            filesTouched: $files,
            timestamp: $now
          }
        })
    ' \
      --arg id "$step_id" \
      --arg lane "$lane" \
      --arg verdict "$verdict" \
      --arg summary "$summary" \
      --argjson findings "$findings_json" \
      --argjson files "$files_json" \
      --arg now "$now"
  fi
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
