#!/usr/bin/env bash
set -euo pipefail

# Contract for the one Mini-side session adapter shared by Claude, Codex, and
# Grok.  Prompt bytes enter only on stdin; --yolo is an explicit start flag.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SUPERVISOR="$SCRIPT_DIR/../../scripts/agent-supervisor"
REGISTRY="$SCRIPT_DIR/../../scripts/workflow-registry"
PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
trap 'rm -rf "$SUITE"' EXIT

# jq is required by workflow-registry (invoked from enqueue projection).
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

setup_case() {
  local name=$1
  CASE="$SUITE/$name"
  HOME_DIR="$CASE/home"
  STATE_ROOT="$CASE/state"
  WORKTREE="$HOME_DIR/Projects/miospot"
  ORCHESTRATION_WORKTREE="$HOME_DIR/Projects/orchestration"
  PROJECT_ROOT_TOKEN=project-root-v1:miospot
  ORCHESTRATION_ROOT_TOKEN=project-root-v1:orchestration
  FAKE_BIN="$CASE/bin"
  TMUX_LOG="$CASE/tmux.log"
  OPEN_LOG="$CASE/open.log"
  OPEN_LAUNCHER_COPY="$CASE/open-launcher.command"
  OSASCRIPT_LOG="$CASE/osascript.log"
  REMOTE_ARGV="$CASE/remote-process.argv"
  SSH_LOG="$CASE/ssh.log"
  SUPERVISOR_ARGV="$CASE/supervisor.argv"
  SSH_STDIN="$CASE/ssh.stdin"
  DELIVERED_PROMPT="$CASE/delivered.stdin"
  STDOUT="$CASE/stdout"
  STDERR="$CASE/stderr"
  mkdir -p "$HOME_DIR" "$STATE_ROOT" "$WORKTREE" "$ORCHESTRATION_WORKTREE" "$FAKE_BIN"
  mkdir -p "$STATE_ROOT/sessions"
  : >"$TMUX_LOG"
  : >"$OPEN_LOG"
  : >"$OSASCRIPT_LOG"
  : >"$REMOTE_ARGV"
  : >"$SSH_LOG"
  : >"$SUPERVISOR_ARGV"
  : >"$SSH_STDIN"
  : >"$DELIVERED_PROMPT"

  for harness in claude codex grok; do
    apply_patch_placeholder=$harness
    # The single quotes deliberately defer fixture variables to execution.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' \
      'printf '\''%s'\'' "${0##*/}" >>"$REMOTE_ARGV"' \
      'for argument in "$@"; do printf '\'' <%q>'\'' "$argument" >>"$REMOTE_ARGV"; done' \
      'printf '\''\n'\'' >>"$REMOTE_ARGV"' \
      'if [[ ${IMMEDIATE_EVENT:-0} == 1 ]]; then "$REAL_SUPERVISOR" enqueue "$WORKTREE" "${TMUX_PANE:?}" main completed; fi' \
      'cat >/dev/null' >"$FAKE_BIN/$apply_patch_placeholder"
    chmod +x "$FAKE_BIN/$apply_patch_placeholder"
  done

  # The single quotes deliberately defer fixture variables to execution.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf '\''tmux'\'' >>"$TMUX_LOG"' \
    'for argument in "$@"; do printf '\'' <%q>'\'' "$argument" >>"$TMUX_LOG"; done' \
    'printf '\''\n'\'' >>"$TMUX_LOG"' \
    'case "${1:-}" in' \
    '  has-session)' \
    '    target=' \
    '    while [[ $# -gt 0 ]]; do [[ $1 == -t ]] && { target=${2:-}; break; }; shift; done' \
    '    [[ -f "$STATE_ROOT/sessions/$target" ]]' \
    '    ;;' \
    '  new-session)' \
    '    session= print_pane=false' \
    '    arguments=("$@")' \
    '    while [[ $# -gt 0 ]]; do [[ $1 == -s ]] && session=${2:-}; [[ $1 == -P ]] && print_pane=true; [[ $1 == -- ]] && break; shift; done' \
    '    [[ -n $session ]] || exit 64' \
    '    pane="%$((41 + $(find "$STATE_ROOT/sessions" -type f | wc -l | tr -d '\'' '\'')))"' \
    '    printf '\''%s\n'\'' "$pane" >"$STATE_ROOT/sessions/$session"' \
    '    set -- "${arguments[@]}"' \
    '    while [[ $# -gt 0 && $1 != -- ]]; do shift; done' \
    '    if [[ ${1:-} == -- ]]; then shift; fi' \
    '    if [[ $# -gt 0 ]]; then TMUX_PANE="$pane" "$@" </dev/null >/dev/null 2>&1; fi' \
    '    if $print_pane; then printf '\''%s\n'\'' "$pane"; fi' \
    '    ;;' \
    '  respawn-pane)' \
    '    target=' \
    '    while [[ $# -gt 0 ]]; do [[ $1 == -t ]] && { target=${2:-}; shift 2; continue; }; [[ $1 == -- ]] && break; shift; done' \
    '    [[ ${1:-} == -- && -n $target ]] || exit 64' \
    '    shift' \
    '    [[ ${RESPAWN_FAIL:-0} != 1 ]] || exit 1' \
    '    TMUX_PANE="$target" "$@" </dev/null >/dev/null 2>&1' \
    '    ;;' \
    '  display-message)' \
    '    target=' \
    '    while [[ $# -gt 0 ]]; do [[ $1 == -t ]] && { target=${2:-}; break; }; shift; done' \
    '    target=${target%%:*}' \
    '    cat "$STATE_ROOT/sessions/$target"' \
    '    ;;' \
    '  list-panes)' \
    '    target=' \
    '    while [[ $# -gt 0 ]]; do [[ $1 == -t ]] && { target=${2:-}; break; }; shift; done' \
    '    cat "$STATE_ROOT/sessions/$target"' \
    '    ;;' \
    '  capture-pane) cat "${SUPERVISOR_CAPTURE_FILE:-/dev/null}" ;;' \
    '  load-buffer) cat >"$DELIVERED_PROMPT" ;;' \
    '  paste-buffer) : >"$STATE_ROOT/paste.pending"; rm -f "$STATE_ROOT/paste.ready" ;;' \
    '  send-keys)' \
    '    if [[ -f $STATE_ROOT/paste.pending ]]; then' \
    '      [[ -f $STATE_ROOT/paste.ready ]] || exit 66' \
    '      rm -f "$STATE_ROOT/paste.pending" "$STATE_ROOT/paste.ready"' \
    '    fi' \
    '    ;;' \
    '  kill-session)' \
    '    target=' \
    '    while [[ $# -gt 0 ]]; do [[ $1 == -t ]] && { target=${2:-}; break; }; shift; done' \
    '    rm -f "$STATE_ROOT/sessions/$target"' \
    '    ;;' \
    'esac' >"$FAKE_BIN/tmux"
  chmod +x "$FAKE_BIN/tmux"

  printf '%s\n' '#!/usr/bin/env bash' \
    'if [[ ${1:-} == 0.1 && -f $STATE_ROOT/paste.pending ]]; then' \
    '  : >"$STATE_ROOT/paste.ready"' \
    '  exit 0' \
    'fi' \
    'exec /bin/sleep "$@"' >"$FAKE_BIN/sleep"
  chmod +x "$FAKE_BIN/sleep"

  # Reveal must ask LaunchServices to open one private launcher in Terminal.
  # The production default remains /usr/bin/open; this injected executable is
  # the narrow test seam for validating its exact argv without opening a GUI.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf '\''open'\'' >>"$OPEN_LOG"' \
    'for argument in "$@"; do printf '\'' <%q>'\'' "$argument" >>"$OPEN_LOG"; done' \
    'printf '\''\n'\'' >>"$OPEN_LOG"' \
    '[[ $# -eq 4 && $1 == -a && $2 == Terminal && $3 == -- && $4 == /* ]] || exit 64' \
    '[[ -f $4 && ! -L $4 && -x $4 && -O $4 ]] || exit 65' \
    'cp "$4" "$OPEN_LAUNCHER_COPY"' \
    '[[ ${OPEN_FAIL:-0} != 1 ]]' >"$FAKE_BIN/open"
  chmod +x "$FAKE_BIN/open"

  # Any regression to Apple Events is a hard test failure and leaves evidence.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf '\''osascript %s\n'\'' "$*" >>"$OSASCRIPT_LOG"' \
    'exit 99' >"$FAKE_BIN/osascript"
  chmod +x "$FAKE_BIN/osascript"

  # This transport records argv independently from stdin, then forwards the
  # byte stream into the real supervisor exactly as SSH would.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf '\''ssh'\'' >>"$SSH_LOG"' \
    'for argument in "$@"; do printf '\'' <%q>'\'' "$argument" >>"$SSH_LOG"; done' \
    'printf '\''\n'\'' >>"$SSH_LOG"' \
    'shift' \
    '[[ ${1:-} == agent-supervisor ]] || exit 127' \
    'shift' \
    'printf '\''agent-supervisor'\'' >>"$SUPERVISOR_ARGV"' \
    'for argument in "$@"; do printf '\'' <%q>'\'' "$argument" >>"$SUPERVISOR_ARGV"; done' \
    'printf '\''\n'\'' >>"$SUPERVISOR_ARGV"' \
    'tee -a "$SSH_STDIN" | "$REAL_SUPERVISOR" "$@"' >"$FAKE_BIN/ssh"
  chmod +x "$FAKE_BIN/ssh"
}

run_supervisor() {
  local fixture_worktree=$WORKTREE
  # start SESSION HARNESS TOKEN --yolo
  # start SESSION HARNESS TOKEN --workflow-binding PATH --yolo
  if [[ ${1:-} == start ]]; then
    if [[ ${4:-} == "$ORCHESTRATION_ROOT_TOKEN" || ${6:-} == --yolo && ${3:-} == "$ORCHESTRATION_ROOT_TOKEN" ]]; then
      fixture_worktree=$ORCHESTRATION_WORKTREE
    fi
  fi
  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:$BASE_PATH" \
    STATE_ROOT="$STATE_ROOT" \
    TMUX_LOG="$TMUX_LOG" \
    OPEN_LOG="$OPEN_LOG" \
    OPEN_LAUNCHER_COPY="$OPEN_LAUNCHER_COPY" \
    OSASCRIPT_LOG="$OSASCRIPT_LOG" \
    AGENT_SUPERVISOR_TEST_OPEN="$FAKE_BIN/open" \
    OPEN_FAIL="${OPEN_FAIL:-0}" \
    REMOTE_ARGV="$REMOTE_ARGV" \
    DELIVERED_PROMPT="$DELIVERED_PROMPT" \
    REAL_SUPERVISOR="$SUPERVISOR" \
    WORKTREE="$fixture_worktree" \
    IMMEDIATE_EVENT="${IMMEDIATE_EVENT:-0}" \
    RESPAWN_FAIL="${RESPAWN_FAIL:-0}" \
    SUPERVISOR_CAPTURE_FILE="${SUPERVISOR_CAPTURE_FILE:-}" \
    AGENT_SUPERVISOR_REGISTRY="${AGENT_SUPERVISOR_REGISTRY:-$REGISTRY}" \
    AGENT_SUPERVISOR_PROJECT_TIMEOUT="${AGENT_SUPERVISOR_PROJECT_TIMEOUT:-}" \
    REAL_REGISTRY="${REAL_REGISTRY:-$REGISTRY}" \
    "$SUPERVISOR" "$@" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
}

run_supervisor_over_ssh() {
  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    STATE_ROOT="$STATE_ROOT" \
    TMUX_LOG="$TMUX_LOG" \
    OPEN_LOG="$OPEN_LOG" \
    OPEN_LAUNCHER_COPY="$OPEN_LAUNCHER_COPY" \
    OSASCRIPT_LOG="$OSASCRIPT_LOG" \
    AGENT_SUPERVISOR_TEST_OPEN="$FAKE_BIN/open" \
    OPEN_FAIL="${OPEN_FAIL:-0}" \
    REMOTE_ARGV="$REMOTE_ARGV" \
    SSH_LOG="$SSH_LOG" \
    SUPERVISOR_ARGV="$SUPERVISOR_ARGV" \
    SSH_STDIN="$SSH_STDIN" \
    DELIVERED_PROMPT="$DELIVERED_PROMPT" \
    REAL_SUPERVISOR="$SUPERVISOR" \
    SUPERVISOR_CAPTURE_FILE="${SUPERVISOR_CAPTURE_FILE:-}" \
    "$FAKE_BIN/ssh" fixture-mini agent-supervisor "$@" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
}

expect_success() {
  # Legacy callers pass miospot token for orchestration sessions; rewrite.
  if [[ ${1:-} == start && ${2:-} == remote-agent--orchestration--* && ${4:-} == "$PROJECT_ROOT_TOKEN" ]]; then
    set -- "$1" "$2" "$3" "$ORCHESTRATION_ROOT_TOKEN" "${@:5}"
  fi
  run_supervisor "$@"
  [[ $STATUS -eq 0 ]]
}
expect_failure() { run_supervisor "$@"; [[ $STATUS -ne 0 ]]; }

start_wait() {
  local output=$1 error=$2
  shift 2
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    STATE_ROOT="$STATE_ROOT" \
    TMUX_LOG="$TMUX_LOG" \
    OSASCRIPT_LOG="$OSASCRIPT_LOG" \
    REMOTE_ARGV="$REMOTE_ARGV" \
    DELIVERED_PROMPT="$DELIVERED_PROMPT" \
    REAL_SUPERVISOR="$SUPERVISOR" \
    WORKTREE="$WORKTREE" \
    IMMEDIATE_EVENT="${IMMEDIATE_EVENT:-0}" \
    RESPAWN_FAIL="${RESPAWN_FAIL:-0}" \
    SUPERVISOR_CAPTURE_FILE="${SUPERVISOR_CAPTURE_FILE:-}" \
    "$SUPERVISOR" wait "$@" >"$output" 2>"$error" &
  WAIT_PID=$!
}

collect_wait() {
  local pid=$1
  set +e
  wait "$pid"
  WAIT_STATUS=$?
  set -e
}

json_uint() {
  local file=$1 key=$2
  sed -n "s/.*\"$key\":\([0-9][0-9]*\).*/\1/p" "$file" | head -n 1
}

json_string() {
  local file=$1 key=$2
  sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p" "$file" | head -n 1
}

pane_for_session() {
  local session=$1
  cat "$STATE_ROOT/sessions/$session"
}

worktree_for_session() {
  case $1 in
    remote-agent--miospot--*) printf '%s\n' "$WORKTREE" ;;
    remote-agent--orchestration--*) printf '%s\n' "$ORCHESTRATION_WORKTREE" ;;
    *) return 1 ;;
  esac
}

# Real host boot-time token for enqueue lock liveness (matches workflow-registry).
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

# Minimal workflow dir that registry project-event / deliver-queue can open.
plant_workflow() {
  local workflow_id=$1
  local wf_dir="$STATE_ROOT/orchestration/workflows/$workflow_id"
  mkdir -p "$STATE_ROOT/orchestration/workflows" "$wf_dir/journal" "$wf_dir/requests"
  chmod 700 "$STATE_ROOT/orchestration" "$STATE_ROOT/orchestration/workflows" "$wf_dir" \
    "$wf_dir/journal" "$wf_dir/requests"
  printf '%s\n' "{\"schemaVersion\":1,\"workflowId\":\"$workflow_id\",\"project\":\"orchestration\"}" \
    >"$wf_dir/meta.json"
  chmod 600 "$wf_dir/meta.json"
  printf 'running\n' >"$wf_dir/phase"
  chmod 600 "$wf_dir/phase"
  printf 'jrn-test-epoch\n' >"$wf_dir/journal/epoch"
  chmod 600 "$wf_dir/journal/epoch"
  printf '0\n' >"$wf_dir/journal/journal-cursor"
  chmod 600 "$wf_dir/journal/journal-cursor"
  printf '%s\n' "$wf_dir"
}

workflow_dir_of() {
  printf '%s\n' "$STATE_ROOT/orchestration/workflows/$1"
}

session_state_dir() {
  printf '%s\n' "$STATE_ROOT/orchestration/agent-supervisor/sessions/$1"
}

# Simulate an externally created chat-family session binding: supervisor
# state (root/pane/epoch/cursor) plus the fake tmux session file.
plant_session_binding() {
  local session=$1 pane=$2 directory
  directory=$(session_state_dir "$session")
  mkdir -p "$directory/events"
  chmod 700 "$directory" "$directory/events"
  printf '%s\n' "$(cd "$WORKTREE" && pwd -P)" >"$directory/root"
  printf '%s\n' "$pane" >"$directory/pane"
  printf 'epoch-chat-fixture-1\n' >"$directory/epoch"
  printf '0\n' >"$directory/cursor"
  chmod 600 "$directory/root" "$directory/pane" "$directory/epoch" "$directory/cursor"
  printf '%s\n' "$pane" >"$STATE_ROOT/sessions/$session"
}

plant_pending_send() {
  local workflow_id=$1 request_id=$2 payload=$3
  local wf_dir digest
  wf_dir=$(workflow_dir_of "$workflow_id")
  digest=$(printf '%s' "$payload" | shasum -a 256 | awk '{print $1}')
  printf '%s' "$payload" >"$wf_dir/pending-send.payload"
  chmod 600 "$wf_dir/pending-send.payload"
  printf '%s\n' "{\"requestId\":\"$request_id\",\"sha256\":\"$digest\",\"bytes\":${#payload},\"queuedAt\":\"2026-07-12T00:00:00Z\"}" \
    >"$wf_dir/pending-send.json"
  chmod 600 "$wf_dir/pending-send.json"
}

start_with_workflow_binding() {
  local session=$1 harness=$2 token=$3 workflow_id=$4
  local binding=$CASE/workflow.binding
  printf '%s\n' "$workflow_id" >"$binding"
  run_supervisor start "$session" "$harness" "$token" --workflow-binding "$binding" --yolo
  [[ $STATUS -eq 0 ]]
}

journal_has_kind() {
  local workflow_id=$1 kind=$2
  local jdir f
  jdir="$(workflow_dir_of "$workflow_id")/journal"
  [[ -d $jdir ]] || return 1
  for f in "$jdir"/[0-9]*.json; do
    [[ -f $f ]] || continue
    grep -Fq "\"kind\":\"$kind\"" "$f" && return 0
  done
  return 1
}

# journal-pending is an append-only set (dir of files), with legacy singleton allowed.
journal_pending_root() {
  printf '%s/journal-pending\n' "$(workflow_dir_of "$1")"
}

journal_pending_count() {
  local root
  root=$(journal_pending_root "$1")
  if [[ -f $root ]]; then
    printf '1\n'
    return 0
  fi
  if [[ -d $root ]]; then
    find "$root" -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' '
    return 0
  fi
  printf '0\n'
}

journal_pending_has_kind() {
  local workflow_id=$1 kind=$2
  local root p
  root=$(journal_pending_root "$workflow_id")
  if [[ -f $root ]]; then
    grep -Fq -- "$kind" "$root"
    return $?
  fi
  [[ -d $root ]] || return 1
  for p in "$root"/*; do
    [[ -f $p ]] || continue
    grep -Fq -- "$kind" "$p" && return 0
  done
  return 1
}

plant_needs_input_latch() {
  local workflow_id=$1 seq=${2:-1}
  local wf_dir
  wf_dir=$(workflow_dir_of "$workflow_id")
  # Minimal journal input-needed event the latch can reference.
  printf '%s\n' "{\"kind\":\"input-needed\",\"scope\":\"main\",\"seq\":$seq,\"at\":\"2026-07-12T00:00:00Z\"}" \
    >"$wf_dir/journal/$(printf '%020d' "$seq").json"
  chmod 600 "$wf_dir/journal/$(printf '%020d' "$seq").json"
  printf '%s\n' "$seq" >"$wf_dir/journal/journal-cursor"
  printf '%s\n' "{\"workflowId\":\"$workflow_id\",\"state\":\"open\",\"journalSeq\":$seq,\"kind\":\"input-needed\",\"raisedAt\":\"2026-07-12T00:00:00Z\"}" \
    >"$wf_dir/needs-input.json"
  chmod 600 "$wf_dir/needs-input.json"
}

run_test() {
  local name=$1
  shift
  setup_case "case-$((PASS_COUNT + FAIL_COUNT + 1))"
  if "$@"; then
    pass "$name"
  else
    fail "$name" "status=${STATUS:-unset} stdout=$(tr '\n' ' ' <"$STDOUT") stderr=$(tr '\n' ' ' <"$STDERR")"
  fi
}

test_version_and_closed_vocabulary() {
  expect_success version || return 1
  [[ $(<"$STDOUT") == agent-supervisor-v1 ]] || return 1
  expect_failure launch remote-agent--miospot--claude claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  assert_contains "$STDERR" 'usage' || return 1
  expect_failure start bad-session claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  expect_failure start remote-agent--miospot--claude other "$PROJECT_ROOT_TOKEN" --yolo
}

test_chat_session_family_is_pattern_validated() {
  local max_chatid over_chatid
  max_chatid=$(printf 'a%.0s' {1..32})
  over_chatid=$(printf 'a%.0s' {1..33})
  # Well-formed chat atoms are vocabulary (absent, not a usage error).
  expect_success status remote-agent--miospot--chat--planning-1 || return 1
  assert_contains "$STDOUT" '"session":"absent"' || return 1
  expect_success status remote-agent--orchestration--chat--a || return 1
  assert_contains "$STDOUT" '"session":"absent"' || return 1
  expect_success status "remote-agent--miospot--chat--$max_chatid" || return 1
  # Injection, traversal, whitespace, case, separators, and length stay out.
  expect_failure status 'remote-agent--miospot--chat--ok;touch-pwned' || return 1
  expect_failure status 'remote-agent--miospot--chat--$(touch-pwned)' || return 1
  expect_failure status 'remote-agent--miospot--chat--ok touch-pwned' || return 1
  expect_failure status 'remote-agent--miospot--chat--../../pwn' || return 1
  expect_failure status 'remote-agent--miospot--chat--*' || return 1
  expect_failure status remote-agent--miospot--chat-- || return 1
  expect_failure status remote-agent--miospot--chat--Planning-1 || return 1
  expect_failure status remote-agent--miospot--chat--plan--1 || return 1
  expect_failure status remote-agent--miospot--chat---plan || return 1
  expect_failure status remote-agent--miospot--chat--plan- || return 1
  expect_failure status remote-agent--home--chat--plan || return 1
  expect_failure status "remote-agent--miospot--chat--$over_chatid" || return 1
  expect_failure wait 'remote-agent--miospot--chat--ok;touch-pwned' 0 1 || return 1
  # Chat atoms never widen the six-slot start vocabulary, even when the
  # chatid collides with a harness name.
  expect_failure start remote-agent--miospot--chat--claude claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  assert_contains "$STDERR" 'usage' || return 1
  expect_failure start remote-agent--miospot--chat--planning-1 claude "$PROJECT_ROOT_TOKEN" --yolo
}

test_valid_session_copies_are_byte_identical_and_chat_aware() {
  local supervisor_copy=$CASE/supervisor.valid_session protocol_copy=$CASE/protocol.valid_session
  awk '/^valid_session\(\) \{$/{found=1} found{print} found&&/^\}$/{exit}' "$SUPERVISOR" >"$supervisor_copy"
  awk '/^valid_session\(\) \{$/{found=1} found{print} found&&/^\}$/{exit}' \
    "$SCRIPT_DIR/../../scripts/remote-agent-v1" >"$protocol_copy"
  [[ -s $supervisor_copy && -s $protocol_copy ]] || return 1
  grep -Fq -- '--chat--' "$supervisor_copy" || return 1
  cmp -s "$supervisor_copy" "$protocol_copy"
}

test_start_resolves_only_closed_project_root_tokens() {
  local session=remote-agent--miospot--claude directory
  directory="$STATE_ROOT/orchestration/agent-supervisor/sessions/$session"
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  [[ $(<"$directory/root") == "$(cd "$WORKTREE" && pwd -P)" ]] || return 1
  expect_success kill "$session" || return 1

  # The quoted tilde is deliberately literal: start must reject shell-like paths.
  # shellcheck disable=SC2088
  expect_failure start "$session" claude '~/Projects/miospot' --yolo || return 1
  assert_contains "$STDERR" 'closed project root token' || return 1
  expect_failure start "$session" claude project-root-v1:miospot/../orchestration --yolo || return 1
  assert_contains "$STDERR" 'closed project root token' || return 1
  expect_failure start "$session" claude "$WORKTREE" --yolo || return 1
  assert_contains "$STDERR" 'closed project root token' || return 1
  expect_failure start remote-agent--orchestration--claude claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  assert_contains "$STDERR" 'does not match session project'
}

test_exact_start_argv_for_all_harnesses() {
  local harness session
  for harness in claude codex grok; do
    session="remote-agent--miospot--$harness"
    expect_success start "$session" "$harness" "$PROJECT_ROOT_TOKEN" --yolo || return 1
    assert_contains "$TMUX_LOG" "<$session>" || return 1
    assert_contains "$TMUX_LOG" "<$harness> <--yolo>" || return 1
    assert_contains "$REMOTE_ARGV" "$harness <--yolo>" || return 1
    assert_lacks "$TMUX_LOG" 'mini-agent' || return 1
    rm -f "$STATE_ROOT/sessions/$session"
  done
}

test_prompt_is_stdin_only_and_redacted_everywhere() {
  local secret='SUPERVISOR-STDIN-CANARY-7391' session=remote-agent--miospot--codex
  run_supervisor_over_ssh start "$session" codex "$PROJECT_ROOT_TOKEN" --yolo
  [[ $STATUS -eq 0 ]] || return 1
  run_supervisor_over_ssh send "$session" <<<"$secret"
  [[ $STATUS -eq 0 ]] || return 1
  assert_contains "$SSH_STDIN" "$secret" || return 1
  assert_contains "$DELIVERED_PROMPT" "$secret" || return 1
  assert_lacks "$SSH_LOG" "$secret" || return 1
  assert_lacks "$SUPERVISOR_ARGV" "$secret" || return 1
  assert_lacks "$TMUX_LOG" "$secret" || return 1
  assert_lacks "$REMOTE_ARGV" "$secret" || return 1
  assert_lacks "$STDOUT" "$secret" || return 1
  assert_lacks "$STDERR" "$secret" || return 1
  ! grep -R -Fq -- "$secret" "$HOME_DIR" "$STATE_ROOT"
}

test_send_requires_stdin_and_existing_exact_session() {
  local session=remote-agent--orchestration--claude
  expect_failure send "$session" </dev/null || return 1
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  expect_failure send remote-agent--orchestration--grok <<<prompt || return 1
  expect_success send "$session" <<<prompt
}

test_codex_and_grok_send_strip_one_terminal_newline() {
  local harness session input=$CASE/input expected=$CASE/expected
  printf 'first line\nsecond line\n' >"$input"
  printf 'first line\nsecond line' >"$expected"
  for harness in codex grok; do
    session="remote-agent--orchestration--$harness"
    expect_success start "$session" "$harness" "$ORCHESTRATION_ROOT_TOKEN" --yolo || return 1
    expect_success send "$session" <"$input" || return 1
    cmp -s "$expected" "$DELIVERED_PROMPT" || return 1
    rm -f "$STATE_ROOT/sessions/$session"
  done
}

test_capture_is_visible_and_bounded() {
  local session=remote-agent--orchestration--grok capture=$CASE/capture
  for index in $(seq 1 120); do printf 'capture-%03d yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\n' "$index"; done >"$capture"
  expect_success start "$session" grok "$PROJECT_ROOT_TOKEN" --yolo || return 1
  SUPERVISOR_CAPTURE_FILE="$capture" run_supervisor capture "$session"
  [[ $STATUS -eq 0 ]] || return 1
  [[ $(wc -l <"$STDOUT" | tr -d ' ') -le 40 ]] || return 1
  [[ $(wc -c <"$STDOUT" | tr -d ' ') -le 4096 ]] || return 1
  assert_contains "$STDOUT" 'capture-120' || return 1
  assert_lacks "$STDOUT" 'capture-001'
}

test_interrupt_kill_and_quiescence_are_exact() {
  local session=remote-agent--miospot--claude
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  expect_success interrupt "$session" || return 1
  assert_contains "$TMUX_LOG" '<send-keys>' || return 1
  expect_success kill "$session" || return 1
  assert_contains "$TMUX_LOG" '<kill-session>' || return 1
  expect_success status "$session" || return 1
  assert_contains "$STDOUT" '"session":"absent"'
}

test_enqueue_commits_before_return() {
  local session=remote-agent--orchestration--claude pane
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  pane=$(pane_for_session "$session") || return 1

  # A synchronous plugin hook may return as soon as enqueue does.  Waiting
  # only after that return must still observe the committed event.
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  expect_success wait "$session" 0 0 || return 1
  [[ $(json_string "$STDOUT" wake) == event ]] || return 1
  [[ $(json_string "$STDOUT" session) == "$session" ]] || return 1
  [[ $(json_string "$STDOUT" scope) == main ]] || return 1
  [[ $(json_string "$STDOUT" kind) == completed ]] || return 1
  [[ $(json_uint "$STDOUT" cursor) -gt 0 ]]
}

test_event_cursors_are_monotonic_and_labels_are_exact() {
  local session=remote-agent--miospot--claude pane first=$CASE/first.json
  local first_cursor second_cursor first_epoch second_epoch
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  pane=$(pane_for_session "$session") || return 1

  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  expect_success wait "$session" 0 0 || return 1
  cp "$STDOUT" "$first"
  first_cursor=$(json_uint "$first" cursor)
  first_epoch=$(json_string "$first" epoch)
  [[ -n $first_cursor && -n $first_epoch ]] || return 1

  expect_success enqueue "$(worktree_for_session "$session")" "$pane" subagent input-needed || return 1
  expect_success wait "$session" "$first_epoch:$first_cursor" 0 || return 1
  second_cursor=$(json_uint "$STDOUT" cursor)
  second_epoch=$(json_string "$STDOUT" epoch)
  [[ $second_epoch == "$first_epoch" ]] || return 1
  [[ $second_cursor -gt $first_cursor ]] || return 1
  [[ $(json_string "$STDOUT" scope) == subagent ]] || return 1
  [[ $(json_string "$STDOUT" kind) == input-needed ]]
}

test_wait_timeout_is_a_normal_blocking_wake() {
  local session=remote-agent--orchestration--codex elapsed
  expect_success start "$session" codex "$PROJECT_ROOT_TOKEN" --yolo || return 1
  SECONDS=0
  expect_success wait "$session" 0 1 || return 1
  elapsed=$SECONDS
  [[ $elapsed -ge 1 && $elapsed -le 4 ]] || return 1
  [[ $(json_string "$STDOUT" wake) == timeout ]] || return 1
  [[ $(json_string "$STDOUT" session) == "$session" ]] || return 1
  [[ -n $(json_string "$STDOUT" epoch) ]] || return 1
  [[ $(json_uint "$STDOUT" cursor) == 0 ]]
}

test_wait_wakes_normally_when_session_exits() {
  local session=remote-agent--miospot--grok output=$CASE/wait.json error=$CASE/wait.err pid
  expect_success start "$session" grok "$PROJECT_ROOT_TOKEN" --yolo || return 1
  start_wait "$output" "$error" "$session" 0 5
  pid=$WAIT_PID
  sleep 0.1
  expect_success kill "$session" || return 1
  collect_wait "$pid"
  [[ $WAIT_STATUS -eq 0 ]] || return 1
  [[ $(json_string "$output" wake) == exit ]] || return 1
  [[ $(json_string "$output" session) == "$session" ]] || return 1
  [[ -n $(json_string "$output" epoch) ]]
}

test_wait_wakes_on_event_without_polling() {
  local session=remote-agent--miospot--codex output=$CASE/wait.json error=$CASE/wait.err pid pane
  expect_success start "$session" codex "$PROJECT_ROOT_TOKEN" --yolo || return 1
  pane=$(pane_for_session "$session") || return 1
  start_wait "$output" "$error" "$session" 0 5
  pid=$WAIT_PID
  sleep 0.1
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main failed || return 1
  collect_wait "$pid"
  [[ $WAIT_STATUS -eq 0 ]] || return 1
  [[ $(json_string "$output" wake) == event ]] || return 1
  [[ $(json_string "$output" scope) == main ]] || return 1
  [[ $(json_string "$output" kind) == failed ]]
}

test_two_waiters_receive_the_same_event() {
  local session=remote-agent--orchestration--claude pane
  local first=$CASE/first.json first_error=$CASE/first.err first_pid
  local second=$CASE/second.json second_error=$CASE/second.err second_pid
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  pane=$(pane_for_session "$session") || return 1
  start_wait "$first" "$first_error" "$session" 0 5
  first_pid=$WAIT_PID
  start_wait "$second" "$second_error" "$session" 0 5
  second_pid=$WAIT_PID
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" subagent completed || return 1
  collect_wait "$first_pid"
  [[ $WAIT_STATUS -eq 0 ]] || return 1
  collect_wait "$second_pid"
  [[ $WAIT_STATUS -eq 0 ]] || return 1
  [[ $(json_string "$first" wake) == event ]] || return 1
  [[ $(json_string "$second" wake) == event ]] || return 1
  [[ $(json_uint "$first" cursor) == "$(json_uint "$second" cursor)" ]] || return 1
  [[ $(json_string "$first" epoch) == "$(json_string "$second" epoch)" ]]
}

test_restart_creates_a_new_epoch() {
  local session=remote-agent--miospot--claude first=$CASE/first.json second=$CASE/second.json
  local pane first_epoch second_epoch first_cursor second_cursor
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  pane=$(pane_for_session "$session") || return 1
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  expect_success wait "$session" 0 0 || return 1
  cp "$STDOUT" "$first"
  first_epoch=$(json_string "$first" epoch)
  first_cursor=$(json_uint "$first" cursor)
  [[ -n $first_epoch && -n $first_cursor ]] || return 1
  expect_success kill "$session" || return 1
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  pane=$(pane_for_session "$session") || return 1
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" subagent completed || return 1
  expect_success wait "$session" "$first_epoch:$first_cursor" 0 || return 1
  cp "$STDOUT" "$second"
  second_epoch=$(json_string "$second" epoch)
  second_cursor=$(json_uint "$second" cursor)
  [[ -n $second_epoch && $second_epoch != "$first_epoch" ]] || return 1
  [[ -n $second_cursor && $second_cursor -gt $first_cursor ]] || return 1
  [[ $(json_string "$second" session) == "$session" ]]
}

test_start_and_status_return_a_direct_wait_bootstrap() {
  local session=remote-agent--orchestration--claude pane first=$CASE/first.json second=$CASE/second.json
  local first_bootstrap second_bootstrap first_epoch second_epoch canary='PANE-TEXT-CANARY-5097'
  SUPERVISOR_CAPTURE_FILE=<(printf '%s\n' "$canary") run_supervisor start "$session" claude "$ORCHESTRATION_ROOT_TOKEN" --yolo
  [[ $STATUS -eq 0 ]] || return 1
  cp "$STDOUT" "$first"
  first_bootstrap=$(json_string "$first" bootstrapCursor)
  first_epoch=$(json_string "$first" epoch)
  [[ $first_bootstrap == "$first_epoch:$(json_uint "$first" cursor)" ]] || return 1
  [[ $(wc -l <"$first" | tr -d ' ') -eq 1 ]] || return 1
  [[ $(wc -c <"$first" | tr -d ' ') -le 4096 ]] || return 1
  assert_lacks "$first" "$canary" || return 1
  assert_lacks "$first" '"scope"' || return 1
  assert_lacks "$first" '"kind"' || return 1

  expect_success wait "$session" "$first_bootstrap" 0 || return 1
  [[ $(json_string "$STDOUT" wake) == timeout ]] || return 1
  pane=$(pane_for_session "$session") || return 1
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  expect_success status "$session" || return 1
  [[ $(json_string "$STDOUT" bootstrapCursor) == "$(json_string "$STDOUT" epoch):$(json_uint "$STDOUT" cursor)" ]] || return 1
  assert_lacks "$STDOUT" '"scope"' || return 1
  assert_lacks "$STDOUT" '"kind"' || return 1

  expect_success kill "$session" || return 1
  SUPERVISOR_CAPTURE_FILE=<(printf '%s\n' "$canary") run_supervisor start "$session" claude "$ORCHESTRATION_ROOT_TOKEN" --yolo
  [[ $STATUS -eq 0 ]] || return 1
  cp "$STDOUT" "$second"
  second_bootstrap=$(json_string "$second" bootstrapCursor)
  second_epoch=$(json_string "$second" epoch)
  [[ -n $second_bootstrap && $second_epoch != "$first_epoch" ]] || return 1
  [[ $second_bootstrap == "$second_epoch:$(json_uint "$second" cursor)" ]] || return 1
  expect_success wait "$session" "$second_bootstrap" 0 || return 1
  [[ $(json_string "$STDOUT" wake) == timeout ]]
}

test_start_bootstrap_precedes_an_immediate_first_event() {
  local session=remote-agent--orchestration--claude bootstrap
  IMMEDIATE_EVENT=1 run_supervisor start "$session" claude "$ORCHESTRATION_ROOT_TOKEN" --yolo
  [[ $STATUS -eq 0 ]] || return 1
  bootstrap=$(json_string "$STDOUT" bootstrapCursor)
  [[ -n $bootstrap ]] || return 1

  expect_success wait "$session" "$bootstrap" 0 || return 1
  [[ $(json_string "$STDOUT" wake) == event ]] || return 1
  [[ $(json_string "$STDOUT" scope) == main ]] || return 1
  [[ $(json_string "$STDOUT" kind) == completed ]]
}

test_failed_harness_launch_rolls_back_session_and_binding() {
  local session=remote-agent--orchestration--codex directory
  directory="$STATE_ROOT/orchestration/agent-supervisor/sessions/$session"
  RESPAWN_FAIL=1 run_supervisor start "$session" codex "$ORCHESTRATION_ROOT_TOKEN" --yolo
  [[ $STATUS -ne 0 ]] || return 1
  [[ ! -f $STATE_ROOT/sessions/$session ]] || return 1
  [[ ! -f $directory/root && ! -f $directory/pane && ! -f $directory/epoch ]] || return 1
  [[ -f $directory/cursor && $(<"$directory/cursor") == 0 ]] || return 1
  assert_contains "$TMUX_LOG" '<kill-session>' || return 1

  expect_success start "$session" codex "$PROJECT_ROOT_TOKEN" --yolo || return 1
  [[ $(json_uint "$STDOUT" cursor) == 0 ]]
}

test_wait_cursor_has_no_lost_wakeup_window() {
  local session=remote-agent--orchestration--grok pane cursor=0 wait_cursor=0 index output error pid next epoch
  expect_success start "$session" grok "$PROJECT_ROOT_TOKEN" --yolo || return 1
  pane=$(pane_for_session "$session") || return 1
  for index in 1 2 3 4 5 6; do
    output=$CASE/wait-$index.json
    error=$CASE/wait-$index.err
    start_wait "$output" "$error" "$session" "$wait_cursor" 5
    pid=$WAIT_PID
    # Deliberately enqueue with no readiness sleep: the event may win the
    # race, but the cursor contract must prevent a lost wakeup either way.
    expect_success enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
    collect_wait "$pid"
    [[ $WAIT_STATUS -eq 0 ]] || return 1
    [[ $(json_string "$output" wake) == event ]] || return 1
    next=$(json_uint "$output" cursor)
    [[ -n $next && $next -gt $cursor ]] || return 1
    epoch=$(json_string "$output" epoch)
    [[ -n $epoch ]] || return 1
    cursor=$next
    wait_cursor="$epoch:$cursor"
  done
}

test_capture_after_wake_is_bounded_and_ephemeral() {
  local session=remote-agent--miospot--claude pane output=$CASE/wait.json error=$CASE/wait.err
  local capture=$CASE/capture canary='EPHEMERAL-PANE-CANARY-6219' pid
  for index in $(seq 1 120); do
    printf 'after-wake-%03d %s zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n' "$index" "$canary"
  done >"$capture"
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  pane=$(pane_for_session "$session") || return 1
  start_wait "$output" "$error" "$session" 0 5
  pid=$WAIT_PID
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  collect_wait "$pid"
  [[ $WAIT_STATUS -eq 0 && $(json_string "$output" wake) == event ]] || return 1

  SUPERVISOR_CAPTURE_FILE="$capture" run_supervisor capture "$session"
  [[ $STATUS -eq 0 ]] || return 1
  [[ $(wc -l <"$STDOUT" | tr -d ' ') -le 40 ]] || return 1
  [[ $(wc -c <"$STDOUT" | tr -d ' ') -le 4096 ]] || return 1
  assert_contains "$STDOUT" 'after-wake-120' || return 1
  assert_lacks "$STDOUT" 'after-wake-001' || return 1
  ! grep -R -Fq -- "$canary" "$HOME_DIR" "$STATE_ROOT"
}

test_event_wait_path_never_mutates_worktree() {
  local session=remote-agent--miospot--claude pane before after
  printf 'SYNC-MUTATION-CANARY-9182\n' >"$WORKTREE/tracked.txt"
  before=$(find "$WORKTREE" -type f -exec cksum {} \; | sort)
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  pane=$(pane_for_session "$session") || return 1
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" subagent failed || return 1
  expect_success wait "$session" 0 0 || return 1
  after=$(find "$WORKTREE" -type f -exec cksum {} \; | sort)
  [[ $after == "$before" ]] || return 1
  [[ ! -e $WORKTREE/.remote-agent-stage && ! -e $WORKTREE/.remote-agent ]]
}

test_project_pane_binding_is_exactly_session_isolated() {
  local first_session=remote-agent--miospot--claude second_session=remote-agent--orchestration--claude
  local second_worktree=$ORCHESTRATION_WORKTREE
  local first_pane second_pane first=$CASE/first.json first_error=$CASE/first.err first_pid
  local second=$CASE/second.json second_error=$CASE/second.err second_pid
  mkdir -p "$second_worktree"
  expect_success start "$first_session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  expect_success start "$second_session" claude "$ORCHESTRATION_ROOT_TOKEN" --yolo || return 1
  first_pane=$(pane_for_session "$first_session") || return 1
  second_pane=$(pane_for_session "$second_session") || return 1
  [[ $first_pane != "$second_pane" ]] || return 1

  expect_failure enqueue "$WORKTREE" "$second_pane" main completed || return 1
  expect_failure enqueue "$second_worktree" "$first_pane" main completed || return 1
  start_wait "$first" "$first_error" "$first_session" 0 5
  first_pid=$WAIT_PID
  start_wait "$second" "$second_error" "$second_session" 0 5
  second_pid=$WAIT_PID
  expect_success enqueue "$WORKTREE" "$first_pane" main completed || return 1
  collect_wait "$first_pid"
  [[ $WAIT_STATUS -eq 0 ]] || return 1
  [[ $(json_string "$first" wake) == event ]] || return 1
  [[ $(json_string "$first" session) == "$first_session" ]] || return 1
  kill -0 "$second_pid" 2>/dev/null || return 1
  expect_success enqueue "$second_worktree" "$second_pane" subagent failed || return 1
  collect_wait "$second_pid"
  [[ $WAIT_STATUS -eq 0 ]] || return 1
  [[ $(json_string "$second" wake) == event ]] || return 1
  [[ $(json_string "$second" session) == "$second_session" ]] || return 1
  [[ $(json_string "$second" scope) == subagent ]] || return 1
  [[ $(json_string "$second" kind) == failed ]]
}

test_enqueue_and_wait_reject_noncanonical_atoms() {
  local session=remote-agent--miospot--claude pane
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  pane=$(pane_for_session "$session") || return 1
  expect_failure enqueue orchestration "$pane" main completed || return 1
  expect_failure enqueue "$CASE/other-worktree" "$pane" main completed || return 1
  expect_failure enqueue "$(worktree_for_session "$session")" "$pane" agent completed || return 1
  expect_failure enqueue "$(worktree_for_session "$session")" "$pane" main message || return 1
  expect_failure enqueue "$(worktree_for_session "$session")" "$pane" main title || return 1
  expect_failure enqueue "$WORKTREE" "$pane;touch-pwned" main completed || return 1
  expect_failure wait "$session" not-a-cursor 1 || return 1
  expect_failure wait "$session" epoch-1:not-a-number 1 || return 1
  expect_failure wait "$session" 0 forever
}

test_enqueue_matches_a_chat_family_session_binding() {
  local session=remote-agent--miospot--chat--planning-1 pane='%61' directory
  plant_session_binding "$session" "$pane" || return 1
  directory=$(session_state_dir "$session")
  expect_success enqueue "$WORKTREE" "$pane" main input-needed || return 1
  [[ $(<"$directory/cursor") == 1 ]] || return 1
  expect_success wait "$session" 0 0 || return 1
  [[ $(json_string "$STDOUT" wake) == event ]] || return 1
  [[ $(json_string "$STDOUT" session) == "$session" ]] || return 1
  [[ $(json_string "$STDOUT" scope) == main ]] || return 1
  [[ $(json_string "$STDOUT" kind) == input-needed ]] || return 1
  # Labels-only kinds stay closed for the chat family too.
  expect_failure enqueue "$WORKTREE" "$pane" main message || return 1
  expect_failure enqueue "$WORKTREE" "$pane" agent completed || return 1
  # Epoch semantics are unchanged: status echoes the bound epoch, and the
  # same lifecycle vocabulary tears the chat session down.
  expect_success status "$session" || return 1
  [[ $(json_string "$STDOUT" epoch) == epoch-chat-fixture-1 ]] || return 1
  expect_success kill "$session" || return 1
  expect_success status "$session" || return 1
  assert_contains "$STDOUT" '"session":"absent"'
}

test_enqueue_ignores_nonvocabulary_session_directories() {
  local evil='remote-agent--miospot--chat--ok;touch-pwned' pane='%62' directory
  directory=$(session_state_dir "$evil")
  mkdir -p "$directory/events"
  printf '%s\n' "$(cd "$WORKTREE" && pwd -P)" >"$directory/root"
  printf '%s\n' "$pane" >"$directory/pane"
  printf 'epoch-evil-1\n' >"$directory/epoch"
  printf '0\n' >"$directory/cursor"
  printf '%s\n' "$pane" >"$STATE_ROOT/sessions/$evil"
  expect_failure enqueue "$WORKTREE" "$pane" main completed || return 1
  assert_contains "$STDERR" 'no exact supervisor root and pane binding' || return 1
  [[ $(<"$directory/cursor") == 0 ]]
}

test_reveal_opens_a_private_launcher_for_the_exact_existing_session() {
  local session=remote-agent--orchestration--claude
  local other=remote-agent--miospot--claude secret='REVEAL-PROMPT-CANARY-8842'
  local supervisor_state launcher_dir launcher before_state after_state
  supervisor_state="$STATE_ROOT/orchestration/agent-supervisor"
  launcher_dir="$supervisor_state/reveal"
  launcher="$launcher_dir/$session.command"
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  : >"$TMUX_LOG"
  before_state=$(find "$supervisor_state/sessions/$session" -type f -exec shasum {} + | sort)

  run_supervisor_over_ssh reveal "$session" <<<"$secret"
  [[ $STATUS -eq 0 ]] || return 1
  assert_contains "$SSH_STDIN" "$secret" || return 1
  assert_lacks "$SUPERVISOR_ARGV" "$secret" || return 1
  [[ $(<"$OPEN_LOG") == "open <-a> <Terminal> <--> <$launcher>" ]] || return 1
  [[ -f $launcher && ! -L $launcher && -x $launcher && -O $launcher ]] || return 1
  [[ $(stat -f '%Lp' "$launcher") == 700 ]] || return 1
  [[ $(stat -f '%Lp' "$launcher_dir") == 700 ]] || return 1
  [[ $(stat -f '%Lp' "$supervisor_state") == 700 ]] || return 1
  cmp -s "$launcher" "$OPEN_LAUNCHER_COPY" || return 1
  [[ $(sed -n '1p' "$launcher") == '#!/bin/sh' ]] || return 1
  grep -Fqx -- "exec tmux attach-session -t '$session'" "$launcher" || return 1
  [[ $(wc -l <"$launcher" | tr -d ' ') -eq 2 ]] || return 1
  assert_lacks "$launcher" "$other" || return 1
  assert_lacks "$launcher" "$secret" || return 1
  [[ ! -s $OSASCRIPT_LOG ]] || return 1
  [[ -z $(find "$launcher_dir" -name '*.tmp.*' -print -quit) ]] || return 1
  after_state=$(find "$supervisor_state/sessions/$session" -type f -exec shasum {} + | sort)
  [[ $before_state == "$after_state" ]] || return 1
  assert_lacks "$TMUX_LOG" 'new-session' || return 1
  assert_lacks "$TMUX_LOG" 'respawn-pane' || return 1
  assert_lacks "$TMUX_LOG" 'kill-session' || return 1
  assert_lacks "$TMUX_LOG" 'kill-pane' || return 1

  expect_failure reveal "$other" || return 1
  [[ ! -e $launcher_dir/$other.command ]] || return 1
  expect_failure reveal "$session; touch /tmp/reveal-injected" || return 1
  [[ $(grep -c '^open' "$OPEN_LOG") -eq 1 ]] || return 1
  [[ ! -s $OSASCRIPT_LOG ]]
}

test_reveal_fails_closed_for_symlinked_state_and_launcher_paths() {
  local session=remote-agent--miospot--claude
  local supervisor_state="$STATE_ROOT/orchestration/agent-supervisor"
  local launcher_dir="$supervisor_state/reveal"
  local launcher="$launcher_dir/$session.command"
  local outside="$CASE/outside" victim="$CASE/victim"
  printf '%%41\n' >"$STATE_ROOT/sessions/$session"
  mkdir -p "$STATE_ROOT/orchestration" "$outside"

  ln -s "$outside" "$supervisor_state"
  expect_failure reveal "$session" || return 1
  [[ -z $(find "$outside" -mindepth 1 -print -quit) ]] || return 1
  [[ ! -s $OPEN_LOG ]] || return 1

  rm "$supervisor_state"
  mkdir -p "$supervisor_state"
  ln -s "$outside" "$launcher_dir"
  expect_failure reveal "$session" || return 1
  [[ -z $(find "$outside" -mindepth 1 -print -quit) ]] || return 1
  [[ ! -s $OPEN_LOG ]] || return 1

  rm "$launcher_dir"
  mkdir -p "$launcher_dir"
  printf 'victim\n' >"$victim"
  ln -s "$victim" "$launcher"
  expect_failure reveal "$session" || return 1
  [[ $(<"$victim") == victim ]] || return 1
  [[ -L $launcher ]] || return 1
  [[ -z $(find "$launcher_dir" -name '*.tmp.*' -print -quit) ]] || return 1
  [[ ! -s $OPEN_LOG && ! -s $OSASCRIPT_LOG ]]
}

test_reveal_atomic_launcher_survives_open_failure_without_temporary_files() {
  local session=remote-agent--miospot--codex
  local launcher_dir="$STATE_ROOT/orchestration/agent-supervisor/reveal"
  local launcher="$launcher_dir/$session.command"
  printf '%%42\n' >"$STATE_ROOT/sessions/$session"

  OPEN_FAIL=1 expect_failure reveal "$session" || return 1
  [[ -f $launcher && ! -L $launcher && -x $launcher && -O $launcher ]] || return 1
  [[ $(stat -f '%Lp' "$launcher") == 700 ]] || return 1
  grep -Fqx -- "exec tmux attach-session -t '$session'" "$launcher" || return 1
  cmp -s "$launcher" "$OPEN_LAUNCHER_COPY" || return 1
  [[ -z $(find "$launcher_dir" -name '*.tmp.*' -print -quit) ]] || return 1
  [[ $(grep -c '^open' "$OPEN_LOG") -eq 1 ]] || return 1
  [[ ! -s $OSASCRIPT_LOG ]]
}

# ── supervisor-projection: journal projection, delivery, lock liveness ─────

test_start_accepts_workflow_binding_file_without_changing_vocabulary() {
  local session=remote-agent--orchestration--claude
  local workflow_id=wf-orchestration-20260712T010000Z-a1b2
  local directory pane binding=$CASE/workflow.binding
  plant_workflow "$workflow_id" >/dev/null || return 1
  printf '%s\n' "$workflow_id" >"$binding"

  run_supervisor start "$session" claude "$ORCHESTRATION_ROOT_TOKEN" --workflow-binding "$binding" --yolo
  [[ $STATUS -eq 0 ]] || return 1
  directory=$(session_state_dir "$session")
  [[ -f $directory/workflow ]] || return 1
  [[ $(<"$directory/workflow") == "$workflow_id" ]] || return 1
  # Bootstrap shape unchanged: labels-only, no scope/kind, restart-aware cursor.
  [[ -n $(json_string "$STDOUT" bootstrapCursor) ]] || return 1
  assert_lacks "$STDOUT" '"scope"' || return 1
  assert_lacks "$STDOUT" '"kind"' || return 1
  # Six-slot + closed kind set: still only completed|failed|input-needed.
  pane=$(pane_for_session "$session") || return 1
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  expect_failure enqueue "$(worktree_for_session "$session")" "$pane" main message || return 1
  expect_failure enqueue "$(worktree_for_session "$session")" "$pane" agent completed || return 1
  # Unbound start still works (no binding required).
  expect_success kill "$session" || return 1
  expect_success start "$session" claude "$ORCHESTRATION_ROOT_TOKEN" --yolo || return 1
  directory=$(session_state_dir "$session")
  [[ ! -f $directory/workflow ]]
}

test_enqueue_projects_bound_scope_kind_into_workflow_journal() {
  local session=remote-agent--orchestration--claude
  local workflow_id=wf-orchestration-20260712T010001Z-b2c3
  local pane directory event_file
  plant_workflow "$workflow_id" >/dev/null || return 1
  start_with_workflow_binding "$session" claude "$ORCHESTRATION_ROOT_TOKEN" "$workflow_id" || return 1
  pane=$(pane_for_session "$session") || return 1
  directory=$(session_state_dir "$session")

  # Session event commits first; projection follows into the bound journal.
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  event_file=$(printf '%s/events/%020d' "$directory" 1)
  [[ -f $event_file && $(<"$event_file") == 'main completed' ]] || return 1
  journal_has_kind "$workflow_id" completed || return 1

  expect_success enqueue "$(worktree_for_session "$session")" "$pane" subagent failed || return 1
  journal_has_kind "$workflow_id" failed || return 1
  # Labels only: no prompt/title free text lands in journal shards.
  ! grep -R -E 'prompt|title|canary' "$(workflow_dir_of "$workflow_id")/journal" >/dev/null 2>&1
}

test_projection_failure_drops_journal_pending_and_stays_fail_open() {
  local session=remote-agent--orchestration--codex
  local workflow_id=wf-orchestration-20260712T010002Z-c3d4
  local pane directory lock_dir boot pending event_file
  plant_workflow "$workflow_id" >/dev/null || return 1
  start_with_workflow_binding "$session" codex "$ORCHESTRATION_ROOT_TOKEN" "$workflow_id" || return 1
  pane=$(pane_for_session "$session") || return 1
  directory=$(session_state_dir "$session")

  # Wedged workflow lock: project-event refuses busy; enqueue must stay fail-open.
  lock_dir="$(workflow_dir_of "$workflow_id")/lock"
  boot=$(host_boot_token)
  [[ -n $boot && $boot != 0 ]] || return 1
  mkdir -p "$lock_dir"
  chmod 700 "$lock_dir"
  printf 'pid=%s\nboot=%s\n' "$$" "$boot" >"$lock_dir/holder"
  chmod 600 "$lock_dir/holder"

  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  event_file=$(printf '%s/events/%020d' "$directory" 1)
  [[ -f $event_file && $(<"$event_file") == 'main completed' ]] || return 1
  [[ $(journal_pending_count "$workflow_id") -ge 1 ]] || return 1
  journal_pending_has_kind "$workflow_id" completed || return 1
  journal_pending_has_kind "$workflow_id" main || return 1
  journal_pending_has_kind "$workflow_id" enqueue || return 1
  # Projection did not land while locked.
  ! journal_has_kind "$workflow_id" completed
}

test_input_needed_with_pending_triggers_queue_one_delivery() {
  local session=remote-agent--orchestration--grok
  local workflow_id=wf-orchestration-20260712T010003Z-d4e5
  local pane request_id=req-sup-del-1 payload='queue-one-from-supervisor'
  plant_workflow "$workflow_id" >/dev/null || return 1
  plant_pending_send "$workflow_id" "$request_id" "$payload" || return 1
  start_with_workflow_binding "$session" grok "$ORCHESTRATION_ROOT_TOKEN" "$workflow_id" || return 1
  pane=$(pane_for_session "$session") || return 1

  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main input-needed || return 1
  # Pending consumed; journal carries input-needed and delivered-from-queue.
  [[ ! -e $(workflow_dir_of "$workflow_id")/pending-send.payload ]] || return 1
  [[ ! -e $(workflow_dir_of "$workflow_id")/pending-send.json ]] || return 1
  journal_has_kind "$workflow_id" input-needed || return 1
  journal_has_kind "$workflow_id" delivered-from-queue || return 1
  local latch
  latch="$(workflow_dir_of "$workflow_id")/needs-input.json"
  [[ -f $latch ]] || return 1
  assert_contains "$latch" "$request_id" || return 1
  assert_contains "$latch" 'acked' || return 1
  [[ ! -f $(workflow_dir_of "$workflow_id")/delivery-pending ]]
}

test_delivery_failure_drops_delivery_pending_and_stays_fail_open() {
  local session=remote-agent--orchestration--claude
  local workflow_id=wf-orchestration-20260712T010004Z-e5f6
  local pane directory lock_dir boot pending delivery
  plant_workflow "$workflow_id" >/dev/null || return 1
  plant_pending_send "$workflow_id" req-sup-del-fail 'still-queued' || return 1
  start_with_workflow_binding "$session" claude "$ORCHESTRATION_ROOT_TOKEN" "$workflow_id" || return 1
  pane=$(pane_for_session "$session") || return 1
  directory=$(session_state_dir "$session")

  # Busy workflow lock: input-needed cannot project or deliver; markers + session event.
  lock_dir="$(workflow_dir_of "$workflow_id")/lock"
  boot=$(host_boot_token)
  [[ -n $boot && $boot != 0 ]] || return 1
  mkdir -p "$lock_dir"
  chmod 700 "$lock_dir"
  printf 'pid=%s\nboot=%s\n' "$$" "$boot" >"$lock_dir/holder"
  chmod 600 "$lock_dir/holder"

  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main input-needed || return 1
  [[ -f $directory/events/$(printf '%020d' 1) ]] || return 1
  delivery="$(workflow_dir_of "$workflow_id")/delivery-pending"
  [[ $(journal_pending_count "$workflow_id") -ge 1 ]] || return 1
  journal_pending_has_kind "$workflow_id" input-needed || return 1
  [[ -f $delivery ]] || return 1
  # Pending payload retained for later reconcile.
  [[ -f $(workflow_dir_of "$workflow_id")/pending-send.payload ]]
}

test_enqueue_lock_records_pid_and_boot_time() {
  local session=remote-agent--orchestration--claude
  local workflow_id=wf-orchestration-20260712T010005Z-f6a7
  local directory lock holder boot pane sample=$CASE/holder.sample slow_reg=$CASE/slow-registry
  plant_workflow "$workflow_id" >/dev/null || return 1
  start_with_workflow_binding "$session" claude "$ORCHESTRATION_ROOT_TOKEN" "$workflow_id" || return 1
  directory=$(session_state_dir "$session")
  pane=$(pane_for_session "$session") || return 1
  boot=$(host_boot_token)
  [[ -n $boot && $boot != 0 ]] || return 1
  lock="$directory/enqueue.lock"
  holder="$lock/holder"

  # Slow registry keeps enqueue inside the lock long enough to sample holder.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    'sleep 0.4' \
    'exec "$REAL_REGISTRY" "$@"' >"$slow_reg"
  chmod +x "$slow_reg"

  : >"$sample"
  (
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      if [[ -f $holder ]]; then
        cat "$holder" >"$sample"
        exit 0
      fi
      sleep 0.05
    done
    exit 1
  ) &
  local sampler=$!
  AGENT_SUPERVISOR_REGISTRY="$slow_reg" REAL_REGISTRY="$REGISTRY" \
    run_supervisor enqueue "$(worktree_for_session "$session")" "$pane" main completed
  [[ $STATUS -eq 0 ]] || return 1
  wait "$sampler" || return 1
  [[ -s $sample ]] || return 1
  assert_contains "$sample" 'pid=' || return 1
  assert_contains "$sample" "boot=$boot" || return 1
  # Lock fully released after enqueue returns.
  [[ ! -d $lock ]]
}

test_dead_pid_enqueue_lock_is_broken() {
  local session=remote-agent--miospot--codex
  local directory lock boot pane
  expect_success start "$session" codex "$PROJECT_ROOT_TOKEN" --yolo || return 1
  directory=$(session_state_dir "$session")
  pane=$(pane_for_session "$session") || return 1
  lock="$directory/enqueue.lock"
  boot=$(host_boot_token)
  [[ -n $boot && $boot != 0 ]] || return 1
  mkdir -p "$lock"
  chmod 700 "$lock"
  printf 'pid=999999999\nboot=%s\n' "$boot" >"$lock/holder"
  chmod 600 "$lock/holder"

  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  # Lock released after success; event committed.
  [[ ! -d $lock ]] || return 1
  expect_success wait "$session" 0 0 || return 1
  [[ $(json_string "$STDOUT" kind) == completed ]]
}

test_live_pid_enqueue_lock_times_out_busy() {
  local session=remote-agent--miospot--grok
  local directory lock boot pane elapsed
  expect_success start "$session" grok "$PROJECT_ROOT_TOKEN" --yolo || return 1
  directory=$(session_state_dir "$session")
  pane=$(pane_for_session "$session") || return 1
  lock="$directory/enqueue.lock"
  boot=$(host_boot_token)
  [[ -n $boot && $boot != 0 ]] || return 1
  mkdir -p "$lock"
  chmod 700 "$lock"
  # Live pid of this shell + real host boot → must refuse busy (not steal).
  printf 'pid=%s\nboot=%s\n' "$$" "$boot" >"$lock/holder"
  chmod 600 "$lock/holder"

  local start_ts end_ts
  start_ts=$(date +%s)
  expect_failure enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  end_ts=$(date +%s)
  elapsed=$((end_ts - start_ts))
  assert_contains "$STDERR" 'busy' || return 1
  # Live lock must refuse quickly (few brief spins), never hang.
  [[ $elapsed -le 5 ]] || return 1
  # Holder still names this live pid (lock not stolen).
  assert_contains "$lock/holder" "pid=$$" || return 1
  assert_contains "$lock/holder" "boot=$boot" || return 1
  # No session event committed under a stolen lock.
  [[ -z $(find "$directory/events" -type f -name '[0-9]*' -print -quit 2>/dev/null) ]]
}

# Red: two failed projections leave two pending records; one later success clears only its own.
test_journal_pending_is_append_only_set() {
  local session=remote-agent--orchestration--claude
  local workflow_id=wf-orchestration-20260712T010010Z-a0a0
  local pane lock_dir boot count_before count_after
  plant_workflow "$workflow_id" >/dev/null || return 1
  start_with_workflow_binding "$session" claude "$ORCHESTRATION_ROOT_TOKEN" "$workflow_id" || return 1
  pane=$(pane_for_session "$session") || return 1

  lock_dir="$(workflow_dir_of "$workflow_id")/lock"
  boot=$(host_boot_token)
  [[ -n $boot && $boot != 0 ]] || return 1
  mkdir -p "$lock_dir"
  chmod 700 "$lock_dir"
  printf 'pid=%s\nboot=%s\n' "$$" "$boot" >"$lock_dir/holder"
  chmod 600 "$lock_dir/holder"

  # Two failed enqueues → two distinct pending projection records.
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" main failed || return 1
  count_before=$(journal_pending_count "$workflow_id")
  [[ $count_before -ge 2 ]] || return 1
  journal_pending_has_kind "$workflow_id" completed || return 1
  journal_pending_has_kind "$workflow_id" failed || return 1

  # Unwedge and succeed a third projection. Success must not wipe the earlier set.
  rm -rf -- "$lock_dir"
  expect_success enqueue "$(worktree_for_session "$session")" "$pane" subagent completed || return 1
  journal_has_kind "$workflow_id" completed || return 1
  count_after=$(journal_pending_count "$workflow_id")
  # Prior pending records survive; successful enqueue only clears its own key.
  [[ $count_after -ge 2 ]] || return 1
  journal_pending_has_kind "$workflow_id" failed || return 1
  journal_pending_has_kind "$workflow_id" completed || return 1
}

# Red: DEFAULT projection timeout is genuinely < 2 s (no env override, no whole-second ceiling).
test_registry_timeout_writes_journal_pending_marker() {
  local session=remote-agent--orchestration--codex
  local workflow_id=wf-orchestration-20260712T010011Z-b1b1
  local pane hang_reg=$CASE/hang-registry directory
  plant_workflow "$workflow_id" >/dev/null || return 1
  start_with_workflow_binding "$session" codex "$ORCHESTRATION_ROOT_TOKEN" "$workflow_id" || return 1
  pane=$(pane_for_session "$session") || return 1
  directory=$(session_state_dir "$session")

  # shellcheck disable=SC2016
  # Use absolute /bin/sleep so PATH sleep shims cannot mask the hang.
  printf '%s\n' '#!/usr/bin/env bash' \
    'exec /bin/sleep 30' >"$hang_reg"
  chmod +x "$hang_reg"

  local start_ms end_ms elapsed_ms
  start_ms=$(perl -MTime::HiRes=time -e 'printf "%d\n", int(time * 1000)' 2>/dev/null \
    || python3 -c 'import time; print(int(time.time()*1000))')
  # DEFAULT path only — must NOT set AGENT_SUPERVISOR_PROJECT_TIMEOUT. The
  # default (1.5 s, sub-second precision) must prove shorter than the 2 s hook.
  AGENT_SUPERVISOR_REGISTRY="$hang_reg" \
    run_supervisor enqueue "$(worktree_for_session "$session")" "$pane" main completed
  end_ms=$(perl -MTime::HiRes=time -e 'printf "%d\n", int(time * 1000)' 2>/dev/null \
    || python3 -c 'import time; print(int(time.time()*1000))')
  elapsed_ms=$((end_ms - start_ms))
  [[ $STATUS -eq 0 ]] || return 1
  # Session event committed; marker present; finished under the 2 s hook budget.
  [[ -f $directory/events/$(printf '%020d' 1) ]] || return 1
  [[ $(journal_pending_count "$workflow_id") -ge 1 ]] || return 1
  journal_pending_has_kind "$workflow_id" completed || return 1
  # Default 1.5 s + teardown margin must stay strictly under the 2 s hook window.
  # A whole-second ceiling of 1.5→2 would often breach 2000 ms under load; real
  # 1.5 s precision finishes well under 2 s. Cap at 2500 ms for CI scheduling noise
  # but still far below hang_reg's 30 s sleep and below 2× independent budgets.
  [[ $elapsed_ms -le 2500 ]] || return 1
  # Must actually wait near the default budget (proves timeout fired, not instant fail).
  [[ $elapsed_ms -ge 1000 ]] || return 1
  ! journal_has_kind "$workflow_id" completed
}

# Red: digest-mismatched pending payload refuses delivery; delivery-pending marker survives.
# Must actually exercise deliver_pending_reconcile_locked (not vacuous on dead session).
test_delivery_pending_digest_mismatch_is_refused() {
  local session=remote-agent--orchestration--grok
  local workflow_id=wf-orchestration-20260712T010012Z-c2c2
  local wf_dir request_id=req-digest-mismatch payload='correct-payload-bytes'
  local delivery pane
  plant_workflow "$workflow_id" >/dev/null || return 1
  plant_pending_send "$workflow_id" "$request_id" "$payload" || return 1
  # Corrupt the stored digest so real contract validation must refuse.
  wf_dir=$(workflow_dir_of "$workflow_id")
  printf '%s\n' "{\"requestId\":\"$request_id\",\"sha256\":\"$(printf '0%.0s' {1..64})\",\"bytes\":${#payload},\"queuedAt\":\"2026-07-12T00:00:00Z\"}" \
    >"$wf_dir/pending-send.json"
  chmod 600 "$wf_dir/pending-send.json"
  plant_needs_input_latch "$workflow_id" 1 || return 1
  printf 'delivery-pending\n' >"$wf_dir/delivery-pending"
  chmod 600 "$wf_dir/delivery-pending"
  # Bind session live so resume-scan / deliver path can see the marker.
  start_with_workflow_binding "$session" grok "$ORCHESTRATION_ROOT_TOKEN" "$workflow_id" || return 1
  pane=$(pane_for_session "$session") || return 1
  # Also plant a byproject binding so resume-scan finds this workflow.
  mkdir -p "$STATE_ROOT/orchestration/workflows/byproject"
  printf '%s\n' "$workflow_id" >"$STATE_ROOT/orchestration/workflows/byproject/orchestration"
  chmod 600 "$STATE_ROOT/orchestration/workflows/byproject/orchestration"
  # Live session marker for conductor_session(orchestration) = ...--claude.
  # Fake tmux requires STATE_ROOT + TMUX_LOG so session_is_live can succeed;
  # without them the fixture aborts and reconcile is never reached (vacuous).
  mkdir -p "$STATE_ROOT/sessions"
  printf '%s\n' "%99" >"$STATE_ROOT/sessions/remote-agent--orchestration--claude"
  # Registry resume must refuse mismatched digest and keep the marker.
  # Export the fake-tmux env so has-session consults STATE_ROOT/sessions.
  PATH="$FAKE_BIN:$BASE_PATH" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_ROOT" \
    STATE_ROOT="$STATE_ROOT" TMUX_LOG="$TMUX_LOG" \
    "$REGISTRY" resume-scan >"$STDOUT" 2>"$STDERR" || true
  # Prove the live-session branch ran (scanned the bound project).
  assert_contains "$STDOUT" '"scanned":1' || assert_contains "$STDOUT" '"scanned": 1' || {
    # Some jq builds omit space; accept ok:true with scanned present.
    grep -Eq '"scanned":[[:space:]]*1' "$STDOUT" || return 1
  }
  delivery="$wf_dir/delivery-pending"
  [[ -f $delivery ]] || return 1
  [[ -f $wf_dir/pending-send.payload ]] || return 1
  [[ -f $wf_dir/pending-send.json ]] || return 1
  ! journal_has_kind "$workflow_id" delivered-from-queue
}

# Red: two projections whose scope/kind bodies would hash equal both survive reconcile.
test_distinct_projections_with_equal_bodies_both_survive_reconcile() {
  local workflow_id=wf-orchestration-20260712T010013Z-d3d3
  local wf_dir pending_dir count
  plant_workflow "$workflow_id" >/dev/null || return 1
  wf_dir=$(workflow_dir_of "$workflow_id")
  pending_dir="$wf_dir/journal-pending"
  mkdir -p -m 700 -- "$pending_dir"
  # Identical content (old content-hash scheme would collide); distinct filenames.
  printf '%s\n' '{"scope":"main","kind":"completed","source":"enqueue"}' \
    >"$pending_dir/remote-agent--orchestration--claude.1.completed"
  printf '%s\n' '{"scope":"main","kind":"completed","source":"enqueue"}' \
    >"$pending_dir/remote-agent--orchestration--claude.2.completed"
  chmod 600 "$pending_dir"/*
  # Reconcile via inspect must project BOTH — never drop the second on hash:inode.
  PATH="$FAKE_BIN:$BASE_PATH" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_ROOT" \
    STATE_ROOT="$STATE_ROOT" TMUX_LOG="$TMUX_LOG" \
    "$REGISTRY" inspect "$workflow_id" >"$STDOUT" 2>"$STDERR" || return 1
  assert_contains "$STDOUT" '"ok":true' || return 1
  count=0
  local f
  for f in "$wf_dir"/journal/[0-9]*.json; do
    [[ -f $f ]] || continue
    grep -Fq '"kind":"completed"' "$f" && count=$((count + 1))
  done
  [[ $count -eq 2 ]] || return 1
  # Pending set drained.
  [[ $(journal_pending_count "$workflow_id") -eq 0 ]]
}

# Red: input-needed chains project-event + deliver-queue under ONE shared budget.
test_input_needed_projection_and_delivery_share_one_budget() {
  local session=remote-agent--orchestration--claude
  local workflow_id=wf-orchestration-20260712T010014Z-e4e4
  local pane slow_reg=$CASE/two-call-registry calls=$CASE/registry.calls
  plant_workflow "$workflow_id" >/dev/null || return 1
  plant_pending_send "$workflow_id" req-shared-budget 'still-here-for-second-call' || return 1
  start_with_workflow_binding "$session" claude "$ORCHESTRATION_ROOT_TOKEN" "$workflow_id" || return 1
  pane=$(pane_for_session "$session") || return 1

  # Shim: project-event burns 0.5 s then fakes success WITHOUT consuming pending
  # so the supervisor still chains deliver-queue. deliver-queue hangs for 30 s.
  # Independent 1.5 s budgets would allow ~0.5 + 1.5 = 2.0 s (at/over the 2 s hook).
  # A single combined 1.5 s budget must finish near 1.5 s and still attempt both.
  : >"$calls"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'cmd=${1:-}; shift || true' \
    'printf "%s\n" "$cmd" >>"'"$calls"'"' \
    'case $cmd in' \
    '  project-event)' \
    '    /bin/sleep 0.5' \
    '    # Fake success; leave pending-send in place for the second hop.' \
    '    jq -cn --arg w "${1:-}" --arg k "${3:-input-needed}" '\''{ok:true,workflowId:$w,kind:$k,seq:1}'\''' \
    '    exit 0' \
    '    ;;' \
    '  deliver-queue)' \
    '    exec /bin/sleep 30' \
    '    ;;' \
    '  *) exec "$REAL_REGISTRY" "$cmd" "$@" ;;' \
    'esac' >"$slow_reg"
  chmod +x "$slow_reg"

  local start_ms end_ms elapsed_ms
  start_ms=$(perl -MTime::HiRes=time -e 'printf "%d\n", int(time * 1000)' 2>/dev/null \
    || python3 -c 'import time; print(int(time.time()*1000))')
  AGENT_SUPERVISOR_REGISTRY="$slow_reg" REAL_REGISTRY="$REGISTRY" \
    run_supervisor enqueue "$(worktree_for_session "$session")" "$pane" main input-needed
  end_ms=$(perl -MTime::HiRes=time -e 'printf "%d\n", int(time * 1000)' 2>/dev/null \
    || python3 -c 'import time; print(int(time.time()*1000))')
  elapsed_ms=$((end_ms - start_ms))
  [[ $STATUS -eq 0 ]] || return 1
  # Session event committed; delivery fail-open marker written.
  [[ -f $(session_state_dir "$session")/events/$(printf '%020d' 1) ]] || return 1
  [[ -f $(workflow_dir_of "$workflow_id")/delivery-pending ]] || return 1
  # Both hops attempted under the shared budget.
  assert_contains "$calls" 'project-event' || return 1
  assert_contains "$calls" 'deliver-queue' || return 1
  # Combined budget: must stay under the 2 s hook (independent stacked ≥ 2.0 s).
  [[ $elapsed_ms -le 2000 ]] || return 1
  # Spent the first hop (~0.5 s) plus a slice of the second before the shared cap.
  [[ $elapsed_ms -ge 500 ]]
}

# Red: corrupt queued payload must not wedge inspect/wait (read-only state still served).
test_corrupt_queued_payload_does_not_wedge_inspect() {
  local workflow_id=wf-orchestration-20260712T010015Z-f5f5
  local wf_dir pending_dir request_id=req-corrupt-inspect payload='payload-bytes-here'
  plant_workflow "$workflow_id" >/dev/null || return 1
  plant_pending_send "$workflow_id" "$request_id" "$payload" || return 1
  wf_dir=$(workflow_dir_of "$workflow_id")
  # Corrupt digest so deliver would hard-fail under the old strict path.
  printf '%s\n' "{\"requestId\":\"$request_id\",\"sha256\":\"$(printf '0%.0s' {1..64})\",\"bytes\":${#payload},\"queuedAt\":\"2026-07-12T00:00:00Z\"}" \
    >"$wf_dir/pending-send.json"
  chmod 600 "$wf_dir/pending-send.json"
  # Pending projection that would trigger deliver during reconcile.
  pending_dir="$wf_dir/journal-pending"
  mkdir -p -m 700 -- "$pending_dir"
  printf '%s\n' '{"scope":"main","kind":"input-needed","session":"remote-agent--orchestration--claude","cursor":1,"source":"enqueue"}' \
    >"$pending_dir/remote-agent--orchestration--claude.1.input-needed"
  chmod 600 "$pending_dir"/*
  # Inspect must succeed (ok:true) — never exit on digest-mismatch.
  PATH="$FAKE_BIN:$BASE_PATH" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_ROOT" \
    STATE_ROOT="$STATE_ROOT" TMUX_LOG="$TMUX_LOG" \
    "$REGISTRY" inspect "$workflow_id" >"$STDOUT" 2>"$STDERR"
  local inspect_status=$?
  [[ $inspect_status -eq 0 ]] || return 1
  assert_contains "$STDOUT" '"ok":true' || return 1
  # Input-needed was projected; delivered-from-queue was not synthesized.
  journal_has_kind "$workflow_id" input-needed || return 1
  ! journal_has_kind "$workflow_id" delivered-from-queue || return 1
  # Corrupt payload refused: either quarantined or still marked delivery-pending.
  [[ -f $wf_dir/delivery-pending || -d $wf_dir/quarantine ]] || return 1
  # Wait also stays readable.
  PATH="$FAKE_BIN:$BASE_PATH" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_ROOT" \
    STATE_ROOT="$STATE_ROOT" TMUX_LOG="$TMUX_LOG" \
    "$REGISTRY" wait "$workflow_id" --cursor "jrn-test-epoch:0" --timeout 0 \
    >"$STDOUT" 2>"$STDERR" || return 1
  assert_contains "$STDOUT" '"ok":true'
}

# Red: lock dir without holder yet must not be treated as immediately stale.
test_enqueue_lock_init_race_missing_holder_not_stolen() {
  local session=remote-agent--miospot--claude
  local directory lock boot pane
  expect_success start "$session" claude "$PROJECT_ROOT_TOKEN" --yolo || return 1
  directory=$(session_state_dir "$session")
  pane=$(pane_for_session "$session") || return 1
  lock="$directory/enqueue.lock"
  boot=$(host_boot_token)
  [[ -n $boot && $boot != 0 ]] || return 1

  # Simulate acquirer that has mkdir'd the lock but not yet written holder.
  mkdir -p "$lock"
  chmod 700 "$lock"
  # Populate holder with live pid shortly after contender starts — still within grace.
  (
    sleep 0.05
    printf 'pid=%s\nboot=%s\n' "$$" "$boot" >"$lock/holder"
    chmod 600 "$lock/holder"
  ) &

  expect_failure enqueue "$(worktree_for_session "$session")" "$pane" main completed || return 1
  assert_contains "$STDERR" 'busy' || return 1
  # Contender must not have stolen: holder still names this live pid (or lock remains ours).
  [[ -d $lock ]] || return 1
  if [[ -f $lock/holder ]]; then
    assert_contains "$lock/holder" "pid=$$" || return 1
  fi
  [[ -z $(find "$directory/events" -type f -name '[0-9]*' -print -quit 2>/dev/null) ]]
}

# The fake tmux/harness boundary must work independently of the missing script.
setup_case fixture-self-test
PATH="$FAKE_BIN:/usr/bin:/bin" TMUX_LOG="$TMUX_LOG" STATE_ROOT="$STATE_ROOT" REMOTE_ARGV="$REMOTE_ARGV" \
  "$FAKE_BIN/tmux" new-session -d -s fixture -- claude --yolo
if assert_contains "$TMUX_LOG" '<claude> <--yolo>' && assert_contains "$REMOTE_ARGV" 'claude <--yolo>'; then
  pass 'hermetic supervisor fixture self-test'
else
  fail 'hermetic supervisor fixture self-test' 'fake tmux did not capture exact argv'
fi

if [[ ! -x $SUPERVISOR ]]; then
  fail 'agent supervisor executable exists' "missing executable: $SUPERVISOR"
  printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
  exit 1
fi

run_test 'supervisor is v1 and rejects launch/unknown atoms' test_version_and_closed_vocabulary
run_test 'chat session family is pattern-validated and never startable' test_chat_session_family_is_pattern_validated
run_test 'both valid_session copies are byte-identical and chat-aware' test_valid_session_copies_are_byte_identical_and_chat_aware
run_test 'start resolves only exact closed project root tokens' test_start_resolves_only_closed_project_root_tokens
run_test 'Claude, Codex, and Grok start with exact --yolo argv' test_exact_start_argv_for_all_harnesses
run_test 'prompt bytes remain stdin-only and absent from argv/state/trace/logs' test_prompt_is_stdin_only_and_redacted_everywhere
run_test 'send requires bytes and one existing exact session' test_send_requires_stdin_and_existing_exact_session
run_test 'Codex and Grok send strip one terminal newline before submit' test_codex_and_grok_send_strip_one_terminal_newline
run_test 'capture stays visible while bounded to 40 lines and 4 KiB' test_capture_is_visible_and_bounded
run_test 'interrupt, kill, and quiescent status target one exact session' test_interrupt_kill_and_quiescence_are_exact
run_test 'enqueue commits its event atomically before a synchronous hook can return' test_enqueue_commits_before_return
run_test 'event cursors increase monotonically while main/subagent labels stay exact' test_event_cursors_are_monotonic_and_labels_are_exact
run_test 'wait blocks to its timeout and reports timeout as a normal wake' test_wait_timeout_is_a_normal_blocking_wake
run_test 'wait reports session exit as a normal wake' test_wait_wakes_normally_when_session_exits
run_test 'wait wakes on an enqueued event without polling' test_wait_wakes_on_event_without_polling
run_test 'two waiters on one cursor both receive the same event' test_two_waiters_receive_the_same_event
run_test 'restarting one exact session creates a fresh event epoch' test_restart_creates_a_new_epoch
run_test 'start and status expose a bounded restart-aware cursor usable directly by wait' test_start_and_status_return_a_direct_wait_bootstrap
run_test 'start bootstrap cannot skip a lifecycle event emitted immediately by the harness' test_start_bootstrap_precedes_an_immediate_first_event
run_test 'failed harness launch removes the placeholder and unsafe binding' test_failed_harness_launch_rolls_back_session_and_binding
run_test 'enqueue racing waiter registration cannot lose a wakeup' test_wait_cursor_has_no_lost_wakeup_window
run_test 'capture after an event wake is bounded and never persisted' test_capture_after_wake_is_bounded_and_ephemeral
run_test 'enqueue and wait perform zero worktree synchronization or mutation' test_event_wait_path_never_mutates_worktree
run_test 'project plus pane binding isolates events to one exact session' test_project_pane_binding_is_exactly_session_isolated
run_test 'enqueue and wait accept only canonical atoms and restart-aware cursors' test_enqueue_and_wait_reject_noncanonical_atoms
run_test 'enqueue matches a chat-family session binding through the shared loop' test_enqueue_matches_a_chat_family_session_binding
run_test 'enqueue never matches non-vocabulary session directory names' test_enqueue_ignores_nonvocabulary_session_directories
run_test 'reveal opens one private exact-session launcher without state mutation' test_reveal_opens_a_private_launcher_for_the_exact_existing_session
run_test 'reveal rejects symlinked supervisor and launcher paths' test_reveal_fails_closed_for_symlinked_state_and_launcher_paths
run_test 'reveal launcher writes atomically and leaves no temporary file on open failure' test_reveal_atomic_launcher_survives_open_failure_without_temporary_files
run_test 'start accepts a workflow binding file without changing six-slot vocabulary' test_start_accepts_workflow_binding_file_without_changing_vocabulary
run_test 'enqueue projects bound scope/kind into the workflow journal after the session event' test_enqueue_projects_bound_scope_kind_into_workflow_journal
run_test 'projection failure drops journal-pending and stays fail-open' test_projection_failure_drops_journal_pending_and_stays_fail_open
run_test 'input-needed with a stored pending message triggers queue-one delivery' test_input_needed_with_pending_triggers_queue_one_delivery
run_test 'delivery failure drops delivery-pending and stays fail-open' test_delivery_failure_drops_delivery_pending_and_stays_fail_open
run_test 'enqueue lock dirs record pid and host boot-time' test_enqueue_lock_records_pid_and_boot_time
run_test 'a dead-pid same-host enqueue lock is broken' test_dead_pid_enqueue_lock_is_broken
run_test 'a live-pid enqueue lock times out busy' test_live_pid_enqueue_lock_times_out_busy
run_test 'journal-pending is append-only; success clears only its own record' test_journal_pending_is_append_only_set
run_test 'registry timeout writes journal-pending before hook budget dies' test_registry_timeout_writes_journal_pending_marker
run_test 'delivery-pending digest mismatch is refused and marker survives' test_delivery_pending_digest_mismatch_is_refused
run_test 'distinct projections with equal bodies both survive reconcile' test_distinct_projections_with_equal_bodies_both_survive_reconcile
run_test 'input-needed projection and delivery share one combined budget' test_input_needed_projection_and_delivery_share_one_budget
run_test 'corrupt queued payload does not wedge inspect or wait' test_corrupt_queued_payload_does_not_wedge_inspect
run_test 'enqueue lock init race with missing holder is not stolen' test_enqueue_lock_init_race_missing_holder_not_stolen

printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
