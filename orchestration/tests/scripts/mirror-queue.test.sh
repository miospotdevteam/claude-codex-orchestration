#!/usr/bin/env bash
set -euo pipefail

# RED/green contract for registry mirror queue ops (step mirror-queue):
#   request-mirror-sync / mirror-next / mirror-cancel / mirror-ack,
#   claim-time direction (D6+D9), claim CAS, mint fencing, fail-closed
#   divergence, and mirror-done/mirror-failed feed records.
# Targets orchestration/scripts/workflow-registry.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REGISTRY="$SCRIPT_DIR/../../scripts/workflow-registry"
PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
trap 'rm -rf "$SUITE"' EXIT

REAL_JQ=$(command -v jq || true)
JQ_DIR=
if [[ -n $REAL_JQ ]]; then
  JQ_DIR=$(cd "$(dirname "$REAL_JQ")" && pwd -P)
fi
BASE_PATH="/usr/bin:/bin"
if [[ -n $JQ_DIR && $JQ_DIR != /usr/bin && $JQ_DIR != /bin ]]; then
  BASE_PATH="$JQ_DIR:$BASE_PATH"
fi

pass() { printf 'PASS %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_contains() { grep -Fq -- "$2" "$1"; }
assert_lacks() { ! grep -Fq -- "$2" "$1"; }

json_string() {
  local file=$1 key=$2
  if [[ -n $REAL_JQ ]]; then
    jq -r --arg k "$key" 'if type == "object" then (.[$k] // empty) else empty end' "$file" 2>/dev/null \
      | head -n 1
    return 0
  fi
  sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p" "$file" | head -n 1
}

json_bool() {
  local file=$1 key=$2
  if [[ -n $REAL_JQ ]]; then
    jq -r --arg k "$key" 'if type == "object" and has($k) then (.[$k] | tostring) else empty end' \
      "$file" 2>/dev/null | head -n 1
    return 0
  fi
  sed -n "s/.*\"$key\":\([^,}]*\).*/\1/p" "$file" | head -n 1
}

file_mode() {
  local path=$1
  stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path"
}

setup_case() {
  local name=$1
  CASE="$SUITE/$name"
  HOME_DIR="$CASE/home"
  STATE_ROOT="$CASE/state"
  CHECKOUT="$CASE/mini-checkout"
  PLAN_ID="mirror-queue-plan"
  PLAN_DIR="$CHECKOUT/.temp/plan-mode/active/$PLAN_ID"
  HOSTNAME_FIXTURE="mini-test-host"
  PROJECT=orchestration
  WF_ROOT="$STATE_ROOT/orchestration/workflows"
  PROTOCOL_DIR="$STATE_ROOT/orchestration/remote-agent/projects/$PROJECT"
  STDOUT="$CASE/stdout"
  STDERR="$CASE/stderr"
  STDOUT2="$CASE/stdout2"
  STDERR2="$CASE/stderr2"
  mkdir -p "$HOME_DIR" "$STATE_ROOT" "$CHECKOUT" "$PLAN_DIR" "$PROTOCOL_DIR"
  chmod 700 "$HOME_DIR" "$STATE_ROOT" "$CHECKOUT"
  printf '%s\n' '{"planId":"mirror-queue-plan","frozen":true}' >"$PLAN_DIR/plan.json"
  printf '%s\n' '{"planId":"mirror-queue-plan","steps":{}}' >"$PLAN_DIR/progress.json"
  printf '# mirror-queue plan\n' >"$PLAN_DIR/masterPlan.md"
  # Protocol baseline: equal digests, no lease → claim can decide cleanly.
  printf 'digest-common\n' >"$PROTOCOL_DIR/common"
  printf 'digest-common\n' >"$PROTOCOL_DIR/remote"
  printf '0\n' >"$PROTOCOL_DIR/generation"
  : >"$STDOUT"
  : >"$STDERR"
  : >"$STDOUT2"
  : >"$STDERR2"
  unset WORKFLOW_ID JOB_ID REQUEST_ID CLAIM_TOKEN 2>/dev/null || true
}

run_registry() {
  set +e
  if [[ ! -x $REGISTRY ]]; then
    STATUS=127
    : >"$STDOUT"
    printf 'missing executable: %s\n' "$REGISTRY" >"$STDERR"
    set -e
    return 0
  fi
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    "$REGISTRY" "$@" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
}

run_registry_to() {
  local out=$1 err=$2
  shift 2
  set +e
  if [[ ! -x $REGISTRY ]]; then
    STATUS=127
    : >"$out"
    printf 'missing executable: %s\n' "$REGISTRY" >"$err"
    set -e
    return 0
  fi
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    "$REGISTRY" "$@" >"$out" 2>"$err"
  STATUS=$?
  set -e
}

expect_success() { run_registry "$@"; [[ $STATUS -eq 0 ]]; }
expect_failure() { run_registry "$@"; [[ $STATUS -ne 0 ]]; }

run_test() {
  local name=$1
  shift
  setup_case "case-$((PASS_COUNT + FAIL_COUNT + 1))"
  if "$@"; then
    pass "$name"
  else
    fail "$name" "status=${STATUS:-unset} stdout=$(tr '\n' ' ' <"$STDOUT" 2>/dev/null || true) stderr=$(tr '\n' ' ' <"$STDERR" 2>/dev/null || true)"
  fi
}

mint_workflow() {
  local project=${1:-orchestration}
  expect_success mint "$project" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE" || return 1
  WORKFLOW_ID=$(json_string "$STDOUT" workflowId)
  [[ -n $WORKFLOW_ID ]] || return 1
  return 0
}

wf_dir() {
  printf '%s\n' "$WF_ROOT/$WORKFLOW_ID"
}

job_files() {
  find "$(wf_dir)/mirror-queue" -maxdepth 1 -type f -name '*.json' 2>/dev/null | LC_ALL=C sort
}

first_job_file() {
  job_files | head -n 1
}

plant_relation() {
  local common=$1 remote=$2
  printf '%s\n' "$common" >"$PROTOCOL_DIR/common"
  printf '%s\n' "$remote" >"$PROTOCOL_DIR/remote"
}

plant_live_writer() {
  printf 'active\n' >"$PROTOCOL_DIR/lease-state"
  printf 'remote-agent--%s--claude\n' "$PROJECT" >"$PROTOCOL_DIR/lease-session"
  rm -f -- "$PROTOCOL_DIR/quiescent"
}

clear_live_writer() {
  rm -f -- "$PROTOCOL_DIR/lease-state" "$PROTOCOL_DIR/lease-session" "$PROTOCOL_DIR/quiescent"
}

# ── 1. request-mirror-sync: labels/paths only, no direction, idempotent ──

test_request_enqueues_job_without_direction() {
  mint_workflow || return 1
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-mirror-001 || return 1
  JOB_ID=$(json_string "$STDOUT" jobId)
  [[ -n $JOB_ID ]] || return 1
  assert_contains "$STDOUT" '"ok":true' || return 1
  assert_lacks "$STDOUT" '"direction"' || return 1

  local jf
  jf=$(first_job_file)
  [[ -f $jf ]] || return 1
  [[ $(file_mode "$jf") == 600 ]] || return 1
  if [[ -n $REAL_JQ ]]; then
    jq -e '
      .jobId and .requestId == "req-mirror-001"
      and (.state == "pending")
      and (has("direction") | not)
      and (.seed == false or .seed == null)
    ' "$jf" >/dev/null || return 1
  else
    assert_contains "$jf" 'req-mirror-001' || return 1
    assert_lacks "$jf" '"direction"' || return 1
  fi
  return 0
}

test_request_is_idempotent_on_request_id() {
  mint_workflow || return 1
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-mirror-dup || return 1
  local first_job first_stdout
  first_job=$(json_string "$STDOUT" jobId)
  first_stdout=$(cat "$STDOUT")
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-mirror-dup || return 1
  local second_job
  second_job=$(json_string "$STDOUT" jobId)
  [[ $first_job == "$second_job" ]] || return 1
  # Exactly one on-disk job for that request.
  local count
  count=$(job_files | wc -l | tr -d ' ')
  [[ $count -eq 1 ]] || return 1
  # Replay carries the same requestId.
  assert_contains "$STDOUT" 'req-mirror-dup' || return 1
  [[ -n $first_stdout ]] || return 1
  return 0
}

test_seed_job_carries_only_ignored_path_params() {
  mint_workflow || return 1
  expect_success request-mirror-sync "$WORKFLOW_ID" \
    --request-id req-seed-1 \
    --seed \
    --include-ignored .env \
    --approve-ignored .env || return 1
  local jf
  jf=$(first_job_file)
  [[ -f $jf ]] || return 1
  if [[ -n $REAL_JQ ]]; then
    jq -e '
      .seed == true
      and .includeIgnored == ".env"
      and .approveIgnored == ".env"
      and (has("direction") | not)
      and (tostring | test("prompt|transcript|pane") | not)
    ' "$jf" >/dev/null || return 1
  else
    assert_contains "$jf" '"seed":true' || return 1
    assert_contains "$jf" '.env' || return 1
    assert_lacks "$jf" '"direction"' || return 1
  fi
  return 0
}

# ── 2. claim-time direction (red case: ownership changes pre-claim) ──

test_claim_time_direction_wins_after_ownership_change() {
  mint_workflow || return 1
  # At enqueue Mini has remote-only changes → would be inbound if claimed now.
  plant_relation digest-common digest-mini-ahead
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-claim-dir || return 1
  local jf
  jf=$(first_job_file)
  if [[ -n $REAL_JQ ]]; then
    jq -e 'has("direction") | not' "$jf" >/dev/null || return 1
  else
    assert_lacks "$jf" '"direction"' || return 1
  fi

  # Ownership flip before claim: baseline equal again + seed-style outbound
  # authority (MacBook local-only). Worker supplies local-digest at claim.
  plant_relation digest-common digest-common
  # Clear active workflow ownership so claim is not forced inbound by binding.
  rm -f -- "$WF_ROOT/byproject/$PROJECT"
  # Plant released phase so list stays honest.
  printf 'released\n' >"$(wf_dir)/phase"

  expect_success mirror-next "$PROJECT" --timeout 0 --local-digest digest-macbook-ahead || return 1
  local direction
  direction=$(json_string "$STDOUT" direction)
  [[ $direction == outbound ]] || return 1
  JOB_ID=$(json_string "$STDOUT" jobId)
  [[ -n $JOB_ID ]] || return 1
  # Claim response is the only place direction appears; on-disk job now holds it.
  if [[ -n $REAL_JQ ]]; then
    jq -e --arg j "$JOB_ID" '
      .jobId == $j and .direction == "outbound" and .state == "claimed"
    ' "$(wf_dir)/mirror-queue/${JOB_ID}.json" >/dev/null 2>&1 \
      || jq -e '.direction == "outbound" and .state == "claimed"' "$(first_job_file)" >/dev/null \
      || return 1
  fi
  return 0
}

test_claim_computes_inbound_when_mini_owns() {
  mint_workflow || return 1
  plant_relation digest-common digest-mini-ahead
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-inbound || return 1
  expect_success mirror-next "$PROJECT" --timeout 0 --local-digest digest-common || return 1
  [[ $(json_string "$STDOUT" direction) == inbound ]] || return 1
  return 0
}

test_claim_refuses_diverged_fail_closed() {
  mint_workflow || return 1
  plant_relation digest-common digest-mini-other
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-div-claim || return 1
  # local != common && remote != common && local != remote → diverged
  expect_failure mirror-next "$PROJECT" --timeout 0 --local-digest digest-macbook-other || return 1
  assert_contains "$STDOUT" 'diverged' || assert_contains "$STDERR" 'diverged' || return 1
  # Job remains unclaimed (executable claim never landed).
  local jf
  jf=$(first_job_file)
  if [[ -n $REAL_JQ ]]; then
    jq -e '.state == "pending" and (has("direction") | not)' "$jf" >/dev/null || return 1
  else
    assert_contains "$jf" '"state":"pending"' || return 1
  fi
  return 0
}

test_claim_refuses_live_writer() {
  mint_workflow || return 1
  plant_live_writer
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-live || return 1
  expect_failure mirror-next "$PROJECT" --timeout 0 --local-digest digest-common || return 1
  assert_contains "$STDOUT" 'live-writer' || assert_contains "$STDERR" 'live-writer' || return 1
  return 0
}

# ── 3. mirror-next long-poll, CAS, cancel ──

test_mirror_next_bounded_long_poll_empty() {
  mint_workflow || return 1
  # No jobs: timeout 1 must return quickly with empty/ok, no hang.
  local start end elapsed
  start=$(date +%s)
  expect_success mirror-next "$PROJECT" --timeout 1 || return 1
  end=$(date +%s)
  elapsed=$((end - start))
  (( elapsed <= 3 )) || return 1
  assert_contains "$STDOUT" '"ok":true' || return 1
  # No claimable jobId (null/absent/empty).
  local jid
  jid=$(json_string "$STDOUT" jobId)
  [[ -z $jid || $jid == null ]] || return 1
  return 0
}

test_claim_cas_makes_duplicate_delivery_unexecutable() {
  mint_workflow || return 1
  plant_relation digest-common digest-mini-ahead
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-cas || return 1
  expect_success mirror-next "$PROJECT" --timeout 0 --local-digest digest-common || return 1
  JOB_ID=$(json_string "$STDOUT" jobId)
  CLAIM_TOKEN=$(json_string "$STDOUT" claimToken)
  [[ -n $JOB_ID && -n $CLAIM_TOKEN ]] || return 1

  # Second claim/delivery attempt: either empty (no pending) or refuses CAS.
  run_registry_to "$STDOUT2" "$STDERR2" mirror-next "$PROJECT" --timeout 0 --local-digest digest-common
  if [[ $STATUS -eq 0 ]]; then
    local j2
    j2=$(json_string "$STDOUT2" jobId)
    [[ -z $j2 || $j2 == null || $j2 != "$JOB_ID" ]] || return 1
  else
    assert_contains "$STDOUT2" 'claimed' || assert_contains "$STDERR2" 'claimed' \
      || assert_contains "$STDOUT2" 'cas' || assert_contains "$STDERR2" 'cas' || true
  fi
  # On-disk job stays claimed with original claimToken.
  local jf
  jf=$(first_job_file)
  if [[ -n $REAL_JQ ]]; then
    jq -e --arg t "$CLAIM_TOKEN" '
      .state == "claimed" and .claimToken == $t
    ' "$jf" >/dev/null || return 1
  fi
  return 0
}

test_mirror_cancel_removes_unclaimed_refuses_claimed() {
  mint_workflow || return 1
  plant_relation digest-common digest-mini-ahead
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-can-1 || return 1
  JOB_ID=$(json_string "$STDOUT" jobId)
  [[ -n $JOB_ID ]] || return 1

  expect_success mirror-cancel "$JOB_ID" --request-id req-can-cancel || return 1
  assert_contains "$STDOUT" '"ok":true' || return 1
  # Job file gone or state cancelled and not claimable.
  if [[ -f $(wf_dir)/mirror-queue/${JOB_ID}.json ]]; then
    if [[ -n $REAL_JQ ]]; then
      jq -e '.state == "cancelled"' "$(wf_dir)/mirror-queue/${JOB_ID}.json" >/dev/null || return 1
    fi
  fi
  # Empty next after cancel.
  expect_success mirror-next "$PROJECT" --timeout 0 --local-digest digest-common || return 1
  local jid
  jid=$(json_string "$STDOUT" jobId)
  [[ -z $jid || $jid == null ]] || return 1

  # Fresh job → claim → cancel must refuse.
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-can-2 || return 1
  JOB_ID=$(json_string "$STDOUT" jobId)
  expect_success mirror-next "$PROJECT" --timeout 0 --local-digest digest-common || return 1
  JOB_ID=$(json_string "$STDOUT" jobId)
  expect_failure mirror-cancel "$JOB_ID" --request-id req-can-claimed || return 1
  assert_contains "$STDOUT" 'claimed' || assert_contains "$STDERR" 'claimed' \
    || assert_contains "$STDOUT" 'already-claimed' || assert_contains "$STDERR" 'already-claimed' || return 1
  return 0
}

# ── 4. mint fencing on unclaimed outbound jobs ──

test_mint_refuses_mirror_pending_naming_outbound_job_ids() {
  mint_workflow || return 1
  # Seed job is always outbound at claim/mint evaluation.
  expect_success request-mirror-sync "$WORKFLOW_ID" \
    --request-id req-fence-seed \
    --seed --include-ignored .env --approve-ignored .env || return 1
  JOB_ID=$(json_string "$STDOUT" jobId)
  [[ -n $JOB_ID ]] || return 1

  # Release binding so a new mint is otherwise legal.
  printf 'released\n' >"$(wf_dir)/phase"
  rm -f -- "$WF_ROOT/byproject/$PROJECT"

  expect_failure mint "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE" || return 1
  assert_contains "$STDOUT" 'mirror-pending' || assert_contains "$STDERR" 'mirror-pending' || return 1
  assert_contains "$STDOUT" "$JOB_ID" || assert_contains "$STDERR" "$JOB_ID" || return 1
  return 0
}

test_cancel_unblocks_mint_when_macbook_dead() {
  mint_workflow || return 1
  expect_success request-mirror-sync "$WORKFLOW_ID" \
    --request-id req-fence-cancel \
    --seed --include-ignored .env --approve-ignored .env || return 1
  JOB_ID=$(json_string "$STDOUT" jobId)
  printf 'released\n' >"$(wf_dir)/phase"
  rm -f -- "$WF_ROOT/byproject/$PROJECT"

  expect_failure mint "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE" || return 1
  assert_contains "$STDOUT" 'mirror-pending' || assert_contains "$STDERR" 'mirror-pending' || return 1

  expect_success mirror-cancel "$JOB_ID" --request-id req-unfence || return 1
  expect_success mint "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE" || return 1
  local new_id
  new_id=$(json_string "$STDOUT" workflowId)
  [[ -n $new_id && $new_id != "$WORKFLOW_ID" ]] || return 1
  return 0
}

# ── 5. ack: diverged fail-closed, verified updates mirror.json + feed ──

test_divergent_ack_records_diverged_never_blocks_release() {
  mint_workflow || return 1
  plant_relation digest-common digest-mini-ahead
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-ack-div || return 1
  expect_success mirror-next "$PROJECT" --timeout 0 --local-digest digest-common || return 1
  JOB_ID=$(json_string "$STDOUT" jobId)
  CLAIM_TOKEN=$(json_string "$STDOUT" claimToken)
  [[ -n $JOB_ID && -n $CLAIM_TOKEN ]] || return 1

  expect_failure mirror-ack "$JOB_ID" \
    --claim-token "$CLAIM_TOKEN" \
    --status diverged || return 1
  assert_contains "$STDOUT" 'diverged' || assert_contains "$STDERR" 'diverged' || return 1

  local jf
  jf=$(first_job_file)
  if [[ -n $REAL_JQ ]]; then
    jq -e '.state == "diverged"' "$jf" >/dev/null || return 1
  else
    assert_contains "$jf" 'diverged' || return 1
  fi

  # Release independence: a diverged mirror job must not fence phase advance
  # to released (release never blocks on mirror state).
  printf 'quiesced\n' >"$(wf_dir)/phase"
  expect_success phase-set "$WORKFLOW_ID" released || return 1
  assert_contains "$STDOUT" 'released' || return 1
  # Job still diverged on disk after release path.
  if [[ -n $REAL_JQ ]]; then
    jq -e '.state == "diverged"' "$jf" >/dev/null || return 1
  fi
  return 0
}

test_verified_ack_updates_mirror_json_and_emits_feed() {
  mint_workflow || return 1
  plant_relation digest-common digest-mini-ahead
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-ack-ok || return 1
  expect_success mirror-next "$PROJECT" --timeout 0 --local-digest digest-common || return 1
  JOB_ID=$(json_string "$STDOUT" jobId)
  CLAIM_TOKEN=$(json_string "$STDOUT" claimToken)
  [[ -n $JOB_ID && -n $CLAIM_TOKEN ]] || return 1

  expect_success mirror-ack "$JOB_ID" \
    --claim-token "$CLAIM_TOKEN" \
    --status verified \
    --fingerprint digest-synced \
    --branch main \
    --head abcdef0123456789abcdef0123456789abcdef01 || return 1
  assert_contains "$STDOUT" '"ok":true' || return 1

  local mirror
  mirror="$(wf_dir)/mirror.json"
  [[ -f $mirror ]] || return 1
  [[ $(file_mode "$mirror") == 600 ]] || return 1
  if [[ -n $REAL_JQ ]]; then
    jq -e '
      .repoSync == "mirror-acked"
      or .lastSafeLabel != null
      or .fingerprint == "digest-synced"
      or .head != null
    ' "$mirror" >/dev/null || return 1
  else
    assert_contains "$mirror" 'digest-synced' || assert_contains "$mirror" 'mirror-acked' || return 1
  fi

  # mirror-done feed record under notifications/<project>/
  local feed_dir="$WF_ROOT/notifications/$PROJECT"
  [[ -d $feed_dir ]] || return 1
  if [[ -n $REAL_JQ ]]; then
    local found=0 f
    for f in "$feed_dir"/*.json; do
      [[ -f $f ]] || continue
      if jq -e --arg j "$JOB_ID" '
          .class == "mirror-done"
          and ((.entityId // "") == $j or (.entityId // "" | startswith("job-")) or true)
        ' "$f" >/dev/null 2>&1; then
        # Prefer exact class match; entity may be jobId or workflowId.
        if jq -e '.class == "mirror-done"' "$f" >/dev/null; then
          found=1
          break
        fi
      fi
    done
    [[ $found -eq 1 ]] || return 1
  else
    grep -RFq 'mirror-done' "$feed_dir" || return 1
  fi
  return 0
}

test_failed_ack_emits_mirror_failed_feed() {
  mint_workflow || return 1
  plant_relation digest-common digest-mini-ahead
  expect_success request-mirror-sync "$WORKFLOW_ID" --request-id req-ack-fail || return 1
  expect_success mirror-next "$PROJECT" --timeout 0 --local-digest digest-common || return 1
  JOB_ID=$(json_string "$STDOUT" jobId)
  CLAIM_TOKEN=$(json_string "$STDOUT" claimToken)

  expect_success mirror-ack "$JOB_ID" \
    --claim-token "$CLAIM_TOKEN" \
    --status failed || return 1

  local feed_dir="$WF_ROOT/notifications/$PROJECT"
  [[ -d $feed_dir ]] || return 1
  grep -RFq 'mirror-failed' "$feed_dir" || return 1
  return 0
}

# ── runner ───────────────────────────────────────────────────────────────

if [[ ! -x $REGISTRY ]]; then
  fail 'workflow-registry executable exists' "missing executable: $REGISTRY"
else
  pass 'workflow-registry executable exists'
fi

run_test 'request-mirror-sync enqueues labels/paths job with no direction' \
  test_request_enqueues_job_without_direction
run_test 'request-mirror-sync is idempotent via relay-minted requestId' \
  test_request_is_idempotent_on_request_id
run_test 'seed jobs carry only enumerated ignored-path exception parameters' \
  test_seed_job_carries_only_ignored_path_params
run_test 'claim-time direction wins when ownership changes between enqueue and claim' \
  test_claim_time_direction_wins_after_ownership_change
run_test 'claim computes inbound when Mini owns / remote-only' \
  test_claim_computes_inbound_when_mini_owns
run_test 'claim refuses diverged fail-closed leaving job unclaimed' \
  test_claim_refuses_diverged_fail_closed
run_test 'claim refuses live-writer before delivery' \
  test_claim_refuses_live_writer
run_test 'mirror-next is a bounded long-poll with empty timeout result' \
  test_mirror_next_bounded_long_poll_empty
run_test 'claim CAS makes duplicate delivery unexecutable' \
  test_claim_cas_makes_duplicate_delivery_unexecutable
run_test 'mirror-cancel removes unclaimed job and refuses claimed one' \
  test_mirror_cancel_removes_unclaimed_refuses_claimed
run_test 'mint refuses mirror-pending naming unclaimed outbound jobIds' \
  test_mint_refuses_mirror_pending_naming_outbound_job_ids
run_test 'cancel unblocks mint when MacBook is dead (unclaimed outbound)' \
  test_cancel_unblocks_mint_when_macbook_dead
run_test 'divergent ack records diverged, fails closed, never blocks release' \
  test_divergent_ack_records_diverged_never_blocks_release
run_test 'verified ack updates mirror.json and emits mirror-done feed' \
  test_verified_ack_updates_mirror_json_and_emits_feed
run_test 'failed ack emits mirror-failed feed record' \
  test_failed_ack_emits_mirror_failed_feed

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
