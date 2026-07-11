#!/usr/bin/env bash

failure_notice() {
  printf '## Orchestration: post-compact hook failed; check .temp/plan-mode/active/ manually\n'
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)
PLAN_UTILS="$SCRIPT_DIR/../scripts/plan-utils.sh"

no_active_notice() {
  printf '## Orchestration\n\n'
  # Backticks are Markdown, so this string must remain single-quoted.
  # shellcheck disable=SC2016
  printf 'No active plan in `.temp/plan-mode/active/`; no active plan to resume.\n'
}

resolve_project_root() {
  local payload cwd
  payload=$(cat 2>/dev/null)
  cwd=""

  if [[ -n "$payload" ]] && command -v jq >/dev/null 2>&1; then
    cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
  fi

  if [[ -z "$cwd" ]]; then
    cwd="${CLAUDE_PROJECT_DIR:-}"
  fi

  if [[ -z "$cwd" ]]; then
    cwd="$PWD"
  fi

  (cd "$cwd" 2>/dev/null && pwd -P) || return 1
}

find_active_plan_dir() {
  local project_root active_dir selected
  project_root=$1
  active_dir="$project_root/.temp/plan-mode/active"

  [[ -d "$active_dir" ]] || return 1

  selected=$(
    find "$active_dir" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
      while IFS= read -r dir; do
        local updated name
        updated=""
        if [[ -f "$dir/progress.json" ]] && command -v jq >/dev/null 2>&1; then
          updated=$(jq -r '.lastUpdatedAt // ""' "$dir/progress.json" 2>/dev/null || printf '')
        fi
        name=$(basename "$dir")
        printf '%s\t%s\t%s\n' "$updated" "$name" "$dir"
      done |
      sort -t "$(printf '\t')" -k1,1r -k2,2 |
      awk -F '\t' 'NR == 1 { print $3 }'
  )

  [[ -n "$selected" ]] || return 1
  (cd "$selected" 2>/dev/null && pwd -P) || return 1
}

status_counts() {
  local progress_file
  progress_file=$1

  jq -r '
    .steps as $steps
    | [
        ["done", ($steps | to_entries | map(select(.value.status == "done")) | length)],
        ["in_progress", ($steps | to_entries | map(select(.value.status == "in_progress")) | length)],
        ["pending", ($steps | to_entries | map(select(.value.status == "pending")) | length)],
        ["blocked", ($steps | to_entries | map(select(.value.status == "blocked")) | length)],
        ["skipped", ($steps | to_entries | map(select(.value.status == "skipped")) | length)]
      ]
    | map(select(.[1] > 0) | "\(.[1]) \(.[0])")
    | if length == 0 then "none" else join(" · ") end
  ' "$progress_file"
}

emit_notice() {
  local project_root plan_dir plan_file progress_file plan_id title status frontier path
  project_root=$1
  plan_dir=$2
  plan_file="$plan_dir/plan.json"
  progress_file="$plan_dir/progress.json"

  [[ -f "$plan_file" && -f "$progress_file" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  jq -e . "$plan_file" >/dev/null 2>&1 || return 1
  jq -e . "$progress_file" >/dev/null 2>&1 || return 1

  plan_id=$(jq -r '.planId // empty' "$plan_file") || return 1
  title=$(jq -r '.title // empty' "$plan_file") || return 1
  status=$(status_counts "$progress_file") || return 1
  [[ -x "$PLAN_UTILS" ]] || return 1
  frontier=$("$PLAN_UTILS" compute-frontier "$plan_dir" 2>/dev/null) || return 1
  frontier=$(printf '%s\n' "$frontier" | awk 'NF { out = out ? out ", " $0 : $0 } END { print out }')
  if [[ -z "$frontier" ]]; then
    frontier="none"
  fi
  path=".temp/plan-mode/active/$(basename "$plan_dir")/"

  printf '## Orchestration: resuming after compaction\n\n'
  # Backticks are Markdown, so these format strings must remain single-quoted.
  # shellcheck disable=SC2016
  printf -- '- **Plan**: `%s` — %s\n' "$plan_id" "$title"
  # shellcheck disable=SC2016
  printf -- '- **Path**: `%s`\n' "$path"
  printf -- '- **Status**: %s\n' "$status"
  printf -- '- **Runnable frontier**: %s\n\n' "$frontier"
  # Backticks are Markdown, so these strings must remain single-quoted.
  # shellcheck disable=SC2016
  printf 'Resumption protocol (from `docs/04-execution-loop.md`):\n\n'
  # shellcheck disable=SC2016
  printf '1. Read `plan.json` (immutable) and `progress.json` (mutable).\n'
  # shellcheck disable=SC2016
  printf '2. Recreate the TaskList from `progress.json`.\n'
  printf '3. Compute the frontier — already shown above.\n'
  # shellcheck disable=SC2016
  printf '4. Dispatch the frontier in parallel via `codex-dispatch`.\n\n'
  printf 'Do not re-read source files or re-run discovery; the plan is your\n'
  printf 'source of truth.\n'
}

main() {
  local project_root plan_dir

  project_root=$(resolve_project_root) || {
    failure_notice
    exit 0
  }

  plan_dir=$(find_active_plan_dir "$project_root") || {
    no_active_notice
    exit 0
  }

  emit_notice "$project_root" "$plan_dir" || failure_notice
  exit 0
}

main "$@"
