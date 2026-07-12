#!/usr/bin/env bash
set -euo pipefail

# RED/GREEN integration for workflow-resume LaunchAgent packaging (D2):
#   - plist invokes workflow-registry resume-scan at load + bounded interval
#   - repeated scans are idempotent (episode ledger prevents double re-bind)
#   - failed-recovery stickiness honored; delivery-pending reconciled
#   - zero frontier/lane logic outside the registry (structural)
#   - scan failures journaled; never user-visible crashes
#   - LaunchAgent PATH is install-time resolved (Homebrew/user bins), not
#     system-only /usr/bin:/bin — tests prove resolution WITHOUT stub PATH
#   - unresolvable tmux/claude is NEVER treated as a dead session (no attempt burn)
#   - installer creates @STATE_HOME@/orchestration/workflows/logs/
#
# Targets:
#   orchestration/templates/mini-relay/com.orchestration.workflow-resume.plist
#   orchestration/scripts/workflow-registry (resume-scan + install-launchagent)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPTS_DIR=$(cd "$SCRIPT_DIR/../../scripts" && pwd -P)
REGISTRY="$SCRIPTS_DIR/workflow-registry"
AGENT_SUPERVISOR="$SCRIPTS_DIR/agent-supervisor"
PLIST="$SCRIPT_DIR/../../templates/mini-relay/com.orchestration.workflow-resume.plist"
PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
trap 'rm -rf "$SUITE"' EXIT

WORKFLOW_ID_RE='^wf-orchestration-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}$'
# StartInterval must be bounded (seconds): frequent enough to recover, not a tight spin.
MIN_INTERVAL=30
MAX_INTERVAL=600

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
  local path=$1
  stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path"
}

# Minimal tmux + session stubs so lifecycle re-bind can compose without a
# real terminal server (matches workflow-registry lifecycle harness).
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
  # Harness-only claude atom so require_resume_rebind_bins can resolve it.
  # Real install PATH must still point at the host claude (see install tests).
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
  CHECKOUT="$CASE/mini-checkout"
  PLAN_ID="resume-supervisor-plan"
  PLAN_DIR="$CHECKOUT/.temp/plan-mode/active/$PLAN_ID"
  HOSTNAME_FIXTURE="mini-test-host"
  PROJECT=orchestration
  WORKFLOWS_ROOT="$STATE_ROOT/orchestration/workflows"
  AUTHORITY_PATH="$STATE_ROOT/orchestration/remote-agent"
  PROTOCOL_PROJECT_DIR="$AUTHORITY_PATH/projects/$PROJECT"
  SESSION="remote-agent--$PROJECT--claude"
  FAKE_BIN="$CASE/bin"
  STDOUT="$CASE/stdout"
  STDERR="$CASE/stderr"
  WORKFLOW_ID=
  mkdir -p "$HOME_DIR" "$STATE_ROOT" "$CHECKOUT" "$PLAN_DIR" "$FAKE_BIN"
  chmod 700 "$HOME_DIR" "$STATE_ROOT" "$CHECKOUT"
  install_lifecycle_stubs "$FAKE_BIN"
  printf '%s\n' '{"planId":"resume-supervisor-plan","frozen":true}' >"$PLAN_DIR/plan.json"
  printf '%s\n' '{"planId":"resume-supervisor-plan","steps":{}}' >"$PLAN_DIR/progress.json"
  printf '# resume-supervisor plan\n' >"$PLAN_DIR/masterPlan.md"
  : >"$STDOUT"
  : >"$STDERR"
}

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
    "$REGISTRY" "$@" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
}

run_registry_with_fault() {
  local fault=$1
  shift
  WORKFLOW_REGISTRY_TEST_FAULT=$fault run_registry "$@"
}

# Install / path-resolution helpers: do NOT inject stub-bin PATH. The install
# path must discover real tool locations the way launchd will see them after
# substitution. Optional extra_path is prepended (e.g. homebrew) when needed.
run_registry_install_env() {
  local install_path=${1:-}
  shift
  local path_for_install
  if [[ -n $install_path ]]; then
    path_for_install=$install_path
  else
    # Machine PATH with common tool roots — never the test stub bin.
    path_for_install="/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin:${HOME}/.local/yolo-bin:${BASE_PATH}"
  fi
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
    PATH="$path_for_install" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    "$REGISTRY" "$@" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
}

# resume-scan under a PATH that deliberately cannot resolve tmux/claude.
# SAFETY: must fail loudly and MUST NOT increment recovery attempts.
# NOTE: do not prepend JQ_DIR when it is homebrew/local (those also hold tmux).
# Plant an isolated bin that only exposes jq.
run_registry_no_lifecycle_bins() {
  local jq_only_bin path_no_tools
  jq_only_bin="$CASE/jq-only-bin"
  mkdir -p "$jq_only_bin"
  if [[ -n $REAL_JQ ]]; then
    ln -sfn "$REAL_JQ" "$jq_only_bin/jq"
  fi
  # System bins only + isolated jq — no homebrew, no FAKE_BIN, no claude.
  path_no_tools="$jq_only_bin:/usr/bin:/bin"
  # Sanity: this PATH must not resolve tmux or claude (else the test is invalid).
  if PATH="$path_no_tools" command -v tmux >/dev/null 2>&1; then
    printf 'test fixture invalid: tmux still resolvable on restricted PATH\n' >&2
    STATUS=99
    return 0
  fi
  if PATH="$path_no_tools" command -v claude >/dev/null 2>&1; then
    printf 'test fixture invalid: claude still resolvable on restricted PATH\n' >&2
    STATUS=99
    return 0
  fi
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
    PATH="$path_no_tools" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    STATE_ROOT="$STATE_ROOT" \
    WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    "$REGISTRY" "$@" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
}

expect_success() { run_registry "$@"; [[ $STATUS -eq 0 ]]; }
expect_failure() { run_registry "$@"; [[ $STATUS -ne 0 ]]; }

plist_path_value() {
  # Extract the <string> immediately after <key>PATH</key> (portable awk).
  awk '
    /<key>PATH<\/key>/ {
      getline
      gsub(/.*<string>/, "")
      gsub(/<\/string>.*/, "")
      print
      exit
    }
  ' "$1"
}

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

workflow_dir_of() { printf '%s\n' "$WORKFLOWS_ROOT/$1"; }

json_field() {
  local file=$1 key=$2
  if [[ -n $REAL_JQ && -s $file ]]; then
    jq -r --arg k "$key" 'if type == "object" then (.[$k] // empty) else empty end' "$file" 2>/dev/null | head -n 1
    return 0
  fi
  sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p" "$file" 2>/dev/null | head -n 1
}

extract_workflow_id() {
  if [[ -n $REAL_JQ && -s $STDOUT ]]; then
    jq -r '.workflowId // empty' "$STDOUT" 2>/dev/null | head -n 1
    return 0
  fi
  sed -n 's/.*"workflowId":"\([^"]*\)".*/\1/p' "$STDOUT" 2>/dev/null | head -n 1
}

capture_workflow_id_from_stdout() {
  WORKFLOW_ID=$(extract_workflow_id) || return 1
  [[ $WORKFLOW_ID =~ $WORKFLOW_ID_RE ]] || return 1
  return 0
}

ensure_protocol_project() {
  mkdir -p "$PROTOCOL_PROJECT_DIR"
  chmod 700 "$AUTHORITY_PATH" 2>/dev/null || true
  chmod 700 "$AUTHORITY_PATH/projects" 2>/dev/null || true
  chmod 700 "$PROTOCOL_PROJECT_DIR"
}

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
  rm -f "$STATE_ROOT/sessions/$SESSION"
}

plant_live_session_marker() {
  mkdir -p "$STATE_ROOT/sessions"
  printf '%%42\n' >"$STATE_ROOT/sessions/$SESSION"
}

plant_exited_open_workflow() {
  local id=$1
  local wf_dir
  wf_dir=$(workflow_dir_of "$id")
  mkdir -p "$wf_dir" "$wf_dir/journal"
  chmod 700 "$wf_dir" "$wf_dir/journal" 2>/dev/null || true
  printf 'exited\n' >"$wf_dir/phase"
  chmod 600 "$wf_dir/phase"
  mkdir -p "$WORKFLOWS_ROOT/byproject"
  chmod 700 "$WORKFLOWS_ROOT" "$WORKFLOWS_ROOT/byproject" 2>/dev/null || true
  printf '%s\n' "$id" >"$WORKFLOWS_ROOT/byproject/$PROJECT"
  chmod 600 "$WORKFLOWS_ROOT/byproject/$PROJECT"
  rm -f "$STATE_ROOT/sessions/$SESSION"
}

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
      --arg lastAttemptAt "2026-07-12T00:00:00Z" \
      '{episodeId:$episodeId,attempts:$attempts,state:$state,lastAttemptAt:$lastAttemptAt}' \
      >"$path"
  else
    cat >"$path" <<JSON
{"episodeId":"$episode","attempts":$attempts,"state":"$state","lastAttemptAt":"2026-07-12T00:00:00Z"}
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
}

bootstrap_bound_workflow() {
  expect_success start-conductor "$PROJECT" "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE" || return 1
  capture_workflow_id_from_stdout || return 1
  return 0
}

# ── structural: LaunchAgent packaging ──────────────────────────────────────

test_plist_invokes_resume_scan_at_load_and_interval() {
  [[ -f $PLIST ]] || return 1

  # Label + GUI user LaunchAgent shape (no root/system daemon markers).
  assert_contains "$PLIST" 'com.orchestration.workflow-resume' || return 1
  assert_contains "$PLIST" 'RunAtLoad' || return 1
  assert_contains "$PLIST" 'StartInterval' || return 1
  # One-shot scan: interval wake, not a long-lived KeepAlive loop of custom logic.
  assert_lacks "$PLIST" 'KeepAlive' || return 1
  assert_lacks "$PLIST" 'UserName' || return 1
  assert_lacks "$PLIST" 'RootDirectory' || return 1

  # ProgramArguments must be ONLY workflow-registry + resume-scan.
  assert_contains "$PLIST" 'workflow-registry' || return 1
  assert_contains "$PLIST" 'resume-scan' || return 1
  # No other ops / shell wrappers in ProgramArguments.
  assert_lacks "$PLIST" 'bash' || return 1
  assert_lacks "$PLIST" '/bin/sh' || return 1
  assert_lacks "$PLIST" 'start-conductor' || return 1
  assert_lacks "$PLIST" 'compute-frontier' || return 1
  assert_lacks "$PLIST" 'plan-utils' || return 1

  # Bounded interval: extract integer after StartInterval key.
  local interval
  interval=$(awk '
    /<key>StartInterval<\/key>/ { getline; if (match($0, /[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit } }
  ' "$PLIST")
  [[ -n ${interval:-} ]] || return 1
  (( interval >= MIN_INTERVAL && interval <= MAX_INTERVAL )) || return 1

  # Template placeholders until install substitutes them.
  assert_contains "$PLIST" '@PLUGIN_ROOT@' || return 1
  assert_contains "$PLIST" '@STATE_HOME@' || return 1
  # PATH must be install-time substituted — not a hardcoded system-only PATH
  # that cannot resolve tmux/claude under launchd on a real Mac.
  assert_contains "$PLIST" '@PATH@' || return 1
  local tmpl_path
  tmpl_path=$(plist_path_value "$PLIST")
  [[ $tmpl_path == '@PATH@' ]] || return 1
  # Refuse the production defect: system-only PATH as the shipped value.
  [[ $tmpl_path != '/usr/bin:/bin:/usr/sbin:/sbin' ]] || return 1
  grep -Eq 'install|placeholder|substituted|template|NOT installed|install-launchagent' "$PLIST" || return 1
  grep -Eq '@PATH@|homebrew|/opt/homebrew|install-time|install time' "$PLIST" || return 1

  # Failures land in launchd log paths, not user-visible dialogs.
  assert_contains "$PLIST" 'StandardOutPath' || return 1
  assert_contains "$PLIST" 'StandardErrorPath' || return 1
  assert_contains "$PLIST" 'ProcessType' || return 1
  assert_contains "$PLIST" 'Background' || return 1
  assert_contains "$PLIST" 'workflows/logs' || return 1
  return 0
}

# Install-time PATH resolution + logs dir creation (no stub-bin masking).
test_install_resolves_path_and_creates_logs_dir() {
  [[ -x $REGISTRY && -f $PLIST ]] || return 1

  local dest_dir=$HOME_DIR/Library/LaunchAgents
  local dest=$dest_dir/com.orchestration.workflow-resume.plist
  local plugin_root
  plugin_root=$(cd "$SCRIPTS_DIR/.." && pwd -P)
  mkdir -p "$dest_dir"

  # Installer must see real tool roots (never FAKE_BIN).
  run_registry_install_env '' install-launchagent \
    --plugin-root "$plugin_root" \
    --dest "$dest" || return 1
  [[ $STATUS -eq 0 ]] || return 1
  [[ -f $dest ]] || return 1

  # Placeholders fully substituted.
  assert_lacks "$dest" '@PLUGIN_ROOT@' || return 1
  assert_lacks "$dest" '@STATE_HOME@' || return 1
  assert_lacks "$dest" '@PATH@' || return 1
  assert_contains "$dest" "$plugin_root/scripts/workflow-registry" || return 1
  assert_contains "$dest" 'resume-scan' || return 1

  # CRITICAL: installed PATH must resolve tmux WITHOUT any stub-bin injection.
  local installed_path
  installed_path=$(plist_path_value "$dest")
  [[ -n $installed_path ]] || return 1
  # Must not be the launchd-unsafe system-only default.
  [[ $installed_path != '/usr/bin:/bin:/usr/sbin:/sbin' ]] || return 1
  # Prefer homebrew / local tool roots on this machine.
  printf '%s' "$installed_path" | grep -Eq '/opt/homebrew/bin|/usr/local/bin|\.local/bin' || return 1

  local resolved_tmux resolved_claude
  resolved_tmux=$(PATH="$installed_path" command -v tmux 2>/dev/null || true)
  [[ -n $resolved_tmux && -x $resolved_tmux ]] || return 1
  # claude is required for re-bind; if present on the host install PATH, it must resolve.
  if command -v claude >/dev/null 2>&1; then
    resolved_claude=$(PATH="$installed_path" command -v claude 2>/dev/null || true)
    [[ -n $resolved_claude && -x $resolved_claude ]] || return 1
  fi

  # Template remains unsubstituted source of truth.
  assert_contains "$PLIST" '@PATH@' || return 1
  assert_contains "$PLIST" '@PLUGIN_ROOT@' || return 1

  # launchd will not create parent dirs — installer must.
  [[ -d $STATE_ROOT/orchestration/workflows/logs ]] || return 1
  # Directory is private (700) consistent with workflow state layout.
  local mode
  mode=$(mode_of "$STATE_ROOT/orchestration/workflows/logs")
  [[ $mode == 700 ]] || return 1
  return 0
}

# SAFETY: missing tmux/claude must fail loudly and never burn a recovery attempt.
test_unresolvable_binary_not_treated_as_dead_session() {
  [[ -x $REGISTRY ]] || return 1
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local gen_before attempts_before attempts_after episode_before episode_after

  gen_before=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_before:-} ]] || gen_before=0

  # Healthy-looking open workflow whose session probe needs tmux. Without the
  # safety gate, missing tmux looks like DEAD and burns attempt 1 of 3.
  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease "$gen_before"
  write_recovery_json "$first" "ep-missbin-1" 0 recovering
  # Leave no live marker — only the probe can decide; missing binary must not
  # be counted as dead.
  rm -f "$STATE_ROOT/sessions/$SESSION"

  attempts_before=$(read_recovery_attempts "$first" || true)
  episode_before=$(read_recovery_episode "$first" || true)
  [[ $attempts_before == 0 ]] || return 1
  [[ $episode_before == ep-missbin-1 ]] || return 1

  run_registry_no_lifecycle_bins resume-scan
  # Loud failure (non-zero), not a silent "session dead → attempt++" success.
  [[ $STATUS -ne 0 ]] || return 1
  # Machine-readable missing-dependency signal (stdout and/or stderr).
  grep -Eiq 'missing-dependency|unresolvable|tmux|claude|required binary' "$STDOUT" "$STDERR" \
    || return 1

  attempts_after=$(read_recovery_attempts "$first" || true)
  episode_after=$(read_recovery_episode "$first" || true)
  # MUST NOT consume a recovery attempt.
  [[ $attempts_after == 0 ]] || return 1
  [[ $episode_after == ep-missbin-1 ]] || return 1
  # Must not have entered sticky failed-recovery.
  local phase state
  phase=$(read_phase "$first" || true)
  [[ $phase != failed-recovery ]] || return 1
  state=$(read_recovery_state "$first" || true)
  [[ $state != failed-recovery && $state != failed ]] || return 1
  # No re-bind session created under restricted PATH.
  [[ ! -f $STATE_ROOT/sessions/$SESSION ]] || return 1
  return 0
}

test_supervisor_path_has_zero_frontier_lane_logic() {
  # Packaging surface (plist body, comments stripped): no plan frontier /
  # verifier-lane machinery. Comments may name the invariant; the loadable
  # keys must not implement it.
  [[ -f $PLIST ]] || return 1
  local body
  body=$(sed -e '/<!--/,/-->/d' "$PLIST")
  printf '%s' "$body" | grep -Eiq \
    'compute-frontier|currentFrontier|laneDispatch|laneDispatches|record-lane|owner:[[:space:]]*(codex|grok|claude)|plan-utils|set-frontier' \
    && return 1

  # agent-supervisor (hook projection) must not grow resume/frontier/lane logic
  # for D2 — resume is registry resume-scan only.
  if [[ -f $AGENT_SUPERVISOR ]]; then
    if grep -Eiq \
      'compute-frontier|currentFrontier|laneDispatch|laneDispatches|resume-scan.*frontier|frontier.*resume' \
      "$AGENT_SUPERVISOR"; then
      return 1
    fi
  fi

  # Plist ProgramArguments: only the two atoms (path + resume-scan).
  local args_block
  args_block=$(awk '
    /<key>ProgramArguments<\/key>/ { grab=1 }
    grab && /<\/array>/ { print; exit }
    grab { print }
  ' "$PLIST")
  printf '%s' "$args_block" | grep -Fq 'resume-scan' || return 1
  printf '%s' "$args_block" | grep -Fq 'workflow-registry' || return 1
  # Exactly two <string> entries in ProgramArguments (binary + one arg).
  local string_count
  string_count=$(printf '%s\n' "$args_block" | grep -c '<string>' || true)
  [[ $string_count -eq 2 ]] || return 1
  # No extra program args smuggling plan/frontier verbs.
  printf '%s' "$args_block" | grep -Eiq 'frontier|lane|plan-utils|start-conductor' && return 1
  return 0
}

# ── integration: D2 via registry (plist delegates all logic) ───────────────

test_repeated_scans_idempotent_episode_ledger() {
  [[ -x $REGISTRY ]] || return 1
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local gen_before gen_after gen_repeat attempts1 attempts2 episode1 episode2
  local snap_before snap_after

  gen_before=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_before:-} ]] || gen_before=0

  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease "$gen_before"
  write_recovery_json "$first" "ep-idemp-1" 0 recovering

  # First scan re-binds once.
  expect_success resume-scan || return 1
  gen_after=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_after:-} ]] || return 1
  (( gen_after > gen_before )) || return 1
  attempts1=$(read_recovery_attempts "$first" || true)
  episode1=$(read_recovery_episode "$first" || true)
  [[ -n ${attempts1:-} && -n ${episode1:-} ]] || return 1
  (( attempts1 >= 1 && attempts1 <= 3 )) || return 1
  # Live session after re-bind.
  [[ -f $STATE_ROOT/sessions/$SESSION ]] || return 1

  # Second + third scans: no double re-bind (episode ledger + live session).
  snap_before=$(lifecycle_fingerprint)
  expect_success resume-scan || return 1
  expect_success resume-scan || return 1
  snap_after=$(lifecycle_fingerprint)
  [[ $snap_after == "$snap_before" ]] || return 1

  gen_repeat=$(read_meta_lease_generation "$first" || true)
  [[ $gen_repeat == "$gen_after" ]] || return 1
  attempts2=$(read_recovery_attempts "$first" || true)
  episode2=$(read_recovery_episode "$first" || true)
  [[ $attempts2 == "$attempts1" ]] || return 1
  [[ $episode2 == "$episode1" ]] || return 1
  return 0
}

test_failed_recovery_stickiness_honored() {
  [[ -x $REGISTRY ]] || return 1
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local gen_before attempts snap_before snap_after phase

  gen_before=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_before:-} ]] || gen_before=0

  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease "$gen_before"
  # Sticky failed-recovery already recorded (3 attempts).
  write_recovery_json "$first" "ep-sticky-pkg" 3 failed-recovery
  printf 'failed-recovery\n' >"$(workflow_dir_of "$first")/phase"
  chmod 600 "$(workflow_dir_of "$first")/phase"

  snap_before=$(lifecycle_fingerprint)
  expect_success resume-scan || return 1
  expect_success resume-scan || return 1
  snap_after=$(lifecycle_fingerprint)
  [[ $snap_after == "$snap_before" ]] || return 1

  phase=$(read_phase "$first" || true)
  [[ $phase == failed-recovery ]] || return 1
  attempts=$(read_recovery_attempts "$first" || true)
  [[ $attempts == 3 ]] || return 1
  local state
  state=$(read_recovery_state "$first" || true)
  [[ $state == failed-recovery || $state == failed ]] || return 1
  # No live re-bind under stickiness.
  [[ ! -f $STATE_ROOT/sessions/$SESSION ]] || return 1
  return 0
}

test_delivery_pending_reconciled_on_scan() {
  [[ -x $REGISTRY && -n $REAL_JQ ]] || return 1
  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local jdir request_id=req-resume-pkg-$$ payload="resume-pkg-payload-$$"
  local digest seq=1

  jdir="$(workflow_dir_of "$first")/journal"
  mkdir -p "$jdir"
  ensure_protocol_project

  digest=$(printf '%s' "$payload" | shasum -a 256 | awk '{print $1}')
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
  printf 'pending-token-%s\n' "$$" >"$(workflow_dir_of "$first")/delivery-pending"
  chmod 600 "$(workflow_dir_of "$first")/delivery-pending"
  printf 'needs-input\n' >"$(workflow_dir_of "$first")/phase"
  write_recovery_json "$first" "ep-deliv" 0 idle
  plant_live_session_marker
  rm -f "$PROTOCOL_PROJECT_DIR/quiescent"

  expect_success resume-scan || return 1

  [[ ! -f $(workflow_dir_of "$first")/delivery-pending ]] || return 1
  [[ ! -e $(workflow_dir_of "$first")/pending-send.payload ]] || return 1
  [[ ! -e $(workflow_dir_of "$first")/pending-send.json ]] || return 1
  assert_contains "$(workflow_dir_of "$first")/needs-input.json" 'acked' || return 1
  grep -Rq 'delivered-from-queue' "$jdir" 2>/dev/null || return 1
  return 0
}

test_scan_failures_journaled_never_user_visible_crash() {
  [[ -x $REGISTRY ]] || return 1
  # Structural: launchd captures stdout/stderr; no crash dialog machinery.
  [[ -f $PLIST ]] || return 1
  assert_contains "$PLIST" 'StandardOutPath' || return 1
  assert_contains "$PLIST" 'StandardErrorPath' || return 1
  # Logs under state home (not /dev/console, not ~/Desktop).
  assert_contains "$PLIST" '@STATE_HOME@' || return 1
  assert_lacks "$PLIST" '/dev/console' || return 1
  assert_lacks "$PLIST" 'Desktop' || return 1
  # Background process type — not interactive crash UI.
  assert_contains "$PLIST" 'Background' || return 1

  bootstrap_bound_workflow || return 1
  local first=$WORKFLOW_ID
  local gen_before attempts episode recovery_path fault_mark jdir

  gen_before=$(read_meta_lease_generation "$first" || true)
  [[ -n ${gen_before:-} ]] || gen_before=0
  plant_exited_open_workflow "$first"
  plant_orphaned_active_lease "$gen_before"
  write_recovery_json "$first" "ep-fail-j" 0 recovering

  recovery_path="$(workflow_dir_of "$first")/recovery.json"
  jdir="$(workflow_dir_of "$first")/journal"
  fault_mark="$STATE_ROOT/orchestration/test-faults/crash-after-recovery-increment"
  mkdir -p "$(dirname "$fault_mark")"
  printf 'armed\n' >"$fault_mark"
  chmod 600 "$fault_mark"

  # Injected mid-scan crash: durable journal/recovery, non-zero exit, no session re-bind.
  run_registry_with_fault crash-after-recovery-increment resume-scan
  [[ $STATUS -ne 0 ]] || return 1
  if [[ -f $fault_mark ]]; then
    [[ $(tr -d '\n' <"$fault_mark") == consumed ]] || return 1
  fi
  attempts=$(read_recovery_attempts "$first" || true)
  [[ -n ${attempts:-} ]] || return 1
  (( attempts >= 1 )) || return 1
  episode=$(read_recovery_episode "$first" || true)
  [[ $episode == ep-fail-j ]] || return 1
  [[ -f $recovery_path ]] || return 1
  # Journal / phase evidence of the recovery attempt (not a silent crash).
  grep -RqiE 'recover|recovery-attempt|lifecycle' "$jdir" 2>/dev/null \
    || [[ $(read_phase "$first" || true) == recovering ]] \
    || return 1
  # No live session after fault (re-bind did not complete).
  [[ ! -f $STATE_ROOT/sessions/$SESSION ]] || return 1
  # Bounded machine-readable channels — not an uncaught traceback blast.
  local bytes
  bytes=$(wc -c <"$STDOUT" | tr -d ' ')
  local ebytes
  ebytes=$(wc -c <"$STDERR" | tr -d ' ')
  (( bytes + ebytes < 65536 )) || return 1
  return 0
}

# ── runner ─────────────────────────────────────────────────────────────────

run_test 'plist invokes workflow-registry resume-scan at load + bounded interval' \
  test_plist_invokes_resume_scan_at_load_and_interval
run_test 'supervisor path has zero frontier/lane logic (structural)' \
  test_supervisor_path_has_zero_frontier_lane_logic
run_test 'install-launchagent resolves PATH (no stub) and creates logs dir' \
  test_install_resolves_path_and_creates_logs_dir
run_test 'unresolvable binary is not a dead session (no attempt burn)' \
  test_unresolvable_binary_not_treated_as_dead_session
run_test 'repeated resume-scan is idempotent via episode ledger' \
  test_repeated_scans_idempotent_episode_ledger
run_test 'scan honors failed-recovery stickiness (no auto re-bind)' \
  test_failed_recovery_stickiness_honored
run_test 'scan reconciles delivery-pending through registry queue-one' \
  test_delivery_pending_reconciled_on_scan
run_test 'scan failures are journaled; never user-visible crashes' \
  test_scan_failures_journaled_never_user_visible_crash

printf '\n%s\n' "resume-supervisor tests: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi
exit 0
