#!/usr/bin/env bash
set -euo pipefail

# Hermetic contract for plugin-scoped lifecycle hooks. The hook is deliberately
# synchronous: it sanitizes one Claude hook payload, atomically hands the small
# event to agent-supervisor, and fails open without emitting a hook decision.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
HOOK_SOURCE="$SCRIPT_DIR/../../hooks/agent-event.sh"
MANIFEST="$SCRIPT_DIR/../../hooks/hooks.json"
PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
trap 'rm -rf "$SUITE"' EXIT

pass() { printf 'PASS %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_contains() { grep -Fq -- "$2" "$1"; }
assert_lacks() { ! grep -Fq -- "$2" "$1"; }

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

setup_case() {
  local name=$1
  CASE="$SUITE/$name"
  HOME_DIR="$CASE/home"
  PLUGIN_ROOT="$CASE/plugin"
  PROJECT_ROOT="$CASE/project-real"
  PROJECT_LINK="$CASE/project-link"
  SUPERVISOR_LOG="$CASE/supervisor.log"
  SUPERVISOR_STDIN="$CASE/supervisor.stdin"
  STDOUT="$CASE/stdout"
  STDERR="$CASE/stderr"
  SETTINGS="$HOME_DIR/.claude/settings.json"
  mkdir -p "$HOME_DIR/.claude" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts" "$PROJECT_ROOT/nested"
  ln -s "$PROJECT_ROOT" "$PROJECT_LINK"
  printf '{"sentinel":"USER-SETTINGS-CANARY-4159"}\n' >"$SETTINGS"
  : >"$SUPERVISOR_LOG"
  : >"$SUPERVISOR_STDIN"
  : >"$STDOUT"
  : >"$STDERR"

  if [[ -f $HOOK_SOURCE ]]; then
    cp "$HOOK_SOURCE" "$PLUGIN_ROOT/hooks/agent-event.sh"
    chmod +x "$PLUGIN_ROOT/hooks/agent-event.sh"
  fi

  # The fake accepts only the event-queue API and records argv separately from
  # stdin, making accidental forwarding of the raw hook payload observable.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf '\''agent-supervisor'\'' >>"$SUPERVISOR_LOG"' \
    'for argument in "$@"; do printf '\'' <%s>'\'' "$argument" >>"$SUPERVISOR_LOG"; done' \
    'printf '\''\n'\'' >>"$SUPERVISOR_LOG"' \
    'cat >>"$SUPERVISOR_STDIN"' \
    '[[ ${1:-} == enqueue && $# -eq 5 ]] || exit 64' \
    'exit "${SUPERVISOR_EXIT:-0}"' >"$PLUGIN_ROOT/scripts/agent-supervisor"
  chmod +x "$PLUGIN_ROOT/scripts/agent-supervisor"
}

run_hook() {
  local payload=$1
  set +e
  env -i \
    HOME="$HOME_DIR" \
    PATH="/usr/bin:/bin" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    CLAUDE_PROJECT_DIR="$PROJECT_LINK" \
    TMUX_PANE='%37' \
    SUPERVISOR_LOG="$SUPERVISOR_LOG" \
    SUPERVISOR_STDIN="$SUPERVISOR_STDIN" \
    SUPERVISOR_EXIT="${SUPERVISOR_EXIT:-0}" \
    "$PLUGIN_ROOT/hooks/agent-event.sh" <<<"$payload" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
}

test_manifest_has_synchronous_plugin_handlers() {
  local event
  jq -e '.hooks | type == "object"' "$MANIFEST" >/dev/null || return 1
  for event in Stop SubagentStop StopFailure Notification; do
    jq -e --arg event "$event" '
      .hooks[$event] as $entries |
      ($entries | type == "array") and
      ($entries | length == 1) and
      ($entries[0] | has("matcher") | not) and
      ($entries[0].hooks | type == "array") and
      ($entries[0].hooks | length == 1) and
      ($entries[0].hooks[0].type == "command") and
      ($entries[0].hooks[0].command == "${CLAUDE_PLUGIN_ROOT}/hooks/agent-event.sh") and
      ($entries[0].hooks[0].async == false) and
      ($entries[0].hooks[0].timeout | type == "number" and . > 0 and . <= 2)
    ' "$MANIFEST" >/dev/null || return 1
  done
}

test_main_and_subagent_events_are_labeled() {
  local payload
  payload=$(cat <<JSON
{"hook_event_name":"Stop","cwd":"$PROJECT_ROOT/nested","transcript_path":"$CASE/TRANSCRIPT-FULL-PATH-CANARY.jsonl","last_assistant_message":"MESSAGE-CANARY-9182","prompt":"PROMPT-CANARY-2654","environment":"ENVIRONMENT-CANARY-6841"}
JSON
)
  run_hook "$payload"
  [[ $STATUS -eq 0 ]] || return 1
  [[ ! -s $STDOUT && ! -s $STDERR ]] || return 1
  assert_contains "$SUPERVISOR_LOG" "agent-supervisor <enqueue> <$PROJECT_ROOT> <%37> <main> <completed>" || return 1

  : >"$SUPERVISOR_LOG"
  payload=$(cat <<JSON
{"hook_event_name":"SubagentStop","cwd":"$PROJECT_ROOT","agent_id":"SUBAGENT-ID-CANARY-3347","agent_type":"Explore","agent_transcript_path":"$CASE/SUBAGENT-FULL-PATH-CANARY.jsonl","last_assistant_message":"SUBAGENT-MESSAGE-CANARY-5510"}
JSON
)
  run_hook "$payload"
  [[ $STATUS -eq 0 ]] || return 1
  assert_contains "$SUPERVISOR_LOG" "agent-supervisor <enqueue> <$PROJECT_ROOT> <%37> <subagent> <completed>" || return 1
  assert_lacks "$SUPERVISOR_LOG" '<main>'
}

test_stop_failure_is_sanitized_failure_event() {
  local payload
  payload=$(cat <<JSON
{"hook_event_name":"StopFailure","cwd":"$PROJECT_ROOT","error":"MESSAGE-CANARY-STOP-FAILURE","transcript_path":"$CASE/FAILURE-FULL-PATH-CANARY.jsonl"}
JSON
)
  run_hook "$payload"
  [[ $STATUS -eq 0 ]] || return 1
  [[ ! -s $STDOUT && ! -s $STDERR ]] || return 1
  assert_contains "$SUPERVISOR_LOG" "agent-supervisor <enqueue> <$PROJECT_ROOT> <%37> <main> <failed>"
}

test_notification_allowlist_only_enqueues_input_needed() {
  local notification payload
  for notification in permission_prompt idle_prompt elicitation_dialog; do
    : >"$SUPERVISOR_LOG"
    payload=$(cat <<JSON
{"hook_event_name":"Notification","notification_type":"$notification","cwd":"$PROJECT_ROOT","message":"MESSAGE-CANARY-$notification","title":"TITLE-CANARY-$notification","transcript_path":"$CASE/$notification-FULL-PATH-CANARY.jsonl"}
JSON
)
    run_hook "$payload"
    [[ $STATUS -eq 0 ]] || return 1
    assert_contains "$SUPERVISOR_LOG" "agent-supervisor <enqueue> <$PROJECT_ROOT> <%37> <main> <input-needed>" || return 1
  done

  for notification in auth_success compact_warning instructions_loaded unknown; do
    : >"$SUPERVISOR_LOG"
    payload="{\"hook_event_name\":\"Notification\",\"notification_type\":\"$notification\",\"cwd\":\"$PROJECT_ROOT\",\"message\":\"MESSAGE-CANARY-DENIED\"}"
    run_hook "$payload"
    [[ $STATUS -eq 0 ]] || return 1
    [[ ! -s $SUPERVISOR_LOG ]] || return 1
  done
}

test_payload_canaries_are_removed() {
  local payload all_output
  payload=$(cat <<JSON
{"hook_event_name":"Notification","notification_type":"permission_prompt","cwd":"$PROJECT_ROOT","message":"MESSAGE-CANARY-4001","title":"TITLE-CANARY-4002","transcript_path":"$CASE/TRANSCRIPT-FULL-PATH-CANARY-4003.jsonl","prompt":"PROMPT-CANARY-4004","environment":{"SECRET_ENV":"ENVIRONMENT-CANARY-4005"}}
JSON
)
  run_hook "$payload"
  [[ $STATUS -eq 0 ]] || return 1
  all_output="$CASE/all-observable"
  cat "$SUPERVISOR_LOG" "$SUPERVISOR_STDIN" "$STDOUT" "$STDERR" >"$all_output"
  assert_contains "$SUPERVISOR_LOG" "<$PROJECT_ROOT>" || return 1
  assert_lacks "$all_output" 'MESSAGE-CANARY' || return 1
  assert_lacks "$all_output" 'TITLE-CANARY' || return 1
  assert_lacks "$all_output" 'TRANSCRIPT-FULL-PATH-CANARY' || return 1
  assert_lacks "$all_output" 'PROMPT-CANARY' || return 1
  assert_lacks "$all_output" 'ENVIRONMENT-CANARY' || return 1
  [[ ! -s $SUPERVISOR_STDIN ]]
}

test_hook_is_fail_open_and_does_not_mutate_settings() {
  local before after payload
  before=$(shasum -a 256 "$SETTINGS" | awk '{print $1}')
  payload="{\"hook_event_name\":\"Stop\",\"cwd\":\"$PROJECT_ROOT\",\"message\":\"FAIL-OPEN-CANARY\"}"
  SUPERVISOR_EXIT=73 run_hook "$payload"
  [[ $STATUS -eq 0 ]] || return 1
  [[ ! -s $STDOUT && ! -s $STDERR ]] || return 1
  after=$(shasum -a 256 "$SETTINGS" | awk '{print $1}')
  [[ $before == "$after" ]] || return 1

  run_hook '{not-json'
  [[ $STATUS -eq 0 ]] || return 1
  [[ ! -s $STDOUT && ! -s $STDERR ]] || return 1
  [[ $(find "$HOME_DIR/.claude" -type f | wc -l | tr -d ' ') -eq 1 ]]
}

# Validate the fixture before the deliberate RED production gates.
setup_case fixture-self-test
SUPERVISOR_LOG="$SUPERVISOR_LOG" SUPERVISOR_STDIN="$SUPERVISOR_STDIN" \
  "$PLUGIN_ROOT/scripts/agent-supervisor" enqueue "$PROJECT_ROOT" '%37' main completed </dev/null
if assert_contains "$SUPERVISOR_LOG" 'agent-supervisor <enqueue>' && [[ ! -s $SUPERVISOR_STDIN ]]; then
  pass 'hermetic hook fixture self-test'
else
  fail 'hermetic hook fixture self-test' 'fake supervisor did not capture the queue call'
fi

run_test 'manifest declares short synchronous plugin-scoped lifecycle handlers' test_manifest_has_synchronous_plugin_handlers

if [[ ! -x $HOOK_SOURCE ]]; then
  fail 'agent event hook executable exists' "missing executable: $HOOK_SOURCE"
else
  run_test 'main and subagent completion events remain distinct' test_main_and_subagent_events_are_labeled
  run_test 'StopFailure emits one sanitized main failure event' test_stop_failure_is_sanitized_failure_event
  run_test 'only the three input-needed notifications enqueue an event' test_notification_allowlist_only_enqueues_input_needed
  run_test 'message title transcript prompt environment and path canaries are removed' test_payload_canaries_are_removed
  run_test 'hook failures open without decisions or user-settings mutation' test_hook_is_fail_open_and_does_not_mutate_settings
fi

printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
