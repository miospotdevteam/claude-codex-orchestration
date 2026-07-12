#!/usr/bin/env bash
# The plan status enum intentionally passes the literal argument `done`.
# shellcheck disable=SC1010
set -euo pipefail

# Fresh timestamp for "recent" fixtures — hardcoded dates rot past the
# 7-day staleness window and would flip these tests.
NOW_TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PLAN_UTILS="$SCRIPT_DIR/../../scripts/plan-utils.sh"
PLAN_SCHEMA="$SCRIPT_DIR/../../schemas/plan.schema.json"
PROGRESS_SCHEMA="$SCRIPT_DIR/../../schemas/progress.schema.json"
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
  local routing_profile=${5:-codex-primary}
  mkdir -p "$dir"
  cat >"$dir/plan.json" <<JSON
{
  "planId": "plan-utils-test",
  "title": "Plan utils test",
  "createdAt": "2026-05-11T00:00:00Z",
  "createdBy": "test",
  "routingProfile": "$routing_profile",
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

create_legacy_plan_dir() {
  local dir=$1
  local owner1=${2:-codex-impl}
  local owner2=${3:-codex-impl}
  local owner3=${4:-codex-impl}
  create_plan_dir "$dir" "$owner1" "$owner2" "$owner3"
  jq 'del(.routingProfile)' "$dir/plan.json" >"$dir/plan.next.json"
  mv "$dir/plan.next.json" "$dir/plan.json"
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

test_schemas_require_profile_and_allow_three_verdict_lanes() {
  jq -e '
    (.required | index("routingProfile")) != null
    and (.properties.routingProfile.enum | sort) == ["codex-primary", "fable-primary"]
  ' "$PLAN_SCHEMA" >/dev/null || return 1
  jq -e '
    (."$defs".stepProgress.properties.verdicts.properties | keys | sort)
      == ["claude", "codex", "grok"]
  ' "$PROGRESS_SCHEMA" >/dev/null
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
  "$PLAN_UTILS" start-step "$dir" step-1 codex gpt-5.6-codex xhigh

  assert_jq "$dir/progress.json" '
    .steps["step-1"].status == "in_progress"
    and (.steps["step-1"].startedAt | test("Z$"))
    and .steps["step-1"].dispatch == {
      executor: "codex",
      model: "gpt-5.6-codex",
      effort: "xhigh",
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

  if "$PLAN_UTILS" start-step "$dir" step-1 invalid model high >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/start-step-invalid.before" "$dir/progress.json" || return 1
  if "$PLAN_UTILS" start-step "$dir" step-1 codex '' high >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/start-step-invalid.before" "$dir/progress.json" || return 1
  if "$PLAN_UTILS" start-step "$dir" missing-step codex model high >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/start-step-invalid.before" "$dir/progress.json" || return 1
  if "$PLAN_UTILS" start-step "$dir" step-1 codex model '' >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/start-step-invalid.before" "$dir/progress.json" || return 1
  # The former four-argument signature must not silently invent effort.
  if "$PLAN_UTILS" start-step "$dir" step-1 codex model >/dev/null 2>&1; then
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
    "$PLAN_UTILS" start-step "$dir" step-1 claude opus high >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/start-step-atomic.before" "$dir/progress.json" || return 1
  ! compgen -G "$dir/.progress.json.tmp.*" >/dev/null
}

test_record_lane_dispatch_persists_per_lane_and_clears_stale_verdict() {
  local dir="$SANDBOX/lane-dispatch"
  create_legacy_plan_dir "$dir" codex-impl codex-impl codex-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" start-step "$dir" step-1 codex gpt-5.6-codex xhigh
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "stale claude" '[]' '[]' claude
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "stale grok" '[]' '[]' grok

  "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 claude claude fable xhigh
  assert_jq "$dir/progress.json" '
    .steps["step-1"].status == "in_progress"
    and .steps["step-1"].laneDispatches.claude == {
      lane: "claude",
      executor: "claude",
      model: "fable",
      effort: "xhigh",
      dispatchedAt: .steps["step-1"].laneDispatches.claude.dispatchedAt
    }
    and (.steps["step-1"].laneDispatches.claude.dispatchedAt | test("Z$"))
    and (.steps["step-1"].verdicts | has("claude") | not)
    and .steps["step-1"].verdicts.grok.verdict == "PASS"
    and .steps["step-1"].verdict == "PASS"
    and .steps["step-1"].result == "stale grok"' || return 1

  "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 grok grok grok-4.5 high
  assert_jq "$dir/progress.json" '
    (.steps["step-1"].laneDispatches | keys | sort) == ["claude", "grok"]
    and .steps["step-1"].laneDispatches.grok.lane == "grok"
    and .steps["step-1"].laneDispatches.grok.executor == "grok"
    and .steps["step-1"].laneDispatches.grok.model == "grok-4.5"
    and .steps["step-1"].laneDispatches.grok.effort == "high"
    and (.steps["step-1"].verdicts | has("grok") | not)'
}

test_record_lane_dispatch_rejects_invalid_input_without_writing() {
  local dir="$SANDBOX/lane-dispatch-invalid"
  create_legacy_plan_dir "$dir" grok-impl grok-impl grok-impl
  "$PLAN_UTILS" init-progress "$dir"
  cp "$dir/progress.json" "$SANDBOX/lane-dispatch-invalid.before"

  if "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 grok grok grok-4.5 high >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/lane-dispatch-invalid.before" "$dir/progress.json" || return 1
  if "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 claude claude fable high >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/lane-dispatch-invalid.before" "$dir/progress.json" || return 1
  if "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 codex grok model high >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/lane-dispatch-invalid.before" "$dir/progress.json" || return 1
  if "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 codex codex '' high >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/lane-dispatch-invalid.before" "$dir/progress.json" || return 1
  if "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 codex codex model '' >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/lane-dispatch-invalid.before" "$dir/progress.json"
}

test_manual_steps_refuse_lane_dispatch_and_verdict() {
  local dir="$SANDBOX/manual-no-verifier-lanes"
  create_plan_dir "$dir" manual manual manual
  "$PLAN_UTILS" init-progress "$dir"
  cp "$dir/progress.json" "$SANDBOX/manual-no-verifier-lanes.before"

  if "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 claude claude model high >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/manual-no-verifier-lanes.before" "$dir/progress.json" || return 1

  if "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "unexpected" '[]' '[]' claude >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/manual-no-verifier-lanes.before" "$dir/progress.json"
}

test_lane_down_records_deviation_and_remains_in_progress() {
  local dir="$SANDBOX/lane-down-deviation"
  create_legacy_plan_dir "$dir" codex-impl codex-impl codex-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" start-step "$dir" step-1 codex gpt-5.6-codex xhigh
  "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 claude claude fable xhigh
  "$PLAN_UTILS" record-deviation "$dir" step-1 verifier-lane-down \
    "claude lane remained at capacity after the bounded 10-minute retries" '[]'
  "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 grok grok grok-4.5 high
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "grok passed" '[]' '[]' grok

  if "$PLAN_UTILS" set-step-status "$dir" step-1 done >/dev/null 2>&1; then
    return 1
  fi
  assert_jq "$dir/progress.json" '
    .steps["step-1"].status == "in_progress"
    and .steps["step-1"].deviations[-1] == {
      type: "verifier-lane-down",
      description: "claude lane remained at capacity after the bounded 10-minute retries",
      files: []
    }
    and .steps["step-1"].verdicts.grok.verdict == "PASS"
    and (.steps["step-1"].verdicts | has("claude") | not)'
}

test_schemas_encode_owner_matrix_and_all_persisted_records() {
  assert_jq "$PLAN_SCHEMA" '
    .["$defs"].owner.enum == ["claude-impl", "codex-impl", "grok-impl", "manual"]
    and .["$defs"].owner["x-requiredVerifierLanes"] == {
      "claude-impl": ["codex", "grok"],
      "codex-impl": ["claude", "grok"],
      "grok-impl": ["codex"],
      "manual": []
    }
    and .["$defs"].step.properties.owner["$ref"] == "#/$defs/owner"' || return 1

  assert_jq "$PROGRESS_SCHEMA" '
    (.["$defs"].dispatch.required | sort) == ["effort", "executor", "model", "startedAt"]
    and (.["$defs"].laneDispatch.required | sort) == ["dispatchedAt", "effort", "executor", "lane", "model"]
    and .["$defs"].laneDispatch.properties.lane.enum == ["claude", "codex", "grok"]
    and .["$defs"].stepProgress.properties.laneDispatches.properties.claude["$ref"] == "#/$defs/laneDispatch"
    and .["$defs"].stepProgress.properties.laneDispatches.properties.claude.properties.lane.const == "claude"
    and .["$defs"].stepProgress.properties.laneDispatches.properties.claude.properties.executor.const == "claude"
    and .["$defs"].stepProgress.properties.laneDispatches.properties.codex["$ref"] == "#/$defs/laneDispatch"
    and .["$defs"].stepProgress.properties.laneDispatches.properties.codex.properties.lane.const == "codex"
    and .["$defs"].stepProgress.properties.laneDispatches.properties.codex.properties.executor.const == "codex"
    and .["$defs"].stepProgress.properties.laneDispatches.properties.grok["$ref"] == "#/$defs/laneDispatch"
    and .["$defs"].stepProgress.properties.laneDispatches.properties.grok.properties.lane.const == "grok"
    and .["$defs"].stepProgress.properties.laneDispatches.properties.grok.properties.executor.const == "grok"
    and .["$defs"].stepProgress.properties.verdicts.properties.claude["$ref"] == "#/$defs/laneVerdict"
    and .["$defs"].stepProgress.properties.verdicts.properties.codex["$ref"] == "#/$defs/laneVerdict"
    and .["$defs"].stepProgress.properties.verdicts.properties.grok["$ref"] == "#/$defs/laneVerdict"'
}

test_set_step_status_round_trip() {
  local dir="$SANDBOX/status-round-trip"
  local started completed
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" set-step-status "$dir" step-1 in_progress
  started=$(jq -r '.steps["step-1"].startedAt' "$dir/progress.json")
  [[ "$started" != "null" && -n "$started" ]] || return 1
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex pass" '[]' '[]' codex
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "grok pass" '[]' '[]' grok
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
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex ok" '[]' '[]' codex
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "grok ok" '[]' '[]' grok
  "$PLAN_UTILS" record-verdict "$dir" step-2 PASS "codex ok" '[]' '[]' codex
  "$PLAN_UTILS" record-verdict "$dir" step-2 PASS "grok ok" '[]' '[]' grok
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  "$PLAN_UTILS" set-step-status "$dir" step-2 done
  actual=$("$PLAN_UTILS" compute-frontier "$dir")
  [[ "$actual" == "step-3" ]]
}

# --- Dual-verifier verdict storage and done-gating ---

test_record_verdict_lane_mirrors_authoritative_for_codex_impl() {
  local dir="$SANDBOX/lane-mirror-codex-impl"
  create_legacy_plan_dir "$dir" codex-impl codex-impl codex-impl
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

  # Claude is the other required lane for codex-owned work. It is stored
  # without overwriting the Grok-authored compatibility mirror.
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "claude ok" '[]' '["c.txt"]' claude
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.claude.verdict == "PASS"
    and .steps["step-1"].verdicts.claude.summary == "claude ok"
    and .steps["step-1"].verdict == "PASS"
    and .steps["step-1"].result == "grok ok"'
}

test_record_verdict_lane_mirrors_authoritative_for_claude_impl() {
  local dir="$SANDBOX/lane-mirror-claude-impl"
  create_legacy_plan_dir "$dir" claude-impl claude-impl claude-impl
  "$PLAN_UTILS" init-progress "$dir"

  # Codex is authoritative for claude-impl.
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex gate" '[]' '["a.txt"]' codex
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.codex.verdict == "PASS"
    and .steps["step-1"].verdict == "PASS"
    and .steps["step-1"].result == "codex gate"' || return 1

  # Non-authoritative Grok PASS: store without overwriting top-level.
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "grok second" '[]' '["g.txt"]' grok
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.grok.verdict == "PASS"
    and .steps["step-1"].verdict == "PASS"
    and .steps["step-1"].result == "codex gate"'
}

test_record_verdict_lane_mirrors_authoritative_for_grok_impl() {
  local dir="$SANDBOX/lane-mirror-grok-impl"
  create_legacy_plan_dir "$dir" grok-impl grok-impl grok-impl
  "$PLAN_UTILS" init-progress "$dir"

  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex auth" '[]' '[]' codex
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.codex.verdict == "PASS"
    and .steps["step-1"].verdict == "PASS"' || return 1

  cp "$dir/progress.json" "$SANDBOX/grok-self-verdict.before"
  if "$PLAN_UTILS" record-verdict "$dir" step-1 FAIL "grok self" '["x"]' '[]' grok >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/grok-self-verdict.before" "$dir/progress.json" || return 1

  if "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "claude family" '[]' '[]' claude >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/grok-self-verdict.before" "$dir/progress.json"
}

test_record_verdict_accepts_claude_lane() {
  local dir="$SANDBOX/lane-claude"
  create_plan_dir "$dir" codex-impl codex-impl codex-impl fable-primary
  "$PLAN_UTILS" init-progress "$dir"

  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "claude review" '[]' '["c.txt"]' claude
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.claude.verdict == "PASS"
    and .steps["step-1"].verdicts.claude.summary == "claude review"
    and .steps["step-1"].verdicts.claude.findings == []
    and .steps["step-1"].verdicts.claude.filesTouched == ["c.txt"]
    and (.steps["step-1"].verdicts.claude.timestamp | test("Z$"))'
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

test_degraded_flag_is_removed_without_writing() {
  local dir="$SANDBOX/done-degraded-removed"
  local err status
  create_plan_dir "$dir" claude-impl claude-impl claude-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex only" '[]' '[]' codex
  cp "$dir/progress.json" "$SANDBOX/done-degraded-removed.before"

  set +e
  err=$("$PLAN_UTILS" set-step-status "$dir" step-1 done --degraded "grok lane unavailable" 2>&1)
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || return 1
  [[ "$err" == *"--degraded"* && ${#err} -lt 500 ]] || return 1
  cmp -s "$SANDBOX/done-degraded-removed.before" "$dir/progress.json"
}

test_done_codex_impl_requires_claude_and_grok_pass() {
  local dir="$SANDBOX/done-codex-impl-two-lanes"
  create_legacy_plan_dir "$dir" codex-impl codex-impl codex-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "grok pass" '[]' '["x.txt"]' grok
  if "$PLAN_UTILS" set-step-status "$dir" step-1 done >/dev/null 2>&1; then
    return 1
  fi
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "claude pass" '[]' '[]' claude
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  assert_jq "$dir/progress.json" '
    .steps["step-1"].status == "done"
    and .steps["step-1"].verdicts.grok.verdict == "PASS"
    and .steps["step-1"].verdicts.claude.verdict == "PASS"
    and .steps["step-1"].verdict == "PASS"'
}

test_done_grok_impl_requires_codex_pass_only() {
  local dir="$SANDBOX/done-grok-impl-codex-only"
  create_legacy_plan_dir "$dir" grok-impl grok-impl grok-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex" '[]' '[]' codex
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  assert_jq "$dir/progress.json" '
    .steps["step-1"].status == "done"
    and .steps["step-1"].verdicts.codex.verdict == "PASS"
    and (.steps["step-1"].verdicts | has("grok") | not)
    and (.steps["step-1"].verdicts | has("claude") | not)'
}

test_codex_profile_requires_codex_and_grok_regardless_owner() {
  local dir="$SANDBOX/codex-profile-all-owners"
  local step
  create_plan_dir "$dir" codex-impl claude-impl grok-impl codex-primary
  "$PLAN_UTILS" init-progress "$dir"

  for step in step-1 step-2 step-3; do
    "$PLAN_UTILS" record-verdict "$dir" "$step" PASS "codex pass" '[]' '[]' codex
    if "$PLAN_UTILS" set-step-status "$dir" "$step" done >/dev/null 2>&1; then
      return 1
    fi
    "$PLAN_UTILS" record-verdict "$dir" "$step" PASS "grok pass" '[]' '[]' grok
    "$PLAN_UTILS" set-step-status "$dir" "$step" done
  done

  assert_jq "$dir/progress.json" '
    [.steps[] | .status] | all(. == "done")'
}

test_fable_profile_requires_all_three_lanes() {
  local dir="$SANDBOX/fable-profile-three-lanes"
  create_plan_dir "$dir" codex-impl codex-impl codex-impl fable-primary
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex pass" '[]' '[]' codex
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "grok pass" '[]' '[]' grok
  if "$PLAN_UTILS" set-step-status "$dir" step-1 done >/dev/null 2>&1; then
    return 1
  fi
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "fable pass" '[]' '[]' claude
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  assert_jq "$dir/progress.json" '
    .steps["step-1"].status == "done"
    and (.steps["step-1"].verdicts | keys | sort) == ["claude", "codex", "grok"]'
}

test_profile_lane_admission_and_manual_exemption() {
  local dir="$SANDBOX/profile-lane-admission"
  create_plan_dir "$dir" codex-impl manual manual codex-primary
  "$PLAN_UTILS" init-progress "$dir"
  cp "$dir/progress.json" "$SANDBOX/profile-lane-admission.before"

  if "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "unexpected Claude" '[]' '[]' claude >/dev/null 2>&1; then
    return 1
  fi
  cmp -s "$SANDBOX/profile-lane-admission.before" "$dir/progress.json" || return 1
  "$PLAN_UTILS" set-step-status "$dir" step-2 done
  assert_jq "$dir/progress.json" '.steps["step-2"].status == "done"'
}

test_profile_no_lane_and_unknown_profile_fail_closed() {
  local dir="$SANDBOX/profile-fail-closed"
  create_plan_dir "$dir"
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "legacy-shaped" '[]' '[]'
  if "$PLAN_UTILS" set-step-status "$dir" step-1 done >/dev/null 2>&1; then
    return 1
  fi

  jq '.routingProfile = "unknown"' "$dir/plan.json" >"$dir/plan.next.json"
  mv "$dir/plan.next.json" "$dir/plan.json"
  if "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex" '[]' '[]' codex >/dev/null 2>&1; then
    return 1
  fi
  assert_jq "$dir/progress.json" '.steps["step-1"].status != "done"'
}

test_legacy_no_lane_pass_never_satisfies_implementation_gate() {
  local dir="$SANDBOX/legacy-no-lane"
  create_legacy_plan_dir "$dir" codex-impl codex-impl codex-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "legacy" '[]' '["a.txt"]'
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdict == "PASS"
    and .steps["step-1"].result == "legacy"
    and (.steps["step-1"] | has("verdicts") | not)' || return 1
  if "$PLAN_UTILS" set-step-status "$dir" step-1 done >/dev/null 2>&1; then
    return 1
  fi
  assert_jq "$dir/progress.json" '.steps["step-1"].status == "pending"'
}

test_findings_invalidate_all_required_lane_passes() {
  local dir="$SANDBOX/findings-invalidate-required-lanes"
  create_legacy_plan_dir "$dir" codex-impl codex-impl codex-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" start-step "$dir" step-1 codex gpt-5.6-codex xhigh
  "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 claude claude fable xhigh
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "claude first pass" '[]' '[]' claude
  "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 grok grok grok-4.5 high
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "grok first pass" '[]' '[]' grok
  "$PLAN_UTILS" record-verdict "$dir" step-1 FINDINGS "grok found an issue" '["fix it"]' '[]' grok
  assert_jq "$dir/progress.json" '
    .steps["step-1"].verdicts.grok.verdict == "FINDINGS"
    and (.steps["step-1"].verdicts | has("claude") | not)
    and .steps["step-1"].laneDispatches.grok.lane == "grok"
    and (.steps["step-1"].laneDispatches | has("claude") | not)' || return 1

  "$PLAN_UTILS" start-step "$dir" step-1 codex gpt-5.6-codex xhigh
  "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 grok grok grok-4.5 high
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "grok after fix" '[]' '[]' grok
  if "$PLAN_UTILS" set-step-status "$dir" step-1 done >/dev/null 2>&1; then
    return 1
  fi
  "$PLAN_UTILS" record-lane-dispatch "$dir" step-1 claude claude fable xhigh
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "claude after fix" '[]' '[]' claude
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  assert_jq "$dir/progress.json" '.steps["step-1"].status == "done"'
}

test_non_pass_verdict_reopens_completed_step() {
  local dir="$SANDBOX/non-pass-reopens-done"
  create_legacy_plan_dir "$dir" grok-impl grok-impl grok-impl
  "$PLAN_UTILS" init-progress "$dir"
  "$PLAN_UTILS" record-verdict "$dir" step-1 PASS "codex pass" '[]' '[]' codex
  "$PLAN_UTILS" set-step-status "$dir" step-1 done
  "$PLAN_UTILS" record-verdict "$dir" step-1 FINDINGS "late finding" '["fix it"]' '[]' codex

  assert_jq "$dir/progress.json" '
    .steps["step-1"].status == "in_progress"
    and (.steps["step-1"] | has("completedAt") | not)
    and .steps["step-1"].verdicts.codex.verdict == "FINDINGS"
    and .steps["step-1"].verdict == "FINDINGS"'
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
run_test "schemas require routing profile and allow three verdict lanes" test_schemas_require_profile_and_allow_three_verdict_lanes
run_test "get-plan-dir selects the most recently updated plan" test_get_plan_dir_selects_most_recent
run_test "read-plan and read-progress return validated files" test_read_plan_and_progress
run_test "start-step records status and full dispatch atomically" test_start_step_records_dispatch
run_test "start-step rejects invalid input without writing" test_start_step_rejects_invalid_input_without_writing
run_test "start-step preserves progress on atomic update failure" test_start_step_atomic_failure_preserves_original
run_test "record-lane-dispatch persists per lane and clears its stale verdict" test_record_lane_dispatch_persists_per_lane_and_clears_stale_verdict
run_test "record-lane-dispatch rejects invalid input without writing" test_record_lane_dispatch_rejects_invalid_input_without_writing
run_test "manual steps refuse verifier lane records" test_manual_steps_refuse_lane_dispatch_and_verdict
run_test "lane down records a deviation and remains in_progress" test_lane_down_records_deviation_and_remains_in_progress
run_test "schemas encode the owner matrix and persisted record shapes" test_schemas_encode_owner_matrix_and_all_persisted_records
run_test "set-step-status preserves startedAt and sets completedAt" test_set_step_status_round_trip
run_test "record-verdict writes PASS FINDINGS and FAIL shapes" test_record_verdict_shapes
run_test "compute-frontier emits dependent step after dependencies done" test_compute_frontier
run_test "set-frontier explicit override round trip" test_set_frontier_override
run_test "init-progress refuses existing progress unless forced" test_init_progress_force
run_test "record-verdict lane mirrors authoritative for codex-impl" test_record_verdict_lane_mirrors_authoritative_for_codex_impl
run_test "record-verdict lane mirrors authoritative for claude-impl" test_record_verdict_lane_mirrors_authoritative_for_claude_impl
run_test "record-verdict lane mirrors authoritative for grok-impl" test_record_verdict_lane_mirrors_authoritative_for_grok_impl
run_test "record-verdict accepts and stores claude lane" test_record_verdict_accepts_claude_lane
run_test "done refused when only one of two dual lanes has PASS" test_done_refused_when_only_one_dual_lane_pass
# Disposition (FORCED F3): the prior green degraded-completion cases were
# deleted because implementation steps may never complete on a single lane.
run_test "--degraded is removed and refuses without writing" test_degraded_flag_is_removed_without_writing
run_test "done for codex-impl requires Claude and Grok PASS" test_done_codex_impl_requires_claude_and_grok_pass
run_test "done for grok-impl requires Codex PASS only" test_done_grok_impl_requires_codex_pass_only
run_test "codex profile requires Codex and Grok regardless owner" test_codex_profile_requires_codex_and_grok_regardless_owner
run_test "fable profile requires Codex Grok and Claude" test_fable_profile_requires_all_three_lanes
run_test "profile lane admission and manual exemption" test_profile_lane_admission_and_manual_exemption
run_test "profile no-lane and unknown profile fail closed" test_profile_no_lane_and_unknown_profile_fail_closed
run_test "legacy no-lane PASS never satisfies an implementation gate" test_legacy_no_lane_pass_never_satisfies_implementation_gate
run_test "findings invalidate every required lane PASS" test_findings_invalidate_all_required_lane_passes
run_test "a non-PASS required-lane verdict reopens a completed step" test_non_pass_verdict_reopens_completed_step
run_test "done refused without PASS and no partial write" test_done_refused_without_pass_no_partial_write
run_test "archive-plan refuses when a step is in_progress" test_archive_plan_refuses_in_progress
run_test "archive-plan moves finished plan to archive/" test_archive_plan_success_moves_dir
run_test "archive-plan --force overrides in_progress refusal" test_archive_plan_force_overrides_in_progress
run_test "archive-plan refuses missing plan.json without moving" test_archive_plan_refuses_missing_plan_json
run_test "list-plans reports real debris and stale fixtures" test_list_plans_real_debris_stale

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
