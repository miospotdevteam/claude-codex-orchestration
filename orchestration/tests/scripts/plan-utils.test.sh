#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PLAN_UTILS="$SCRIPT_DIR/../../scripts/plan-utils.sh"

PASS_COUNT=0
FAIL_COUNT=0
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

assert_jq() {
  local file=$1
  local filter=$2
  jq -e "$filter" "$file" >/dev/null
}

create_plan_dir() {
  local dir=$1
  mkdir -p "$dir"
  cat >"$dir/plan.json" <<JSON
{
  "planId": "plan-utils-test",
  "title": "Plan utils test",
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
      "description": "First root step.",
      "acceptanceCriteria": ["done"],
      "files": ["one.txt"],
      "dependsOn": [],
      "owner": "codex-impl"
    },
    {
      "id": "step-2",
      "title": "Step 2",
      "description": "Second root step.",
      "acceptanceCriteria": ["done"],
      "files": ["two.txt"],
      "dependsOn": [],
      "owner": "codex-impl"
    },
    {
      "id": "step-3",
      "title": "Step 3",
      "description": "Dependent step.",
      "acceptanceCriteria": ["done"],
      "files": ["three.txt"],
      "dependsOn": ["step-1", "step-2"],
      "owner": "codex-impl"
    }
  ]
}
JSON
}

test_init_progress() {
  local dir="$SANDBOX/init-progress"
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  assert_jq "$dir/progress.json" \
    '.planId == "plan-utils-test"
     and (.startedAt | test("Z$"))
     and (.lastUpdatedAt | test("Z$"))
     and .currentFrontier == ["step-1", "step-2"]
     and ([.steps[] | .status] | all(. == "pending"))
     and (.steps | keys | sort) == ["step-1", "step-2", "step-3"]'
}

test_set_step_status_round_trip() {
  local dir="$SANDBOX/status-round-trip"
  local started completed
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" set-step-status "$dir" step-1 in_progress
  started=$(jq -r '.steps["step-1"].startedAt' "$dir/progress.json")
  [[ "$started" != "null" && -n "$started" ]] || return 1
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  completed=$(jq -r '.steps["step-1"].completedAt' "$dir/progress.json")
  [[ "$completed" != "null" && -n "$completed" ]] || return 1
  jq -e --arg started "$started" \
    '.steps["step-1"].status == "done"
     and .steps["step-1"].startedAt == $started' \
    "$dir/progress.json" >/dev/null
}

test_record_verdict_shapes() {
  local dir="$SANDBOX/verdicts"
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "pass summary" '[]' '["a.txt"]'
  assert_jq "$dir/progress.json" \
    '.steps["step-1"].verdict == "PASS"
     and .steps["step-1"].result == "pass summary"
     and .steps["step-1"].findings == []
     and .steps["step-1"].filesTouched == ["a.txt"]' || return 1
  "$PLAN_UTILS" record-verdict "$dir" step-2 FINDINGS "findings summary" '["one finding"]' '["b.txt"]'
  assert_jq "$dir/progress.json" \
    '.steps["step-2"].verdict == "FINDINGS"
     and .steps["step-2"].findings == ["one finding"]
     and .steps["step-2"].filesTouched == ["b.txt"]' || return 1
  "$PLAN_UTILS" record-verdict "$dir" step-3 FAIL "fail summary" '["one failure"]' '["c.txt"]'
  assert_jq "$dir/progress.json" \
    '.steps["step-3"].verdict == "FAIL"
     and .steps["step-3"].result == "fail summary"
     and .steps["step-3"].findings == ["one failure"]
     and .steps["step-3"].filesTouched == ["c.txt"]'
}

test_compute_frontier() {
  local dir="$SANDBOX/frontier-compute"
  local actual
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  "$PLAN_UTILS" set-step-status "$dir" step-2 done
  actual=$("$PLAN_UTILS" compute-frontier "$dir")
  [[ "$actual" == "step-3" ]]
}

test_set_frontier_override() {
  local dir="$SANDBOX/frontier-override"
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" set-frontier "$dir" "step-3 step-1"
  assert_jq "$dir/progress.json" '.currentFrontier == ["step-3", "step-1"]'
}

test_init_progress_force() {
  local dir="$SANDBOX/init-force"
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  if "$PLAN_UTILS" init-progress "$dir" >/dev/null 2>&1; then
    return 1
  fi
  "$PLAN_UTILS" set-frontier "$dir" step-3
  "$PLAN_UTILS" init-progress --force "$dir"
  assert_jq "$dir/progress.json" '.currentFrontier == ["step-1", "step-2"]'
}

run_test "init-progress creates root frontier and pending steps" test_init_progress
run_test "set-step-status preserves startedAt and sets completedAt" test_set_step_status_round_trip
run_test "record-verdict writes PASS FINDINGS and FAIL shapes" test_record_verdict_shapes
run_test "compute-frontier emits dependent step after dependencies done" test_compute_frontier
run_test "set-frontier explicit override round trip" test_set_frontier_override
run_test "init-progress refuses existing progress unless forced" test_init_progress_force

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
