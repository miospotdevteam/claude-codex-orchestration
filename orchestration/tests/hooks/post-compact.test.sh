#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
HOOK="$SCRIPT_DIR/../../hooks/post-compact.sh"

PASS_COUNT=0
FAIL_COUNT=0
HOOK_OUTPUT=""
HOOK_STATUS=0
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

pass() {
  printf 'PASS %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

run_test() {
  local name=$1
  shift
  if "$@"; then
    pass "$name"
  else
    fail "$name" "assertion failed"
  fi
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "$haystack" == *"$needle"* ]]
}

assert_exit_zero() {
  local status=$1
  [[ "$status" -eq 0 ]]
}

write_plan() {
  local dir=$1
  local plan_id=$2
  mkdir -p "$dir"
  cat >"$dir/plan.json" <<JSON
{
  "planId": "$plan_id",
  "title": "Post compact test plan",
  "createdAt": "2026-05-11T00:00:00Z",
  "createdBy": "test",
  "frozen": true,
  "context": {
    "rootDir": "$SANDBOX",
    "branch": "test"
  },
  "steps": [
    {
      "id": "step-1",
      "title": "Step 1",
      "description": "Completed dependency.",
      "acceptanceCriteria": ["done"],
      "files": ["one.txt"],
      "dependsOn": [],
      "owner": "codex-impl"
    },
    {
      "id": "step-2",
      "title": "Step 2",
      "description": "Runnable dependent step.",
      "acceptanceCriteria": ["done"],
      "files": ["two.txt"],
      "dependsOn": ["step-1"],
      "owner": "codex-impl"
    },
    {
      "id": "step-3",
      "title": "Step 3",
      "description": "Runnable root step.",
      "acceptanceCriteria": ["done"],
      "files": ["three.txt"],
      "dependsOn": [],
      "owner": "codex-impl"
    }
  ]
}
JSON
}

write_progress() {
  local dir=$1
  local step_1_status=$2
  local step_2_status=$3
  local step_3_status=$4
  cat >"$dir/progress.json" <<JSON
{
  "planId": "post-compact-test",
  "startedAt": "2026-05-11T00:00:00Z",
  "lastUpdatedAt": "2026-05-11T00:01:00Z",
  "currentFrontier": [],
  "steps": {
    "step-1": { "status": "$step_1_status" },
    "step-2": { "status": "$step_2_status" },
    "step-3": { "status": "$step_3_status" }
  }
}
JSON
}

invoke_hook() {
  local project_root=$1
  local output status

  set +e
  output=$(CLAUDE_PROJECT_DIR="$project_root" "$HOOK")
  status=$?
  set -e

  HOOK_OUTPUT=$output
  HOOK_STATUS=$status
}

test_no_plan_dir() {
  local root="$SANDBOX/no-plan"
  mkdir -p "$root"

  invoke_hook "$root"
  assert_exit_zero "$HOOK_STATUS" || return 1
  assert_contains "$HOOK_OUTPUT" 'no active plan to resume'
}

test_non_empty_frontier_notice() {
  local root="$SANDBOX/non-empty-frontier"
  local plan_dir="$root/.temp/plan-mode/active/post-compact-test-plan"

  write_plan "$plan_dir" "post-compact-test"
  write_progress "$plan_dir" done pending pending

  invoke_hook "$root"
  assert_exit_zero "$HOOK_STATUS" || return 1
  assert_contains "$HOOK_OUTPUT" '## Orchestration: resuming after compaction' || return 1
  assert_contains "$HOOK_OUTPUT" '- **Plan**: `post-compact-test` — Post compact test plan' || return 1
  assert_contains "$HOOK_OUTPUT" '- **Runnable frontier**: step-2, step-3' || return 1
  assert_contains "$HOOK_OUTPUT" '1. Read `plan.json` (immutable) and `progress.json` (mutable).' || return 1
  assert_contains "$HOOK_OUTPUT" '2. Recreate the TaskList from `progress.json`.' || return 1
  assert_contains "$HOOK_OUTPUT" '3. Compute the frontier — already shown above.' || return 1
  assert_contains "$HOOK_OUTPUT" '4. Dispatch the frontier in parallel via `codex-dispatch`.' || return 1
  assert_contains "$HOOK_OUTPUT" 'Do not re-read source files or re-run discovery; the plan is your' || return 1
  assert_contains "$HOOK_OUTPUT" 'source of truth.'
}

test_empty_frontier_notice() {
  local root="$SANDBOX/empty-frontier"
  local plan_dir="$root/.temp/plan-mode/active/post-compact-test-plan"

  write_plan "$plan_dir" "post-compact-test"
  write_progress "$plan_dir" done done done

  invoke_hook "$root"
  assert_exit_zero "$HOOK_STATUS" || return 1
  assert_contains "$HOOK_OUTPUT" '## Orchestration: resuming after compaction' || return 1
  assert_contains "$HOOK_OUTPUT" '- **Runnable frontier**: none'
}

test_corrupt_progress_fallback() {
  local root="$SANDBOX/corrupt-progress"
  local plan_dir="$root/.temp/plan-mode/active/post-compact-test-plan"

  write_plan "$plan_dir" "post-compact-test"
  printf '{ not json\n' >"$plan_dir/progress.json"

  invoke_hook "$root"
  assert_exit_zero "$HOOK_STATUS" || return 1
  [[ "$HOOK_OUTPUT" == '## Orchestration: post-compact hook failed; check .temp/plan-mode/active/ manually' ]]
}

run_test "no plan dir emits no active notice and exits zero" test_no_plan_dir
run_test "non-empty frontier notice includes plan frontier and protocol" test_non_empty_frontier_notice
run_test "empty frontier notice emits none and exits zero" test_empty_frontier_notice
run_test "corrupt progress emits fallback and exits zero" test_corrupt_progress_fallback

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
