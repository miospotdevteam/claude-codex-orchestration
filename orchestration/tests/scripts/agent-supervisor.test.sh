#!/usr/bin/env bash
set -euo pipefail

# Contract for the one Mini-side session adapter shared by Claude, Codex, and
# Grok.  Prompt bytes enter only on stdin; --yolo is an explicit start flag.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SUPERVISOR="$SCRIPT_DIR/../../scripts/agent-supervisor"
PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
trap 'rm -rf "$SUITE"' EXIT

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
  if [[ ${1:-} == start && ${4:-} == "$ORCHESTRATION_ROOT_TOKEN" ]]; then
    fixture_worktree=$ORCHESTRATION_WORKTREE
  fi
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
    DELIVERED_PROMPT="$DELIVERED_PROMPT" \
    REAL_SUPERVISOR="$SUPERVISOR" \
    WORKTREE="$fixture_worktree" \
    IMMEDIATE_EVENT="${IMMEDIATE_EVENT:-0}" \
    RESPAWN_FAIL="${RESPAWN_FAIL:-0}" \
    SUPERVISOR_CAPTURE_FILE="${SUPERVISOR_CAPTURE_FILE:-}" \
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
run_test 'reveal opens one private exact-session launcher without state mutation' test_reveal_opens_a_private_launcher_for_the_exact_existing_session
run_test 'reveal rejects symlinked supervisor and launcher paths' test_reveal_fails_closed_for_symlinked_state_and_launcher_paths
run_test 'reveal launcher writes atomically and leaves no temporary file on open failure' test_reveal_atomic_launcher_survives_open_failure_without_temporary_files

printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
