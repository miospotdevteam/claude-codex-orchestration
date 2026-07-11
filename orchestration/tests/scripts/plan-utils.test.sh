#!/usr/bin/env bash
# The plan status enum intentionally passes the literal argument `done`.
# shellcheck disable=SC1010
set -euo pipefail

# Fresh timestamp for "recent" fixtures — hardcoded dates rot past the
# 7-day staleness window and would flip these tests.
NOW_TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PLAN_UTILS="$SCRIPT_DIR/../../scripts/plan-utils.sh"
REAL_JQ=$(command -v jq)

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
  local owner1=${2:-codex-impl}
  local owner2=${3:-codex-impl}
  local owner3=${4:-codex-impl}
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
      "owner": "$owner1"
    },
    {
      "id": "step-2",
      "title": "Step 2",
      "description": "Second root step.",
      "acceptanceCriteria": ["done"],
      "files": ["two.txt"],
      "dependsOn": [],
      "owner": "$owner2"
    },
    {
      "id": "step-3",
      "title": "Step 3",
      "description": "Dependent step.",
      "acceptanceCriteria": ["done"],
      "files": ["three.txt"],
      "dependsOn": ["step-1", "step-2"],
      "owner": "$owner3"
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

test_get_plan_dir_selects_most_recent() {
  local root="$SANDBOX/get-plan-dir"
  local older="$root/.temp/plan-mode/active/older"
  local newer="$root/.temp/plan-mode/active/newer"
  local actual
  create_plan_dir "$older"
  create_plan_dir "$newer"
  "$PLAN_UTILS" init-progress "$older"
  "$PLAN_UTILS" init-progress "$newer"
  jq '.lastUpdatedAt = "2026-05-11T00:00:00Z"' "$older/progress.json" >"$older/progress.next.json"
  mv "$older/progress.next.json" "$older/progress.json"
  jq '.lastUpdatedAt = "2026-05-12T00:00:00Z"' "$newer/progress.json" >"$newer/progress.next.json"
  mv "$newer/progress.next.json" "$newer/progress.json"

  actual=$("$PLAN_UTILS" get-plan-dir "$root")
  [[ "$actual" == "$(cd "$newer" && pwd -P)" ]]
}

test_read_plan_and_progress() {
  local dir="$SANDBOX/read-files"
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"

  "$PLAN_UTILS" read-plan "$dir" >"$SANDBOX/read-plan.out"
  "$PLAN_UTILS" read-progress "$dir" >"$SANDBOX/read-progress.out"
  cmp -s "$dir/plan.json" "$SANDBOX/read-plan.out" || return 1
  cmp -s "$dir/progress.json" "$SANDBOX/read-progress.out"
}

test_start_step_records_dispatch() {
  local dir="$SANDBOX/start-step"
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" start-step "$dir" step-1 codex gpt-5.6-codex

  assert_jq "$dir/progress.json" '
    .steps["step-1"].status == "in_progress"
    and (.steps["step-1"].startedAt | test("Z$"))
    and .steps["step-1"].dispatch == {
      executor: "codex",
      model: "gpt-5.6-codex",
      startedAt: .steps["step-1"].startedAt
    }
    and (.steps["step-1"] | has("completedAt") | not)
    and .lastUpdatedAt == .steps["step-1"].dispatch.startedAt'
}

test_start_step_rejects_invalid_input_without_writing() {
  local dir="$SANDBOX/start-step-invalid"
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  cp "$dir/progress.json" "$SANDBOX/start-step-invalid.before"

  if "$PLAN_UTILS" start-step "$dir" step-1 invalid model >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/start-step-invalid.before" "$dir/progress.json" || return 1
  if "$PLAN_UTILS" start-step "$dir" step-1 codex '' >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/start-step-invalid.before" "$dir/progress.json" || return 1
  if "$PLAN_UTILS" start-step "$dir" missing-step codex model >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/start-step-invalid.before" "$dir/progress.json"
}

test_start_step_atomic_failure_preserves_original() {
  local dir="$SANDBOX/start-step-atomic"
  local fake_bin="$SANDBOX/fake-bin"
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  cp "$dir/progress.json" "$SANDBOX/start-step-atomic.before"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/jq" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    *'.steps[$id].dispatch'*)
      printf '{"partial":'
      exit 7
      ;;
  esac
done
exec "$REAL_JQ" "$@"
SH
  chmod +x "$fake_bin/jq"

  if REAL_JQ="$REAL_JQ" PATH="$fake_bin:$PATH" \
    "$PLAN_UTILS" start-step "$dir" step-1 claude opus >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/start-step-atomic.before" "$dir/progress.json" || return 1
  ! compgen -G "$dir/.progress.json.tmp.*" >/dev/null
}

test_set_step_status_round_trip() {
  local dir="$SANDBOX/status-round-trip"
  local started completed
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" set-step-status "$dir" step-1 in_progress
  started=$(jq -r '.steps["step-1"].startedAt' "$dir/progress.json")
  [[ "$started" != "null" && -n "$started" ]] || return 1
  # Legacy no-lane path: top-level PASS is required before done for codex-impl.
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "legacy pass" '[]' '[]'
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
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "ok" '[]' '[]'
  "$PLAN_UTILS" record-verdict "$dir" step-2 PASS "ok" '[]' '[]'
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  "$PLAN_UTILS" set-step-status "$dir" step-2 done
  actual=$("$PLAN_UTILS" compute-frontier "$dir")
  [[ "$actual" == "step-3" ]]
}

# --- Dual-verifier verdict storage and done-gating ---

test_record_verdict_lane_mirrors_authoritative_for_codex_impl() {
  local dir="$SANDBOX/lane-mirror-codex-impl"
  create_plan_dir "$dir" codex-impl codex-impl codex-impl
  "$PLAN_UTILS" init-progress "$dir"

  # Grok is authoritative for codex-impl: lane write + top-level mirror.
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "grok ok" '[]' '["g.txt"]' grok
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.grok.verdict == "PASS"
    and .steps["step-1"].verdicts.grok.summary == "grok ok"
    and .steps["step-1"].verdicts.grok.findings == []
    and .steps["step-1"].verdicts.grok.filesTouched == ["g.txt"]
    and (.steps["step-1"].verdicts.grok.timestamp | test("Z$"))
    and .steps["step-1"].verdict == "PASS"
    and .steps["step-1"].result == "grok ok"
    and .steps["step-1"].filesTouched == ["g.txt"]' || return 1

  # Non-authoritative codex lane on codex-impl: store lane only, no top-level overwrite.
  "$PLAN_UTILS" record-verdict "$dir" step-1 FINDINGS "codex second" '["c"]' '["c.txt"]' codex
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.codex.verdict == "FINDINGS"
    and .steps["step-1"].verdicts.codex.summary == "codex second"
    and .steps["step-1"].verdict == "PASS"
    and .steps["step-1"].result == "grok ok"'
}

test_record_verdict_lane_mirrors_authoritative_for_claude_impl() {
  local dir="$SANDBOX/lane-mirror-claude-impl"
  create_plan_dir "$dir" claude-impl claude-impl claude-impl
  "$PLAN_UTILS" init-progress "$dir"

  # Codex is authoritative for claude-impl.
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex gate" '[]' '["a.txt"]' codex
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.codex.verdict == "PASS"
    and .steps["step-1"].verdict == "PASS"
    and .steps["step-1"].result == "codex gate"' || return 1

  # Non-authoritative grok lane: store without overwriting top-level.
  "$PLAN_UTILS" record-verdict "$dir" step-1 FINDINGS "grok second" '["g"]' '["g.txt"]' grok
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.grok.verdict == "FINDINGS"
    and .steps["step-1"].verdict == "PASS"
    and .steps["step-1"].result == "codex gate"'
}

test_record_verdict_lane_mirrors_authoritative_for_grok_impl() {
  local dir="$SANDBOX/lane-mirror-grok-impl"
  create_plan_dir "$dir" grok-impl grok-impl grok-impl
  "$PLAN_UTILS" init-progress "$dir"

  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex auth" '[]' '[]' codex
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.codex.verdict == "PASS"
    and .steps["step-1"].verdict == "PASS"' || return 1

  "$PLAN_UTILS" record-verdict "$dir" step-1 FAIL "grok self" '["x"]' '[]' grok
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.grok.verdict == "FAIL"
    and .steps["step-1"].verdict == "PASS"
    and .steps["step-1"].result == "codex auth"'
}

test_done_refused_when_only_one_dual_lane_pass() {
  local dir="$SANDBOX/done-one-lane"
  create_plan_dir "$dir" claude-impl claude-impl claude-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex only" '[]' '[]' codex
  cp "$dir/progress.json" "$SANDBOX/done-one-lane.before"

  if "$PLAN_UTILS" set-step-status "$dir" step-1 done >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/done-one-lane.before" "$dir/progress.json" || return 1
  assert_jq "$dir/progress.json" '.steps["step-1"].status != "done"'
}

test_done_accepted_with_degraded_and_deviation() {
  local dir="$SANDBOX/done-degraded"
  create_plan_dir "$dir" claude-impl claude-impl claude-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex only" '[]' '[]' codex

  "$PLAN_UTILS" set-step-status "$dir" step-1 done --degraded "grok lane unavailable"
  assert_jq "$dir/progress.json" '
    .steps["step-1"].status == "done"
    and (.steps["step-1"].completedAt | test("Z$"))
    and (.deviations | length) >= 1
    and (.deviations[-1].note | test("grok lane unavailable"))
    and (.deviations[-1].at | test("Z$"))'
}

test_done_degraded_refused_without_lane_pass() {
  local dir="$SANDBOX/done-degraded-no-lane"
  create_plan_dir "$dir" claude-impl claude-impl claude-impl
  "$PLAN_UTILS" init-progress "$dir"
  # Legacy top-level PASS only (no lane argument): --degraded must refuse.
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "legacy top-level only" '[]' '[]'

  if "$PLAN_UTILS" set-step-status "$dir" step-1 done --degraded "grok lane unavailable" >/dev/null 2>&1; then
    return 1
  fi
  assert_jq "$dir/progress.json" '.steps["step-1"].status != "done"'
}

test_done_codex_impl_with_grok_lane_pass() {
  local dir="$SANDBOX/done-codex-impl-grok"
  create_plan_dir "$dir" codex-impl codex-impl codex-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "grok sole" '[]' '["x.txt"]' grok
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  assert_jq "$dir/progress.json" '
    .steps["step-1"].status == "done"
    and .steps["step-1"].verdicts.grok.verdict == "PASS"
    and .steps["step-1"].verdict == "PASS"'
}

test_done_dual_lanes_both_pass() {
  local dir="$SANDBOX/done-dual-both"
  create_plan_dir "$dir" grok-impl grok-impl grok-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex" '[]' '[]' codex
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "grok" '[]' '[]' grok
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.codex.verdict == "PASS"
    and .steps["step-1"].verdicts.grok.verdict == "PASS"' || return 1
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  assert_jq "$dir/progress.json" '.steps["step-1"].status == "done"'
}

test_legacy_no_lane_record_and_done() {
  local dir="$SANDBOX/legacy-no-lane"
  create_plan_dir "$dir" codex-impl codex-impl codex-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "legacy" '[]' '["a.txt"]'
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdict == "PASS"
    and .steps["step-1"].result == "legacy"
    and (.steps["step-1"] | has("verdicts") | not)' || return 1
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  assert_jq "$dir/progress.json" '.steps["step-1"].status == "done"'
}

test_done_refused_without_pass_no_partial_write() {
  local dir="$SANDBOX/done-no-pass"
  create_plan_dir "$dir" codex-impl codex-impl codex-impl
  "$PLAN_UTILS" init-progress "$dir"
  cp "$dir/progress.json" "$SANDBOX/done-no-pass.before"
  if "$PLAN_UTILS" set-step-status "$dir" step-1 done >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/done-no-pass.before" "$dir/progress.json"
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

test_archive_plan_refuses_in_progress() {
  local root="$SANDBOX/archive-in-progress"
  local plan_dir="$root/.temp/plan-mode/active/busy-plan"
  local err
  create_plan_dir "$plan_dir"
  "$PLAN_UTILS" init-progress "$plan_dir"
  "$PLAN_UTILS" set-step-status "$plan_dir" step-1 in_progress
  cp -R "$plan_dir" "$SANDBOX/archive-in-progress.before"

  set +e
  err=$("$PLAN_UTILS" archive-plan "$plan_dir" 2>&1)
  local status=$?
  set -e
  [[ "$status" -ne 0 ]] || return 1
  [[ "$err" == *in_progress* ]] || return 1
  [[ -d "$plan_dir" ]] || return 1
  [[ ! -d "$root/.temp/plan-mode/archive/busy-plan" ]] || return 1
  cmp -s "$SANDBOX/archive-in-progress.before/progress.json" "$plan_dir/progress.json"
}

test_archive_plan_success_moves_dir() {
  local root="$SANDBOX/archive-success"
  local plan_dir="$root/.temp/plan-mode/active/done-plan"
  local dest actual
  create_plan_dir "$plan_dir"
  "$PLAN_UTILS" init-progress "$plan_dir"
  # All pending is fine — no in_progress.
  actual=$("$PLAN_UTILS" archive-plan "$plan_dir")
  dest=$(cd "$root/.temp/plan-mode/archive/done-plan" && pwd -P)
  [[ "$actual" == "$dest" ]] || return 1
  [[ ! -d "$plan_dir" ]] || return 1
  [[ -f "$dest/plan.json" ]] || return 1
  [[ -f "$dest/progress.json" ]]
}

test_archive_plan_force_overrides_in_progress() {
  local root="$SANDBOX/archive-force"
  local plan_dir="$root/.temp/plan-mode/active/forced-plan"
  local dest actual
  create_plan_dir "$plan_dir"
  "$PLAN_UTILS" init-progress "$plan_dir"
  "$PLAN_UTILS" set-step-status "$plan_dir" step-1 in_progress
  actual=$("$PLAN_UTILS" archive-plan --force "$plan_dir")
  dest=$(cd "$root/.temp/plan-mode/archive/forced-plan" && pwd -P)
  [[ "$actual" == "$dest" ]] || return 1
  [[ ! -d "$plan_dir" ]] || return 1
  [[ -d "$dest" ]]
}

test_archive_plan_refuses_missing_plan_json() {
  local root="$SANDBOX/archive-missing-plan"
  local plan_dir="$root/.temp/plan-mode/active/debris-only"
  local err
  mkdir -p "$plan_dir/logs"
  printf 'noise\n' >"$plan_dir/logs/x.log"

  set +e
  err=$("$PLAN_UTILS" archive-plan "$plan_dir" 2>&1)
  local status=$?
  set -e
  [[ "$status" -ne 0 ]] || return 1
  [[ "$err" == *plan.json* ]] || return 1
  [[ -d "$plan_dir" ]] || return 1
  [[ ! -d "$root/.temp/plan-mode/archive/debris-only" ]]
}

test_list_plans_real_debris_stale() {
  local root="$SANDBOX/list-plans"
  local real_dir="$root/.temp/plan-mode/active/real-plan"
  local debris_dir="$root/.temp/plan-mode/active/debris-dir"
  local stale_dir="$root/.temp/plan-mode/active/stale-plan"
  local out

  create_plan_dir "$real_dir"
  "$PLAN_UTILS" init-progress "$real_dir"
  jq --arg now "$NOW_TS" '.lastUpdatedAt = $now' "$real_dir/progress.json" >"$real_dir/progress.next.json"
  mv "$real_dir/progress.next.json" "$real_dir/progress.json"

  mkdir -p "$debris_dir/logs"
  printf 'junk\n' >"$debris_dir/logs/x.log"

  create_plan_dir "$stale_dir"
  "$PLAN_UTILS" init-progress "$stale_dir"
  "$PLAN_UTILS" set-step-status "$stale_dir" step-1 in_progress
  jq '.lastUpdatedAt = "2026-01-01T00:00:00Z"' "$stale_dir/progress.json" >"$stale_dir/progress.next.json"
  mv "$stale_dir/progress.next.json" "$stale_dir/progress.json"

  out=$("$PLAN_UTILS" list-plans "$root")
  printf '%s\n' "$out" | grep -q 'real-plan' || return 1
  printf '%s\n' "$out" | grep -q 'debris-dir' || return 1
  printf '%s\n' "$out" | grep -q 'stale-plan' || return 1
  # real vs debris markers
  printf '%s\n' "$out" | grep 'real-plan' | grep -Eq 'real|plan\.json' || return 1
  printf '%s\n' "$out" | grep 'debris-dir' | grep -Eq 'debris|no plan\.json' || return 1
  # status counts appear for real plans
  printf '%s\n' "$out" | grep 'real-plan' | grep -q 'pending' || return 1
  # staleness marker on old lastUpdatedAt
  printf '%s\n' "$out" | grep 'stale-plan' | grep -qi 'stale' || return 1
  # recent real plan is not marked stale
  ! printf '%s\n' "$out" | grep 'real-plan' | grep -qi 'stale' || return 1
  # lastUpdatedAt surfaces
  printf '%s\n' "$out" | grep 'stale-plan' | grep -q '2026-01-01T00:00:00Z'
}

run_test "init-progress creates root frontier and pending steps" test_init_progress
run_test "get-plan-dir selects the most recently updated plan" test_get_plan_dir_selects_most_recent
run_test "read-plan and read-progress return validated files" test_read_plan_and_progress
run_test "start-step records status and full dispatch atomically" test_start_step_records_dispatch
run_test "start-step rejects invalid input without writing" test_start_step_rejects_invalid_input_without_writing
run_test "start-step preserves progress on atomic update failure" test_start_step_atomic_failure_preserves_original
run_test "set-step-status preserves startedAt and sets completedAt" test_set_step_status_round_trip
run_test "record-verdict writes PASS FINDINGS and FAIL shapes" test_record_verdict_shapes
run_test "compute-frontier emits dependent step after dependencies done" test_compute_frontier
run_test "set-frontier explicit override round trip" test_set_frontier_override
run_test "init-progress refuses existing progress unless forced" test_init_progress_force
run_test "record-verdict lane mirrors authoritative for codex-impl" test_record_verdict_lane_mirrors_authoritative_for_codex_impl
run_test "record-verdict lane mirrors authoritative for claude-impl" test_record_verdict_lane_mirrors_authoritative_for_claude_impl
run_test "record-verdict lane mirrors authoritative for grok-impl" test_record_verdict_lane_mirrors_authoritative_for_grok_impl
run_test "done refused when only one of two dual lanes has PASS" test_done_refused_when_only_one_dual_lane_pass
run_test "done accepted with --degraded and deviation recorded" test_done_accepted_with_degraded_and_deviation
run_test "done refused with --degraded when no lane has PASS" test_done_degraded_refused_without_lane_pass
run_test "done for codex-impl with grok-lane PASS" test_done_codex_impl_with_grok_lane_pass
run_test "done for dual-mandate when both lanes PASS" test_done_dual_lanes_both_pass
run_test "legacy no-lane record-verdict and done still green" test_legacy_no_lane_record_and_done
run_test "done refused without PASS and no partial write" test_done_refused_without_pass_no_partial_write
run_test "archive-plan refuses when a step is in_progress" test_archive_plan_refuses_in_progress
run_test "archive-plan moves finished plan to archive/" test_archive_plan_success_moves_dir
run_test "archive-plan --force overrides in_progress refusal" test_archive_plan_force_overrides_in_progress
run_test "archive-plan refuses missing plan.json without moving" test_archive_plan_refuses_missing_plan_json
run_test "list-plans reports real debris and stale fixtures" test_list_plans_real_debris_stale

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
