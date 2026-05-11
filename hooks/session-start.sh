#!/usr/bin/env bash
set +e

emit_no_plan() {
  cat <<'EOF'
## Orchestration

No active plan in `.temp/plan-mode/active/`. The `conductor` skill
will create one when you start a non-trivial task.
EOF
}

resolve_project_root() {
  local payload cwd_from_stdin
  payload=""
  cwd_from_stdin=""

  if [[ ! -t 0 ]]; then
    payload=$(cat 2>/dev/null)
  fi

  if [[ -n "$payload" ]] && command -v jq >/dev/null 2>&1; then
    cwd_from_stdin=$(printf '%s' "$payload" | jq -er '.cwd // empty' 2>/dev/null)
    if [[ $? -eq 0 && -n "$cwd_from_stdin" ]]; then
      printf '%s\n' "$cwd_from_stdin"
      return 0
    fi
  fi

  if [[ -n "$CLAUDE_PROJECT_DIR" ]]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return 0
  fi

  printf '%s\n' "$PWD"
}

fallback_and_exit() {
  emit_no_plan
  exit 0
}

project_root=$(resolve_project_root)
if [[ -z "$project_root" ]]; then
  fallback_and_exit
fi

if ! command -v jq >/dev/null 2>&1; then
  fallback_and_exit
fi

active_dir="$project_root/.temp/plan-mode/active"
if [[ ! -d "$active_dir" ]]; then
  fallback_and_exit
fi

plan_dirs=()
while IFS= read -r plan_dir; do
  plan_dirs+=("$plan_dir")
done < <(find "$active_dir" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null)

if [[ ${#plan_dirs[@]} -eq 0 ]]; then
  fallback_and_exit
fi

tab=$(printf '\t')
records=""
for plan_dir in "${plan_dirs[@]}"; do
  progress_file="$plan_dir/progress.json"
  if [[ ! -f "$progress_file" ]]; then
    fallback_and_exit
  fi

  updated=$(jq -er '.lastUpdatedAt // ""' "$progress_file" 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    fallback_and_exit
  fi

  name=$(basename "$plan_dir")
  records="${records}${updated}${tab}${name}${tab}${plan_dir}"$'\n'
done

selected_dir=$(printf '%s' "$records" | sort -t "$tab" -k1,1r -k2,2 | awk -F "$tab" 'NR == 1 { print $3 }')
if [[ -z "$selected_dir" ]]; then
  fallback_and_exit
fi

selected_name=$(basename "$selected_dir")
selected_plan="$selected_dir/plan.json"
selected_progress="$selected_dir/progress.json"
if [[ ! -f "$selected_plan" || ! -f "$selected_progress" ]]; then
  fallback_and_exit
fi

jq -e . "$selected_plan" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  fallback_and_exit
fi

jq -e . "$selected_progress" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  fallback_and_exit
fi

rel_path=".temp/plan-mode/active/${selected_name}/"
notice=$(
  jq -r -n \
    --arg path "$rel_path" \
    --slurpfile plan "$selected_plan" \
    --slurpfile progress "$selected_progress" \
    '
      def truncate_title:
        if length > 50 then .[0:47] + "..." else . end;
      def step_status($p; $id):
        $p.steps[$id].status // "pending";
      def frontier_ids($plan; $progress):
        if (($progress.currentFrontier // []) | length) > 0 then
          $progress.currentFrontier[]
        else
          $plan.steps[]
          | select((step_status($progress; .id) == "pending")
              and all((.dependsOn // [])[]; step_status($progress; .) == "done"))
          | .id
        end;

      $plan[0] as $pl
      | $progress[0] as $pr
      | ($pl.planId // "unknown-plan") as $planId
      | ($pl.title // "Untitled plan") as $title
      | (["done", "in_progress", "pending", "blocked", "skipped"]
          | map(. as $status
              | ([($pr.steps // {}) | to_entries[] | select(.value.status == $status)] | length) as $count
              | select($count > 0)
              | "\($count) \($status)")
          | if length == 0 then "0 steps" else join(" · ") end) as $statusLine
      | ([frontier_ids($pl; $pr) as $id
          | ($pl.steps[] | select(.id == $id)) as $step
          | "\($id) (\($step.title | truncate_title))"]
          | if length == 0 then "none" else join(", ") end) as $frontierLine
      | "## Orchestration: active plan\n\n"
        + "- **Plan**: `\($planId)` — \($title)\n"
        + "- **Status**: \($statusLine)\n"
        + "- **Frontier**: \($frontierLine)\n"
        + "- **Path**: `\($path)`\n\n"
        + "The `conductor` skill will pick this up. Read `plan.json` and\n"
        + "`progress.json` before dispatching the frontier."
    ' 2>/dev/null
)

if [[ $? -ne 0 || -z "$notice" ]]; then
  fallback_and_exit
fi

printf '%s\n' "$notice"

if [[ ${#plan_dirs[@]} -gt 1 ]]; then
  other_ids=""
  for plan_dir in "${plan_dirs[@]}"; do
    if [[ "$plan_dir" == "$selected_dir" ]]; then
      continue
    fi

    other_id=$(jq -er '.planId // empty' "$plan_dir/plan.json" 2>/dev/null)
    if [[ $? -ne 0 || -z "$other_id" ]]; then
      continue
    fi

    if [[ -n "$other_ids" ]]; then
      other_ids="${other_ids}, "
    fi
    other_ids="${other_ids}\`${other_id}\`"
  done

  if [[ -n "$other_ids" ]]; then
    printf 'Warning: other active plans exist and were not selected: %s.\n' "$other_ids"
  fi
fi

exit 0
