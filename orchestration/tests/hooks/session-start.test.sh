#!/usr/bin/env bash
# Fixtures intentionally use the literal plan status `done` and Markdown
# backticks in single-quoted expected output.
# shellcheck disable=SC1010,SC2016
set -euo pipefail

# Fresh timestamp for "recent" fixtures — hardcoded dates rot past the
# 7-day staleness window and would flip these tests.
NOW_TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
HOOK="$SCRIPT_DIR/../../hooks/session-start.sh"

PASS_COUNT=0
FAIL_COUNT=0
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

RUN_OUTPUT=""
RUN_STATUS=0

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

run_hook() {
  local root=$1
  local payload=${2-}
  set +e
  if [[ $# -ge 2 ]]; then
    RUN_OUTPUT=$(CLAUDE_PROJECT_DIR="$root" "$HOOK" <<<"$payload")
  else
    RUN_OUTPUT=$(CLAUDE_PROJECT_DIR="$root" "$HOOK")
  fi
  RUN_STATUS=$?
  set -e
}

create_plan() {
  local root=$1
  local dir_name=$2
  local plan_id=$3
  local title=$4
  local last_updated=$5
  local frontier_json=$6
  local step1_status=$7
  local step2_status=$8
  local step3_status=$9

  local plan_dir="$root/.temp/plan-mode/active/$dir_name"
  mkdir -p "$plan_dir"

  cat >"$plan_dir/plan.json" <<JSON
{
  "planId": "$plan_id",
  "title": "$title",
  "createdAt": "2026-05-11T00:00:00Z",
  "createdBy": "test",
  "frozen": true,
  "steps": [
    {
      "id": "step-1",
      "title": "Prepare first fixture step",
      "description": "Fixture.",
      "acceptanceCriteria": ["done"],
      "files": ["one.txt"],
      "dependsOn": [],
      "owner": "codex-impl"
    },
    {
      "id": "step-2",
      "title": "Run second fixture step",
      "description": "Fixture.",
      "acceptanceCriteria": ["done"],
      "files": ["two.txt"],
      "dependsOn": [],
      "owner": "codex-impl"
    },
    {
      "id": "step-3",
      "title": "Complete third fixture step with a title",
      "description": "Fixture.",
      "acceptanceCriteria": ["done"],
      "files": ["three.txt"],
      "dependsOn": ["step-1"],
      "owner": "codex-impl"
    }
  ]
}
JSON

  cat >"$plan_dir/progress.json" <<JSON
{
  "planId": "$plan_id",
  "startedAt": "2026-05-11T00:00:00Z",
  "lastUpdatedAt": "$last_updated",
  "currentFrontier": $frontier_json,
  "steps": {
    "step-1": {"status": "$step1_status"},
    "step-2": {"status": "$step2_status"},
    "step-3": {"status": "$step3_status"}
  }
}
JSON
}

test_no_active_dir() {
  local root="$SANDBOX/no-active-dir"
  mkdir -p "$root"
  run_hook "$root"
  [[ "$RUN_STATUS" -eq 0 ]] || return 1
  assert_contains "$RUN_OUTPUT" "## Orchestration" || return 1
  assert_contains "$RUN_OUTPUT" "No active plan in \`.temp/plan-mode/active/\`"
}

test_one_plan_mixed_status() {
  local root="$SANDBOX/one-plan"
  mkdir -p "$root"
  # lastUpdatedAt is recent so hygiene does not inject a stale flag (notice unchanged).
  create_plan "$root" "session-hook-test" "session-hook-plan" "Session hook plan title" \
    "$NOW_TS" '["step-3"]' done in_progress pending

  run_hook "$root"
  [[ "$RUN_STATUS" -eq 0 ]] || return 1
  assert_contains "$RUN_OUTPUT" "## Orchestration: active plan" || return 1
  assert_contains "$RUN_OUTPUT" '**Plan**: `session-hook-plan` — Session hook plan title' || return 1
  assert_contains "$RUN_OUTPUT" "**Status**: 1 done · 1 in_progress · 1 pending" || return 1
  assert_contains "$RUN_OUTPUT" "**Frontier**: step-3 (Complete third fixture step with a title)"
}

test_multiple_plans_newest_wins() {
  local root="$SANDBOX/two-plans"
  mkdir -p "$root"
  create_plan "$root" "older-dir" "older-plan" "Older plan title" \
    "2026-05-11T09:00:00Z" '["step-1"]' pending pending pending
  create_plan "$root" "newer-dir" "newer-plan" "Newer plan title" \
    "2026-05-11T11:00:00Z" '["step-2"]' done pending pending

  run_hook "$root"
  [[ "$RUN_STATUS" -eq 0 ]] || return 1
  assert_contains "$RUN_OUTPUT" '**Plan**: `newer-plan` — Newer plan title' || return 1
  assert_contains "$RUN_OUTPUT" "Warning: other active plans exist" || return 1
  assert_contains "$RUN_OUTPUT" '`older-plan`'
}

test_corrupt_progress_exits_zero() {
  local root="$SANDBOX/corrupt-progress"
  local plan_dir="$root/.temp/plan-mode/active/bad-progress"
  mkdir -p "$plan_dir"
  cat >"$plan_dir/plan.json" <<'JSON'
{
  "planId": "bad-progress",
  "title": "Bad progress",
  "steps": []
}
JSON
  printf '{not-json\n' >"$plan_dir/progress.json"

  run_hook "$root"
  [[ "$RUN_STATUS" -eq 0 ]]
}

test_missing_plan_exits_zero() {
  local root="$SANDBOX/missing-plan"
  local plan_dir="$root/.temp/plan-mode/active/missing-plan-json"
  mkdir -p "$plan_dir"
  cat >"$plan_dir/progress.json" <<'JSON'
{
  "planId": "missing-plan-json",
  "lastUpdatedAt": "2026-05-11T12:00:00Z",
  "currentFrontier": [],
  "steps": {}
}
JSON

  run_hook "$root"
  [[ "$RUN_STATUS" -eq 0 ]]
}

test_hygiene_debris_notice() {
  local root="$SANDBOX/hygiene-debris"
  mkdir -p "$root"
  create_plan "$root" "good-plan" "good-plan" "Good plan" \
    "$NOW_TS" '["step-1"]' pending pending pending
  mkdir -p "$root/.temp/plan-mode/active/log-debris/logs"
  printf 'noise\n' >"$root/.temp/plan-mode/active/log-debris/logs/x.log"

  run_hook "$root"
  [[ "$RUN_STATUS" -eq 0 ]] || return 1
  assert_contains "$RUN_OUTPUT" '**Plan**: `good-plan`' || return 1
  assert_contains "$RUN_OUTPUT" "debris" || return 1
  assert_contains "$RUN_OUTPUT" "log-debris"
}

test_hygiene_done_plan_suggests_archive() {
  local root="$SANDBOX/hygiene-done"
  mkdir -p "$root"
  create_plan "$root" "finished-plan" "finished-plan" "Finished plan" \
    "$NOW_TS" '[]' done done done

  run_hook "$root"
  [[ "$RUN_STATUS" -eq 0 ]] || return 1
  assert_contains "$RUN_OUTPUT" '**Plan**: `finished-plan`' || return 1
  assert_contains "$RUN_OUTPUT" "archive-plan" || return 1
  assert_contains "$RUN_OUTPUT" "finished-plan"
}

test_hygiene_stale_in_progress() {
  local root="$SANDBOX/hygiene-stale"
  mkdir -p "$root"
  create_plan "$root" "old-active" "old-active" "Old active plan" \
    "2026-01-01T00:00:00Z" '["step-2"]' done in_progress pending

  run_hook "$root"
  [[ "$RUN_STATUS" -eq 0 ]] || return 1
  assert_contains "$RUN_OUTPUT" '**Plan**: `old-active`' || return 1
  # Must be the hygiene flag, not a coincidental plan name substring.
  assert_contains "$RUN_OUTPUT" "stale in_progress" || return 1
  assert_contains "$RUN_OUTPUT" "old-active"
}
test_hygiene_quiet_when_clean() {
  local root="$SANDBOX/hygiene-quiet"
  mkdir -p "$root"
  create_plan "$root" "clean-plan" "clean-plan" "Clean plan" \
    "$NOW_TS" '["step-3"]' done in_progress pending

  run_hook "$root"
  [[ "$RUN_STATUS" -eq 0 ]] || return 1
  assert_contains "$RUN_OUTPUT" '**Plan**: `clean-plan`' || return 1
  # Quiet path: no hygiene flags when none of the three conditions apply.
  ! assert_contains "$RUN_OUTPUT" "debris" || return 1
  ! assert_contains "$RUN_OUTPUT" "archive-plan" || return 1
  ! assert_contains "$RUN_OUTPUT" "stale" || return 1
  assert_contains "$RUN_OUTPUT" "**Status**: 1 done · 1 in_progress · 1 pending"
}

run_test "no active plan directory emits no-plan notice" test_no_active_dir
run_test "one plan emits active notice with counts and frontier" test_one_plan_mixed_status
run_test "multiple plans select newest and warn about others" test_multiple_plans_newest_wins
run_test "corrupt progress exits zero" test_corrupt_progress_exits_zero
run_test "missing plan exits zero" test_missing_plan_exits_zero
run_test "hygiene flags debris dirs without plan.json" test_hygiene_debris_notice
run_test "hygiene suggests archive-plan for fully-done active plans" test_hygiene_done_plan_suggests_archive
run_test "hygiene flags stale in_progress plans older than 7 days" test_hygiene_stale_in_progress
run_test "hygiene quiet when none of the three conditions apply" test_hygiene_quiet_when_clean

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
