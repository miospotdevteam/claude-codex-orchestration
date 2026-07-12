#!/usr/bin/env bash
set -euo pipefail

# RED contract for scripts/remote-agent.sh after the desktop helper becomes a
# stateless relay.  The Mini registry owns every workflow decision; this file
# deliberately refuses to preserve the old client-side conductor/sync engine.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REMOTE_AGENT="$SCRIPT_DIR/../../scripts/remote-agent.sh"
PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
SUITE=$(cd "$SUITE" && pwd -P)
trap 'rm -rf "$SUITE"' EXIT

pass() { printf 'PASS %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_contains() { grep -Fq -- "$2" "$1"; }
assert_lacks() { ! grep -Fq -- "$2" "$1"; }
assert_count() { [[ $(grep -Fc -- "$2" "$1" 2>/dev/null || true) -eq $3 ]]; }

setup_case() {
  local name=$1
  CASE="$SUITE/$name"
  HOME_DIR="$CASE/home"
  STATE_DIR="$CASE/state"
  CHECKOUT="$CASE/orchestration"
  FAKE_BIN="$CASE/bin"
  SSH_LOG="$CASE/ssh.log"
  SSH_STDIN="$CASE/ssh.stdin"
  STDOUT="$CASE/stdout"
  STDERR="$CASE/stderr"
  MINI_STATE="$CASE/mini-state"
  mkdir -p "$HOME_DIR" "$STATE_DIR" "$CHECKOUT" "$FAKE_BIN" "$MINI_STATE"
  : >"$SSH_LOG"
  : >"$SSH_STDIN"
  : >"$STDOUT"
  : >"$STDERR"
  printf 'mini-authority-sentinel\n' >"$MINI_STATE/authority"
  printf '.env.local\n' >"$CHECKOUT/.gitignore"
  printf 'tracked\n' >"$CHECKOUT/README.md"
  printf 'ignored seed\n' >"$CHECKOUT/.env.local"
  git -C "$CHECKOUT" init -q
  git -C "$CHECKOUT" add .gitignore README.md
  git -C "$CHECKOUT" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture

  cat >"$FAKE_BIN/ssh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
: "${SSH_LOG:?}" "${SSH_STDIN:?}" "${MINI_STATE:?}"
host=${1:-}
shift || true
remote_command=$*
parsed=$(mktemp "${TMPDIR:-/tmp}/relay-argv.XXXXXX")
/bin/sh -c "set -- $remote_command
printf '%s\\0' \"\$@\"" >"$parsed"
argv=()
while IFS= read -r -d '' argument; do argv+=("$argument"); done <"$parsed"
rm -f "$parsed"

{
  printf 'CALL\nARG\t%s\n' "$host"
  for argument in "${argv[@]}"; do printf 'ARG\t%s\n' "$argument"; done
  printf 'END\n'
} >>"$SSH_LOG"
cat >>"$SSH_STDIN"

request_id=
for ((i=0; i<${#argv[@]}; i++)); do
  if [[ ${argv[$i]} == --request-id && $((i + 1)) -lt ${#argv[@]} ]]; then
    request_id=${argv[$((i + 1))]}
  fi
done

# A read-only list is the only operation used by the client-close proof.  Any
# additional Mini-side operation makes the fixture state observably different,
# so a relay that tries to clean up remotely when its local client disappears
# cannot pass by construction.
operation=${argv[1]:-}
if [[ $operation != list ]]; then
  printf '%s\n' "$operation" >>"$MINI_STATE/transport-mutations"
fi

case ${SSH_MODE:-success} in
  success)
    printf '{"ok":true,"requestId":"%s","status":"ok"}\n' "$request_id"
    ;;
  queued)
    printf '{"ok":true,"requestId":"%s","status":"queued"}\n' "$request_id"
    ;;
  diagnostic-held)
    printf '%s\n' '{"ok":true,"workflows":[{"project":"miospot","phase":"diagnostic-held"}]}'
    ;;
  queue-full)
    printf '%s\n' '{"ok":false,"error":"queue-full","message":"one message is already pending"}'
    exit 75
    ;;
  stale-ack)
    printf '%s\n' '{"ok":false,"error":"stale-ack","message":"a newer input event is pending"}'
    exit 65
    ;;
  mini-offline)
    printf 'ssh: connect to host fixture-mini: Connection refused\n' >&2
    exit 255
    ;;
  *)
    printf '%s\n' '{"ok":false,"error":"fixture-mode"}'
    exit 70
    ;;
esac
MOCK
  chmod +x "$FAKE_BIN/ssh"
}

run_helper() {
  local mode=$1
  shift
  : >"$SSH_LOG"
  : >"$SSH_STDIN"
  : >"$STDOUT"
  : >"$STDERR"
  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_DIR" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    REMOTE_AGENT_HOST=fixture-mini \
    LOCAL_MIOSPOT_ROOT="$CHECKOUT" \
    LOCAL_ORCHESTRATION_ROOT="$CHECKOUT" \
    SSH_LOG="$SSH_LOG" \
    SSH_STDIN="$SSH_STDIN" \
    MINI_STATE="$MINI_STATE" \
    SSH_MODE="$mode" \
    "$REMOTE_AGENT" "$@" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
}

combined_output() { cat "$STDOUT" "$STDERR"; }

registry_request_id() {
  awk '$0 == "ARG\t--request-id" { getline; sub(/^ARG\t/, ""); print; exit }' "$SSH_LOG"
}

assert_one_registry_op() {
  local operation=$1
  assert_count "$SSH_LOG" 'CALL' 1 || return 1
  awk -F $'\t' '$1 == "ARG" && $2 ~ /(^|\/)workflow-registry$/ { found=1 } END { exit !found }' \
    "$SSH_LOG" || return 1
  assert_count "$SSH_LOG" $'ARG\t'"$operation" 1 || return 1
  assert_lacks "$SSH_LOG" 'remote-agent-v1' || return 1
  assert_lacks "$SSH_LOG" 'agent-supervisor' || return 1
  assert_lacks "$SSH_LOG" 'run-codex-' || return 1
  assert_lacks "$SSH_LOG" 'run-grok-'
}

test_registry_op_anchor_matches_tab_delimited_log() {
  cat >"$SSH_LOG" <<'EOF'
CALL
ARG	/opt/orchestration/workflow-registry
ARG	list
END
EOF
  assert_one_registry_op list
}

assert_mutating_outcome() {
  local request_id
  request_id=$(registry_request_id)
  [[ -n $request_id ]] || return 1
  combined_output | grep -Fq -- "$request_id"
}

run_test() {
  local name=$1
  shift
  setup_case "test-$((PASS_COUNT + FAIL_COUNT + 1))"
  STATUS=0
  if "$@"; then
    pass "$name"
  else
    fail "$name" "status=$STATUS stdout=$(tr '\n' ' ' <"$STDOUT" 2>/dev/null || true) stderr=$(tr '\n' ' ' <"$STDERR" 2>/dev/null || true)"
  fi
}

test_read_verb_maps_once() {
  local verb=$1 operation=$2
  shift 2
  run_helper success "$verb" "$@"
  [[ $STATUS -eq 0 ]] || return 1
  assert_one_registry_op "$operation"
}

test_mutating_verb_maps_once() {
  local verb=$1 operation=$2
  shift 2
  run_helper success "$verb" "$@"
  [[ $STATUS -eq 0 ]] || return 1
  assert_one_registry_op "$operation" || return 1
  assert_mutating_outcome
}

test_sync_cancel_maps_to_mirror_cancel() {
  run_helper success sync wf-miospot-20260711T151201Z-9f3c --cancel job-17
  [[ $STATUS -eq 0 ]] || return 1
  assert_one_registry_op mirror-cancel || return 1
  assert_mutating_outcome
}

test_request_id_reuse_is_exact() {
  local wanted=req-relay-retry-0001 actual
  printf 'retry payload\n' >"$CASE/prompt"
  run_helper success send wf-miospot-20260711T151201Z-9f3c \
    --prompt-file "$CASE/prompt" --request-id "$wanted"
  [[ $STATUS -eq 0 ]] || return 1
  actual=$(registry_request_id)
  [[ $actual == "$wanted" ]] || return 1
  assert_contains "$STDOUT" "$wanted"
}

test_failed_mutation_prints_pre_send_request_id() {
  printf 'queued input\n' >"$CASE/prompt"
  run_helper queue-full send wf-miospot-20260711T151201Z-9f3c --prompt-file "$CASE/prompt"
  [[ $STATUS -ne 0 ]] || return 1
  assert_one_registry_op send || return 1
  assert_contains "$STDOUT" 'queue-full' || assert_contains "$STDERR" 'queue-full' || return 1
  assert_mutating_outcome || return 1
  (( $(combined_output | wc -c | tr -d ' ') <= 4096 ))
}

test_busy_send_queues_without_conductor_busy() {
  printf 'queue me\n' >"$CASE/prompt"
  run_helper queued send wf-miospot-20260711T151201Z-9f3c --prompt-file "$CASE/prompt"
  [[ $STATUS -eq 0 ]] || return 1
  assert_one_registry_op send || return 1
  assert_contains "$STDOUT" 'queued' || return 1
  assert_lacks "$STDOUT" 'conductor-busy' || return 1
  assert_lacks "$STDERR" 'conductor-busy'
}

test_cancel_pending_is_same_send_op() {
  run_helper success send wf-miospot-20260711T151201Z-9f3c --cancel-pending
  [[ $STATUS -eq 0 ]] || return 1
  assert_one_registry_op send || return 1
  assert_contains "$SSH_LOG" $'ARG\t--cancel-pending' || return 1
  assert_mutating_outcome || return 1
  (( $(combined_output | wc -c | tr -d ' ') <= 4096 ))
}

test_ack_event_is_forwarded_as_data() {
  printf 'answer\n' >"$CASE/prompt"
  run_helper stale-ack send wf-miospot-20260711T151201Z-9f3c \
    --prompt-file "$CASE/prompt" --ack-event 17
  [[ $STATUS -ne 0 ]] || return 1
  assert_one_registry_op send || return 1
  assert_contains "$SSH_LOG" $'ARG\t--ack-event' || return 1
  assert_contains "$SSH_LOG" $'ARG\t17' || return 1
  combined_output | grep -Fq 'stale-ack' || return 1
  assert_mutating_outcome
}

test_diagnostic_family_takes_registry_lease() {
  run_helper success diagnostic start miospot codex
  [[ $STATUS -eq 0 ]] || return 1
  assert_one_registry_op diagnostic-start || return 1
  assert_mutating_outcome || return 1

  run_helper diagnostic-held list
  [[ $STATUS -eq 0 ]] || return 1
  assert_one_registry_op list || return 1
  assert_contains "$STDOUT" 'diagnostic-held'
}

test_explicit_host_precedes_environment() {
  run_helper success --host cli-mini list
  [[ $STATUS -eq 0 ]] || return 1
  assert_one_registry_op list || return 1
  assert_contains "$SSH_LOG" $'ARG\tcli-mini' || return 1
  assert_lacks "$SSH_LOG" $'ARG\tfixture-mini'
}

test_hostile_argv_is_rejected_as_data_before_network() {
  local marker="$CASE/PWNED"
  run_helper success inspect 'wf-miospot-20260711T151201Z-9f3c;touch PWNED'
  [[ $STATUS -ne 0 ]] || return 1
  [[ ! -e $marker ]] || return 1
  [[ ! -s $SSH_LOG ]] || return 1
  (( $(combined_output | wc -c | tr -d ' ') <= 4096 ))
}

test_unknown_and_removed_client_orchestration_refuse() {
  local invocation
  for invocation in \
    'dance' \
    'continue wf-miospot-20260711T151201Z-9f3c' \
    'status miospot' \
    'reclaim miospot' \
    'start-conductor miospot selected --with-plan selected' \
    'start-conductor miospot selected --active-plan selected'; do
    # shellcheck disable=SC2086 -- fixture words intentionally form argv.
    run_helper success $invocation
    [[ $STATUS -ne 0 ]] || return 1
    [[ ! -s $SSH_LOG ]] || return 1
    (( $(combined_output | wc -c | tr -d ' ') <= 4096 )) || return 1
  done
}

test_source_has_no_client_orchestration_or_marker_writer() {
  local forbidden
  for forbidden in \
    'run-codex-impl' 'run-codex-verify' 'run-grok-impl' 'run-grok-verify' \
    'plan-utils.sh' 'set-frontier' 'start-step' 'record-verdict' \
    'mini-workflow.json' '.temp/plan-mode' '--with-plan' '--active-plan'; do
    assert_lacks "$REMOTE_AGENT" "$forbidden" || return 1
  done
}

test_relay_writes_no_local_state_or_marker() {
  local before after
  before=$(find "$HOME_DIR" "$STATE_DIR" -type f -print -exec shasum -a 256 {} \; | LC_ALL=C sort)
  run_helper success list
  [[ $STATUS -eq 0 ]] || return 1
  after=$(find "$HOME_DIR" "$STATE_DIR" -type f -print -exec shasum -a 256 {} \; | LC_ALL=C sort)
  [[ $after == "$before" ]] || return 1
  ! find "$CASE" -name mini-workflow.json -print | grep -q .
}

test_prompt_is_bounded_stdin_only_and_hashed_locally() {
  local secret='RELAY-STDIN-CANARY' expected
  printf '%s\n' "$secret" >"$CASE/prompt"
  expected=$(shasum -a 256 "$CASE/prompt" | awk '{print $1}')
  run_helper success send wf-miospot-20260711T151201Z-9f3c --prompt-file "$CASE/prompt"
  [[ $STATUS -eq 0 ]] || return 1
  assert_one_registry_op send || return 1
  assert_contains "$SSH_STDIN" "$secret" || return 1
  assert_lacks "$SSH_LOG" "$secret" || return 1
  assert_lacks "$STDOUT" "$secret" || return 1
  assert_lacks "$STDERR" "$secret" || return 1
  assert_contains "$SSH_LOG" $'ARG\t--payload-sha256' || return 1
  assert_contains "$SSH_LOG" "$expected" || return 1

  printf '%65537s' '' >"$CASE/oversized"
  run_helper success send wf-miospot-20260711T151201Z-9f3c --prompt-file "$CASE/oversized"
  [[ $STATUS -ne 0 ]] || return 1
  [[ ! -s $SSH_LOG ]] || return 1
  combined_output | grep -Fq '65536' || return 1
}

test_mini_offline_is_bounded_and_keeps_request_id() {
  printf 'offline input\n' >"$CASE/prompt"
  run_helper mini-offline send wf-miospot-20260711T151201Z-9f3c --prompt-file "$CASE/prompt"
  [[ $STATUS -ne 0 ]] || return 1
  assert_count "$SSH_LOG" CALL 1 || return 1
  combined_output | grep -Fq 'mini-unreachable' || return 1
  assert_mutating_outcome || return 1
  (( $(combined_output | wc -c | tr -d ' ') <= 4096 ))
}

test_client_close_has_no_mini_side_effect() {
  local probe_before probe_after before after
  probe_before=$(find "$MINI_STATE" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort)
  SSH_LOG="$SSH_LOG" SSH_STDIN="$SSH_STDIN" MINI_STATE="$MINI_STATE" SSH_MODE=success \
    "$FAKE_BIN/ssh" fixture-mini \
      "'/opt/orchestration/workflow-registry' 'release'" >/dev/null
  probe_after=$(find "$MINI_STATE" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort)
  [[ $probe_after != "$probe_before" ]] || return 1
  rm -f "$MINI_STATE/transport-mutations"

  before=$(find "$MINI_STATE" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort)
  run_helper success list
  [[ $STATUS -eq 0 ]] || return 1
  assert_one_registry_op list || return 1
  rm -rf "$HOME_DIR" "$STATE_DIR"
  after=$(find "$MINI_STATE" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort)
  [[ $after == "$before" ]]
}

test_refusal_hard_stops_after_one_registry_call() {
  printf 'answer\n' >"$CASE/prompt"
  run_helper stale-ack send wf-miospot-20260711T151201Z-9f3c \
    --prompt-file "$CASE/prompt" --ack-event 17
  [[ $STATUS -ne 0 ]] || return 1
  assert_count "$SSH_LOG" CALL 1 || return 1
  assert_lacks "$SSH_LOG" 'lease-release' || return 1
  assert_lacks "$SSH_LOG" 'mirror-next' || return 1
  (( $(combined_output | wc -c | tr -d ' ') <= 4096 ))
}

test_seed_consent_identical_approval() {
  run_helper success sync wf-miospot-20260711T151201Z-9f3c --seed \
    --include-ignored .env.local
  [[ $STATUS -ne 0 ]] || return 1
  [[ ! -s $SSH_LOG ]] || return 1
  combined_output | grep -Fq 'ignored path needs identical explicit approval'
}

test_seed_consent_literal_path_no_glob() {
  run_helper success sync wf-miospot-20260711T151201Z-9f3c --seed \
    --include-ignored '.env*' --approve-ignored '.env*'
  [[ $STATUS -ne 0 ]] || return 1
  [[ ! -s $SSH_LOG ]] || return 1
  combined_output | grep -Fq 'ignored approval must name one literal path'
}

test_seed_consent_path_must_be_ignored() {
  run_helper success sync wf-miospot-20260711T151201Z-9f3c --seed \
    --include-ignored README.md --approve-ignored README.md
  [[ $STATUS -ne 0 ]] || return 1
  [[ ! -s $SSH_LOG ]] || return 1
  combined_output | grep -Fq 'approved seed path must be ignored'
}

test_seed_consent_forwards_one_exact_exception() {
  run_helper success sync wf-miospot-20260711T151201Z-9f3c --seed \
    --include-ignored .env.local --approve-ignored .env.local
  [[ $STATUS -eq 0 ]] || return 1
  assert_one_registry_op request-mirror-sync || return 1
  assert_count "$SSH_LOG" $'ARG\t.env.local' 2 || return 1
  assert_mutating_outcome
}

# Disposition schema: old-case|preserved-in=... / re-hosted-to=... /
# superseded-because=...|bounded rationale.  The three legacy_* rows are the
# deleted plan-seed/client-marker cases called out by R7 even though they were
# design cases rather than registrations in the immediately preceding suite.
OLD_CASES=$(cat <<'EOF'
test_validation
test_closed_mapping_and_host_precedence
test_project_mapping_ignores_decoy_git_cwd
test_project_mapping_defaults_and_rejects_invalid_roots
test_relative_prompt_file_is_independent_of_mapped_root
test_hostile_argv_is_data
test_exact_sessions
test_inspect_captures_without_sync
test_inspect_capture_is_visible
test_continue_captures_before_send
test_wait_requires_a_bounded_cursor_and_timeout
test_wait_delegates_exact_sessions_for_every_harness
test_wait_surfaces_timeout_exit_and_event_wakes
test_wait_exit_recheck_refuses_a_restarted_session
test_wait_preserves_monotonic_restart_aware_cursors
test_start_and_status_expose_direct_wait_bootstrap_without_leakage
test_wait_capture_is_visible_bounded_and_not_persisted_locally
test_reveal_delegates_exact_terminal_attachment_without_mutation
test_prompt_is_bounded_and_redacted
test_control_lifecycle
test_start_local_only_transfer
test_start_accepts_optional_prompt
test_supervisor_rejects_legacy_launch_verb
test_codex_uses_shared_supervisor
test_start_forwards_yolo_exactly
test_failed_supervisor_start_aborts_provisional_lease
test_supervisor_prompt_transport_is_stdin_only
test_start_refuses_live_writer_and_divergence
test_first_contact_rules
test_snapshot_is_strong_and_nul_safe
test_divergence_matrix
test_remote_lease_mutex_and_cas
test_writer_records_fail_closed_without_stale_inference
test_transfer_universe_and_deletions
test_ignored_paths_need_exact_consent
test_active_plan_is_bounded_and_stable
test_private_staging_and_restore_journal
test_network_staging_failure_stops_before_apply
test_failed_apply_restores_before_state_change
test_nonzero_apply_status_restores_before_state_change
test_failed_restore_preserves_recovery_evidence
test_reclaim_remote_only_release_last
test_outbound_handoff_requests_bundle_and_exact_git_alignment
test_reclaim_fast_forwards_branch_and_resets_index_mixed
test_reclaim_refuses_non_fast_forward_without_ref_mutation
test_refusal_paths_never_mutate_git_refs_or_index
test_equal_quiescent_reclaim_releases_without_transfer
test_local_only_quiescent_reclaim_releases_without_transfer
test_reclaim_stages_before_local_apply
test_reclaim_refuses_live_writer_before_transfer
test_post_sync_mismatch_keeps_lease
test_real_backend_adapter_over_fake_ssh
legacy_with_plan_seed_trio
legacy_client_side_mini_workflow_marker
legacy_stale_client_marker_clear
EOF
)

DISPOSITION_TABLE=$(cat <<'EOF'
test_validation|preserved-in=remote-agent.test.sh#test_unknown_and_removed_client_orchestration_refuse|closed verbs and bounded unknown refusal
test_closed_mapping_and_host_precedence|preserved-in=remote-agent.test.sh#test_explicit_host_precedes_environment|explicit and configured Mini host remain transport inputs
test_project_mapping_ignores_decoy_git_cwd|re-hosted-to=mirror-worker.test.sh#test_worker_roots_default_and_invalid_refusals|checkout discovery belongs to the mechanical worker
test_project_mapping_defaults_and_rejects_invalid_roots|re-hosted-to=mirror-worker.test.sh#test_worker_roots_default_and_invalid_refusals|worker validates its configured checkout
test_relative_prompt_file_is_independent_of_mapped_root|preserved-in=remote-agent.test.sh#test_prompt_is_bounded_stdin_only_and_hashed_locally|prompt resolution remains relay-local
test_hostile_argv_is_data|preserved-in=remote-agent.test.sh#test_registry_op_anchor_matches_tab_delimited_log|one serialized registry argv and closed atoms
test_exact_sessions|re-hosted-to=workflow-registry.test.sh#test_mint_workflow_id_format|registry owns workflow and session binding
test_inspect_captures_without_sync|preserved-in=remote-agent.test.sh#test_read_verb_maps_once|inspect is one read-only registry op
test_inspect_capture_is_visible|preserved-in=remote-agent.test.sh#test_read_verb_maps_once|bounded registry response is surfaced
test_continue_captures_before_send|superseded-because=start-conductor-and-send-are-separate-closed-ops|client continue orchestration is deleted
test_wait_requires_a_bounded_cursor_and_timeout|preserved-in=remote-agent.test.sh#test_read_verb_maps_once|relay forwards one bounded wait
test_wait_delegates_exact_sessions_for_every_harness|re-hosted-to=workflow-journal.test.sh#test_wait_is_one_bounded_blocking_call|registry journal replaces harness waits
test_wait_surfaces_timeout_exit_and_event_wakes|re-hosted-to=workflow-journal.test.sh#test_wait_is_one_bounded_blocking_call|durable journal owns wake classification
test_wait_exit_recheck_refuses_a_restarted_session|superseded-because=registry-cursor-is-restart-durable|client recheck loop is deleted
test_wait_preserves_monotonic_restart_aware_cursors|re-hosted-to=workflow-journal.test.sh#test_wait_replays_from_zero_and_mid_cursor|registry cursor replaces supervisor epoch cursor
test_start_and_status_expose_direct_wait_bootstrap_without_leakage|superseded-because=list-and-start-conductor-return-registry-cursors|status alias is deleted
test_wait_capture_is_visible_bounded_and_not_persisted_locally|preserved-in=remote-agent.test.sh#test_client_close_has_no_mini_side_effect|relay keeps no wait state
test_reveal_delegates_exact_terminal_attachment_without_mutation|preserved-in=remote-agent.test.sh#test_mutating_verb_maps_once|reveal is one bounded registry op
test_prompt_is_bounded_and_redacted|preserved-in=remote-agent.test.sh#test_prompt_is_bounded_stdin_only_and_hashed_locally|64KiB stdin-only and digest assertions retained
test_control_lifecycle|preserved-in=remote-agent.test.sh#test_mutating_verb_maps_once|interrupt kill and release map one-to-one
test_start_local_only_transfer|superseded-because=start-conductor-never-mirrors-client-content|mirror queue is a separate operation
test_start_accepts_optional_prompt|superseded-because=start-conductor-and-send-are-separate-idempotent-ops|combined client transaction is deleted
test_supervisor_rejects_legacy_launch_verb|re-hosted-to=workflow-registry.test.sh#test_start_conductor_is_claude_only|registry composes the fixed supervisor start verb
test_codex_uses_shared_supervisor|re-hosted-to=workflow-registry.test.sh#test_diagnostic_held_refuses_start_conductor_boundedly|diagnostic family is registry guarded
test_start_forwards_yolo_exactly|re-hosted-to=workflow-registry.test.sh#test_start_conductor_ordered_mutex_cas_lease|registry owns fixed conductor launch argv
test_failed_supervisor_start_aborts_provisional_lease|re-hosted-to=workflow-registry.test.sh#test_start_conductor_ordered_mutex_cas_lease|registry owns the atomic start transaction
test_supervisor_prompt_transport_is_stdin_only|preserved-in=remote-agent.test.sh#test_prompt_is_bounded_stdin_only_and_hashed_locally|relay sends prompt bytes only on stdin
test_start_refuses_live_writer_and_divergence|re-hosted-to=workflow-registry.test.sh#test_existing_protocol_refusals_surface_through_registry|registry surfaces protocol refusal unchanged
test_first_contact_rules|re-hosted-to=remote-agent-protocol.test.sh#test_probe_classifies_all_relations|protocol owns baseline adoption
test_snapshot_is_strong_and_nul_safe|re-hosted-to=mirror-worker.test.sh#test_snapshot_is_strong_and_nul_safe|worker owns strong checkout fingerprints
test_divergence_matrix|re-hosted-to=mirror-worker.test.sh#test_claim_direction_is_computed_at_claim_time|registry computes direction at claim time
test_remote_lease_mutex_and_cas|re-hosted-to=remote-agent-protocol.test.sh#test_generation_cas_never_clobbers|authority remains protocol-owned
test_writer_records_fail_closed_without_stale_inference|re-hosted-to=workflow-registry.test.sh#test_existing_protocol_refusals_surface_through_registry|registry preserves writer refusal evidence
test_transfer_universe_and_deletions|re-hosted-to=mirror-worker.test.sh#test_transfer_universe_and_deletions|worker stages tracked and ordinary untracked only
test_ignored_paths_need_exact_consent|preserved-in=remote-agent.test.sh#test_seed_consent_identical_approval|single seed exception retains all three consent guards
test_active_plan_is_bounded_and_stable|superseded-because=Mini-born-plans-delete-with-plan-handoff|plan trio never crosses the relay
test_private_staging_and_restore_journal|re-hosted-to=mirror-worker.test.sh#test_private_staging_and_restore_journal|worker and protocol own private staging
test_network_staging_failure_stops_before_apply|re-hosted-to=mirror-worker.test.sh#test_network_staging_failure_stops_before_apply|worker hard-stops failed transfer
test_failed_apply_restores_before_state_change|re-hosted-to=remote-agent-protocol.test.sh#test_staging_apply_and_verified_restore|protocol restores before authority advances
test_nonzero_apply_status_restores_before_state_change|re-hosted-to=remote-agent-protocol.test.sh#test_staging_apply_and_verified_restore|protocol handles nonzero apply identically
test_failed_restore_preserves_recovery_evidence|re-hosted-to=remote-agent-protocol.test.sh#test_alignment_failure_restores_prior_refs_index_and_content|authority preserves failed restore evidence
test_reclaim_remote_only_release_last|superseded-because=release-and-mirror-ack-are-independent-registry-ops|five-step client reclaim is deleted
test_outbound_handoff_requests_bundle_and_exact_git_alignment|re-hosted-to=mirror-worker.test.sh#test_outbound_handoff_requests_bundle_and_exact_git_alignment|step-1 assertions moved intact
test_reclaim_fast_forwards_branch_and_resets_index_mixed|re-hosted-to=mirror-worker.test.sh#test_reclaim_fast_forwards_branch_and_resets_index_mixed|step-1 assertions moved intact
test_reclaim_refuses_non_fast_forward_without_ref_mutation|re-hosted-to=mirror-worker.test.sh#test_reclaim_refuses_non_fast_forward_without_ref_mutation|step-1 refusal assertions moved intact
test_refusal_paths_never_mutate_git_refs_or_index|re-hosted-to=mirror-worker.test.sh#test_refusal_paths_never_mutate_git_refs_or_index|step-1 guard assertions moved intact
test_equal_quiescent_reclaim_releases_without_transfer|superseded-because=release-is-registry-owned-and-mirror-is-separately-queued|client reclaim branch deleted
test_local_only_quiescent_reclaim_releases_without_transfer|superseded-because=release-is-registry-owned-and-mirror-is-separately-queued|client reclaim branch deleted
test_reclaim_stages_before_local_apply|re-hosted-to=mirror-worker.test.sh#test_reclaim_stages_before_local_apply|worker receives into private staging
test_reclaim_refuses_live_writer_before_transfer|re-hosted-to=mirror-worker.test.sh#test_claim_refusal_precedes_worker_transfer|registry refuses impossible claim before worker transfer
test_post_sync_mismatch_keeps_lease|re-hosted-to=mirror-worker.test.sh#test_post_sync_mismatch_keeps_lease|divergent ack does not release authority
test_real_backend_adapter_over_fake_ssh|preserved-in=remote-agent.test.sh#test_registry_op_anchor_matches_tab_delimited_log|relay boundary is tested directly
legacy_with_plan_seed_trio|superseded-because=Mini-born-plans-delete-with-plan-handoff|deleted R7 seed plan-trio case
legacy_client_side_mini_workflow_marker|superseded-because=registry-writes-only-the-Mini-side-marker|deleted R7 client provenance case
legacy_stale_client_marker_clear|superseded-because=no-client-marker-can-become-stale|deleted R7 stale-marker case
EOF
)

assert_disposition_targets_exist() {
  local table=$1 row disposition location file anchor
  while IFS= read -r row; do
    disposition=$(printf '%s\n' "$row" | cut -d'|' -f2)
    case $disposition in
      preserved-in=*|re-hosted-to=*)
        location=${disposition#*=}
        [[ $location == *#* ]] || return 1
        file=${location%%#*}
        anchor=${location#*#}
        [[ -f $SCRIPT_DIR/$file ]] || return 1
        grep -Eq -- "^${anchor}\\(\\)[[:space:]]*\\{" "$SCRIPT_DIR/$file" || return 1
        ;;
      superseded-because=*) ;;
      *) return 1 ;;
    esac
  done <<<"$table"
}

test_disposition_table_is_complete_and_well_formed() {
  local expected actual actual_count unique_count
  expected="$CASE/expected"
  actual="$CASE/actual"
  printf '%s\n' "$OLD_CASES" | sed '/^$/d' | LC_ALL=C sort >"$expected"
  printf '%s\n' "$DISPOSITION_TABLE" | awk -F'|' '
    NF != 3 { bad=1 }
    $2 !~ /^(preserved-in|re-hosted-to|superseded-because)=/ { bad=1 }
    length($3) == 0 { bad=1 }
    { print $1 }
    END { exit bad }
  ' | LC_ALL=C sort >"$actual" || return 1
  cmp -s "$expected" "$actual" || return 1
  actual_count=$(wc -l <"$actual" | tr -d ' ')
  unique_count=$(uniq "$actual" | wc -l | tr -d ' ')
  [[ $actual_count -eq $unique_count ]] || return 1
  printf '%s\n' "$DISPOSITION_TABLE" | grep -Fq 'legacy_with_plan_seed_trio|superseded-because=' || return 1
  printf '%s\n' "$DISPOSITION_TABLE" | grep -Fq 'legacy_client_side_mini_workflow_marker|superseded-because=' || return 1
  printf '%s\n' "$DISPOSITION_TABLE" | grep -Fq 'test_ignored_paths_need_exact_consent|preserved-in=' || return 1
  printf '%s\n' "$DISPOSITION_TABLE" | grep -Fq 'test_outbound_handoff_requests_bundle_and_exact_git_alignment|re-hosted-to=mirror-worker.test.sh' || return 1
  assert_disposition_targets_exist "$DISPOSITION_TABLE" || return 1
  if assert_disposition_targets_exist \
      'phantom|re-hosted-to=mirror-worker.test.sh#test_anchor_does_not_exist|negative control'; then
    return 1
  fi
}

if [[ ! -x $REMOTE_AGENT ]]; then
  fail 'remote-agent helper exists' "missing executable: $REMOTE_AGENT"
else
  pass 'remote-agent helper exists'
fi

run_test 'registry-op helper recognizes a real tab-delimited SSH log' test_registry_op_anchor_matches_tab_delimited_log
run_test 'list maps to exactly one serialized registry list op' test_read_verb_maps_once list list
run_test 'start-conductor maps to one mutation with a pre-send requestId' test_mutating_verb_maps_once start-conductor start-conductor miospot selected
run_test 'inspect maps to exactly one serialized registry inspect op' test_read_verb_maps_once inspect inspect wf-miospot-20260711T151201Z-9f3c
printf 'map send\n' >"$SUITE/map-send-prompt"
run_test 'send maps to one mutation with a pre-send requestId' test_mutating_verb_maps_once send send wf-miospot-20260711T151201Z-9f3c --prompt-file "$SUITE/map-send-prompt"
run_test 'wait maps to exactly one bounded registry wait op' test_read_verb_maps_once wait wait wf-miospot-20260711T151201Z-9f3c --cursor jrn-fixture:0 --timeout 1
run_test 'interrupt maps to one registry mutation' test_mutating_verb_maps_once interrupt interrupt wf-miospot-20260711T151201Z-9f3c
run_test 'kill maps to one registry mutation' test_mutating_verb_maps_once kill kill wf-miospot-20260711T151201Z-9f3c
run_test 'release maps to one registry mutation' test_mutating_verb_maps_once release release wf-miospot-20260711T151201Z-9f3c
run_test 'sync maps to request-mirror-sync exactly once' test_mutating_verb_maps_once sync request-mirror-sync wf-miospot-20260711T151201Z-9f3c
run_test 'sync --cancel maps to mirror-cancel exactly once' test_sync_cancel_maps_to_mirror_cancel
run_test 'reveal maps to one registry mutation and bounded ack' test_mutating_verb_maps_once reveal reveal wf-miospot-20260711T151201Z-9f3c
run_test 'caller-provided requestId is reused exactly' test_request_id_reuse_is_exact
run_test 'failed mutations print the requestId minted before SSH' test_failed_mutation_prints_pre_send_request_id
run_test 'busy send queues without conductor-busy refusal' test_busy_send_queues_without_conductor_busy
run_test 'send --cancel-pending stays one idempotent send op' test_cancel_pending_is_same_send_op
run_test 'send --ack-event forwards the exact event and surfaces stale-ack' test_ack_event_is_forwarded_as_data
run_test 'desktop diagnostic family takes a registry lease visible as diagnostic-held' test_diagnostic_family_takes_registry_lease
run_test 'diagnostic inspect maps to exactly one registry op' test_read_verb_maps_once diagnostic diagnostic-inspect inspect miospot codex
run_test 'diagnostic send maps to one requestId mutation' test_mutating_verb_maps_once diagnostic diagnostic-send send miospot codex --prompt-file "$SUITE/map-send-prompt"
run_test 'diagnostic interrupt maps to one requestId mutation' test_mutating_verb_maps_once diagnostic diagnostic-interrupt interrupt miospot codex
run_test 'diagnostic kill maps to one requestId mutation' test_mutating_verb_maps_once diagnostic diagnostic-kill kill miospot codex
run_test 'diagnostic release maps to one requestId mutation' test_mutating_verb_maps_once diagnostic diagnostic-release release miospot codex
run_test 'explicit Mini host precedes environment without fallback' test_explicit_host_precedes_environment
run_test 'hostile argv is rejected as data before network send' test_hostile_argv_is_rejected_as_data_before_network
run_test 'unknown and removed client-orchestration verbs refuse before SSH' test_unknown_and_removed_client_orchestration_refuse
run_test 'relay source contains no lane frontier plan handoff or marker writer' test_source_has_no_client_orchestration_or_marker_writer
run_test 'relay writes no local state or mini-workflow marker' test_relay_writes_no_local_state_or_marker
run_test 'prompt is 64KiB bounded stdin-only and locally SHA-256 labelled' test_prompt_is_bounded_stdin_only_and_hashed_locally
run_test 'Mini offline returns bounded mini-unreachable with requestId' test_mini_offline_is_bounded_and_keeps_request_id
run_test 'closing the stateless client changes nothing Mini-side' test_client_close_has_no_mini_side_effect
run_test 'registry refusal hard-stops after one network call' test_refusal_hard_stops_after_one_registry_call
run_test 'seed consent requires identical explicit approval' test_seed_consent_identical_approval
run_test 'seed consent rejects glob patterns and requires a literal path' test_seed_consent_literal_path_no_glob
run_test 'seed consent path must actually be ignored' test_seed_consent_path_must_be_ignored
run_test 'seed consent forwards exactly one approved ignored exception' test_seed_consent_forwards_one_exact_exception
run_test 'legacy disposition table covers every old seed marker and behavior case' test_disposition_table_is_complete_and_well_formed

printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
