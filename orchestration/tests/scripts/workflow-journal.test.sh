#!/usr/bin/env bash
set -euo pipefail

# RED contract for the durable workflow journal, needs-input latch/ack,
# queue-one send (D1), requestId idempotency + payload digest (D8), lock
# liveness, the labels-only notification feed, and the per-device outbox
# (notificationTransport). Targets orchestration/scripts/workflow-registry.
#
# Green for this suite lands in journal-latch-green (after registry-core-green).
# The implementation may be absent here; every case must still fail for a
# behavioral reason (missing op / wrong outcome), not a fixture error.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REGISTRY="$SCRIPT_DIR/../../scripts/workflow-registry"
PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
trap 'rm -rf "$SUITE"' EXIT

# jq is required by the registry (bash+jq). Keep a resolved path for env -i.
REAL_JQ=$(command -v jq || true)
JQ_DIR=
if [[ -n $REAL_JQ ]]; then
  JQ_DIR=$(cd "$(dirname "$REAL_JQ")" && pwd -P)
fi
BASE_PATH="/usr/bin:/bin"
if [[ -n $JQ_DIR && $JQ_DIR != /usr/bin && $JQ_DIR != /bin ]]; then
  BASE_PATH="$JQ_DIR:$BASE_PATH"
fi

# Closed-class notification feed enum (labels only).
FEED_CLOSED_CLASSES='needs-input|awaiting-approval|failed-recovery|completed|released|mirror-done|mirror-failed|chat-question|chat-reply-completed'

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

json_has_key() {
  local file=$1 key=$2
  if [[ -n $REAL_JQ ]]; then
    jq -e --arg k "$key" 'type == "object" and has($k)' "$file" >/dev/null 2>&1
    return $?
  fi
  grep -Fq "\"$key\"" "$file"
}

file_mode() {
  local path=$1
  stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path"
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

# Real host boot-time token the implementation must use for lock liveness.
# Linux: /proc/stat btime. macOS: kern.boottime sec field (never usec —
# naive "sec =" matching falsely hits the "sec" inside "usec").
host_boot_token() {
  if [[ -r /proc/stat ]]; then
    awk '/^btime / { print $2; exit }' /proc/stat
    return 0
  fi
  if command -v sysctl >/dev/null 2>&1; then
    local raw
    raw=$(sysctl -n kern.boottime 2>/dev/null || true)
    # "{ sec = 1781914829, usec = 515966 } ..." → field named sec only (not usec).
    printf '%s\n' "$raw" | awk -F'[=,{} \t]+' '{
      for (i = 1; i <= NF; i++)
        if ($i == "sec" && $(i+1) ~ /^[0-9]+$/) { print $(i+1); exit }
    }'
    return 0
  fi
  # Last resort: root birth time (still host-derived, not fabricated).
  stat -c %W / 2>/dev/null || stat -f %B / 2>/dev/null || printf '0\n'
}

setup_case() {
  local name=$1
  CASE="$SUITE/$name"
  HOME_DIR="$CASE/home"
  STATE_ROOT="$CASE/state"
  # Mini checkout + plan fixture (matches workflow-registry mint arity contract).
  CHECKOUT="$CASE/mini-checkout"
  PLAN_ID="journal-latch-red-plan"
  PLAN_DIR="$CHECKOUT/.temp/plan-mode/active/$PLAN_ID"
  HOSTNAME_FIXTURE="mini-test-host"
  PROJECT=orchestration
  WF_ROOT="$STATE_ROOT/orchestration/workflows"
  STDOUT="$CASE/stdout"
  STDERR="$CASE/stderr"
  STDOUT2="$CASE/stdout2"
  STDERR2="$CASE/stderr2"
  STATUS_FILE="$CASE/status"
  mkdir -p "$HOME_DIR" "$STATE_ROOT" "$CHECKOUT" "$PLAN_DIR" "$CASE/bin"
  chmod 700 "$HOME_DIR" "$STATE_ROOT" "$CHECKOUT"
  printf '%s\n' '{"planId":"journal-latch-red-plan","frozen":true}' >"$PLAN_DIR/plan.json"
  printf '%s\n' '{"planId":"journal-latch-red-plan","steps":{}}' >"$PLAN_DIR/progress.json"
  printf '# journal-latch-red plan\n' >"$PLAN_DIR/masterPlan.md"
  : >"$STDOUT"
  : >"$STDERR"
  : >"$STDOUT2"
  : >"$STDERR2"
  : >"$STATUS_FILE"
  unset WORKFLOW_ID JOURNAL_EPOCH CURSOR LATCH_SEQ REQUEST_ID PAYLOAD DIGEST 2>/dev/null || true
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

# Payload on a tempfile (never pipe the helper itself — that subshells STATUS).
send_payload() {
  local payload=$1
  shift
  local payload_file=$CASE/stdin-payload
  printf '%s' "$payload" >"$payload_file"
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
    "$REGISTRY" "$@" <"$payload_file" >"$STDOUT" 2>"$STDERR"
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

# ── helpers that exercise the public registry surface ──────────────────────

# mint PROJECT PLAN_ID CHECKOUT HOST — four-arg contract from registry-red.
mint_workflow() {
  local project=${1:-orchestration}
  expect_success mint "$project" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE" || return 1
  WORKFLOW_ID=$(json_string "$STDOUT" workflowId)
  if [[ -z $WORKFLOW_ID ]]; then
    WORKFLOW_ID=$(json_string "$STDOUT" id)
  fi
  [[ -n $WORKFLOW_ID && $WORKFLOW_ID == wf-"$project"-* ]] || return 1
  JOURNAL_EPOCH=$(json_string "$STDOUT" journalEpoch)
  if [[ -z $JOURNAL_EPOCH ]]; then
    local cursor
    cursor=$(json_string "$STDOUT" cursor)
    case $cursor in
      jrn-*:*) JOURNAL_EPOCH=${cursor%:*} ;;
      *) JOURNAL_EPOCH=jrn-1 ;;
    esac
  fi
  case $JOURNAL_EPOCH in
    jrn-*) ;;
    *) JOURNAL_EPOCH="jrn-$JOURNAL_EPOCH" ;;
  esac
  CURSOR=$(json_string "$STDOUT" cursor)
  if [[ -z $CURSOR ]]; then
    CURSOR="${JOURNAL_EPOCH}:0"
  fi
  return 0
}

project_event() {
  local wf=$1 scope=$2 kind=$3
  expect_success project-event "$wf" "$scope" "$kind" || return 1
}

set_phase() {
  local wf=$1 phase=$2
  expect_success phase-set "$wf" "$phase" || return 1
}

workflow_dir() {
  printf '%s\n' "$WF_ROOT/$WORKFLOW_ID"
}

pending_payload_path() {
  printf '%s\n' "$(workflow_dir)/pending-send.payload"
}

pending_meta_path() {
  printf '%s\n' "$(workflow_dir)/pending-send.json"
}

needs_input_path() {
  printf '%s\n' "$(workflow_dir)/needs-input.json"
}

journal_dir() {
  printf '%s\n' "$(workflow_dir)/journal"
}

cursor_at() {
  local seq=$1
  printf '%s:%s\n' "$JOURNAL_EPOCH" "$seq"
}

# Extract wait batch kinds/classes in order (jq required for exact membership).
batch_kinds() {
  local file=$1
  if [[ -z $REAL_JQ ]]; then
    return 1
  fi
  jq -r '
    (.batch // .events // [])
    | map(.kind // .eventClass // .class // .label // empty)
    | .[]
  ' "$file" 2>/dev/null
}

batch_length() {
  local file=$1
  if [[ -z $REAL_JQ ]]; then
    echo 0
    return 0
  fi
  jq -r '(.batch // .events // []) | length' "$file" 2>/dev/null || echo 0
}

wait_cursor() {
  json_string "$STDOUT" cursor
}

# Byte-identity snapshot of a workflow tree (or any state subtree).
# Used to prove no re-delivery / no side effects under refusal or replay.
state_fingerprint() {
  local root=$1
  local path rel mode
  if [[ ! -d $root ]]; then
    printf 'missing:%s\n' "$root"
    return 0
  fi
  while IFS= read -r path; do
    rel=${path#"$root"/}
    mode=$(file_mode "$path")
    if [[ -f $path ]]; then
      printf 'file %s %s ' "$mode" "$rel"
      cksum "$path" | awk '{print $1" "$2}'
    elif [[ -d $path ]]; then
      printf 'dir %s %s\n' "$mode" "$rel"
    fi
  done < <(find "$root" -mindepth 1 -print | LC_ALL=C sort)
}

workflow_fingerprint() {
  state_fingerprint "$(workflow_dir)"
}

# Labels-only whitelist: EVERY record key must be in this closed set.
# Allowed fields ONLY:
#   class      — "class" or synonym "eventClass"
#   opaque ref — "entityId" | "entity" | "ref" | "reference" | "workflowId"
#   seq        — "seq"
#   cursor     — "cursor" (transport position; optional on feed, required-or-absent on outbox)
# ANY other key fails (including body/text/prompt/project/requestId/delivered/acked/dedupKey).
RECORD_ALLOWED_KEYS='["class","eventClass","entityId","entity","ref","reference","workflowId","seq","cursor"]'

outbox_record_keys_allowed() {
  local file=$1
  [[ -n $REAL_JQ ]] || return 1
  jq -e --argjson allowed "$RECORD_ALLOWED_KEYS" '
    (.records // .batch // .events // []) as $rows
    | ($rows | length) > 0
    and ($rows | all(
          (has("class") or has("eventClass"))
          and (has("entityId") or has("entity") or has("ref") or has("reference") or has("workflowId"))
          and has("seq")
          and ((keys - $allowed) | length) == 0
        ))
  ' "$file" >/dev/null 2>&1
}

feed_record_keys_allowed() {
  local file=$1
  [[ -n $REAL_JQ ]] || return 1
  jq -e --argjson allowed "$RECORD_ALLOWED_KEYS" '
    (if type == "array" then . else [.] end) as $rows
    | ($rows | length) > 0
    and ($rows | all(
          (has("class") or has("eventClass"))
          and (has("entityId") or has("entity") or has("ref") or has("reference") or has("workflowId"))
          and has("seq")
          and ((keys - $allowed) | length) == 0
        ))
  ' "$file" >/dev/null 2>&1
}

# Collect feed rows as sorted "class|entityId|seq" lines for exact set compare.
feed_triple_set() {
  local feed_dir=$1
  [[ -n $REAL_JQ && -d $feed_dir ]] || return 1
  local f
  for f in "$feed_dir"/*.json; do
    [[ -f $f ]] || continue
    jq -r '
      (if type == "array" then .[] else . end)
      | [
          (.class // .eventClass // ""),
          (.entityId // .entity // .workflowId // .ref // .reference // ""),
          ((.seq // 0) | tonumber | tostring)
        ]
      | join("|")
    ' "$f" 2>/dev/null
  done | LC_ALL=C sort
}

# ── 1. journal / wait ──────────────────────────────────────────────────────

test_wait_replays_from_zero_and_mid_cursor() {
  mint_workflow orchestration || return 1
  project_event "$WORKFLOW_ID" main completed || return 1
  project_event "$WORKFLOW_ID" main failed || return 1
  project_event "$WORKFLOW_ID" main input-needed || return 1

  # Replay from :0 — exact membership and order of the three projected events.
  local start_cursor
  start_cursor=$(cursor_at 0)
  expect_success wait "$WORKFLOW_ID" --cursor "$start_cursor" --timeout 5 || return 1
  json_has_key "$STDOUT" cursor || return 1
  json_has_key "$STDOUT" phase || return 1
  json_has_key "$STDOUT" latch || return 1
  [[ -n $REAL_JQ ]] || return 1

  local len full_cursor expected_full k0 k1 k2
  len=$(batch_length "$STDOUT")
  [[ $len -eq 3 ]] || return 1
  # Exact order via jq (bash 3.2 has no mapfile).
  k0=$(jq -r '(.batch // .events // [])[0] | (.kind // .eventClass // .class // .label // empty)' "$STDOUT")
  k1=$(jq -r '(.batch // .events // [])[1] | (.kind // .eventClass // .class // .label // empty)' "$STDOUT")
  k2=$(jq -r '(.batch // .events // [])[2] | (.kind // .eventClass // .class // .label // empty)' "$STDOUT")
  # Order: completed, failed, input-needed (projected kinds).
  [[ $k0 == completed || $k0 == 'main/completed' ]] || return 1
  [[ $k1 == failed || $k1 == 'main/failed' ]] || return 1
  [[ $k2 == input-needed || $k2 == 'main/input-needed' || $k2 == needs-input ]] || return 1

  # Capture the EXACT epoch:number token returned by the API and require it.
  full_cursor=$(wait_cursor)
  expected_full=$(cursor_at 3)
  [[ -n $full_cursor ]] || return 1
  # Full token equality — not a prefix/seq-only check. Wrong epoch or wrong seq fails.
  [[ $full_cursor == "$expected_full" ]] || return 1
  # Token must also be the journal epoch captured at mint (epoch half is exact).
  [[ ${full_cursor%:*} == "$JOURNAL_EPOCH" ]] || return 1

  # Mid-cursor wait from :1 returns ONLY events after seq 1 (failed, input-needed).
  local mid_start mid_cursor expected_mid
  mid_start=$(cursor_at 1)
  expect_success wait "$WORKFLOW_ID" --cursor "$mid_start" --timeout 5 || return 1
  len=$(batch_length "$STDOUT")
  [[ $len -eq 2 ]] || return 1
  k0=$(jq -r '(.batch // .events // [])[0] | (.kind // .eventClass // .class // .label // empty)' "$STDOUT")
  k1=$(jq -r '(.batch // .events // [])[1] | (.kind // .eventClass // .class // .label // empty)' "$STDOUT")
  [[ $k0 == failed || $k0 == 'main/failed' ]] || return 1
  [[ $k1 == input-needed || $k1 == 'main/input-needed' || $k1 == needs-input ]] || return 1
  # No seq ≤ 1 in the mid-cursor batch.
  jq -e '
    (.batch // .events // [])
    | map(.seq // (.cursor | tostring | split(":") | last | tonumber?) // 0)
    | all(. > 1)
  ' "$STDOUT" >/dev/null 2>&1 || return 1
  # Capture mid-cursor API token and require exact epoch:number equality.
  mid_cursor=$(wait_cursor)
  expected_mid=$(cursor_at 3)
  [[ $mid_cursor == "$expected_mid" ]] || return 1
  [[ ${mid_cursor%:*} == "$JOURNAL_EPOCH" ]] || return 1
  # Mid token must equal the full-replay token (same durable epoch end position).
  [[ $mid_cursor == "$full_cursor" ]] || return 1
  return 0
}

test_supervisor_restart_stays_inside_one_journal_epoch() {
  mint_workflow orchestration || return 1
  local epoch_before
  epoch_before=$JOURNAL_EPOCH
  project_event "$WORKFLOW_ID" main completed || return 1

  # Simulate a supervisor restart: wipe the session event epoch under the
  # supervisor state dir. The registry journal epoch must be unchanged.
  local supervisor_sessions="$STATE_ROOT/orchestration/agent-supervisor/sessions"
  mkdir -p "$supervisor_sessions/remote-agent--orchestration--claude"
  printf 'epoch-old-1\n' >"$supervisor_sessions/remote-agent--orchestration--claude/epoch"
  printf '3\n' >"$supervisor_sessions/remote-agent--orchestration--claude/cursor"
  rm -f "$supervisor_sessions/remote-agent--orchestration--claude/epoch"
  printf 'epoch-new-99\n' >"$supervisor_sessions/remote-agent--orchestration--claude/epoch"
  printf '0\n' >"$supervisor_sessions/remote-agent--orchestration--claude/cursor"

  project_event "$WORKFLOW_ID" main input-needed || return 1
  expect_success wait "$WORKFLOW_ID" --cursor "$(cursor_at 0)" --timeout 5 || return 1
  local epoch_after
  epoch_after=$(json_string "$STDOUT" journalEpoch)
  if [[ -z $epoch_after ]]; then
    local c
    c=$(json_string "$STDOUT" cursor)
    epoch_after=${c%:*}
  fi
  [[ $epoch_after == "$epoch_before" ]] || return 1
  [[ -n $REAL_JQ ]] || return 1
  # Both projected events still present under the same durable epoch.
  local joined
  joined=$(batch_kinds "$STDOUT" | tr '\n' ',')
  [[ $joined == *completed* ]] || return 1
  [[ $joined == *input-needed* || $joined == *needs-input* ]] || return 1
  # Supervisor's wiped epoch must not appear as the journal epoch.
  assert_lacks "$STDOUT" 'epoch-new-99' || return 1
  assert_lacks "$STDOUT" 'epoch-old-1'
}

test_reconcile_at_read_heals_dropped_projection() {
  mint_workflow orchestration || return 1
  project_event "$WORKFLOW_ID" main completed || return 1

  # Baseline membership BEFORE reconcile: completed is present exactly once.
  expect_success wait "$WORKFLOW_ID" --cursor "$(cursor_at 0)" --timeout 5 || return 1
  [[ -n $REAL_JQ ]] || return 1
  local completed_before input_before joined_before
  completed_before=$(jq -r '
    [(.batch // .events // [])[]
      | select((.kind // .eventClass // .class // "") | test("completed"))]
    | length
  ' "$STDOUT")
  input_before=$(jq -r '
    [(.batch // .events // [])[]
      | select((.kind // .eventClass // .class // "") | test("input-needed|needs-input"))]
    | length
  ' "$STDOUT")
  [[ ${completed_before:-0} -eq 1 ]] || return 1
  [[ ${input_before:-0} -eq 0 ]] || return 1
  joined_before=$(batch_kinds "$STDOUT" | tr '\n' ',')
  [[ $joined_before == *completed* ]] || return 1

  # Drop the projection: leave a journal-pending marker as if enqueue
  # succeeded but the workflow-journal write failed (fail-open path).
  local pending
  pending="$(workflow_dir)/journal-pending"
  mkdir -p "$(workflow_dir)"
  printf '%s\n' '{"scope":"main","kind":"input-needed","source":"enqueue"}' >"$pending"
  chmod 600 "$pending"

  # First read reconciles exactly once: event lands, latch raised, marker cleared.
  expect_success inspect "$WORKFLOW_ID" || return 1
  assert_contains "$STDOUT" 'input-needed' || return 1
  [[ ! -e $pending ]] || return 1
  local latch_file
  latch_file=$(needs_input_path)
  [[ -f $latch_file ]] || return 1

  expect_success wait "$WORKFLOW_ID" --cursor "$(cursor_at 0)" --timeout 5 || return 1
  local completed_after input_after joined_after
  completed_after=$(jq -r '
    [(.batch // .events // [])[]
      | select((.kind // .eventClass // .class // "") | test("completed"))]
    | length
  ' "$STDOUT")
  input_after=$(jq -r '
    [(.batch // .events // [])[]
      | select((.kind // .eventClass // .class // "") | test("input-needed|needs-input"))]
    | length
  ' "$STDOUT")
  # Pre-existing completed MUST SURVIVE reconcile (exact membership before+after).
  [[ ${completed_after:-0} -eq 1 ]] || return 1
  [[ ${completed_after:-0} -eq ${completed_before:-0} ]] || return 1
  [[ ${input_after:-0} -eq 1 ]] || return 1
  joined_after=$(batch_kinds "$STDOUT" | tr '\n' ',')
  [[ $joined_after == *completed* ]] || return 1
  [[ $joined_after == *input-needed* || $joined_after == *needs-input* ]] || return 1

  # Second read must not double-project (exactly-once reconciliation).
  expect_success inspect "$WORKFLOW_ID" || return 1
  expect_success wait "$WORKFLOW_ID" --cursor "$(cursor_at 0)" --timeout 5 || return 1
  completed_after=$(jq -r '
    [(.batch // .events // [])[]
      | select((.kind // .eventClass // .class // "") | test("completed"))]
    | length
  ' "$STDOUT")
  input_after=$(jq -r '
    [(.batch // .events // [])[]
      | select((.kind // .eventClass // .class // "") | test("input-needed|needs-input"))]
    | length
  ' "$STDOUT")
  [[ ${completed_after:-0} -eq 1 ]] || return 1
  [[ ${input_after:-0} -eq 1 ]]
}

# ── 2. latch / ack ─────────────────────────────────────────────────────────

test_latch_raise_supersede_and_ack() {
  mint_workflow orchestration || return 1
  project_event "$WORKFLOW_ID" main input-needed || return 1
  local latch1 seq1
  latch1=$(needs_input_path)
  [[ -f $latch1 ]] || return 1
  seq1=$(json_string "$latch1" journalSeq)
  if [[ -z $seq1 ]]; then
    seq1=$(json_string "$latch1" seq)
  fi
  [[ -n $seq1 ]] || return 1

  # A newer input-needed supersedes the unacked latch.
  project_event "$WORKFLOW_ID" main input-needed || return 1
  local seq2
  seq2=$(json_string "$latch1" journalSeq)
  if [[ -z $seq2 ]]; then
    seq2=$(json_string "$latch1" seq)
  fi
  [[ -n $seq2 && $seq2 != "$seq1" ]] || return 1
  if [[ $seq2 =~ ^[0-9]+$ && $seq1 =~ ^[0-9]+$ ]]; then
    (( seq2 > seq1 )) || return 1
  fi

  REQUEST_ID="req-ack-$(printf '%04x' $$)"
  PAYLOAD='ack-body'
  DIGEST=$(printf '%s' "$PAYLOAD" | sha256_of)
  send_payload "$PAYLOAD" send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" \
    --payload-sha256 "$DIGEST" \
    --ack-event "$seq2"
  [[ $STATUS -eq 0 ]] || return 1
  # Latch cleared or marked acked after a matching ack.
  # When the latch file remains in state=acked, requestId is MANDATORY and must
  # equal the relay-minted id used for the ack (empty requestId is a soft miss).
  if [[ -f $latch1 ]]; then
    local state ack_req
    state=$(json_string "$latch1" state)
    [[ $state == acked || $state == none || $state == cleared ]] || return 1
    ack_req=$(json_string "$latch1" requestId)
    if [[ $state == acked ]]; then
      [[ -n $ack_req && $ack_req == "$REQUEST_ID" ]] || return 1
    else
      # none/cleared may omit requestId, but if present it must match.
      [[ -z $ack_req || $ack_req == "$REQUEST_ID" ]] || return 1
    fi
  fi
  assert_contains "$STDOUT" "$REQUEST_ID"
}

test_stale_ack_is_refused() {
  mint_workflow orchestration || return 1
  project_event "$WORKFLOW_ID" main input-needed || return 1
  local latch seq1 seq2
  latch=$(needs_input_path)
  seq1=$(json_string "$latch" journalSeq)
  [[ -z $seq1 ]] && seq1=$(json_string "$latch" seq)
  [[ -n $seq1 ]] || return 1

  project_event "$WORKFLOW_ID" main input-needed || return 1
  seq2=$(json_string "$latch" journalSeq)
  [[ -z $seq2 ]] && seq2=$(json_string "$latch" seq)
  [[ -n $seq2 && $seq2 != "$seq1" ]] || return 1

  REQUEST_ID="req-stale-$(printf '%04x' $$)"
  PAYLOAD='stale'
  DIGEST=$(printf '%s' "$PAYLOAD" | sha256_of)
  # STATUS must be observed in the parent (send_payload, not a pipe subshell).
  send_payload "$PAYLOAD" send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" \
    --payload-sha256 "$DIGEST" \
    --ack-event "$seq1"
  [[ $STATUS -ne 0 ]] || return 1
  assert_contains "$STDERR" 'stale-ack' || assert_contains "$STDOUT" 'stale-ack' || return 1
  # Latch must still be pending at the newer seq.
  local still
  still=$(json_string "$latch" journalSeq)
  [[ -z $still ]] && still=$(json_string "$latch" seq)
  [[ $still == "$seq2" ]]
}

test_latch_survives_epoch_wipe() {
  mint_workflow orchestration || return 1
  project_event "$WORKFLOW_ID" main input-needed || return 1
  local latch before after
  latch=$(needs_input_path)
  [[ -f $latch ]] || return 1
  before=$(cksum "$latch" | awk '{print $1" "$2}')

  local supervisor_sessions="$STATE_ROOT/orchestration/agent-supervisor/sessions"
  mkdir -p "$supervisor_sessions/remote-agent--orchestration--claude/events"
  printf 'epoch-wipe-1\n' >"$supervisor_sessions/remote-agent--orchestration--claude/epoch"
  rm -rf "$supervisor_sessions/remote-agent--orchestration--claude/events"
  mkdir -p "$supervisor_sessions/remote-agent--orchestration--claude/events"
  printf 'epoch-wipe-2\n' >"$supervisor_sessions/remote-agent--orchestration--claude/epoch"
  printf '0\n' >"$supervisor_sessions/remote-agent--orchestration--claude/cursor"

  [[ -f $latch ]] || return 1
  after=$(cksum "$latch" | awk '{print $1" "$2}')
  [[ $before == "$after" ]] || return 1

  expect_success inspect "$WORKFLOW_ID" || return 1
  assert_contains "$STDOUT" 'input-needed' || assert_contains "$STDOUT" 'needs-input' || assert_contains "$STDOUT" 'latch'
}

# ── 3. queue-one (D1) ──────────────────────────────────────────────────────

test_queue_one_stores_single_pending_with_0600_and_digest() {
  mint_workflow orchestration || return 1
  set_phase "$WORKFLOW_ID" running || return 1

  REQUEST_ID="req-q1-$(printf '%04x' $$)"
  PAYLOAD='queued-message-body'
  DIGEST=$(printf '%s' "$PAYLOAD" | sha256_of)
  send_payload "$PAYLOAD" send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" \
    --payload-sha256 "$DIGEST"
  [[ $STATUS -eq 0 ]] || return 1

  local payload_path meta_path
  payload_path=$(pending_payload_path)
  meta_path=$(pending_meta_path)
  [[ -f $payload_path && -f $meta_path ]] || return 1
  [[ $(file_mode "$payload_path") == 600 ]] || return 1
  [[ $(file_mode "$meta_path") == 600 ]] || return 1
  [[ $(<"$payload_path") == "$PAYLOAD" ]] || return 1
  assert_contains "$meta_path" "$DIGEST" || return 1
  assert_contains "$meta_path" "$REQUEST_ID" || return 1

  expect_success inspect "$WORKFLOW_ID" || return 1
  assert_contains "$STDOUT" 'pending' || assert_contains "$STDOUT" 'queue' || assert_contains "$STDOUT" "$REQUEST_ID"
}

test_second_send_refuses_queue_full() {
  mint_workflow orchestration || return 1
  set_phase "$WORKFLOW_ID" running || return 1

  REQUEST_ID="req-qf1-$(printf '%04x' $$)"
  PAYLOAD='first'
  DIGEST=$(printf '%s' "$PAYLOAD" | sha256_of)
  send_payload "$PAYLOAD" send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" --payload-sha256 "$DIGEST"
  [[ $STATUS -eq 0 ]] || return 1

  local second_id second_digest
  second_id="req-qf2-$(printf '%04x' $$)"
  second_digest=$(printf 'second' | sha256_of)
  send_payload 'second' send "$WORKFLOW_ID" \
    --request-id "$second_id" --payload-sha256 "$second_digest"
  [[ $STATUS -ne 0 ]] || return 1
  assert_contains "$STDERR" 'queue-full' || assert_contains "$STDOUT" 'queue-full' || return 1

  # First pending remains intact.
  [[ $(<"$(pending_payload_path)") == first ]]
}

test_cancel_pending_is_idempotent() {
  mint_workflow orchestration || return 1
  set_phase "$WORKFLOW_ID" running || return 1

  REQUEST_ID="req-can-$(printf '%04x' $$)"
  PAYLOAD='to-cancel'
  DIGEST=$(printf '%s' "$PAYLOAD" | sha256_of)
  send_payload "$PAYLOAD" send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" --payload-sha256 "$DIGEST"
  [[ $STATUS -eq 0 ]] || return 1
  [[ -f $(pending_payload_path) ]] || return 1

  expect_success send "$WORKFLOW_ID" --request-id "req-can-op-1" --cancel-pending || return 1
  [[ ! -e $(pending_payload_path) ]] || return 1
  [[ ! -e $(pending_meta_path) ]] || return 1

  # Second cancel is a no-op success (idempotent removal).
  expect_success send "$WORKFLOW_ID" --request-id "req-can-op-2" --cancel-pending || return 1
  [[ ! -e $(pending_payload_path) ]]
}

test_delivery_requires_fresh_latch_and_journals_delivered_from_queue() {
  mint_workflow orchestration || return 1
  set_phase "$WORKFLOW_ID" running || return 1

  REQUEST_ID="req-del-$(printf '%04x' $$)"
  PAYLOAD='deliver-me'
  DIGEST=$(printf '%s' "$PAYLOAD" | sha256_of)
  send_payload "$PAYLOAD" send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" --payload-sha256 "$DIGEST"
  [[ $STATUS -eq 0 ]] || return 1
  [[ -f $(pending_payload_path) ]] || return 1

  # Without a latch, deliver-queue must refuse (never force-paste mid-step):
  # (a) exits nonzero with a bounded latch refusal AND
  # (b) leaves the COMPLETE workflow state byte-identical.
  local snap_before_latchless snap_after_latchless
  snap_before_latchless=$(workflow_fingerprint)
  run_registry deliver-queue "$WORKFLOW_ID"
  [[ $STATUS -ne 0 ]] || return 1
  assert_contains "$STDERR" 'latch' || assert_contains "$STDOUT" 'latch' || \
    assert_contains "$STDERR" 'needs-input' || assert_contains "$STDOUT" 'needs-input' || return 1
  snap_after_latchless=$(workflow_fingerprint)
  [[ $snap_before_latchless == "$snap_after_latchless" ]] || return 1
  [[ -f $(pending_payload_path) ]] || return 1

  # Snapshot journal size before latch-triggered delivery.
  local jdir before_count after_count
  jdir=$(journal_dir)
  before_count=0
  if [[ -d $jdir ]]; then
    before_count=$(find "$jdir" -type f ! -name 'journal-cursor' | wc -l | tr -d ' ')
  fi

  # Fresh verified latch (input-needed projection) triggers delivery.
  project_event "$WORKFLOW_ID" main input-needed || return 1

  # Pending is consumed; journal carries delivered-from-queue.
  [[ ! -e $(pending_payload_path) ]] || return 1
  expect_success wait "$WORKFLOW_ID" --cursor "$(cursor_at 0)" --timeout 5 || return 1
  assert_contains "$STDOUT" 'delivered-from-queue' || return 1

  # Latch evidence is MANDATORY: ack record exists AND carries exactly the
  # queued requestId (not optional, not empty, not a freshly minted id).
  local latch_file latch_state latch_req
  latch_file=$(needs_input_path)
  [[ -f $latch_file ]] || return 1
  latch_state=$(json_string "$latch_file" state)
  [[ $latch_state == acked || $latch_state == none || $latch_state == cleared ]] || return 1
  latch_req=$(json_string "$latch_file" requestId)
  [[ -n $latch_req ]] || return 1
  [[ $latch_req == "$REQUEST_ID" ]] || return 1
  # Request ledger records the delivery under the queued requestId.
  local req_record
  req_record="$(workflow_dir)/requests/${REQUEST_ID}.json"
  [[ -f $req_record ]] || return 1
  assert_contains "$req_record" 'delivered-from-queue' || assert_contains "$req_record" 'delivered' || return 1
  assert_contains "$req_record" "$REQUEST_ID" || return 1
  assert_contains "$req_record" "$DIGEST" || return 1

  # Snapshot FULL delivery state (all workflow files + digests) before replay.
  local snap_before snap_after
  snap_before=$(workflow_fingerprint)

  send_payload "$PAYLOAD" send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" --payload-sha256 "$DIGEST"
  [[ $STATUS -eq 0 ]] || return 1
  assert_contains "$STDOUT" "$REQUEST_ID" || return 1
  # Byte-identical state after replay: no re-delivery, no journal growth.
  snap_after=$(workflow_fingerprint)
  [[ $snap_before == "$snap_after" ]] || return 1
  [[ ! -e $(pending_payload_path) ]] || return 1
  # Latch requestId still exactly the queued id.
  latch_req=$(json_string "$latch_file" requestId)
  [[ $latch_req == "$REQUEST_ID" ]] || return 1
  return 0
}

# ── 4. idempotency / digest / wait bound ───────────────────────────────────

test_duplicate_request_id_replays_recorded_outcome() {
  mint_workflow orchestration || return 1
  project_event "$WORKFLOW_ID" main input-needed || return 1
  local latch seq
  latch=$(needs_input_path)
  seq=$(json_string "$latch" journalSeq)
  [[ -z $seq ]] && seq=$(json_string "$latch" seq)
  [[ -n $seq ]] || return 1

  REQUEST_ID="req-idem-$(printf '%04x' $$)"
  PAYLOAD='once-only'
  DIGEST=$(printf '%s' "$PAYLOAD" | sha256_of)
  send_payload "$PAYLOAD" send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" --payload-sha256 "$DIGEST" --ack-event "$seq"
  [[ $STATUS -eq 0 ]] || return 1
  cp "$STDOUT" "$STDOUT2"
  local first_out first_cursor delivered_before snap_before snap_after
  first_out=$(cat "$STDOUT")
  expect_success wait "$WORKFLOW_ID" --cursor "$(cursor_at 0)" --timeout 5 || return 1
  first_cursor=$(wait_cursor)
  delivered_before=$(batch_length "$STDOUT")

  # Snapshot full delivery state (files + digests) before duplicate replay.
  snap_before=$(workflow_fingerprint)
  local req_record
  req_record="$(workflow_dir)/requests/${REQUEST_ID}.json"
  [[ -f $req_record ]] || return 1
  assert_contains "$req_record" "$DIGEST" || return 1

  # Duplicate requestId + same digest replays the recorded outcome; no
  # second execution (byte-identical workflow state; no journal growth).
  send_payload "$PAYLOAD" send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" --payload-sha256 "$DIGEST" --ack-event "$seq"
  [[ $STATUS -eq 0 ]] || return 1
  # Full delivery outcome byte-identity: whole JSON payload, not just
  # requestId+status fields. first_out/STDOUT2 hold the first result.
  local second_out
  second_out=$(cat "$STDOUT")
  [[ -n $first_out && -n $second_out ]] || return 1
  [[ $first_out == "$second_out" ]] || return 1
  cmp -s "$STDOUT" "$STDOUT2" || return 1
  # Full state byte-identity: no re-delivery, no journal growth.
  snap_after=$(workflow_fingerprint)
  [[ $snap_before == "$snap_after" ]] || return 1

  # Cursor and batch length unchanged under wait replay.
  expect_success wait "$WORKFLOW_ID" --cursor "$(cursor_at 0)" --timeout 5 || return 1
  [[ $(wait_cursor) == "$first_cursor" ]] || return 1
  [[ $(batch_length "$STDOUT") -eq ${delivered_before:-0} ]] || return 1
  # Latch remains acked with the original requestId.
  [[ -f $latch ]] || return 1
  local state latch_req
  state=$(json_string "$latch" state)
  [[ $state == acked || $state == none || $state == cleared ]] || return 1
  latch_req=$(json_string "$latch" requestId)
  [[ $latch_req == "$REQUEST_ID" ]] || return 1
  return 0
}

test_reused_request_id_with_different_digest_fails_closed() {
  mint_workflow orchestration || return 1
  project_event "$WORKFLOW_ID" main input-needed || return 1
  local latch seq
  latch=$(needs_input_path)
  seq=$(json_string "$latch" journalSeq)
  [[ -z $seq ]] && seq=$(json_string "$latch" seq)
  [[ -n $seq ]] || return 1

  REQUEST_ID="req-dig-$(printf '%04x' $$)"
  PAYLOAD='alpha'
  DIGEST=$(printf '%s' "$PAYLOAD" | sha256_of)
  send_payload "$PAYLOAD" send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" --payload-sha256 "$DIGEST" --ack-event "$seq"
  [[ $STATUS -eq 0 ]] || return 1

  local snap_before snap_after other_digest
  snap_before=$(workflow_fingerprint)
  other_digest=$(printf 'beta' | sha256_of)
  send_payload 'beta' send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" --payload-sha256 "$other_digest" --ack-event "$seq"
  [[ $STATUS -ne 0 ]] || return 1
  assert_contains "$STDERR" 'digest' || assert_contains "$STDOUT" 'digest' || \
    assert_contains "$STDERR" 'conflict' || assert_contains "$STDOUT" 'conflict' || return 1
  # Fail-closed: no state mutation on digest conflict.
  snap_after=$(workflow_fingerprint)
  [[ $snap_before == "$snap_after" ]] || return 1
  return 0
}

test_payload_sha256_mismatch_refuses_before_delivery() {
  mint_workflow orchestration || return 1
  project_event "$WORKFLOW_ID" main input-needed || return 1
  local latch seq
  latch=$(needs_input_path)
  seq=$(json_string "$latch" journalSeq)
  [[ -z $seq ]] && seq=$(json_string "$latch" seq)
  [[ -n $seq ]] || return 1

  # Snapshot full delivery state BEFORE the refused send.
  local snap_before snap_after
  snap_before=$(workflow_fingerprint)

  REQUEST_ID="req-mis-$(printf '%04x' $$)"
  PAYLOAD='real-bytes'
  local wrong
  wrong=$(printf 'other-bytes' | sha256_of)
  send_payload "$PAYLOAD" send "$WORKFLOW_ID" \
    --request-id "$REQUEST_ID" --payload-sha256 "$wrong" --ack-event "$seq"
  [[ $STATUS -ne 0 ]] || return 1
  assert_contains "$STDERR" 'payload-sha256' || assert_contains "$STDOUT" 'payload-sha256' || \
    assert_contains "$STDERR" 'digest' || assert_contains "$STDOUT" 'digest' || return 1

  # Pre-delivery refusal: full workflow state is UNCHANGED (same snapshot method).
  snap_after=$(workflow_fingerprint)
  [[ $snap_before == "$snap_after" ]] || return 1

  # Latch must remain pending (no delivery / no ack).
  [[ -f $latch ]] || return 1
  local state
  state=$(json_string "$latch" state)
  [[ -z $state || $state == open || $state == pending || $state == raised ]] || return 1
  # No request ledger entry at all for a pre-delivery mismatch (nothing delivered).
  [[ ! -e "$(workflow_dir)/requests/${REQUEST_ID}.json" ]] || return 1
  [[ ! -e $(pending_payload_path) ]] || return 1
  return 0
}

test_wait_is_one_bounded_blocking_call() {
  mint_workflow orchestration || return 1

  # Timeout above 300 s is refused at the CLI boundary.
  expect_failure wait "$WORKFLOW_ID" --cursor "$(cursor_at 0)" --timeout 301 || return 1
  assert_contains "$STDERR" 'usage' || assert_contains "$STDERR" 'timeout' || \
    assert_contains "$STDOUT" 'timeout' || return 1

  # Prove wait BLOCKS: inject a delayed project-event, then wait for it.
  # Elapsed time must be ≥ the injected delay (not an immediate empty return).
  local delay_s=2
  local start end elapsed wait_out wait_err wait_status
  wait_out="$CASE/wait-block.out"
  wait_err="$CASE/wait-block.err"
  (
    sleep "$delay_s"
    env -i \
      HOME="$HOME_DIR" \
      XDG_STATE_HOME="$STATE_ROOT" \
      PATH="$BASE_PATH" \
      HOSTNAME="$HOSTNAME_FIXTURE" \
      WORKFLOW_REGISTRY_TEST=1 \
      REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
      REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
      "$REGISTRY" project-event "$WORKFLOW_ID" main completed \
      >"$CASE/delayed-event.out" 2>"$CASE/delayed-event.err"
    echo $? >"$CASE/delayed-event.status"
  ) &
  local injector_pid=$!

  start=$(date +%s)
  set +e
  if [[ ! -x $REGISTRY ]]; then
    STATUS=127
    : >"$wait_out"
    printf 'missing executable: %s\n' "$REGISTRY" >"$wait_err"
  else
    env -i \
      HOME="$HOME_DIR" \
      XDG_STATE_HOME="$STATE_ROOT" \
      PATH="$BASE_PATH" \
      HOSTNAME="$HOSTNAME_FIXTURE" \
      WORKFLOW_REGISTRY_TEST=1 \
      REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
      REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
      "$REGISTRY" wait "$WORKFLOW_ID" --cursor "$(cursor_at 0)" --timeout 10 \
      >"$wait_out" 2>"$wait_err"
    STATUS=$?
  fi
  set -e
  end=$(date +%s)
  elapsed=$((end - start))
  wait "$injector_pid" 2>/dev/null || true
  cp "$wait_out" "$STDOUT"
  cp "$wait_err" "$STDERR"
  [[ $STATUS -eq 0 ]] || return 1
  # Blocking proof: must have waited at least the injected delay.
  (( elapsed >= delay_s )) || return 1
  # Upper bound: one call ≤300 s (here timeout was 10).
  (( elapsed <= 15 )) || return 1
  json_has_key "$STDOUT" cursor || return 1
  json_has_key "$STDOUT" phase || return 1
  json_has_key "$STDOUT" latch || return 1
  [[ -n $REAL_JQ ]] || return 1
  jq -e '
    has("batch") and (.batch | type == "array")
    and has("cursor") and has("phase") and has("latch")
  ' "$STDOUT" >/dev/null 2>&1 || return 1
  # Batch content must include the delayed completed event (not an empty wake).
  local batch_has_completed
  batch_has_completed=$(jq -r '
    [(.batch // .events // [])[]
      | select((.kind // .eventClass // .class // .label // "") | test("completed"))]
    | length
  ' "$STDOUT")
  [[ ${batch_has_completed:-0} -ge 1 ]] || return 1
  return 0
}

# ── 5. locks + notification feed ───────────────────────────────────────────

test_dead_pid_lock_is_broken_and_journaled() {
  mint_workflow orchestration || return 1
  local lock_dir boot
  lock_dir="$(workflow_dir)/lock"
  mkdir -p "$lock_dir"
  boot=$(host_boot_token)
  [[ -n $boot ]] || return 1
  # Dead pid + real host boot token → lock is breakable on this host.
  printf 'pid=999999999\nboot=%s\n' "$boot" >"$lock_dir/holder"
  chmod 600 "$lock_dir/holder"

  project_event "$WORKFLOW_ID" main completed || return 1
  expect_success wait "$WORKFLOW_ID" --cursor "$(cursor_at 0)" --timeout 5 || return 1
  assert_contains "$STDOUT" 'completed' || return 1
  [[ -n $REAL_JQ ]] || return 1
  # Require a journaled lock-break record with exact label and dead-pid field.
  # Substring "lock" alone is insufficient.
  jq -e '
    (.batch // .events // [])
    | map(select(
        ((.kind // .eventClass // .class // .label // "")
          | test("^lock-broken$|^lock_broken$|lock-broken|lock_broken"))
      ))
    | length >= 1
    and all(
      ((.kind // .eventClass // .class // .label) | test("lock-broken|lock_broken"))
      and (
        ((.pid // .deadPid // .holderPid // empty) | tostring) == "999999999"
        or ((.detail // .reason // .message // "") | tostring | test("999999999"))
      )
    )
  ' "$STDOUT" >/dev/null 2>&1 || return 1
  return 0
}

test_live_pid_lock_refuses_busy() {
  mint_workflow orchestration || return 1
  local lock_dir boot snap_before snap_after
  lock_dir="$(workflow_dir)/lock"
  mkdir -p "$lock_dir"
  # Live pid of this shell + the REAL host boot-time source (no fabricated token).
  boot=$(host_boot_token)
  [[ -n $boot && $boot != 0 ]] || return 1
  printf 'pid=%s\nboot=%s\n' "$$" "$boot" >"$lock_dir/holder"
  chmod 600 "$lock_dir/holder"

  # Snapshot full workflow state; busy refusal must mutate nothing.
  snap_before=$(workflow_fingerprint)
  run_registry project-event "$WORKFLOW_ID" main completed
  [[ $STATUS -ne 0 ]] || return 1
  assert_contains "$STDERR" 'busy' || assert_contains "$STDOUT" 'busy' || return 1
  snap_after=$(workflow_fingerprint)
  [[ $snap_before == "$snap_after" ]] || return 1
  # Holder file still names this live pid (lock not stolen).
  assert_contains "$lock_dir/holder" "pid=$$" || return 1
  return 0
}

test_feed_appends_closed_class_labels_only_with_dedup() {
  mint_workflow orchestration || return 1
  [[ -n $REAL_JQ ]] || return 1

  local feed_dir expected actual row_count entity_a entity_b
  feed_dir="$WF_ROOT/notifications/orchestration"
  entity_a="$WORKFLOW_ID"
  entity_b="${WORKFLOW_ID}-other"

  # Construct rows so ONLY the full class+entityId+seq key distinguishes them:
  #   - pair differing ONLY by entityId (same class, same seq)
  #   - pair differing ONLY by seq (same class, same entityId)
  #   - pair differing ONLY by class (same entityId, same seq) — catches
  #     implementations whose dedup key omits class
  #   - one exact duplicate of the first triple
  # Omitting class, entityId, or seq from the key must each fail the set compare.
  expect_success feed-append orchestration needs-input "$entity_a" 1 || return 1
  expect_success feed-append orchestration needs-input "$entity_b" 1 || return 1
  expect_success feed-append orchestration needs-input "$entity_a" 2 || return 1
  # Same entityId+seq as the first row; differs ONLY by closed class.
  expect_success feed-append orchestration completed "$entity_a" 1 || return 1
  [[ -d $feed_dir ]] || return 1

  # Exact retained set: four distinct full triples (sorted for compare).
  expected=$(printf '%s\n' \
    "completed|${entity_a}|1" \
    "needs-input|${entity_a}|1" \
    "needs-input|${entity_a}|2" \
    "needs-input|${entity_b}|1" | LC_ALL=C sort)
  actual=$(feed_triple_set "$feed_dir") || return 1
  [[ $actual == "$expected" ]] || return 1
  row_count=$(printf '%s\n' "$actual" | grep -c . || true)
  [[ ${row_count:-0} -eq 4 ]] || return 1

  # Exact duplicate of the first triple is a no-op: exact row set unchanged.
  expect_success feed-append orchestration needs-input "$entity_a" 1 || return 1
  actual=$(feed_triple_set "$feed_dir") || return 1
  [[ $actual == "$expected" ]] || return 1
  row_count=$(printf '%s\n' "$actual" | grep -c . || true)
  [[ ${row_count:-0} -eq 4 ]] || return 1

  # No duplicate rows within any single feed file.
  local f within
  for f in "$feed_dir"/*.json; do
    [[ -f $f ]] || continue
    within=$(jq -r '
      [ (if type == "array" then .[] else . end)
        | [(.class // .eventClass // ""),
           (.entityId // .entity // .workflowId // .ref // .reference // ""),
           ((.seq // 0) | tonumber | tostring)]
        | join("|") ]
      | length as $n
      | (unique | length) as $u
      | if $n == $u then "ok" else "dup" end
    ' "$f")
    [[ $within == ok ]] || return 1
    # Whitelist: fail on ANY key outside class / opaque ref / seq / cursor.
    feed_record_keys_allowed "$f" || return 1
  done

  # Free text / unknown class is refused (no row set growth).
  expect_failure feed-append orchestration 'please restart the box now' "$WORKFLOW_ID" 99 || return 1
  assert_contains "$STDERR" 'class' || assert_contains "$STDERR" 'usage' || \
    assert_contains "$STDOUT" 'class' || return 1
  actual=$(feed_triple_set "$feed_dir") || return 1
  [[ $actual == "$expected" ]] || return 1

  expect_failure feed-append orchestration not-a-real-class "$WORKFLOW_ID" 3 || return 1
  actual=$(feed_triple_set "$feed_dir") || return 1
  [[ $actual == "$expected" ]] || return 1
  return 0
}

# ── 6. per-device outbox (notificationTransport) ────────────────────────────

test_device_register_and_revoke() {
  mint_workflow orchestration || return 1
  local device cred
  device="dev-phone-$(printf '%04x' $$)"
  cred="cred-$(printf '%04x' $$)-secret"
  REQUEST_ID="req-reg-$(printf '%04x' $$)"

  expect_success device-register \
    --device-id "$device" \
    --credential "$cred" \
    --build-type sandbox \
    --request-id "$REQUEST_ID" || return 1
  assert_contains "$STDOUT" "$device" || return 1

  local device_dir
  device_dir="$WF_ROOT/outbox/$device"
  [[ -d $device_dir ]] || return 1
  if [[ -f $device_dir/credential || -f $device_dir/credential.enc || -f $device_dir/meta.json ]]; then
    local mode_file
    mode_file=$(find "$device_dir" -type f | head -n 1)
    [[ $(file_mode "$mode_file") == 600 ]] || return 1
  fi

  expect_success device-revoke \
    --device-id "$device" \
    --request-id "req-rev-$(printf '%04x' $$)" || return 1
}

test_outbox_derives_from_feed_with_durable_cursor_and_replay() {
  mint_workflow orchestration || return 1
  [[ -n $REAL_JQ ]] || return 1

  # Two devices for per-device cursor isolation.
  local device_a cred_a device_b cred_b
  device_a="dev-desk-a-$(printf '%04x' $$)"
  cred_a="cred-desk-a-$(printf '%04x' $$)"
  device_b="dev-desk-b-$(printf '%04x' $$)"
  cred_b="cred-desk-b-$(printf '%04x' $$)"
  expect_success device-register \
    --device-id "$device_a" --credential "$cred_a" \
    --build-type production --request-id "req-reg2a-$$" || return 1
  expect_success device-register \
    --device-id "$device_b" --credential "$cred_b" \
    --build-type production --request-id "req-reg2b-$$" || return 1

  expect_success feed-append orchestration needs-input "$WORKFLOW_ID" 10 || return 1
  expect_success feed-append orchestration completed "$WORKFLOW_ID" 11 || return 1

  # Device B baseline: full undelivered set + its cursor token.
  expect_success outbox-fetch \
    --device-id "$device_b" --credential "$cred_b" --cursor 0 || return 1
  local b_cursor_before b_membership_before
  b_cursor_before=$(json_string "$STDOUT" cursor)
  [[ -n $b_cursor_before ]] || return 1
  b_membership_before=$(jq -r '
    [(.records // .batch // .events // [])[]
      | [(.class // .eventClass), ((.seq // 0) | tonumber | tostring)]
      | join(":")]
    | sort | join(",")
  ' "$STDOUT")
  [[ $b_membership_before == 'completed:11,needs-input:10' ]] || return 1
  outbox_record_keys_allowed "$STDOUT" || return 1
  assert_lacks "$STDOUT" "$cred_b" || return 1

  # Device A: fetch full set, then ack seq 10 (advances only A's durable cursor).
  expect_success outbox-fetch \
    --device-id "$device_a" --credential "$cred_a" --cursor 0 || return 1
  local a_n_needs a_n_completed a_cursor_full
  a_n_needs=$(jq -r \
    '[(.records // .batch // .events // [])[] | select((.class // .eventClass) == "needs-input")] | length' \
    "$STDOUT")
  a_n_completed=$(jq -r \
    '[(.records // .batch // .events // [])[] | select((.class // .eventClass) == "completed")] | length' \
    "$STDOUT")
  [[ ${a_n_needs:-0} -eq 1 && ${a_n_completed:-0} -eq 1 ]] || return 1
  a_cursor_full=$(json_string "$STDOUT" cursor)
  [[ -n $a_cursor_full ]] || return 1
  outbox_record_keys_allowed "$STDOUT" || return 1

  expect_success outbox-ack \
    --device-id "$device_a" --credential "$cred_a" \
    --request-id "req-ack-ob-1-$$" --seq 10 || return 1
  local a_cursor_after_ack
  a_cursor_after_ack=$(json_string "$STDOUT" cursor)
  [[ -n $a_cursor_after_ack ]] || return 1

  # Isolation: B's cursor and replay membership are UNCHANGED after A's advance.
  expect_success outbox-fetch \
    --device-id "$device_b" --credential "$cred_b" --cursor 0 || return 1
  local b_cursor_after b_membership_after
  b_cursor_after=$(json_string "$STDOUT" cursor)
  b_membership_after=$(jq -r '
    [(.records // .batch // .events // [])[]
      | [(.class // .eventClass), ((.seq // 0) | tonumber | tostring)]
      | join(":")]
    | sort | join(",")
  ' "$STDOUT")
  [[ $b_cursor_after == "$b_cursor_before" ]] || return 1
  [[ $b_membership_after == "$b_membership_before" ]] || return 1
  [[ $b_membership_after == 'completed:11,needs-input:10' ]] || return 1

  # Reconnect A: EXACT undelivered set is completed:11 only (seq 10 acked).
  expect_success outbox-fetch \
    --device-id "$device_a" --credential "$cred_a" --cursor 0 || return 1
  local a_membership_reconnect
  a_membership_reconnect=$(jq -r '
    [(.records // .batch // .events // [])[]
      | [(.class // .eventClass), ((.seq // 0) | tonumber | tostring)]
      | join(":")]
    | sort | join(",")
  ' "$STDOUT")
  [[ $a_membership_reconnect == 'completed:11' ]] || return 1
  a_n_needs=$(jq -r \
    '[(.records // .batch // .events // [])[] | select((.class // .eventClass) == "needs-input" and ((.seq // 0) | tonumber) == 10)] | length' \
    "$STDOUT")
  a_n_completed=$(jq -r \
    '[(.records // .batch // .events // [])[] | select((.class // .eventClass) == "completed")] | length' \
    "$STDOUT")
  [[ ${a_n_needs:-0} -eq 0 ]] || return 1
  [[ ${a_n_completed:-0} -eq 1 ]] || return 1
  return 0
}

test_delivery_failure_never_erases_outbox_events() {
  mint_workflow orchestration || return 1
  local device cred
  device="dev-fail-$(printf '%04x' $$)"
  cred="cred-fail-$(printf '%04x' $$)"
  expect_success device-register \
    --device-id "$device" --credential "$cred" \
    --build-type sandbox --request-id "req-reg3-$$" || return 1
  expect_success feed-append orchestration failed-recovery "$WORKFLOW_ID" 20 || return 1

  # Inject a delivery failure (transport error) without erasing the event.
  expect_success outbox-mark-failed \
    --device-id "$device" --seq 20 --reason transport-error || return 1

  # Event remains durable and fetchable after the failure.
  expect_success outbox-fetch \
    --device-id "$device" --credential "$cred" --cursor 0 || return 1
  [[ -n $REAL_JQ ]] || return 1
  jq -e '
    [(.records // .batch // .events // [])[]
      | select((.class // .eventClass) == "failed-recovery"
          and ((.seq // 0) | tonumber) == 20)]
    | length == 1
  ' "$STDOUT" >/dev/null 2>&1 || return 1
  # Failure is recorded in device state but does not drop the record.
  local device_dir
  device_dir="$WF_ROOT/outbox/$device"
  if [[ -d $device_dir ]]; then
    # Either a failed marker exists, or the fetch still surfaces the event (proven above).
    :
  fi
  return 0
}

test_revoked_device_credential_fetches_nothing() {
  mint_workflow orchestration || return 1
  local device cred
  device="dev-rev-$(printf '%04x' $$)"
  cred="cred-rev-$(printf '%04x' $$)"
  expect_success device-register \
    --device-id "$device" --credential "$cred" \
    --build-type sandbox --request-id "req-reg4-$$" || return 1
  expect_success feed-append orchestration released "$WORKFLOW_ID" 30 || return 1
  expect_success device-revoke \
    --device-id "$device" --request-id "req-rev2-$$" || return 1

  run_registry outbox-fetch --device-id "$device" --credential "$cred" --cursor 0
  # Revoked credential: either non-zero exit, or success with EMPTY records.
  # "fetches nothing" — no lifecycle records (released etc.) beside a revoked label.
  if [[ $STATUS -eq 0 ]]; then
    [[ -n $REAL_JQ ]] || return 1
    # Records array must be empty (no undelivered lifecycle payload).
    jq -e '(.records // .batch // .events // []) | length == 0' "$STDOUT" >/dev/null 2>&1 || return 1
    # Explicitly refuse any lifecycle class on the wire after revoke.
    assert_lacks "$STDOUT" 'released' || return 1
    assert_lacks "$STDOUT" 'needs-input' || return 1
    assert_lacks "$STDOUT" 'completed' || return 1
    # Optional top-level revoked label is allowed; free text is not.
    if assert_contains "$STDOUT" 'revoked'; then
      :
    fi
  else
    # Failure path: still must not leak lifecycle records.
    assert_lacks "$STDOUT" 'released' || return 1
    assert_contains "$STDERR" 'revoked' || assert_contains "$STDOUT" 'revoked' || \
      assert_contains "$STDERR" 'credential' || assert_contains "$STDOUT" 'credential' || return 1
  fi
  return 0
}

test_outbox_ack_request_id_dedupe() {
  mint_workflow orchestration || return 1
  [[ -n $REAL_JQ ]] || return 1
  local device cred
  device="dev-dedupe-$(printf '%04x' $$)"
  cred="cred-dedupe-$(printf '%04x' $$)"
  expect_success device-register \
    --device-id "$device" --credential "$cred" \
    --build-type sandbox --request-id "req-reg5-$$" || return 1
  expect_success feed-append orchestration awaiting-approval "$WORKFLOW_ID" 40 || return 1

  local ack_id device_dir
  ack_id="req-ob-ack-$$"
  device_dir="$WF_ROOT/outbox/$device"
  expect_success outbox-ack \
    --device-id "$device" --credential "$cred" \
    --request-id "$ack_id" --seq 40 || return 1
  cp "$STDOUT" "$STDOUT2"
  local first_outcome first_status cursor_after_first snap_before
  first_outcome=$(cat "$STDOUT")
  first_status=$(json_string "$STDOUT2" status)
  cursor_after_first=$(json_string "$STDOUT2" cursor)
  [[ -n $cursor_after_first ]] || return 1
  [[ -d $device_dir ]] || return 1
  # Durable ledger record for this requestId MUST exist after first ack.
  local ledger_hits
  ledger_hits=$(grep -rF -- "$ack_id" "$device_dir" 2>/dev/null | wc -l | tr -d ' ')
  [[ ${ledger_hits:-0} -ge 1 ]] || return 1
  snap_before=$(state_fingerprint "$device_dir")

  # Same requestId ack is a pure replay — outcome equality, no state mutation.
  expect_success outbox-ack \
    --device-id "$device" --credential "$cred" \
    --request-id "$ack_id" --seq 40 || return 1
  assert_contains "$STDOUT" "$ack_id" || return 1
  local second_status cursor_after_second snap_after
  second_status=$(json_string "$STDOUT" status)
  cursor_after_second=$(json_string "$STDOUT" cursor)
  [[ $cursor_after_first == "$cursor_after_second" ]] || return 1
  if [[ -n $first_status && -n $second_status ]]; then
    [[ $first_status == "$second_status" ]] || return 1
  fi
  # Exactly-once: device outbox fingerprint unchanged on replay.
  snap_after=$(state_fingerprint "$device_dir")
  [[ $snap_before == "$snap_after" ]] || return 1
  # Ledger still names the requestId (not erased, not duplicated unboundedly).
  local ledger_hits2
  ledger_hits2=$(grep -rF -- "$ack_id" "$device_dir" 2>/dev/null | wc -l | tr -d ' ')
  [[ ${ledger_hits2:-0} -eq ${ledger_hits:-0} ]] || return 1

  # Fetch must not return the acked seq 40 as undelivered.
  expect_success outbox-fetch \
    --device-id "$device" --credential "$cred" --cursor 0 || return 1
  jq -e '
    [(.records // .batch // .events // [])[]
      | select(((.seq // 0) | tonumber) == 40)]
    | length == 0
  ' "$STDOUT" >/dev/null 2>&1 || return 1
  return 0
}

test_concurrent_ack_append_races_never_lose_or_duplicate() {
  mint_workflow orchestration || return 1
  [[ -n $REAL_JQ ]] || return 1
  local device cred
  device="dev-race-$(printf '%04x' $$)"
  cred="cred-race-$(printf '%04x' $$)"
  expect_success device-register \
    --device-id "$device" --credential "$cred" \
    --build-type sandbox --request-id "req-reg6-$$" || return 1

  # Seed one record, then race two acks of seq 50 (different requestIds) + appends.
  expect_success feed-append orchestration needs-input "$WORKFLOW_ID" 50 || return 1

  [[ -x $REGISTRY ]] || return 1

  local race_dir=$CASE/race
  mkdir -p "$race_dir"
  local i ack_win_id ack_lose_id
  ack_win_id="req-race-ack-win-$$"
  ack_lose_id="req-race-ack-lose-$$"
  for i in 51 52 53 54 55; do
    (
      env -i \
        HOME="$HOME_DIR" \
        XDG_STATE_HOME="$STATE_ROOT" \
        PATH="$BASE_PATH" \
        HOSTNAME="$HOSTNAME_FIXTURE" \
        WORKFLOW_REGISTRY_TEST=1 \
        REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
        REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
        "$REGISTRY" feed-append orchestration completed "$WORKFLOW_ID" "$i" \
        >"$race_dir/append-$i.out" 2>"$race_dir/append-$i.err"
      echo $? >"$race_dir/append-$i.status"
    ) &
  done
  (
    env -i \
      HOME="$HOME_DIR" \
      XDG_STATE_HOME="$STATE_ROOT" \
      PATH="$BASE_PATH" \
      HOSTNAME="$HOSTNAME_FIXTURE" \
      WORKFLOW_REGISTRY_TEST=1 \
      REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
      REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
      "$REGISTRY" outbox-ack \
        --device-id "$device" --credential "$cred" \
        --request-id "$ack_win_id" --seq 50 \
      >"$race_dir/ack-win.out" 2>"$race_dir/ack-win.err"
    echo $? >"$race_dir/ack-win.status"
  ) &
  (
    env -i \
      HOME="$HOME_DIR" \
      XDG_STATE_HOME="$STATE_ROOT" \
      PATH="$BASE_PATH" \
      HOSTNAME="$HOSTNAME_FIXTURE" \
      WORKFLOW_REGISTRY_TEST=1 \
      REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
      REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
      "$REGISTRY" outbox-ack \
        --device-id "$device" --credential "$cred" \
        --request-id "$ack_lose_id" --seq 50 \
      >"$race_dir/ack-lose.out" 2>"$race_dir/ack-lose.err"
    echo $? >"$race_dir/ack-lose.status"
  ) &
  wait

  # Assert BOTH ack operation statuses were recorded.
  [[ -f $race_dir/ack-win.status && -f $race_dir/ack-lose.status ]] || return 1
  local st_win st_lose winners losers winner_id
  st_win=$(tr -d ' \n' <"$race_dir/ack-win.status")
  st_lose=$(tr -d ' \n' <"$race_dir/ack-lose.status")
  [[ -n $st_win && -n $st_lose ]] || return 1
  winners=0
  losers=0
  winner_id=
  if [[ $st_win -eq 0 ]]; then
    winners=$((winners + 1))
    winner_id=$ack_win_id
  else
    losers=$((losers + 1))
  fi
  if [[ $st_lose -eq 0 ]]; then
    winners=$((winners + 1))
    winner_id=$ack_lose_id
  else
    losers=$((losers + 1))
  fi
  # Exactly one winner acked (status 0), exactly one loser refused (status != 0).
  # Ack is never lost: winners must be 1.
  [[ $winners -eq 1 && $losers -eq 1 ]] || return 1
  [[ -n $winner_id ]] || return 1
  # Durable ledger records the winner requestId exactly once (not the loser).
  local device_dir hits_winner hits_loser loser_id
  device_dir="$WF_ROOT/outbox/$device"
  [[ -d $device_dir ]] || return 1
  if [[ $winner_id == "$ack_win_id" ]]; then
    loser_id=$ack_lose_id
  else
    loser_id=$ack_win_id
  fi
  hits_winner=$(grep -rF -- "$winner_id" "$device_dir" 2>/dev/null | wc -l | tr -d ' ')
  hits_loser=$(grep -rF -- "$loser_id" "$device_dir" 2>/dev/null | wc -l | tr -d ' ')
  [[ ${hits_winner:-0} -ge 1 ]] || return 1
  [[ ${hits_loser:-0} -eq 0 ]] || return 1

  # All append operations must report status (assert every status file).
  for i in 51 52 53 54 55; do
    [[ -f $race_dir/append-$i.status ]] || return 1
    local st_a
    st_a=$(tr -d ' \n' <"$race_dir/append-$i.status")
    [[ $st_a -eq 0 ]] || return 1
  done

  expect_success outbox-fetch \
    --device-id "$device" --credential "$cred" --cursor 0 || return 1

  # Exactly-one-winner by identity: each completed seq 51–55 appears exactly once.
  local s count_s
  for s in 51 52 53 54 55; do
    count_s=$(jq -r --argjson seq "$s" '
      [(.records // .batch // .events // [])[]
        | select((.class // .eventClass) == "completed"
            and ((.seq // 0) | tonumber) == $seq)]
      | length
    ' "$STDOUT")
    [[ ${count_s:-0} -eq 1 ]] || return 1
  done
  # Ack is NEVER lost: needs-input seq 50 is absent from undelivered (exactly once acked).
  local needs_count
  needs_count=$(jq -r '
    [(.records // .batch // .events // [])[]
      | select((.class // .eventClass) == "needs-input"
          and ((.seq // 0) | tonumber) == 50)]
    | length
  ' "$STDOUT")
  [[ ${needs_count:-0} -eq 0 ]] || return 1

  # Total completed records exactly 5 (no duplicate winners).
  local completed_count
  completed_count=$(jq -r '
    [(.records // .batch // .events // [])[]
      | select((.class // .eventClass) == "completed")]
    | length
  ' "$STDOUT")
  [[ ${completed_count:-0} -eq 5 ]] || return 1

  # Privacy whitelist on race results.
  outbox_record_keys_allowed "$STDOUT" || return 1
  assert_lacks "$STDOUT" "$cred" || return 1
  return 0
}

test_outbox_records_are_class_plus_opaque_reference_only() {
  mint_workflow orchestration || return 1
  local device cred
  device="dev-priv-$(printf '%04x' $$)"
  cred="cred-priv-$(printf '%04x' $$)"
  expect_success device-register \
    --device-id "$device" --credential "$cred" \
    --build-type sandbox --request-id "req-reg7-$$" || return 1
  expect_success feed-append orchestration chat-question "$WORKFLOW_ID" 60 || return 1

  expect_success outbox-fetch \
    --device-id "$device" --credential "$cred" --cursor 0 || return 1
  assert_contains "$STDOUT" 'chat-question' || return 1
  # Opaque reference present (workflow id).
  assert_contains "$STDOUT" "$WORKFLOW_ID" || return 1
  # WHITELIST: every record keys ⊆ class + opaque ref (+ transport seq/cursor).
  outbox_record_keys_allowed "$STDOUT" || return 1
  # Credential material never on the wire.
  assert_lacks "$STDOUT" "$cred" || return 1
  return 0
}

# ── runner ─────────────────────────────────────────────────────────────────

# Prove the hermetic fixture before the behavioral cases.
setup_case fixture-self-test
if [[ -d $STATE_ROOT && -d $HOME_DIR && -d $CHECKOUT && -f $PLAN_DIR/plan.json ]]; then
  pass 'hermetic journal fixture self-test'
else
  fail 'hermetic journal fixture self-test' 'private fixture could not be initialized'
fi

if [[ ! -x $REGISTRY ]]; then
  # Still emit an explicit gate failure, then run every case so the green
  # implementer sees the full red surface (each case fails closed).
  fail 'workflow-registry executable exists' "missing executable: $REGISTRY"
fi

# 1. journal / wait
run_test 'wait replays the full journal from :0 and only the tail from a mid-cursor' \
  test_wait_replays_from_zero_and_mid_cursor
run_test 'supervisor restart records stay inside one durable journal epoch' \
  test_supervisor_restart_stays_inside_one_journal_epoch
run_test 'reconcile-at-read heals a dropped journal-pending projection' \
  test_reconcile_at_read_heals_dropped_projection

# 2. latch / ack
run_test 'latch raises, supersedes on newer input-needed, and acks on matching seq' \
  test_latch_raise_supersede_and_ack
run_test 'ack of a superseded seq refuses stale-ack' \
  test_stale_ack_is_refused
run_test 'needs-input latch survives a supervisor epoch wipe' \
  test_latch_survives_epoch_wipe

# 3. queue-one (D1)
run_test 'queue-one stores a single pending message with 0600 payload and digest' \
  test_queue_one_stores_single_pending_with_0600_and_digest
run_test 'a second send while one message is pending refuses queue-full' \
  test_second_send_refuses_queue_full
run_test 'send --cancel-pending removes the pending message and is idempotent' \
  test_cancel_pending_is_idempotent
run_test 'delivery requires a fresh latch, journals delivered-from-queue, and is requestId-deduped' \
  test_delivery_requires_fresh_latch_and_journals_delivered_from_queue

# 4. idempotency / digest / wait bound
run_test 'duplicate relay-minted requestId replays the recorded outcome without re-execution' \
  test_duplicate_request_id_replays_recorded_outcome
run_test 'reused requestId with a different payload digest fails closed' \
  test_reused_request_id_with_different_digest_fails_closed
run_test '--payload-sha256 mismatch refuses before any delivery or ack' \
  test_payload_sha256_mismatch_refuses_before_delivery
run_test 'wait is one bounded blocking call ≤300s returning batch+cursor+phase+latch' \
  test_wait_is_one_bounded_blocking_call

# 5. locks + feed
run_test 'a dead-pid registry lock is broken and the break is journaled' \
  test_dead_pid_lock_is_broken_and_journaled
run_test 'a live-pid registry lock refuses busy' \
  test_live_pid_lock_refuses_busy
run_test 'notification feed appends closed-class labels-only records with class+entityId+seq dedup' \
  test_feed_appends_closed_class_labels_only_with_dedup

# 6. outbox / device (notificationTransport)
run_test 'device-register and device-revoke are guarded registry ops' \
  test_device_register_and_revoke
run_test 'outbox derives from the feed with a durable per-device cursor and reconnect replay' \
  test_outbox_derives_from_feed_with_durable_cursor_and_replay
run_test 'delivery failure never erases outbox events' \
  test_delivery_failure_never_erases_outbox_events
run_test 'a revoked device credential fetches nothing' \
  test_revoked_device_credential_fetches_nothing
run_test 'per-device outbox ack is requestId-deduped' \
  test_outbox_ack_request_id_dedupe
run_test 'concurrent ack/append races never lose or duplicate an outbox record' \
  test_concurrent_ack_append_races_never_lose_or_duplicate
run_test 'outbox records carry event class and opaque reference ONLY' \
  test_outbox_records_are_class_plus_opaque_reference_only

printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
