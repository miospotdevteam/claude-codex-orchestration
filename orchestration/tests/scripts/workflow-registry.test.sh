#!/usr/bin/env bash
set -euo pipefail

# Hermetic contract for workflow-registry:
#   - registry-red: identity, on-disk layout, enumeration, client-close
#   - lifecycle-red: start-conductor / re-bind / auto-resume episodes /
#     kill-quiesce-release / refusal preservation
# Targets orchestration/scripts/workflow-registry.
#
# Green for identity/layout lands in registry-core-green; lifecycle ops
# green in lifecycle-green. The implementation may be absent here; every
# case must still fail for a behavioral reason (missing executable / wrong
# outcome / missing op), not a fixture error.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPTS_DIR=$(cd "$SCRIPT_DIR/../../scripts" && pwd -P)
REGISTRY="$SCRIPTS_DIR/workflow-registry"
PROTOCOL="$SCRIPTS_DIR/remote-agent-v1"
PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
trap 'rm -rf "$SUITE"' EXIT

# workflowId = wf-<project>-<UTCstamp>-<4hex> (converged.plan.md)
# e.g. wf-orchestration-20260711T151201Z-9f3c
WORKFLOW_ID_RE='^wf-orchestration-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}$'
MAX_LIST_BYTES=4096
AUTHORITY_TOKEN=authority-root-v1

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

pass() { printf 'PASS %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_contains() { grep -Fq -- "$2" "$1"; }
assert_lacks() { ! grep -Fq -- "$2" "$1"; }

mode_of() {
  # Portable mode bits (GNU stat -c, BSD stat -f).
  local path=$1
  stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path"
}

sha256_of_file() {
  local path=$1
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    sha256sum "$path" | awk '{print $1}'
  fi
}

# Real host boot-time token for lock liveness (matches journal-latch-red).
host_boot_token() {
  if [[ -r /proc/stat ]]; then
    awk '/^btime / { print $2; exit }' /proc/stat
    return 0
  fi
  if command -v sysctl >/dev/null 2>&1; then
    local raw
    raw=$(sysctl -n kern.boottime 2>/dev/null || true)
    printf '%s\n' "$raw" | awk -F'[=,{} \t]+' '{
      for (i = 1; i <= NF; i++)
        if ($i == "sec" && $(i+1) ~ /^[0-9]+$/) { print $(i+1); exit }
    }'
    return 0
  fi
  stat -c %W / 2>/dev/null || stat -f %B / 2>/dev/null || printf '0\n'
}

# Minimal tmux + session stubs so lifecycle-green can compose supervisor
# without a real terminal server. Session presence is a marker file.
install_lifecycle_stubs() {
  local bin=$1
  mkdir -p "$bin" "$STATE_ROOT/sessions"
  # shellcheck disable=SC2016
  cat >"$bin/tmux" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  has-session)
    target=
    while [[ $# -gt 0 ]]; do [[ $1 == -t ]] && { target=${2:-}; break; }; shift; done
    [[ -f ${STATE_ROOT:?}/sessions/$target ]]
    ;;
  new-session)
    session=
    while [[ $# -gt 0 ]]; do [[ $1 == -s ]] && session=${2:-}; [[ $1 == -- ]] && break; shift; done
    [[ -n $session ]] || exit 64
    printf '%%42\n' >"$STATE_ROOT/sessions/$session"
    ;;
  kill-session)
    target=
    while [[ $# -gt 0 ]]; do [[ $1 == -t ]] && { target=${2:-}; break; }; shift; done
    rm -f "$STATE_ROOT/sessions/$target"
    ;;
  list-sessions) ls -1 "$STATE_ROOT/sessions" 2>/dev/null || true ;;
  capture-pane) : ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$bin/tmux"
  # Harness-only claude atom: resume-scan re-bind refuses to burn attempts when
  # claude is unresolvable (not treated as a dead session).
  cat >"$bin/claude" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
exit 0
STUB
  chmod +x "$bin/claude"
}

setup_case() {
  local name=$1
  CASE="$SUITE/$name"
  HOME_DIR="$CASE/home"
  STATE_ROOT="$CASE/state"
  # Mini checkout is the project worktree root (REMOTE_AGENT_ROOT_*).
  CHECKOUT="$CASE/mini-checkout"
  CLIENT_CHECKOUT="$CASE/client-checkout"
  PLAN_ID="registry-red-plan"
  PLAN_DIR="$CHECKOUT/.temp/plan-mode/active/$PLAN_ID"
  CLIENT_PLAN_DIR="$CLIENT_CHECKOUT/.temp/plan-mode/active/$PLAN_ID"
  HOSTNAME_FIXTURE="mini-test-host"
  PROJECT=orchestration
  WORKFLOWS_ROOT="$STATE_ROOT/orchestration/workflows"
  AUTHORITY_PATH="$STATE_ROOT/orchestration/remote-agent"
  PROTOCOL_PROJECT_DIR="$AUTHORITY_PATH/projects/$PROJECT"
  SESSION="remote-agent--$PROJECT--claude"
  DIAG_SESSION="remote-agent--$PROJECT--codex"
  FAKE_BIN="$CASE/bin"
  STDOUT="$CASE/stdout"
  STDERR="$CASE/stderr"
  WORKFLOW_ID=
  LEASE_GENERATION=
  mkdir -p "$HOME_DIR" "$STATE_ROOT" "$CHECKOUT" "$CLIENT_CHECKOUT" \
    "$PLAN_DIR" "$CLIENT_PLAN_DIR" "$FAKE_BIN"
  chmod 700 "$HOME_DIR" "$STATE_ROOT" "$CHECKOUT" "$CLIENT_CHECKOUT"
  install_lifecycle_stubs "$FAKE_BIN"
  # Minimal plan trio so the Mini marker has a real plan dir to land in.
  printf '%s\n' '{"planId":"registry-red-plan","frozen":true}' >"$PLAN_DIR/plan.json"
  printf '%s\n' '{"planId":"registry-red-plan","steps":{}}' >"$PLAN_DIR/progress.json"
  printf '# plan\n' >"$PLAN_DIR/masterPlan.md"
  # Parallel client plan dir is a distractor for D7 (no client provenance).
  printf '%s\n' '{"planId":"registry-red-plan","frozen":true}' >"$CLIENT_PLAN_DIR/plan.json"
  printf '%s\n' '{"planId":"registry-red-plan","steps":{}}' >"$CLIENT_PLAN_DIR/progress.json"
  printf '# client plan\n' >"$CLIENT_PLAN_DIR/masterPlan.md"
  : >"$STDOUT"
  : >"$STDERR"
}

# PATH includes FAKE_BIN (tmux stubs) + SCRIPTS_DIR (remote-agent-v1 /
# agent-supervisor) so lifecycle composition can call real protocol verbs.
# Optional first arg via run_registry_with_fault injects WORKFLOW_REGISTRY_TEST_FAULT.
run_registry() {
  local fault=${WORKFLOW_REGISTRY_TEST_FAULT:-}
  set +e
  if [[ ! -x $REGISTRY ]]; then
    STATUS=127
    : >"$STDOUT"
    printf 'missing executable: %s\n' "$REGISTRY" >"$STDERR"
    set -e
    return 0
  fi
  # CLIENT_CHECKOUT is supplied via WORKFLOW_CLIENT_CHECKOUT so a buggy
  # implementation that writes client-side mini-workflow provenance can be
  # caught. REMOTE_AGENT_ROOT_* and mint arg3 remain the Mini checkout only.
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:$SCRIPTS_DIR:$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    STATE_ROOT="$STATE_ROOT" \
    WORKFLOW_REGISTRY_TEST=1 \
    WORKFLOW_REGISTRY_TEST_FAULT="$fault" \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    WORKFLOW_CLIENT_CHECKOUT="$CLIENT_CHECKOUT" \
    "$REGISTRY" "$@" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
}

# Inject a lifecycle fault (crash-after-recovery-increment, …) for one call.
run_registry_with_fault() {
  local fault=$1
  shift
  WORKFLOW_REGISTRY_TEST_FAULT=$fault run_registry "$@"
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

# Snapshot of every path under the workflows root: type, mode, relative path,
# and content checksum for files. Used for client-close byte-identity.
workflows_fingerprint() {
  local path rel mode
  if [[ ! -d $WORKFLOWS_ROOT ]]; then
    printf 'missing\n'
    return 0
  fi
  while IFS= read -r path; do
    rel=${path#"$WORKFLOWS_ROOT"/}
    mode=$(mode_of "$path")
    if [[ -f $path ]]; then
      printf 'file %s %s ' "$mode" "$rel"
      cksum "$path" | awk '{print $1" "$2}'
    elif [[ -d $path ]]; then
      printf 'dir %s %s\n' "$mode" "$rel"
    fi
  done < <(find "$WORKFLOWS_ROOT" -mindepth 1 -print | LC_ALL=C sort)
}

# Lifecycle no-op fingerprint: workflows + protocol project state + session
# markers + protocol operation TRACE. A no-op that freezes the registry tree
# while still acquiring/releasing the protocol mutex (trace growth) is a
# false green; the trace must be part of the snapshot.
lifecycle_fingerprint() {
  printf 'workflows:\n'
  workflows_fingerprint
  printf 'protocol:\n'
  if [[ -d ${PROTOCOL_PROJECT_DIR:-} ]]; then
    local path rel mode
    while IFS= read -r path; do
      rel=${path#"$PROTOCOL_PROJECT_DIR"/}
      mode=$(mode_of "$path")
      if [[ -f $path ]]; then
        printf 'file %s %s ' "$mode" "$rel"
        cksum "$path" | awk '{print $1" "$2}'
      elif [[ -d $path ]]; then
        printf 'dir %s %s\n' "$mode" "$rel"
      fi
    done < <(find "$PROTOCOL_PROJECT_DIR" -mindepth 1 -print 2>/dev/null | LC_ALL=C sort)
  else
    printf 'missing-protocol\n'
  fi
  printf 'sessions:\n'
  if [[ -d ${STATE_ROOT:-}/sessions ]]; then
    local s
    while IFS= read -r s; do
      printf 'session %s ' "$(basename "$s")"
      cksum "$s" | awk '{print $1" "$2}'
    done < <(find "$STATE_ROOT/sessions" -mindepth 1 -maxdepth 1 -type f -print 2>/dev/null | LC_ALL=C sort)
  else
    printf 'missing-sessions\n'
  fi
  # Protocol operation trace: hidden mutex-acquire/CAS/retry activity must fail.
  printf 'protocol-trace:\n'
  local tfile
  tfile=$(protocol_trace_file)
  if [[ -f $tfile ]]; then
    printf 'file %s ' "$(mode_of "$tfile")"
    cksum "$tfile" | awk '{print $1" "$2}'
  else
    printf 'missing-trace\n'
  fi
}

# Protocol operation-trace path (remote-agent-v1: authority/trace/<project>.trace).
protocol_trace_file() {
  printf '%s\n' "$AUTHORITY_PATH/trace/$PROJECT.trace"
}

# Assert mutex-acquire → common-state-cas → lease-provisional → lease-commit
# with the mutex REMAINING HELD across CAS and lease (no intervening
# mutex-release). A commit-only or released-mid trace must FAIL.
#
# EVERY provisional lease is validated through its corresponding lease-commit
# (provisional alone is insufficient). Applies to all lease-taking transitions
# present in the trace — initial start, re-bind, and resume-scan.
assert_mutex_cas_lease_order() {
  local trace provisional_line next_provisional commit_line release_mid
  local last_mutex cas_after_mutex
  local found_any=0
  trace=$(protocol_trace_file)
  [[ -f $trace ]] || return 1

  # At least one provisional is required (commit-only fails).
  grep -q '^lease-provisional$' "$trace" 2>/dev/null || return 1
  grep -q '^lease-commit$' "$trace" 2>/dev/null || return 1

  # Every lease-provisional must pair with a corresponding lease-commit after
  # it (before the next provisional, if any), under a held mutex with a
  # preceding CAS. A mis-ordered re-bind or resume-scan must FAIL here.
  while IFS= read -r provisional_line; do
    [[ -n $provisional_line ]] || continue
    found_any=1

    last_mutex=$(grep -n '^mutex-acquire$' "$trace" \
      | awk -F: -v p="$provisional_line" '$1 < p { last=$1 } END { print last }')
    [[ -n ${last_mutex:-} ]] || return 1

    cas_after_mutex=$(grep -n '^common-state-cas$' "$trace" \
      | awk -F: -v m="${last_mutex}" -v p="$provisional_line" \
        '$1 > m && $1 < p { print $1; exit }')
    [[ -n ${cas_after_mutex:-} ]] || return 1

    # Next provisional (if any) bounds the commit window for this pair.
    next_provisional=$(grep -n '^lease-provisional$' "$trace" \
      | awk -F: -v p="$provisional_line" '$1 > p { print $1; exit }')

    if [[ -n ${next_provisional:-} ]]; then
      commit_line=$(grep -n '^lease-commit$' "$trace" \
        | awk -F: -v p="$provisional_line" -v n="$next_provisional" \
          '$1 > p && $1 < n { print $1; exit }')
    else
      commit_line=$(grep -n '^lease-commit$' "$trace" \
        | awk -F: -v p="$provisional_line" '$1 > p { print $1; exit }')
    fi
    # Corresponding commit is REQUIRED — provisional alone fails.
    [[ -n ${commit_line:-} ]] || return 1

    # Strict order for this transition: mutex → CAS → provisional → commit.
    (( last_mutex < cas_after_mutex \
      && cas_after_mutex < provisional_line \
      && provisional_line < commit_line )) || return 1

    # Mutex remains held across the whole critical section through commit.
    release_mid=$(awk -v a="$last_mutex" -v b="$commit_line" '
      NR > a && NR < b && $0 == "mutex-release" { print NR; exit }
    ' "$trace")
    [[ -z ${release_mid:-} ]] || return 1
  done < <(grep -n '^lease-provisional$' "$trace" 2>/dev/null | cut -d: -f1 || true)

  [[ $found_any -eq 1 ]] || return 1
  return 0
}

# Kill → release composition: quiescent ownership, then post-sync /
# release-only-verify, then lease-release. Missing any step fails.
assert_kill_release_trace_order() {
  local trace q_line v_line r_line
  trace=$(protocol_trace_file)
  [[ -f $trace ]] || return 1
  q_line=$(grep -n '^quiescent$' "$trace" 2>/dev/null | head -1 | cut -d: -f1 || true)
  v_line=$(grep -nE '^(release-only-verify|post-sync-verify)$' "$trace" 2>/dev/null | head -1 | cut -d: -f1 || true)
  r_line=$(grep -n '^lease-release$' "$trace" 2>/dev/null | head -1 | cut -d: -f1 || true)
  [[ -n ${q_line:-} && -n ${v_line:-} && -n ${r_line:-} ]] || return 1
  (( q_line < v_line && v_line < r_line )) || return 1
  return 0
}

# ACTIVE protocol lease at the given generation under the Claude session,
# plus a live tmux session marker.
assert_active_claude_lease_at_generation() {
  local gen=$1
  local state lease_gen session_val
  [[ -f $PROTOCOL_PROJECT_DIR/lease-state ]] || return 1
  state=$(tr -d '\n' <"$PROTOCOL_PROJECT_DIR/lease-state")
  [[ $state == active ]] || return 1
  lease_gen=$(tr -d '\n' <"$PROTOCOL_PROJECT_DIR/lease-generation" 2>/dev/null || true)
  [[ -n ${lease_gen:-} && $lease_gen == "$gen" ]] || return 1
  session_val=$(tr -d '\n' <"$PROTOCOL_PROJECT_DIR/lease-session" 2>/dev/null || true)
  [[ $session_val == "$SESSION" ]] || return 1
  assert_lacks "$PROTOCOL_PROJECT_DIR/lease-session" 'codex' || return 1
  assert_lacks "$PROTOCOL_PROJECT_DIR/lease-session" 'grok' || return 1
  [[ -f $STATE_ROOT/sessions/$SESSION ]] || return 1
  return 0
}

# Combined stdout+stderr byte length (bounded refusal contract).
# Write to a file and measure with wc -c so trailing newlines are counted;
# command substitution would strip them and under-count the bound.
refusal_output_bytes() {
  local combined_file
  combined_file="${CASE:-/tmp}/refusal-combined.bytes"
  cat "$STDOUT" "$STDERR" >"$combined_file" 2>/dev/null || : >"$combined_file"
  wc -c <"$combined_file" | tr -d '[:space:]'
}

# Exact (fixed-string) refusal token on a capture file; STATUS must be non-zero.
# Transformed/OR-ed loose patterns are not accepted — call once per exact token.
assert_refusal_capture_exact() {
  local out_file=$1
  local exact=$2
  [[ -s $out_file ]] || return 1
  grep -q '^STATUS=0$' "$out_file" && return 1
  grep -Fq -- "$exact" "$out_file" || return 1
  return 0
}

# Run remote-agent-v1 under the same hermetic env as the registry (for
# post-recovery guarded acquisition proofs).
run_protocol_verb() {
  local out=$CASE/protocol-stdout err=$CASE/protocol-stderr
  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:$SCRIPTS_DIR:$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    STATE_ROOT="$STATE_ROOT" \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    "$PROTOCOL" "$@" >"$out" 2>"$err"
  local st=$?
  set -e
  PROTOCOL_STATUS=$st
  PROTOCOL_STDOUT=$out
  PROTOCOL_STDERR=$err
  return 0
}

# Extract the minted workflowId from mint stdout (one-line JSON preferred;
# fall back to the first wf- token on the line).
extract_workflow_id() {
  local raw id
  raw=$(tr -d '\n' <"$STDOUT")
  if [[ -n $REAL_JQ ]]; then
    id=$(printf '%s' "$raw" | jq -r '
      if type == "object" then
        (.workflowId // .id // empty)
      else empty end
    ' 2>/dev/null || true)
    if [[ -n ${id:-} && $id != null ]]; then
      printf '%s\n' "$id"
      return 0
    fi
  fi
  if [[ $raw =~ (wf-orchestration-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# mint PROJECT PLAN_ID CHECKOUT HOST — registry writes identity under
# XDG_STATE_HOME and the Mini-side mini-workflow.json marker into the Mini
# checkout plan dir. REMOTE_AGENT_ROOT_* + HOSTNAME are also set in env.
do_mint() {
  expect_success mint "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"
}

do_mint_refuse() {
  expect_failure mint "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"
}

# Machine-readable closed-op refusal: JSON on stdout OR documented refusal
# token on either channel (case-insensitive). Not limited to lowercase stderr.
assert_machine_readable_refusal() {
  local combined
  combined=$(cat "$STDOUT" "$STDERR" 2>/dev/null || true)
  if [[ -n $REAL_JQ ]] && [[ -s $STDOUT ]]; then
    if jq -e '
      type == "object" and (
        (.error // .refusal // .code // .reason // .verdict // empty) != empty
        or .ok == false
        or ((.status // .result // "") | tostring
            | test("error|refus|unknown|closed|invalid|unsupported"; "i"))
      )
    ' <"$STDOUT" >/dev/null 2>&1; then
      return 0
    fi
  fi
  # Documented refusal form on either channel, any case.
  printf '%s' "$combined" | grep -qiE \
    'unknown|usage|closed|refus|invalid|unsupported|error|not.implemented|unrecognized' \
    && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Identity / layout
# ---------------------------------------------------------------------------

test_mint_workflow_id_format() {
  do_mint || return 1
  local id
  id=$(extract_workflow_id) || return 1
  [[ $id =~ $WORKFLOW_ID_RE ]]
}

test_one_active_workflow_per_project() {
  do_mint || return 1
  local first
  first=$(extract_workflow_id) || return 1

  # One-active-per-project must cover a DISTINCT second plan/checkout for the
  # same project — not a duplicate-mint of the same planId+checkout.
  local plan2_id="registry-red-plan-second"
  local checkout2="$CASE/mini-checkout-second"
  local plan2_dir="$checkout2/.temp/plan-mode/active/$plan2_id"
  mkdir -p "$plan2_dir"
  chmod 700 "$checkout2"
  printf '%s\n' "{\"planId\":\"$plan2_id\",\"frozen\":true}" >"$plan2_dir/plan.json"
  printf '%s\n' "{\"planId\":\"$plan2_id\",\"steps\":{}}" >"$plan2_dir/progress.json"
  printf '# second plan\n' >"$plan2_dir/masterPlan.md"

  # Keep REMOTE_AGENT_ROOT_ORCHESTRATION consistent with mint arg3. run_registry
  # binds REMOTE_AGENT_ROOT_* from CHECKOUT; a mismatch between that env and
  # mint arg3 would refuse as root-mismatch, not one-active-per-project.
  local saved_checkout=$CHECKOUT
  CHECKOUT=$checkout2
  # mint arg3 must be the same path CHECKOUT now names (second Mini checkout).
  expect_failure mint "$PROJECT" "$plan2_id" "$CHECKOUT" "$HOSTNAME_FIXTURE" || {
    CHECKOUT=$saved_checkout
    return 1
  }
  CHECKOUT=$saved_checkout
  assert_contains "$STDERR" "$first" || assert_contains "$STDOUT" "$first" || return 1

  # Exactly one workflow directory under the registry root.
  local count
  count=$(find "$WORKFLOWS_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'wf-*' 2>/dev/null | wc -l | tr -d ' ')
  [[ $count -eq 1 ]]
}

test_byproject_binding() {
  do_mint || return 1
  local id binding
  id=$(extract_workflow_id) || return 1
  binding="$WORKFLOWS_ROOT/byproject/$PROJECT"
  [[ -f $binding ]] || return 1
  # One line: the current workflowId (converged layout).
  [[ $(wc -l <"$binding" | tr -d ' ') -eq 1 ]] || return 1
  [[ $(tr -d '\n' <"$binding") == "$id" ]]
}

test_modes_0700_dirs_0600_files() {
  do_mint || return 1
  local id wf_dir path mode
  id=$(extract_workflow_id) || return 1
  wf_dir="$WORKFLOWS_ROOT/$id"
  [[ -d $wf_dir ]] || return 1

  # Parent registry dirs must be 0700 (0755 must fail this contract).
  [[ $(mode_of "$WORKFLOWS_ROOT") == 700 ]] || return 1
  [[ -d $WORKFLOWS_ROOT/byproject ]] || return 1
  [[ $(mode_of "$WORKFLOWS_ROOT/byproject") == 700 ]] || return 1
  [[ $(mode_of "$wf_dir") == 700 ]] || return 1

  # byproject binding file is private.
  [[ $(mode_of "$WORKFLOWS_ROOT/byproject/$PROJECT") == 600 ]] || return 1

  # Every regular file under the workflow dir is 0600; every subdir 0700.
  while IFS= read -r path; do
    mode=$(mode_of "$path")
    if [[ -f $path ]]; then
      [[ $mode == 600 ]] || return 1
    elif [[ -d $path ]]; then
      [[ $mode == 700 ]] || return 1
    fi
  done < <(find "$wf_dir" -mindepth 1 -print)

  # Required identity files exist and are private.
  [[ -f $wf_dir/meta.json ]] || return 1
  [[ -f $wf_dir/phase ]] || return 1
  [[ $(mode_of "$wf_dir/meta.json") == 600 ]] || return 1
  [[ $(mode_of "$wf_dir/phase") == 600 ]]
}

test_closed_op_refusal() {
  expect_failure unknown-operation || return 1
  # Bounded refusal contract: machine-readable JSON on stdout OR documented
  # refusal form on either channel (case-insensitive). Not stderr-only text.
  assert_machine_readable_refusal || return 1
  # Closed vocabulary must not create any state as a side effect of refusal.
  [[ ! -e $WORKFLOWS_ROOT ]] || [[ -z $(find "$WORKFLOWS_ROOT" -mindepth 1 -print -quit 2>/dev/null) ]]
}

# ---------------------------------------------------------------------------
# Mini-side marker (D7): registry writes into the Mini checkout plan dir only.
# Client-side provenance is deleted — no marker on a client plan dir.
# ---------------------------------------------------------------------------

test_mini_side_marker_no_client_provenance() {
  do_mint || return 1
  local id marker client_marker
  id=$(extract_workflow_id) || return 1
  marker="$PLAN_DIR/mini-workflow.json"
  client_marker="$CLIENT_PLAN_DIR/mini-workflow.json"

  # Mini checkout plan dir receives the marker.
  [[ -f $marker ]] || return 1
  [[ $(mode_of "$marker") == 600 ]] || return 1
  if [[ -n $REAL_JQ ]]; then
    # Origin fields must name the Mini (residentHost + Mini checkout/plan path).
    # A wrong origin or client path here fails the case for real.
    jq -e \
      --arg id "$id" \
      --arg host "$HOSTNAME_FIXTURE" \
      --arg project "$PROJECT" \
      --arg checkout "$CHECKOUT" \
      --arg planDir "$PLAN_DIR" \
      --arg client "$CLIENT_CHECKOUT" \
      '.workflowId == $id
       and .residentHost == $host
       and .project == $project
       and (
         (.checkout // .planDir // .planPath // .root // "") == ""
         or (.checkout // .planDir // .planPath // .root) == $checkout
         or (.checkout // .planDir // .planPath // .root) == $planDir
       )
       and (
         (.checkout // .planDir // .planPath // .root // "")
         | tostring
         | (contains($client) | not)
       )' \
      "$marker" >/dev/null || return 1
  else
    assert_contains "$marker" "$id" || return 1
    assert_contains "$marker" "$HOSTNAME_FIXTURE" || return 1
    assert_contains "$marker" "$PROJECT" || return 1
    assert_lacks "$marker" "$CLIENT_CHECKOUT" || return 1
  fi

  # No client-side provenance (D7): WORKFLOW_CLIENT_CHECKOUT was supplied on
  # every registry invocation; a buggy write into that tree must fail here.
  [[ ! -e $client_marker ]] || return 1
  [[ -z $(find "$CLIENT_CHECKOUT" -name 'mini-workflow.json' -print -quit 2>/dev/null) ]] || return 1

  # Exactly one marker under the whole case, and it lives under the Mini checkout.
  local markers marker_count mini_markers
  markers=$(find "$CASE" -name 'mini-workflow.json' -print 2>/dev/null | LC_ALL=C sort || true)
  marker_count=$(printf '%s\n' "$markers" | grep -c . || true)
  [[ $marker_count -eq 1 ]] || return 1
  mini_markers=$(printf '%s\n' "$markers" | grep -F "$CHECKOUT" | grep -c . || true)
  [[ $mini_markers -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Client-close persistence: state is byte-identical after simulated relay death.
# ---------------------------------------------------------------------------

test_client_close_persistence_byte_identical() {
  do_mint || return 1
  local id before after
  id=$(extract_workflow_id) || return 1
  before=$(workflows_fingerprint) || return 1
  [[ $before != missing && -n $before ]] || return 1

  # Simulate relay death: drop any client-held env, new process, no cursor.
  # The Mini registry root is the same disk; the client holds nothing.
  unset STATUS
  STDOUT="$CASE/stdout-fresh"
  STDERR="$CASE/stderr-fresh"
  : >"$STDOUT"
  : >"$STDERR"
  expect_success list || return 1
  # Fresh list must rediscover the workflow with zero prior client state.
  assert_contains "$STDOUT" "$id" || return 1

  after=$(workflows_fingerprint) || return 1
  [[ $after == "$before" ]]
}

# ---------------------------------------------------------------------------
# Fresh-client list: workflows + latches + pending queue-one + pending mirror
# jobs, bounded ≤4096 B, zero prior client state.
# ---------------------------------------------------------------------------

plant_latch_queue_mirror() {
  local id=$1
  local wf_dir="$WORKFLOWS_ROOT/$id"
  # Modes match what the implementation enforces (0700 dirs / 0600 files).
  mkdir -p "$wf_dir/mirror-queue" "$wf_dir/requests"
  chmod 700 "$WORKFLOWS_ROOT" 2>/dev/null || true
  if [[ -d $WORKFLOWS_ROOT/byproject ]]; then
    chmod 700 "$WORKFLOWS_ROOT/byproject"
  fi
  chmod 700 "$wf_dir" "$wf_dir/mirror-queue" "$wf_dir/requests"

  # Latch fields (state + journalSeq). workflowId may live on this object
  # (flat) or only on the parent workflow record (nested) — list assertions
  # accept either; planting uses flat association for a concrete on-disk file.
  if [[ -n $REAL_JQ ]]; then
    jq -n --arg id "$id" \
      '{workflowId:$id, state:"pending", journalSeq:17, kind:"idle_prompt", raisedAt:"2026-07-11T15:12:01Z"}' \
      >"$wf_dir/needs-input.json"
  else
    cat >"$wf_dir/needs-input.json" <<JSON
{"workflowId":"$id","state":"pending","journalSeq":17,"kind":"idle_prompt","raisedAt":"2026-07-11T15:12:01Z"}
JSON
  fi
  chmod 600 "$wf_dir/needs-input.json"

  # Queue-one (D1): meta + 0600 payload + real sha256 (not CRC).
  printf 'queued-reply-body\n' >"$wf_dir/pending-send.payload"
  chmod 600 "$wf_dir/pending-send.payload"
  local digest bytes
  digest=$(sha256_of_file "$wf_dir/pending-send.payload")
  bytes=$(wc -c <"$wf_dir/pending-send.payload" | tr -d ' ')
  # sha256 hex is 64 chars; refuse to plant a non-sha256 stand-in.
  [[ ${#digest} -eq 64 ]] || return 1
  cat >"$wf_dir/pending-send.json" <<JSON
{"requestId":"req-test-queue-one","sha256":"$digest","bytes":$bytes,"queuedAt":"2026-07-11T15:13:00Z"}
JSON
  chmod 600 "$wf_dir/pending-send.json"

  # Pending mirror job (no direction — computed at claim time).
  cat >"$wf_dir/mirror-queue/job-test-pending.json" <<'JSON'
{"jobId":"job-test-pending","state":"pending","createdAt":"2026-07-11T15:14:00Z"}
JSON
  chmod 600 "$wf_dir/mirror-queue/job-test-pending.json"
  chmod 700 "$wf_dir/mirror-queue"
}

# Latch enumeration: workflowId association + state + journalSeq structurally.
# Accept flat ({workflowId, state, journalSeq}) or nested (parent carries
# workflowId; latch body has state+journalSeq — never require workflowId
# duplicated inside the latch object). Generic "pending"/"17" alone is not enough.
assert_list_latch_shape() {
  local id=$1
  if [[ -n $REAL_JQ ]]; then
    # Use // null (not // empty) in or-chains: empty poisons boolean or and
    # makes select() drop every candidate under .. | objects.
    jq -e --arg id "$id" '
      def state_ok:
        ((.state // "") | tostring | test("pending|needs-input"; "i"));
      def seq_ok:
        ((.journalSeq // .seq) == 17 or (.journalSeq // .seq) == "17");
      # Latch body: state + journalSeq only. Do NOT require .workflowId here.
      def latch_body_ok:
        type == "object" and state_ok and seq_ok;

      # Flat: workflowId + latch fields on the same object.
      def flat_record:
        latch_body_ok and ((.workflowId // null) == $id);

      # Nested: a parent object carries workflowId; some latch-shaped child
      # (singular or array) has only state + journalSeq — id is not required
      # on the latch object itself.
      def nested_record:
        type == "object"
        and ((.workflowId // null) == $id)
        and (
          ((.latch // null) | latch_body_ok)
          or ((.needsInput // null) | latch_body_ok)
          or ((.needs_input // null) | latch_body_ok)
          or ((."needs-input" // null) | latch_body_ok)
          or ((.latches // []) | map(select(latch_body_ok)) | length > 0)
        );

      ([.. | objects | select(flat_record)] | length) > 0
      or ([.. | objects | select(nested_record)] | length) > 0
    ' <"$STDOUT" >/dev/null 2>&1
    return $?
  fi
  # Fallback without jq: workflowId association somewhere in the list output
  # plus exact state and journalSeq fields (not bare tokens alone). Does not
  # require the id to sit inside a nested latch object.
  assert_contains "$STDOUT" "\"workflowId\":\"$id\"" \
    || assert_contains "$STDOUT" "\"workflowId\": \"$id\"" \
    || return 1
  assert_contains "$STDOUT" '"state":"pending"' \
    || assert_contains "$STDOUT" '"state": "pending"' \
    || assert_contains "$STDOUT" '"state":"needs-input"' \
    || assert_contains "$STDOUT" '"state": "needs-input"' \
    || return 1
  assert_contains "$STDOUT" '"journalSeq":17' \
    || assert_contains "$STDOUT" '"journalSeq": 17' \
    || return 1
}

test_fresh_client_list_enumerates_and_is_bounded() {
  do_mint || return 1
  local id bytes lines
  id=$(extract_workflow_id) || return 1
  plant_latch_queue_mirror "$id" || return 1

  # Completely fresh client process: no cursor, no prior stdout, same disk.
  STDOUT="$CASE/stdout-list"
  STDERR="$CASE/stderr-list"
  : >"$STDOUT"
  : >"$STDERR"
  expect_success list || return 1

  # One-line (or single record) JSON, bounded ≤4096 B.
  bytes=$(wc -c <"$STDOUT" | tr -d ' ')
  lines=$(wc -l <"$STDOUT" | tr -d ' ')
  (( bytes <= MAX_LIST_BYTES )) || return 1
  (( lines <= 1 )) || return 1
  if [[ -n $REAL_JQ ]]; then
    jq -e . <"$STDOUT" >/dev/null || return 1
  fi

  # Enumerates the workflow itself.
  assert_contains "$STDOUT" "$id" || return 1

  # Exact latch record shape (workflowId + state + journalSeq), not bare tokens.
  assert_list_latch_shape "$id" || return 1

  # Surfaces pending queue-one (requestId).
  assert_contains "$STDOUT" 'req-test-queue-one' || return 1
  # Surfaces pending mirror job.
  assert_contains "$STDOUT" 'job-test-pending' || return 1

  # Structured presence via jq when available.
  if [[ -n $REAL_JQ ]]; then
    jq -e --arg id "$id" '
      (tostring | contains($id))
      and (tostring | test("req-test-queue-one"))
      and (tostring | test("job-test-pending"))
    ' <"$STDOUT" >/dev/null || return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Lifecycle helpers (lifecycle-red)
# ---------------------------------------------------------------------------

workflow_dir_of() {
  printf '%s\n' "$WORKFLOWS_ROOT/$1"
}

json_field() {
  local file=$1 key=$2
  if [[ -n $REAL_JQ && -s $file ]]; then
    jq -r --arg k "$key" '
      if type == "object" then (.[$k] // empty)
      else empty end
    ' "$file" 2>/dev/null | head -n 1
    return 0
  fi
  sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p" "$file" 2>/dev/null | head -n 1
}

# start-conductor is Claude-only, project-scoped, mint-arity plan args.
# Same four atoms as mint so identity + lease bind in one guarded op.
do_start_conductor() {
  expect_success start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"
}

do_start_conductor_refuse() {
  expect_failure start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"
}

capture_workflow_id_from_stdout() {
  WORKFLOW_ID=$(extract_workflow_id) || return 1
  [[ $WORKFLOW_ID =~ $WORKFLOW_ID_RE ]] || return 1
  LEASE_GENERATION=$(json_field "$STDOUT" leaseGeneration)
  if [[ -z ${LEASE_GENERATION:-} ]]; then
    LEASE_GENERATION=$(json_field "$STDOUT" generation)
  fi
  return 0
}

# Protocol authority path used by remote-agent-v1 under XDG_STATE_HOME.
ensure_protocol_project() {
  mkdir -p "$PROTOCOL_PROJECT_DIR"
  chmod 700 "$AUTHORITY_PATH" 2>/dev/null || true
  chmod 700 "$AUTHORITY_PATH/projects" 2>/dev/null || true
  chmod 700 "$PROTOCOL_PROJECT_DIR"
}

# Plant a reboot-orphaned ACTIVE lease: lease files survive, tmux session does not.
# common/remote match so release-only-verify can succeed during composed re-bind.
plant_orphaned_active_lease() {
  local gen=${1:-0}
  ensure_protocol_project
  printf 'active\n' >"$PROTOCOL_PROJECT_DIR/lease-state"
  printf '%s\n' "$SESSION" >"$PROTOCOL_PROJECT_DIR/lease-session"
  printf 'conductor\n' >"$PROTOCOL_PROJECT_DIR/lease-owner"
  printf '%s\n' "$gen" >"$PROTOCOL_PROJECT_DIR/lease-generation"
  printf '%s\n' "$gen" >"$PROTOCOL_PROJECT_DIR/generation"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/common"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/remote"
  rm -f "$PROTOCOL_PROJECT_DIR/quiescent" \
    "$PROTOCOL_PROJECT_DIR/post-sync-verified" \
    "$PROTOCOL_PROJECT_DIR/recovery-required"
  chmod 600 "$PROTOCOL_PROJECT_DIR/lease-state" \
    "$PROTOCOL_PROJECT_DIR/lease-session" \
    "$PROTOCOL_PROJECT_DIR/lease-owner" \
    "$PROTOCOL_PROJECT_DIR/lease-generation" \
    "$PROTOCOL_PROJECT_DIR/generation" \
    "$PROTOCOL_PROJECT_DIR/common" \
    "$PROTOCOL_PROJECT_DIR/remote" 2>/dev/null || true
  # Session absent after reboot (no tmux marker).
  rm -f "$STATE_ROOT/sessions/$SESSION"
}

plant_live_session_marker() {
  mkdir -p "$STATE_ROOT/sessions"
  printf '%%42\n' >"$STATE_ROOT/sessions/$SESSION"
}

# Mark the workflow open but conductor-exited (wake hint only).
plant_exited_open_workflow() {
  local id=$1
  local wf_dir
  wf_dir=$(workflow_dir_of "$id")
  mkdir -p "$wf_dir" "$wf_dir/journal"
  chmod 700 "$wf_dir" "$wf_dir/journal" 2>/dev/null || true
  printf 'exited\n' >"$wf_dir/phase"
  chmod 600 "$wf_dir/phase"
  # Ensure byproject still binds this open workflow.
  mkdir -p "$WORKFLOWS_ROOT/byproject"
  chmod 700 "$WORKFLOWS_ROOT" "$WORKFLOWS_ROOT/byproject" 2>/dev/null || true
  printf '%s\n' "$id" >"$WORKFLOWS_ROOT/byproject/$PROJECT"
  chmod 600 "$WORKFLOWS_ROOT/byproject/$PROJECT"
  # No live session.
  rm -f "$STATE_ROOT/sessions/$SESSION"
}

# recovery.json episode ledger (D2).
write_recovery_json() {
  local id=$1 episode=$2 attempts=$3 state=$4
  local wf_dir path
  wf_dir=$(workflow_dir_of "$id")
  mkdir -p "$wf_dir"
  path="$wf_dir/recovery.json"
  if [[ -n $REAL_JQ ]]; then
    jq -n \
      --arg episodeId "$episode" \
      --argjson attempts "$attempts" \
      --arg state "$state" \
      --arg lastAttemptAt "2026-07-11T15:00:00Z" \
      '{episodeId:$episodeId,attempts:$attempts,state:$state,lastAttemptAt:$lastAttemptAt}' \
      >"$path"
  else
    cat >"$path" <<JSON
{"episodeId":"$episode","attempts":$attempts,"state":"$state","lastAttemptAt":"2026-07-11T15:00:00Z"}
JSON
  fi
  chmod 600 "$path"
}

read_recovery_attempts() {
  local id=$1 path
  path="$(workflow_dir_of "$id")/recovery.json"
  [[ -f $path ]] || return 1
  if [[ -n $REAL_JQ ]]; then
    jq -r '.attempts // empty' "$path"
  else
    sed -n 's/.*"attempts":\([0-9]*\).*/\1/p' "$path" | head -n 1
  fi
}

read_recovery_episode() {
  local id=$1 path
  path="$(workflow_dir_of "$id")/recovery.json"
  [[ -f $path ]] || return 1
  if [[ -n $REAL_JQ ]]; then
    jq -r '.episodeId // empty' "$path"
  else
    sed -n 's/.*"episodeId":"\([^"]*\)".*/\1/p' "$path" | head -n 1
  fi
}

read_recovery_state() {
  local id=$1 path
  path="$(workflow_dir_of "$id")/recovery.json"
  [[ -f $path ]] || return 1
  if [[ -n $REAL_JQ ]]; then
    jq -r '.state // empty' "$path"
  else
    sed -n 's/.*"state":"\([^"]*\)".*/\1/p' "$path" | head -n 1
  fi
}

read_meta_lease_generation() {
  local id=$1 path
  path="$(workflow_dir_of "$id")/meta.json"
  [[ -f $path ]] || return 1
  if [[ -n $REAL_JQ ]]; then
    jq -r '.leaseGeneration // .generation // empty' "$path"
  else
    sed -n 's/.*"leaseGeneration":\([0-9]*\).*/\1/p' "$path" | head -n 1
  fi
}

read_phase() {
  local id=$1 path
  path="$(workflow_dir_of "$id")/phase"
  [[ -f $path ]] || return 1
  tr -d '\n' <"$path"
}

# Search journal records for a lifecycle rebind label (class/kind/label).
journal_has_lifecycle_rebind() {
  local id=$1
  local jdir path
  jdir="$(workflow_dir_of "$id")/journal"
  [[ -d $jdir ]] || return 1
  # Any journal shard mentioning rebind + lifecycle (labels only).
  if grep -RqiE 'lifecycle[[:space:]]*rebind|rebind|"kind"[[:space:]]*:[[:space:]]*"rebind"|"class"[[:space:]]*:[[:space:]]*"rebind"' \
    "$jdir" 2>/dev/null; then
    return 0
  fi
  return 1
}

# Feed notifications dir for closed-class records.
feed_has_class() {
  local class=$1 entity=$2
  local feed_dir f
  feed_dir="$WORKFLOWS_ROOT/notifications/$PROJECT"
  [[ -d $feed_dir ]] || return 1
  if [[ -n $REAL_JQ ]]; then
    for f in "$feed_dir"/*.json; do
      [[ -f $f ]] || continue
      if jq -e --arg c "$class" --arg e "$entity" '
        (if type == "array" then .[] else . end)
        | ((.class // .eventClass // "") == $c)
        and ((.entityId // .entity // .workflowId // .ref // .reference // "") == $e)
      ' "$f" >/dev/null 2>&1; then
        return 0
      fi
    done
    return 1
  fi
  grep -RFq "$class" "$feed_dir" 2>/dev/null \
    && grep -RFq "$entity" "$feed_dir" 2>/dev/null
}

plant_delivery_pending() {
  local id=$1
  local wf_dir
  wf_dir=$(workflow_dir_of "$id")
  mkdir -p "$wf_dir"
  printf 'delivery-pending\n' >"$wf_dir/delivery-pending"
  chmod 600 "$wf_dir/delivery-pending"
}

# Protocol mutex with dead-pid + host boot-time (auto-recoverable).
plant_dead_pid_protocol_mutex() {
  local boot
  ensure_protocol_project
  boot=$(host_boot_token)
  [[ -n $boot && $boot != 0 ]] || return 1
  mkdir -p "$PROTOCOL_PROJECT_DIR/mutex"
  chmod 700 "$PROTOCOL_PROJECT_DIR/mutex"
  printf 'wedged-owner\n' >"$PROTOCOL_PROJECT_DIR/mutex/owner"
  printf 'pid=999999999\nboot=%s\n' "$boot" >"$PROTOCOL_PROJECT_DIR/mutex/holder"
  chmod 600 "$PROTOCOL_PROJECT_DIR/mutex/owner" "$PROTOCOL_PROJECT_DIR/mutex/holder"
}

plant_live_pid_protocol_mutex() {
  local boot
  ensure_protocol_project
  boot=$(host_boot_token)
  [[ -n $boot && $boot != 0 ]] || return 1
  mkdir -p "$PROTOCOL_PROJECT_DIR/mutex"
  chmod 700 "$PROTOCOL_PROJECT_DIR/mutex"
  printf 'live-owner\n' >"$PROTOCOL_PROJECT_DIR/mutex/owner"
  printf 'pid=%s\nboot=%s\n' "$$" "$boot" >"$PROTOCOL_PROJECT_DIR/mutex/holder"
  chmod 600 "$PROTOCOL_PROJECT_DIR/mutex/owner" "$PROTOCOL_PROJECT_DIR/mutex/holder"
}

# Diagnostic full-lease holder (D5): list shows diagnostic-held.
plant_diagnostic_held_lease() {
  local gen=${1:-0}
  ensure_protocol_project
  printf 'active\n' >"$PROTOCOL_PROJECT_DIR/lease-state"
  printf '%s\n' "$DIAG_SESSION" >"$PROTOCOL_PROJECT_DIR/lease-session"
  printf 'diagnostic\n' >"$PROTOCOL_PROJECT_DIR/lease-owner"
  printf '%s\n' "$gen" >"$PROTOCOL_PROJECT_DIR/lease-generation"
  printf '%s\n' "$gen" >"$PROTOCOL_PROJECT_DIR/generation"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/common"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/remote"
  rm -f "$PROTOCOL_PROJECT_DIR/quiescent" "$PROTOCOL_PROJECT_DIR/post-sync-verified"
  mkdir -p "$STATE_ROOT/sessions"
  printf '%%43\n' >"$STATE_ROOT/sessions/$DIAG_SESSION"
  # Registry-side marker that list surfaces as diagnostic-held.
  mkdir -p "$WORKFLOWS_ROOT/byproject"
  printf 'diagnostic-held\n' >"$WORKFLOWS_ROOT/byproject/$PROJECT.diagnostic" 2>/dev/null || true
  if [[ -n $REAL_JQ ]]; then
    mkdir -p "$WORKFLOWS_ROOT"
    jq -n --arg session "$DIAG_SESSION" \
      '{holder:"diagnostic",session:$session,state:"diagnostic-held"}' \
      >"$WORKFLOWS_ROOT/byproject/$PROJECT.holder.json" 2>/dev/null || true
  fi
}

# Ensure a workflow tree exists even when mint is the only green path yet.
# Used by plant-then-op cases that still must fail for missing lifecycle ops.
plant_minimal_workflow_tree() {
  local id=$1
  local gen=${2:-0}
  local wf_dir
  wf_dir=$(workflow_dir_of "$id")
  mkdir -p "$wf_dir/journal" "$WORKFLOWS_ROOT/byproject"
  chmod 700 "$WORKFLOWS_ROOT" "$wf_dir" "$wf_dir/journal" "$WORKFLOWS_ROOT/byproject"
  printf '%s\n' "$id" >"$WORKFLOWS_ROOT/byproject/$PROJECT"
  chmod 600 "$WORKFLOWS_ROOT/byproject/$PROJECT"
  if [[ -n $REAL_JQ ]]; then
    jq -n --arg id "$id" --arg project "$PROJECT" --argjson gen "$gen" \
      '{workflowId:$id,project:$project,leaseGeneration:$gen,session:"remote-agent--orchestration--claude"}' \
      >"$wf_dir/meta.json"
  else
    cat >"$wf_dir/meta.json" <<JSON
{"workflowId":"$id","project":"$PROJECT","leaseGeneration":$gen,"session":"remote-agent--orchestration--claude"}
JSON
  fi
  chmod 600 "$wf_dir/meta.json"
  printf 'running\n' >"$wf_dir/phase"
  chmod 600 "$wf_dir/phase"
}

# Bootstrap: prefer real start-conductor; fall back to mint so plant helpers
# still run under a partial green (registry-core without lifecycle).
bootstrap_bound_workflow() {
  if do_start_conductor; then
    capture_workflow_id_from_stdout || return 1
    return 0
  fi
  if do_mint; then
    capture_workflow_id_from_stdout || return 1
    return 0
  fi
  # Full red (no registry): plant a deterministic id so subsequent ops still
  # exercise the missing lifecycle surface rather than fixture errors.
  WORKFLOW_ID="wf-orchestration-20260711T151201Z-9f3c"
  plant_minimal_workflow_tree "$WORKFLOW_ID" 0
  return 0
}

# ---------------------------------------------------------------------------
# lifecycle-red: start-conductor + re-bind
# ---------------------------------------------------------------------------

test_start_conductor_is_claude_only() {
  # Explicit non-Claude harness atoms must refuse (Claude-only; no harness arg).
  # Loop over EVERY non-Claude harness — short-circuit after the first would
  # false-green an implementation that only refuses one of them.
  local harness harness_out snap_before snap_after bytes
  ensure_protocol_project
  snap_before=$(lifecycle_fingerprint)
  for harness in codex grok; do
    # Prefer flag form so the verb is still start-conductor (not a 5th positional).
    if ! expect_failure start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE" --harness "$harness"; then
      # Positional harness atom is also accepted as a refuse path for that harness.
      expect_failure start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE" "$harness" \
        || return 1
    fi
    assert_machine_readable_refusal || return 1
    # Bounded refusal (≤4096 B combined channels).
    bytes=$(refusal_output_bytes)
    (( bytes <= MAX_LIST_BYTES )) || return 1
    # Must be a harness/Claude-only refusal — not a generic unknown-op for a
    # missing verb (that would false-green once only registry-core is present).
    harness_out=$(cat "$STDOUT" "$STDERR" 2>/dev/null || true)
    printf '%s' "$harness_out" | grep -qiE \
      'claude-only|claude only|harness|not claude|non-claude' \
      || return 1
    # Zero mutation of protocol + session + registry on non-Claude refuse.
    snap_after=$(lifecycle_fingerprint)
    [[ $snap_after == "$snap_before" ]] || return 1
    # Harness refusal alone must not bind a workflow.
    [[ ! -e $WORKFLOWS_ROOT/byproject/$PROJECT ]] \
      || [[ -z $(tr -d '[:space:]' <"$WORKFLOWS_ROOT/byproject/$PROJECT" 2>/dev/null || true) ]] \
      || return 1
  done

  # Bare start-conductor (no harness) must be a recognized verb: success, or a
  # non-unknown refusal (e.g. already-bound). "unknown operation" means the
  # lifecycle surface is still missing → keep the case red.
  run_registry start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"
  if [[ $STATUS -ne 0 ]]; then
    local bare
    bare=$(cat "$STDOUT" "$STDERR" 2>/dev/null || true)
    printf '%s' "$bare" | grep -qiE \
      'unknown.operation|unrecognized|not.implemented|missing executable' \
      && return 1
  fi

  # No workflow bound as a side effect of a harness refusal alone: if bare
  # start did not succeed, byproject must still be empty.
  if [[ $STATUS -ne 0 ]]; then
    [[ ! -e $WORKFLOWS_ROOT/byproject/$PROJECT ]] \
      || [[ -z $(tr -d '[:space:]' <"$WORKFLOWS_ROOT/byproject/$PROJECT" 2>/dev/null || true) ]] \
      || return 1
  fi
  return 0
}

test_start_conductor_ordered_mutex_cas_lease() {
  do_start_conductor || return 1
  capture_workflow_id_from_stdout || return 1
  local wf_dir gen
  wf_dir=$(workflow_dir_of "$WORKFLOW_ID")
  [[ -d $wf_dir ]] || return 1
  [[ -f $wf_dir/meta.json ]] || return 1

  # Protocol lease is ACTIVE under the Claude session atom only.
  # Leaving the lease provisional is not a completed start-conductor.
  ensure_protocol_project
  [[ -f $PROTOCOL_PROJECT_DIR/lease-state ]] || return 1
  [[ $(tr -d '\n' <"$PROTOCOL_PROJECT_DIR/lease-state") == active ]] || return 1
  assert_contains "$PROTOCOL_PROJECT_DIR/lease-session" "$SESSION" || return 1
  # Never a codex/grok session for start-conductor.
  assert_lacks "$PROTOCOL_PROJECT_DIR/lease-session" 'codex' || return 1
  assert_lacks "$PROTOCOL_PROJECT_DIR/lease-session" 'grok' || return 1

  # Ordered mutex → CAS → lease-provisional → lease-commit with mutex held
  # throughout. Commit-only or released-mid traces fail.
  assert_mutex_cas_lease_order || return 1

  gen=$(read_meta_lease_generation "$WORKFLOW_ID" || true)
  [[ -n ${gen:-} ]] || gen=${LEASE_GENERATION:-}
  [[ -n ${gen:-} ]] || return 1

  # ACTIVE Claude lease at the bound generation + live session marker.
  assert_active_claude_lease_at_generation "$gen" || return 1

  # byproject binds the live id.
  [[ -f $WORKFLOWS_ROOT/byproject/$PROJECT ]] || return 1
  [[ $(tr -d '\n' <"$WORKFLOWS_ROOT/byproject/$PROJECT") == "$WORKFLOW_ID" ]] || return 1

  # Phase is a live open phase (not released / failed-recovery).
  local phase
  phase=$(read_phase "$WORKFLOW_ID" || true)
  [[ -n $phase ]] || return 1
  case $phase in
    released|failed-recovery|quiesced) return 1 ;;
  esac
  return 0
}

test_second_start_refuses_with_live_id() {
  do_start_conductor || return 1
  capture_workflow_id_from_stdout || return 1
  local first=$WORKFLOW_ID

  do_start_conductor_refuse || return 1
  assert_contains "$STDERR" "$first" || assert_contains "$STDOUT" "$first" || return 1
  assert_machine_readable_refusal || return 1

  # Still exactly one bound workflow id.
  [[ $(tr -d '\n' <"$WORKFLOWS_ROOT/byproject/$PROJECT") == "$first" ]] || return 1
  local count
  count=$(find "$WORKFLOWS_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'wf-*' 2>/dev/null | wc -l | tr -d ' ')
  [[ $count -eq 1 ]]
}

test_rebind_orphaned_active_lease_same_workflow_bumps_generation() {
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local gen_before gen_after

  gen_before=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_before:-} ]] || gen_before=${LEASE_GENERATION:-0}
  [[ -n ${gen_before:-} ]] || gen_before=0

  # Reboot-orphaned: ACTIVE lease files remain; conductor session is gone.
  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease "$gen_before"

  # Human start-conductor path must itself perform the composed re-bind.
  # Falling back to resume-scan is a false green for the human path.
  expect_success start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE" || return 1

  # SAME workflowId — never mint a second id for re-bind.
  local bound
  bound=$(tr -d '\n' <"$WORKFLOWS_ROOT/byproject/$PROJECT" 2>/dev/null || true)
  [[ $bound == "$first" ]] || return 1
  local count
  count=$(find "$WORKFLOWS_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'wf-*' 2>/dev/null | wc -l | tr -d ' ')
  [[ $count -eq 1 ]] || return 1

  gen_after=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_after:-} ]] || return 1
  # leaseGeneration must strictly bump.
  (( gen_after > gen_before )) || return 1

  # ACTIVE protocol lease AT the bumped generation + live Claude session.
  # Metadata-only generation bumps without a real lease/session re-bind fail.
  assert_active_claude_lease_at_generation "$gen_after" || return 1

  # Re-bind takes the lease: every provisional in the trace (including this
  # re-bind) must pair through lease-commit under mutex+CAS. Mis-ordered re-bind fails.
  assert_mutex_cas_lease_order || return 1

  # lifecycle rebind journaled under the same workflow by the human path.
  journal_has_lifecycle_rebind "$first" || return 1

  # Phase leaves exited toward bootstrapping / running / recovering (not released).
  local phase
  phase=$(read_phase "$first" || true)
  case $phase in
    exited|released|failed-recovery) return 1 ;;
  esac
  return 0
}

test_rebind_idempotent_against_live_conductor() {
  do_start_conductor || return 1
  capture_workflow_id_from_stdout || return 1
  local first=$WORKFLOW_ID
  local gen_before gen_after snap_pre_start snap_after

  plant_live_session_marker
  gen_before=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_before:-} ]] || gen_before=0
  # KEEP the pre-start fingerprint; compare against it after the idempotent path.
  # Re-capturing after start would mask mutations performed by a false "no-op".
  snap_pre_start=$(lifecycle_fingerprint)

  # Live conductor: re-bind / second start must be idempotent (refuse or no-op).
  run_registry start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"
  # Either non-zero refuse with live id, or success that does not bump generation.
  if [[ $STATUS -ne 0 ]]; then
    assert_contains "$STDERR" "$first" || assert_contains "$STDOUT" "$first" || return 1
  else
    gen_after=$(read_meta_lease_generation "$first" || true)
    [[ ${gen_after:-} == "$gen_before" ]] || return 1
  fi

  # Protocol + session + registry + trace must be unchanged vs pre-start.
  snap_after=$(lifecycle_fingerprint)
  [[ $snap_after == "$snap_pre_start" ]] || return 1

  # Still one workflow; identity unchanged.
  [[ $(tr -d '\n' <"$WORKFLOWS_ROOT/byproject/$PROJECT") == "$first" ]] || return 1
  local count
  count=$(find "$WORKFLOWS_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'wf-*' 2>/dev/null | wc -l | tr -d ' ')
  [[ $count -eq 1 ]] || return 1

  # Resume-scan is also a no-op against a healthy live conductor (including
  # protocol TRACE — hidden retry/acquire activity fails).
  expect_success resume-scan || return 1
  snap_after=$(lifecycle_fingerprint)
  [[ $snap_after == "$snap_pre_start" ]] || return 1
  gen_after=$(read_meta_lease_generation "$first" || true)
  [[ ${gen_after:-} == "$gen_before" ]]
}

# ---------------------------------------------------------------------------
# lifecycle-red: auto-resume episodes (D2)
# ---------------------------------------------------------------------------

test_resume_scan_rebinds_exited_open_workflow() {
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local gen_before gen_after

  gen_before=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_before:-} ]] || gen_before=0

  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease "$gen_before"
  write_recovery_json "$first" "ep-auto-1" 0 recovering

  expect_success resume-scan || return 1

  # Same workflowId, generation bumped, rebind journaled.
  [[ $(tr -d '\n' <"$WORKFLOWS_ROOT/byproject/$PROJECT") == "$first" ]] || return 1
  gen_after=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_after:-} ]] || return 1
  (( gen_after > gen_before )) || return 1
  journal_has_lifecycle_rebind "$first" || return 1
  # ACTIVE lease at bumped generation + live Claude session after auto re-bind.
  assert_active_claude_lease_at_generation "$gen_after" || return 1

  # resume-scan re-bind takes the lease: every provisional through its
  # corresponding lease-commit under mutex+CAS. Mis-ordered resume-scan fails.
  assert_mutex_cas_lease_order || return 1

  # attempts incremented durably (>= 1).
  local attempts
  attempts=$(read_recovery_attempts "$first" || true)
  [[ -n ${attempts:-} ]] || return 1
  (( attempts >= 1 ))
}

test_recovery_attempts_increment_before_attempt_and_survive_reboot() {
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local gen_before gen_mid attempts1 attempts2 attempts_mid episode1 phase_mid
  local recovery_path fault_mark
  recovery_path="$(workflow_dir_of "$first")/recovery.json"
  fault_mark="$STATE_ROOT/orchestration/test-faults/crash-after-recovery-increment"

  gen_before=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_before:-} ]] || gen_before=0

  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease "$gen_before"
  write_recovery_json "$first" "ep-reboot-1" 0 recovering

  # Arm a consumable fault marker. lifecycle-green MUST honor
  # WORKFLOW_REGISTRY_TEST_FAULT=crash-after-recovery-increment by: (1) durable
  # increment, (2) writing "consumed" (or removing the armed file), (3) exiting
  # non-zero BEFORE re-bind completes. Ignoring the fault and incrementing only
  # after success must FAIL this case.
  mkdir -p "$(dirname "$fault_mark")"
  printf 'armed\n' >"$fault_mark"
  chmod 600 "$fault_mark"

  run_registry_with_fault crash-after-recovery-increment resume-scan

  # Injected crash/fault MUST have occurred (marker consumed).
  if [[ -f $fault_mark ]]; then
    [[ $(tr -d '\n' <"$fault_mark") == consumed ]] || return 1
  fi
  # Crash exits non-zero; a full successful re-bind means the fault was ignored.
  [[ $STATUS -ne 0 ]] || return 1

  # Durable increment is not optional and must precede the failed attempt.
  attempts1=$(read_recovery_attempts "$first" || true)
  [[ -n ${attempts1:-} ]] || return 1
  (( attempts1 >= 1 )) || return 1
  [[ -f $recovery_path ]] || return 1
  episode1=$(read_recovery_episode "$first" || true)
  [[ -n ${episode1:-} ]] || return 1

  # Re-bind must NOT have completed under the fault (generation unbumped /
  # phase still exited or recovering without a live session re-bind).
  gen_mid=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_mid:-} ]] || gen_mid=$gen_before
  (( gen_mid == gen_before )) || return 1
  phase_mid=$(read_phase "$first" || true)
  case $phase_mid in
    exited|recovering) ;;
    *) return 1 ;;
  esac
  # No live session after a crashed attempt.
  [[ ! -f $STATE_ROOT/sessions/$SESSION ]] || return 1

  # Read recovery.json between attempts (before the next scan) to prove the
  # durable write is visible to a fresh observer, not only post-success.
  attempts_mid=$(read_recovery_attempts "$first" || true)
  [[ $attempts_mid == "$attempts1" ]] || return 1

  # Simulated reboot: wipe only process-local markers; recovery.json must survive.
  rm -f "$STATE_ROOT/sessions/$SESSION"
  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease "$(read_meta_lease_generation "$first" || echo "$gen_before")"
  # recovery.json still on disk with prior attempts.
  [[ -f $recovery_path ]] || return 1
  [[ $(read_recovery_attempts "$first") == "$attempts1" ]] || return 1

  # Second attempt (no fault): increments further; reboot did not reset counter.
  expect_success resume-scan || return 1
  attempts2=$(read_recovery_attempts "$first" || true)
  [[ -n ${attempts2:-} ]] || return 1
  (( attempts2 > attempts1 )) || return 1
  # Cap: attempts must never exceed 3 even across repeated scans.
  (( attempts2 <= 3 )) || return 1
  # Same episode across the simulated reboot.
  [[ $(read_recovery_episode "$first") == "$episode1" ]]
}

test_third_failure_sets_sticky_failed_recovery_and_stops_retries() {
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local gen_before phase attempts snap_before snap_after

  gen_before=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_before:-} ]] || gen_before=0

  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease "$gen_before"
  # Two prior durable failures already recorded; next attempt is the 3rd.
  write_recovery_json "$first" "ep-sticky-1" 2 recovering

  # Drive the 3rd failure: resume-scan attempts re-bind; force failure by
  # planting recovery-required so release-only-verify / re-bind cannot complete.
  ensure_protocol_project
  printf 'forced-failure\n' >"$PROTOCOL_PROJECT_DIR/recovery-required"
  chmod 600 "$PROTOCOL_PROJECT_DIR/recovery-required"

  # The scan itself should succeed (bounded); episode lands sticky failed-recovery.
  expect_success resume-scan || return 1

  attempts=$(read_recovery_attempts "$first" || true)
  [[ -n ${attempts:-} ]] || return 1
  # Exactly the 3rd attempt — never 4, and not a loose >=3 that accepts 4+.
  (( attempts == 3 )) || return 1

  phase=$(read_phase "$first" || true)
  [[ $phase == failed-recovery ]] || return 1
  [[ $(read_recovery_state "$first") == failed-recovery ]] \
    || [[ $(read_recovery_state "$first") == failed ]] \
    || return 1

  # Feed record emitted for failed-recovery.
  feed_has_class failed-recovery "$first" || return 1

  # Further automatic retries stop: scan is a no-op (state sticky).
  # A 4th attempt is a failure of the implementation, not an accept.
  snap_before=$(lifecycle_fingerprint)
  expect_success resume-scan || return 1
  snap_after=$(lifecycle_fingerprint)
  [[ $snap_after == "$snap_before" ]] || return 1
  [[ $(read_phase "$first") == failed-recovery ]] || return 1
  [[ $(read_recovery_attempts "$first") == 3 ]] || return 1
  # Explicit: even under continued exit+orphan plant, attempts stay at 3.
  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease "$gen_before"
  printf 'forced-failure\n' >"$PROTOCOL_PROJECT_DIR/recovery-required"
  expect_success resume-scan || return 1
  attempts=$(read_recovery_attempts "$first" || true)
  (( attempts == 3 )) || return 1
  [[ $(read_phase "$first") == failed-recovery ]]
}

test_human_start_mints_new_episode_journaling_prior_failure() {
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local prior_episode new_episode gen_before gen_after

  gen_before=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_before:-} ]] || gen_before=${LEASE_GENERATION:-0}
  [[ -n ${gen_before:-} ]] || gen_before=0

  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease "$gen_before"
  write_recovery_json "$first" "ep-prior-fail" 3 failed-recovery
  printf 'failed-recovery\n' >"$(workflow_dir_of "$first")/phase"
  prior_episode="ep-prior-fail"

  # Human start-conductor continues: NEW episode, prior failure journaled, not silent reset.
  expect_success start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE" || return 1

  # Same workflowId (continue, not a brand-new project mint that drops history).
  [[ $(tr -d '\n' <"$WORKFLOWS_ROOT/byproject/$PROJECT") == "$first" ]] || return 1

  # ACTIVE Claude lease + LIVE session + BUMPED generation. A metadata-only
  # restart (episode/recovery rewritten without re-binding the protocol lease)
  # must FAIL these three assertions.
  gen_after=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_after:-} ]] || return 1
  (( gen_after > gen_before )) || return 1
  assert_active_claude_lease_at_generation "$gen_after" || return 1
  # Human recovery also takes the lease under the ordered mutex+CAS contract.
  assert_mutex_cas_lease_order || return 1

  new_episode=$(read_recovery_episode "$first" || true)
  [[ -n ${new_episode:-} ]] || return 1
  [[ $new_episode != "$prior_episode" ]] || return 1

  # Attempts reset for the NEW episode (fresh counter), not a silent wipe of history:
  # journal must still mention the prior failure / prior episode.
  local jdir
  jdir="$(workflow_dir_of "$first")/journal"
  [[ -d $jdir ]] || return 1
  grep -Rq "$prior_episode" "$jdir" 2>/dev/null \
    || grep -RqiE 'failed-recovery|prior.*fail|episode.*fail' "$jdir" 2>/dev/null \
    || return 1

  local attempts
  attempts=$(read_recovery_attempts "$first" || true)
  [[ -n ${attempts:-} ]] || return 1
  # Fresh episode starts at 0 or 1 — never retains sticky 3 without journaling.
  (( attempts <= 1 )) || return 1
  local state
  state=$(read_recovery_state "$first" || true)
  [[ $state != failed-recovery ]] || return 1
  return 0
}

test_resume_scan_noop_healthy_quiescent_failed_and_reconciles_delivery_pending() {
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local snap_before snap_after jdir journal_before journal_after reconcile_label

  # 1) Healthy live conductor → no-op (workflows + protocol + session + TRACE).
  plant_live_session_marker
  snap_before=$(lifecycle_fingerprint)
  expect_success resume-scan || return 1
  snap_after=$(lifecycle_fingerprint)
  [[ $snap_after == "$snap_before" ]] || return 1

  # 2) Quiescent workflow → no-op (kill path left writer quiescent; not auto-resume).
  ensure_protocol_project
  printf 'active\n' >"$PROTOCOL_PROJECT_DIR/lease-state"
  printf '%s\n' "$SESSION" >"$PROTOCOL_PROJECT_DIR/lease-session"
  printf '%s\n' "$SESSION" >"$PROTOCOL_PROJECT_DIR/quiescent"
  printf 'quiesced\n' >"$(workflow_dir_of "$first")/phase"
  rm -f "$STATE_ROOT/sessions/$SESSION"
  snap_before=$(lifecycle_fingerprint)
  expect_success resume-scan || return 1
  snap_after=$(lifecycle_fingerprint)
  [[ $snap_after == "$snap_before" ]] || return 1
  [[ $(read_phase "$first") == quiesced ]] || return 1
  # Quiescent ownership retained for the Claude session through the no-op.
  [[ $(tr -d '\n' <"$PROTOCOL_PROJECT_DIR/quiescent") == "$SESSION" ]] || return 1

  # 3) Sticky failed-recovery → no-op.
  write_recovery_json "$first" "ep-noop-fail" 3 failed-recovery
  printf 'failed-recovery\n' >"$(workflow_dir_of "$first")/phase"
  snap_before=$(lifecycle_fingerprint)
  expect_success resume-scan || return 1
  snap_after=$(lifecycle_fingerprint)
  [[ $snap_after == "$snap_before" ]] || return 1
  [[ $(read_phase "$first") == failed-recovery ]] || return 1

  # 4) delivery-pending is reconciled through the REAL queue-one contract:
  # stored payload + digest + requestId + open latch. Must NOT synthesize a
  # journal entry or clear the marker without validating the payload.
  rm -f "$PROTOCOL_PROJECT_DIR/quiescent"
  jdir="$(workflow_dir_of "$first")/journal"
  mkdir -p "$jdir"
  local request_id=req-resume-del-$$
  local payload="resume-delivery-payload-$$"
  local digest seq=1
  digest=$(printf '%s' "$payload" | shasum -a 256 | awk '{print $1}')
  journal_before=$(find "$jdir" -type f -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    cksum "$f"
    cat "$f"
  done)
  printf '%s' "$journal_before" | grep -Fq 'delivered-from-queue' && return 1

  # Plant latch evidence + matching queued payload (real contract inputs).
  printf '%s\n' "{\"kind\":\"input-needed\",\"scope\":\"main\",\"seq\":$seq,\"at\":\"2026-07-12T00:00:00Z\"}" \
    >"$jdir/$(printf '%020d' "$seq").json"
  chmod 600 "$jdir/$(printf '%020d' "$seq").json"
  printf '%s\n' "$seq" >"$jdir/journal-cursor"
  printf '%s\n' "{\"workflowId\":\"$first\",\"state\":\"open\",\"journalSeq\":$seq,\"kind\":\"input-needed\",\"raisedAt\":\"2026-07-12T00:00:00Z\"}" \
    >"$(workflow_dir_of "$first")/needs-input.json"
  chmod 600 "$(workflow_dir_of "$first")/needs-input.json"
  printf '%s' "$payload" >"$(workflow_dir_of "$first")/pending-send.payload"
  chmod 600 "$(workflow_dir_of "$first")/pending-send.payload"
  printf '%s\n' "{\"requestId\":\"$request_id\",\"sha256\":\"$digest\",\"bytes\":${#payload},\"queuedAt\":\"2026-07-12T00:00:00Z\"}" \
    >"$(workflow_dir_of "$first")/pending-send.json"
  chmod 600 "$(workflow_dir_of "$first")/pending-send.json"
  plant_delivery_pending "$first"
  printf 'pending-token-%s\n' "$$" >"$(workflow_dir_of "$first")/delivery-pending"
  chmod 600 "$(workflow_dir_of "$first")/delivery-pending"
  # Open non-failed workflow so reconcile path can run without re-bind.
  printf 'needs-input\n' >"$(workflow_dir_of "$first")/phase"
  plant_live_session_marker
  write_recovery_json "$first" "ep-healthy" 0 idle
  # Live non-quiescent conductor for reconcile (quiescent must stay cleared).
  [[ ! -f $PROTOCOL_PROJECT_DIR/quiescent ]] || return 1

  expect_success resume-scan || return 1

  # Planted quiescent marker must NOT reappear / remain.
  [[ ! -f $PROTOCOL_PROJECT_DIR/quiescent ]] || return 1
  # delivery-pending marker must be cleared after real delivery.
  [[ ! -f $(workflow_dir_of "$first")/delivery-pending ]] || return 1
  # Payload consumed; latch ACKed.
  [[ ! -e $(workflow_dir_of "$first")/pending-send.payload ]] || return 1
  [[ ! -e $(workflow_dir_of "$first")/pending-send.json ]] || return 1
  assert_contains "$(workflow_dir_of "$first")/needs-input.json" 'acked' || return 1

  # Exact new journal entry from real contract (not a synthetic resume label).
  journal_after=$(find "$jdir" -type f -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    cksum "$f"
    cat "$f"
  done)
  [[ "$journal_after" != "$journal_before" ]] || return 1
  printf '%s' "$journal_after" | grep -Fq 'delivered-from-queue' || return 1
  return 0
}

# ---------------------------------------------------------------------------
# lifecycle-red: protocol mutex auto-recovery
# ---------------------------------------------------------------------------

test_dead_pid_protocol_mutex_auto_recovers_as_recovering() {
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  plant_dead_pid_protocol_mutex || return 1

  # Any guarded lifecycle op must break the dead-pid mutex and surface a
  # transient recovering phase. Recovering phase alone is insufficient: the
  # dead holder must be REMOVED and a subsequent guarded acquisition must
  # SUCCEED.
  run_registry start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"

  local phase
  phase=$(read_phase "$first" 2>/dev/null || true)

  # Dead-pid holder MUST be removed (not merely papered over by phase).
  if [[ -f ${PROTOCOL_PROJECT_DIR}/mutex/holder ]]; then
    assert_lacks "$PROTOCOL_PROJECT_DIR/mutex/holder" '999999999' || return 1
  fi
  # Owner file for the dead wedge must not still claim wedged-owner either.
  if [[ -f ${PROTOCOL_PROJECT_DIR}/mutex/owner ]]; then
    assert_lacks "$PROTOCOL_PROJECT_DIR/mutex/owner" 'wedged-owner' || return 1
  fi

  # Observable transient recovering (phase, journal, or channels).
  local recovered_signal=0
  if [[ $phase == recovering ]]; then
    recovered_signal=1
  elif grep -RqiE \
    '"phase"[[:space:]]*:[[:space:]]*"recovering"|lifecycle[[:space:]]*recovering|mutex.*recover|lock-broken|recovering' \
    "$(workflow_dir_of "$first")/journal" 2>/dev/null; then
    recovered_signal=1
  elif assert_contains "$STDOUT" 'recovering' || assert_contains "$STDERR" 'recovering'; then
    recovered_signal=1
  fi
  [[ $recovered_signal -eq 1 ]] || return 1

  # Subsequent guarded acquisition must SUCCEED: clear any live holder left by
  # the recovering op (if still held by a live pid of the just-finished process,
  # the protocol mutex dir should already be released). If a live non-dead
  # holder remains, force-release is not allowed — acquisition must succeed
  # because recovery left the mutex free.
  if [[ -d ${PROTOCOL_PROJECT_DIR}/mutex ]]; then
    # Still held: only acceptable if holder is live and we can wait — but the
    # contract requires acquisition to succeed, so a leftover mutex dir after
    # the lifecycle op returns is a failure unless we can acquire.
    :
  fi
  run_protocol_verb mutex-acquire "$PROJECT" "post-recovery-owner" "$AUTHORITY_TOKEN"
  [[ ${PROTOCOL_STATUS:-1} -eq 0 ]] || return 1
  # Proof of successful acquire: mutex dir present with our owner.
  [[ -d $PROTOCOL_PROJECT_DIR/mutex ]] || return 1
  assert_contains "$PROTOCOL_PROJECT_DIR/mutex/owner" 'post-recovery-owner' || return 1
  # Release for cleanliness.
  run_protocol_verb mutex-release "$PROJECT" "post-recovery-owner" "$AUTHORITY_TOKEN"
  return 0
}

test_live_pid_protocol_mutex_refuses() {
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  plant_live_pid_protocol_mutex || return 1

  local snap_before snap_after
  snap_before=$(lifecycle_fingerprint)
  do_start_conductor_refuse || return 1
  # Must be a mutex/busy refusal — not a generic unknown-op for a missing verb.
  assert_contains "$STDERR" 'busy' || assert_contains "$STDOUT" 'busy' \
    || assert_contains "$STDERR" 'mutex' || assert_contains "$STDOUT" 'mutex' \
    || return 1
  local refuse_out
  refuse_out=$(cat "$STDOUT" "$STDERR" 2>/dev/null || true)
  printf '%s' "$refuse_out" | grep -qiE \
    'unknown.operation|unrecognized|not.implemented|missing executable' \
    && return 1

  # Live holder not stolen.
  assert_contains "$PROTOCOL_PROJECT_DIR/mutex/holder" "pid=$$" || return 1
  [[ -d $PROTOCOL_PROJECT_DIR/mutex ]] || return 1

  snap_after=$(lifecycle_fingerprint)
  # Bound id and protocol/session state unchanged on refuse.
  [[ $(tr -d '\n' <"$WORKFLOWS_ROOT/byproject/$PROJECT") == "$first" ]] || return 1
  [[ $snap_after == "$snap_before" ]] || return 1
  # No silent second workflow.
  local count
  count=$(find "$WORKFLOWS_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'wf-*' 2>/dev/null | wc -l | tr -d ' ')
  [[ $count -eq 1 ]]
}

# ---------------------------------------------------------------------------
# lifecycle-red: kill / quiesce / release + refusal preservation
# ---------------------------------------------------------------------------

test_kill_quiesce_release_semantics() {
  do_start_conductor || return 1
  capture_workflow_id_from_stdout || return 1
  local first=$WORKFLOW_ID
  plant_live_session_marker
  # Live conductor session must exist before kill so absence after is meaningful.
  [[ -f $STATE_ROOT/sessions/$SESSION ]] || return 1

  # kill → quiescing/quiesced; protocol quiescent recorded; does NOT release.
  expect_success kill "$first" || expect_success kill "$PROJECT" || return 1
  local phase
  phase=$(read_phase "$first" || true)
  case $phase in
    quiescing|quiesced|quiescent) ;;
    *)
      # Accept protocol quiescent even if phase word varies slightly.
      [[ -f $PROTOCOL_PROJECT_DIR/quiescent ]] || return 1
      ;;
  esac
  [[ -f $PROTOCOL_PROJECT_DIR/quiescent ]] || return 1
  # Quiescent ownership must be the Claude session (not a different harness).
  [[ $(tr -d '\n' <"$PROTOCOL_PROJECT_DIR/quiescent") == "$SESSION" ]] || return 1
  # kill genuinely terminates the live conductor session (tmux marker gone).
  [[ ! -f $STATE_ROOT/sessions/$SESSION ]] || return 1
  # Lease still present until release.
  [[ -f $PROTOCOL_PROJECT_DIR/lease-state ]] || return 1
  [[ $(tr -d '\n' <"$PROTOCOL_PROJECT_DIR/lease-state") == active ]] || return 1
  # byproject still bound (kill does not clear ownership).
  [[ $(tr -d '\n' <"$WORKFLOWS_ROOT/byproject/$PROJECT") == "$first" ]] || return 1

  # release without prior quiescence path is already satisfied; release clears.
  # If kill left us quiesced, release must succeed and clear byproject.
  expect_success release "$first" || expect_success release "$PROJECT" || return 1
  phase=$(read_phase "$first" || true)
  [[ $phase == released ]] || return 1
  # Lease cleared.
  [[ ! -f $PROTOCOL_PROJECT_DIR/lease-state ]] || return 1
  # Session remains absent after release (not resurrected).
  [[ ! -f $STATE_ROOT/sessions/$SESSION ]] || return 1
  # byproject cleared or no longer names the released id as active.
  if [[ -f $WORKFLOWS_ROOT/byproject/$PROJECT ]]; then
    [[ $(tr -d '\n' <"$WORKFLOWS_ROOT/byproject/$PROJECT") != "$first" ]] || return 1
  fi
  # Protocol trace: quiescent → (post-sync-verify|release-only-verify) → lease-release.
  assert_kill_release_trace_order || return 1
  # Feed records for completed path: released (and optionally completed).
  feed_has_class released "$first" || return 1
  return 0
}

test_release_refuses_without_quiescence() {
  do_start_conductor || return 1
  capture_workflow_id_from_stdout || return 1
  local first=$WORKFLOW_ID
  plant_live_session_marker
  # Ensure not quiescent.
  rm -f "$PROTOCOL_PROJECT_DIR/quiescent"

  expect_failure release "$first" || expect_failure release "$PROJECT" || return 1
  assert_machine_readable_refusal || return 1
  # KNOWN bounded refusal — exact protocol token, not unknown-operation.
  local refuse_out
  refuse_out=$(cat "$STDOUT" "$STDERR" 2>/dev/null || true)
  printf '%s' "$refuse_out" | grep -qiE \
    'unknown.operation|unrecognized|not.implemented|missing executable' \
    && return 1
  # Exact unchanged remote-agent-v1 tokens (or the compact registry code form
  # that embeds the same token text).
  printf '%s' "$refuse_out" | grep -Fq 'quiescence required before release' \
    || printf '%s' "$refuse_out" | grep -Fq 'quiescence required before verification' \
    || printf '%s' "$refuse_out" | grep -Fq 'post-sync verification required before release' \
    || return 1
  local bytes
  bytes=$(refusal_output_bytes)
  (( bytes <= MAX_LIST_BYTES )) || return 1
  # Still bound and leased.
  [[ $(tr -d '\n' <"$WORKFLOWS_ROOT/byproject/$PROJECT") == "$first" ]] || return 1
  [[ -f $PROTOCOL_PROJECT_DIR/lease-state ]] || return 1
  local phase
  phase=$(read_phase "$first" || true)
  [[ $phase != released ]]
}

# Capture stdout+stderr for one registry op into a dedicated file (never overwrite
# prior class captures — each refusal class must be inspectable independently).
capture_registry_op() {
  local out_file=$1
  shift
  run_registry "$@"
  {
    printf 'STATUS=%s\n' "$STATUS"
    printf '%s\n' '---stdout---'
    cat "$STDOUT" 2>/dev/null || true
    printf '%s\n' '---stderr---'
    cat "$STDERR" 2>/dev/null || true
  } >"$out_file"
}

# Assert a captured registry op refused and surfaces an expected protocol token.
assert_refusal_capture() {
  local out_file=$1
  local expect_re=$2
  [[ -s $out_file ]] || return 1
  grep -q '^STATUS=0$' "$out_file" && return 1
  grep -qiE "$expect_re" "$out_file" || return 1
  return 0
}

test_existing_protocol_refusals_surface_through_registry() {
  # Enumerate EVERY remote-agent-v1 refusal class that lifecycle composition
  # must re-surface UNCHANGED (exact tokens, not transformed/OR-ed). Capture
  # each operation's output separately — never overwrite the first capture.
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local cap_dir="$CASE/refusal-captures"
  mkdir -p "$cap_dir"

  # --- 1) recovery-required → exact release-only-verify refuse token ---
  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease 0
  ensure_protocol_project
  printf 'evidence\n' >"$PROTOCOL_PROJECT_DIR/recovery-required"
  chmod 600 "$PROTOCOL_PROJECT_DIR/recovery-required"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/common"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/remote"
  capture_registry_op "$cap_dir/01-recovery-required.txt" \
    start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"
  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease 0
  printf 'evidence\n' >"$PROTOCOL_PROJECT_DIR/recovery-required"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/common"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/remote"
  capture_registry_op "$cap_dir/01b-recovery-required-scan.txt" resume-scan
  # Exact unchanged token from remote-agent-v1 release-only-verify.
  assert_refusal_capture_exact "$cap_dir/01-recovery-required.txt" \
    'recovery evidence blocks release-only verification' \
    || assert_refusal_capture_exact "$cap_dir/01b-recovery-required-scan.txt" \
      'recovery evidence blocks release-only verification' \
    || return 1
  [[ -f $PROTOCOL_PROJECT_DIR/recovery-required ]] || return 1

  # --- 2) remote/common divergence — exact token ---
  rm -f "$PROTOCOL_PROJECT_DIR/recovery-required"
  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease 0
  printf 'common-a\n' >"$PROTOCOL_PROJECT_DIR/common"
  printf 'remote-b\n' >"$PROTOCOL_PROJECT_DIR/remote"
  capture_registry_op "$cap_dir/02-divergence.txt" \
    start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"
  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease 0
  printf 'common-a\n' >"$PROTOCOL_PROJECT_DIR/common"
  printf 'remote-b\n' >"$PROTOCOL_PROJECT_DIR/remote"
  capture_registry_op "$cap_dir/02b-divergence-scan.txt" resume-scan
  assert_refusal_capture_exact "$cap_dir/02-divergence.txt" \
    'remote state does not match common state' \
    || assert_refusal_capture_exact "$cap_dir/02b-divergence-scan.txt" \
      'remote state does not match common state' \
    || return 1

  # --- 3) live protocol mutex held — exact token ---
  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease 0
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/common"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/remote"
  plant_live_pid_protocol_mutex || return 1
  capture_registry_op "$cap_dir/03-mutex-held.txt" \
    start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"
  assert_refusal_capture_exact "$cap_dir/03-mutex-held.txt" 'mutex is held' || return 1
  assert_contains "$PROTOCOL_PROJECT_DIR/mutex/holder" "pid=$$" || return 1
  rm -rf "$PROTOCOL_PROJECT_DIR/mutex"

  # --- 4) lease already exists — exact token ---
  ensure_protocol_project
  printf 'active\n' >"$PROTOCOL_PROJECT_DIR/lease-state"
  printf '%s\n' "$SESSION" >"$PROTOCOL_PROJECT_DIR/lease-session"
  printf '0\n' >"$PROTOCOL_PROJECT_DIR/lease-generation"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/common"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/remote"
  plant_live_session_marker
  mkdir -p "$WORKFLOWS_ROOT/byproject"
  printf '%s\n' "$first" >"$WORKFLOWS_ROOT/byproject/$PROJECT"
  capture_registry_op "$cap_dir/04-lease-already.txt" \
    start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"
  # Second start may surface "lease already exists" (provisional path) or the
  # live-id one-active refusal that embeds the same lease-already protocol token
  # when composition attempts provisional under an active lease.
  assert_refusal_capture_exact "$cap_dir/04-lease-already.txt" 'lease already exists' \
    || {
      # Also accept live-id refuse that still embeds the protocol token text.
      grep -q '^STATUS=0$' "$cap_dir/04-lease-already.txt" && return 1
      grep -Fq -- "$first" "$cap_dir/04-lease-already.txt" \
        && grep -Fq -- 'lease already exists' "$cap_dir/04-lease-already.txt"
    } || return 1
  [[ -s $cap_dir/01-recovery-required.txt ]] || return 1
  [[ -s $cap_dir/02-divergence.txt ]] || return 1
  [[ -s $cap_dir/03-mutex-held.txt ]] || return 1

  # --- 5) release without quiescence — exact token ---
  ensure_protocol_project
  printf 'active\n' >"$PROTOCOL_PROJECT_DIR/lease-state"
  printf '%s\n' "$SESSION" >"$PROTOCOL_PROJECT_DIR/lease-session"
  rm -f "$PROTOCOL_PROJECT_DIR/quiescent" "$PROTOCOL_PROJECT_DIR/post-sync-verified"
  plant_live_session_marker
  mkdir -p "$WORKFLOWS_ROOT/byproject"
  printf '%s\n' "$first" >"$WORKFLOWS_ROOT/byproject/$PROJECT"
  capture_registry_op "$cap_dir/05-quiescence-required.txt" release "$first"
  if ! assert_refusal_capture_exact "$cap_dir/05-quiescence-required.txt" \
      'quiescence required before release'; then
    capture_registry_op "$cap_dir/05b-quiescence-required.txt" release "$PROJECT"
    assert_refusal_capture_exact "$cap_dir/05b-quiescence-required.txt" \
      'quiescence required before release' \
      || assert_refusal_capture_exact "$cap_dir/05-quiescence-required.txt" \
        'quiescence required before verification' \
      || assert_refusal_capture_exact "$cap_dir/05b-quiescence-required.txt" \
        'quiescence required before verification' \
      || return 1
  fi

  # --- 6) generation mismatch — exact token ---
  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease 0
  printf '99\n' >"$PROTOCOL_PROJECT_DIR/generation"
  printf '0\n' >"$PROTOCOL_PROJECT_DIR/lease-generation"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/common"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/remote"
  rm -f "$PROTOCOL_PROJECT_DIR/recovery-required"
  capture_registry_op "$cap_dir/06-generation.txt" \
    start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE"
  assert_refusal_capture_exact "$cap_dir/06-generation.txt" 'generation mismatch' \
    || assert_refusal_capture_exact "$cap_dir/06-generation.txt" 'lease generation mismatch' \
    || {
      capture_registry_op "$cap_dir/06b-generation-scan.txt" resume-scan
      assert_refusal_capture_exact "$cap_dir/06b-generation-scan.txt" 'generation mismatch' \
        || assert_refusal_capture_exact "$cap_dir/06b-generation-scan.txt" 'lease generation mismatch' \
        || return 1
    }

  # --- 7) lease session mismatch — EXACT remote-agent-v1 token only ---
  # Plant ACTIVE lease under a DIFFERENT valid session (codex diagnostic) so
  # Claude-scoped kill/release hits lease-session check first and can ONLY
  # surface "lease session mismatch" (not "quiescent session mismatch", which
  # requires lease-session to already match). No quiescent marker planted.
  ensure_protocol_project
  printf 'active\n' >"$PROTOCOL_PROJECT_DIR/lease-state"
  printf '%s\n' "$DIAG_SESSION" >"$PROTOCOL_PROJECT_DIR/lease-session"
  printf '0\n' >"$PROTOCOL_PROJECT_DIR/lease-generation"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/common"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/remote"
  rm -f "$PROTOCOL_PROJECT_DIR/quiescent" \
    "$PROTOCOL_PROJECT_DIR/recovery-required" \
    "$PROTOCOL_PROJECT_DIR/post-sync-verified"
  plant_live_session_marker
  mkdir -p "$WORKFLOWS_ROOT/byproject"
  printf '%s\n' "$first" >"$WORKFLOWS_ROOT/byproject/$PROJECT"
  printf 'running\n' >"$(workflow_dir_of "$first")/phase"
  # Kill composes quiescent under Claude session; protocol dies with the exact
  # token. Exact class only — do not accept "quiescent session mismatch".
  capture_registry_op "$cap_dir/07-lease-session.txt" kill "$first"
  if ! assert_refusal_capture_exact "$cap_dir/07-lease-session.txt" 'lease session mismatch'; then
    # Release under Claude with foreign lease-session is the alternate compose path.
    capture_registry_op "$cap_dir/07b-lease-session-release.txt" release "$first"
    assert_refusal_capture_exact "$cap_dir/07b-lease-session-release.txt" \
      'lease session mismatch' || return 1
  fi

  # --- 8) post-sync verification required before release (missing class) ---
  ensure_protocol_project
  printf 'active\n' >"$PROTOCOL_PROJECT_DIR/lease-state"
  printf '%s\n' "$SESSION" >"$PROTOCOL_PROJECT_DIR/lease-session"
  printf '%s\n' "$SESSION" >"$PROTOCOL_PROJECT_DIR/quiescent"
  rm -f "$PROTOCOL_PROJECT_DIR/post-sync-verified" "$PROTOCOL_PROJECT_DIR/recovery-required"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/common"
  printf 'fingerprint-common\n' >"$PROTOCOL_PROJECT_DIR/remote"
  plant_live_session_marker
  # Kill already quiesced; release without post-sync must surface the token.
  # Drive release directly so the registry composes lease-release.
  printf 'quiesced\n' >"$(workflow_dir_of "$first")/phase"
  capture_registry_op "$cap_dir/08-post-sync-required.txt" release "$first"
  if ! assert_refusal_capture_exact "$cap_dir/08-post-sync-required.txt" \
      'post-sync verification required before release'; then
    capture_registry_op "$cap_dir/08b-post-sync-required.txt" release "$PROJECT"
    assert_refusal_capture_exact "$cap_dir/08b-post-sync-required.txt" \
      'post-sync verification required before release' || return 1
  fi

  # --- 9) active lease required (missing class) — release with no lease ---
  rm -f "$PROTOCOL_PROJECT_DIR/lease-state" "$PROTOCOL_PROJECT_DIR/lease-session" \
    "$PROTOCOL_PROJECT_DIR/lease-owner" "$PROTOCOL_PROJECT_DIR/lease-generation" \
    "$PROTOCOL_PROJECT_DIR/quiescent" "$PROTOCOL_PROJECT_DIR/post-sync-verified"
  capture_registry_op "$cap_dir/09-active-lease-required.txt" release "$first"
  assert_refusal_capture_exact "$cap_dir/09-active-lease-required.txt" 'active lease required' \
    || {
      capture_registry_op "$cap_dir/09b-active-lease-required.txt" release "$PROJECT"
      assert_refusal_capture_exact "$cap_dir/09b-active-lease-required.txt" 'active lease required' \
        || return 1
    }

  # --- 10) closed / unknown op (registry closed vocabulary) ---
  capture_registry_op "$cap_dir/10-unknown-op.txt" unknown-lifecycle-op
  assert_refusal_capture "$cap_dir/10-unknown-op.txt" \
    'unknown|unsupported|unrecognized|usage|closed' || return 1

  # Every capture file must still exist independently (no overwrite of first).
  local f
  for f in \
    "$cap_dir/01-recovery-required.txt" \
    "$cap_dir/02-divergence.txt" \
    "$cap_dir/03-mutex-held.txt" \
    "$cap_dir/04-lease-already.txt" \
    "$cap_dir/10-unknown-op.txt"
  do
    [[ -s $f ]] || return 1
  done
  return 0
}

test_diagnostic_held_refuses_start_conductor_boundedly() {
  plant_diagnostic_held_lease 0
  local snap_before snap_after bytes combined

  snap_before=$(lifecycle_fingerprint)

  do_start_conductor_refuse || return 1
  assert_machine_readable_refusal || return 1
  combined=$(cat "$STDOUT" "$STDERR" 2>/dev/null || true)
  printf '%s' "$combined" | grep -qiE 'diagnostic-held|diagnostic' || return 1
  # Bounded-size assertion (≤4096 B combined channels).
  bytes=$(refusal_output_bytes)
  (( bytes <= MAX_LIST_BYTES )) || return 1
  # Must not be a generic unknown-operation once lifecycle is present.
  # (During red, unknown-operation is the correct closed fail — but then the
  # diagnostic-specific token is absent and we already require it above.)
  printf '%s' "$combined" | grep -qiE 'unknown.operation|not.implemented|missing executable' \
    && ! printf '%s' "$combined" | grep -qiE 'diagnostic-held|diagnostic' \
    && return 1

  # Zero mutation of protocol + session + registry on diagnostic refuse.
  snap_after=$(lifecycle_fingerprint)
  [[ $snap_after == "$snap_before" ]] || return 1

  # No workflow byproject bind overwrote the diagnostic holder silently.
  if [[ -f $WORKFLOWS_ROOT/byproject/$PROJECT ]]; then
    local bound
    bound=$(tr -d '\n' <"$WORKFLOWS_ROOT/byproject/$PROJECT")
    [[ $bound != wf-* ]] || return 1
  fi
  # Diagnostic lease still held under the codex diagnostic session.
  [[ -f $PROTOCOL_PROJECT_DIR/lease-state ]] || return 1
  assert_contains "$PROTOCOL_PROJECT_DIR/lease-session" 'codex' || return 1
  [[ -f $STATE_ROOT/sessions/$DIAG_SESSION ]] || return 1
  return 0
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

# Prove the shell fixture itself before checking the deliberately missing file.
setup_case fixture-self-test
if [[ -d $PLAN_DIR && -f $PLAN_DIR/plan.json && $(mode_of "$STATE_ROOT") == 700 ]]; then
  # Plant helper self-check: sha256 + modes (must pass without the binary).
  mkdir -p "$WORKFLOWS_ROOT/wf-fixture-self/mirror-queue" "$WORKFLOWS_ROOT/wf-fixture-self/requests" \
    "$WORKFLOWS_ROOT/byproject"
  chmod 700 "$WORKFLOWS_ROOT" "$WORKFLOWS_ROOT/byproject" \
    "$WORKFLOWS_ROOT/wf-fixture-self" \
    "$WORKFLOWS_ROOT/wf-fixture-self/mirror-queue" \
    "$WORKFLOWS_ROOT/wf-fixture-self/requests"
  printf 'body\n' >"$WORKFLOWS_ROOT/wf-fixture-self/pending-send.payload"
  chmod 600 "$WORKFLOWS_ROOT/wf-fixture-self/pending-send.payload"
  digest=$(sha256_of_file "$WORKFLOWS_ROOT/wf-fixture-self/pending-send.payload")
  if [[ ${#digest} -eq 64 \
      && $(mode_of "$WORKFLOWS_ROOT") == 700 \
      && $(mode_of "$WORKFLOWS_ROOT/byproject") == 700 \
      && $(mode_of "$WORKFLOWS_ROOT/wf-fixture-self") == 700 ]]; then
    pass 'hermetic registry fixture self-test'
  else
    fail 'hermetic registry fixture self-test' 'sha256 or 0700 layout helper broken'
  fi
  rm -rf "$WORKFLOWS_ROOT"
else
  fail 'hermetic registry fixture self-test' 'private fixture could not be initialized'
fi

if [[ ! -x $REGISTRY ]]; then
  # Still emit an explicit gate failure, then run every case so the green
  # implementer sees the full red surface (each case fails closed).
  fail 'workflow-registry executable exists' "missing executable: $REGISTRY"
fi

# registry-red
run_test 'workflowId mint format matches wf-<project>-<UTCstamp>-<4hex>' test_mint_workflow_id_format
run_test 'one active workflow per project; second mint refuses with live id' test_one_active_workflow_per_project
run_test 'byproject binding records the current workflowId' test_byproject_binding
run_test 'registry dirs are 0700 and state files are 0600' test_modes_0700_dirs_0600_files
run_test 'closed op set refuses unknown ops without mutating state' test_closed_op_refusal
run_test 'Mini-side mini-workflow.json marker written; no client-side provenance' test_mini_side_marker_no_client_provenance
run_test 'client-close persistence: state byte-identical after simulated relay death' test_client_close_persistence_byte_identical
run_test 'fresh-client list enumerates workflows latches queue-one mirror jobs ≤4096 B' test_fresh_client_list_enumerates_and_is_bounded

# lifecycle-red — start / re-bind
run_test 'start-conductor is Claude-only and refuses non-Claude harness atoms' test_start_conductor_is_claude_only
run_test 'start-conductor ordered mutex+CAS+lease binds Claude session and byproject' test_start_conductor_ordered_mutex_cas_lease
run_test 'second start-conductor on a bound project refuses with the live id' test_second_start_refuses_with_live_id
run_test 'reboot-orphaned ACTIVE lease re-binds same workflowId with generation bump' test_rebind_orphaned_active_lease_same_workflow_bumps_generation
run_test 're-bind is idempotent against a live conductor; resume-scan is a no-op' test_rebind_idempotent_against_live_conductor

# lifecycle-red — episodes / resume-scan (D2)
run_test 'resume-scan re-binds an exited open workflow and increments recovery attempts' test_resume_scan_rebinds_exited_open_workflow
run_test 'recovery.json attempts increment before each attempt and survive reboot' test_recovery_attempts_increment_before_attempt_and_survive_reboot
run_test '3rd failure sets sticky failed-recovery, emits feed, stops auto retries' test_third_failure_sets_sticky_failed_recovery_and_stops_retries
run_test 'human start-conductor mints a NEW episode journaling the prior failure' test_human_start_mints_new_episode_journaling_prior_failure
run_test 'resume-scan no-op on healthy/quiescent/failed-recovery; reconciles delivery-pending' test_resume_scan_noop_healthy_quiescent_failed_and_reconciles_delivery_pending

# lifecycle-red — mutex recovery
run_test 'wedged dead-pid protocol mutex auto-recovers as transient recovering' test_dead_pid_protocol_mutex_auto_recovers_as_recovering
run_test 'live-pid protocol mutex refuses without stealing the holder' test_live_pid_protocol_mutex_refuses

# lifecycle-red — kill/quiesce/release + refusals
run_test 'kill records quiescent without release; release clears lease and byproject' test_kill_quiesce_release_semantics
run_test 'release refuses without quiescence and leaves the live bind intact' test_release_refuses_without_quiescence
run_test 'existing remote-agent-v1 refusals surface unchanged through registry ops' test_existing_protocol_refusals_surface_through_registry
run_test 'diagnostic-held refuses start-conductor boundedly' test_diagnostic_held_refuses_start_conductor_boundedly

printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
