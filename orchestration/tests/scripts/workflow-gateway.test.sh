#!/usr/bin/env bash
set -euo pipefail

# Contract for scripts/workflow-gateway: the phone-facing loopback HTTP
# adapter over the Mini-resident workflow-registry.  The gateway relays a
# closed workflow-family route table onto exactly one registry exec per
# request with validated fixed atoms; it never orchestrates, never puts
# prompt text in argv or logs, and always answers with bounded JSON under
# no-store/CSP headers.  Every case runs curl against an ephemeral loopback
# port with a fake registry that records argv and stdin.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
GATEWAY="$SCRIPT_DIR/../../scripts/workflow-gateway"
PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
SUITE=$(cd "$SUITE" && pwd -P)

cleanup() {
  local pid_file pid
  for pid_file in "$SUITE"/gw-*/pid; do
    [[ -f $pid_file ]] || continue
    pid=$(head -n 1 "$pid_file" 2>/dev/null || true)
    [[ -n $pid ]] && kill "$pid" 2>/dev/null || true
  done
  rm -rf "$SUITE"
}
trap cleanup EXIT

pass() { printf 'PASS %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_contains() { grep -Fq -- "$2" "$1"; }
assert_lacks() { ! grep -Fq -- "$2" "$1"; }
perm_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }

LOGIN='operator@tailnet.example'
SERVE_HOST='mini.tail.example'
WF='wf-miospot-20260711T151201Z-9f3c'
PROMPT_CANARY='GATEWAY-PROMPT-CANARY-7f3a1c'

ALLOWLIST="$SUITE/allowlist"
printf '%s\n' "$LOGIN" >"$ALLOWLIST"
chmod 600 "$ALLOWLIST"

STATIC_DIR="$SUITE/static"
mkdir -p "$STATIC_DIR"
printf '<h1>GATEWAY-APP-SHELL</h1>\n' >"$STATIC_DIR/index.html"
printf 'LAUNCHAGENT-SECRET\n' >"$STATIC_DIR/evil.plist"
printf 'NOT-WHITELISTED\n' >"$STATIC_DIR/notlisted.txt"

FAKE_REGISTRY="$SUITE/workflow-registry"
cat >"$FAKE_REGISTRY" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
: "${GW_REG_LOG:?}" "${GW_REG_STDIN:?}" "${GW_REG_CTRL:?}"
{
  printf 'CALL\n'
  for argument in "$@"; do printf 'ARG\t%s\n' "$argument"; done
  printf 'END\n'
} >>"$GW_REG_LOG"
cat >>"$GW_REG_STDIN"
request_id=
argv=("$@")
for ((i = 0; i < ${#argv[@]}; i++)); do
  if [[ ${argv[$i]} == --request-id && $((i + 1)) -lt ${#argv[@]} ]]; then
    request_id=${argv[$((i + 1))]}
  fi
done
mode=$(head -n 1 "$GW_REG_CTRL/mode" 2>/dev/null || printf 'success')
case $mode in
  success)
    printf '{"ok":true,"op":"%s","requestId":"%s"}\n' "${1:-}" "$request_id"
    ;;
  wait)
    printf '{"ok":true,"journalEpoch":"jrn-fixture","cursor":"jrn-fixture:9","phase":"running","latch":null,"batch":[{"kind":"step-done","seq":9}]}\n'
    ;;
  mutex-held)
    printf '{"ok":false,"error":"mutex-held","message":"protocol mutex is held"}\n'
    exit 75
    ;;
  queue-full)
    printf '{"ok":false,"error":"queue-full","message":"one input is already pending"}\n'
    exit 65
    ;;
  not-found)
    printf '{"ok":false,"error":"not-found","message":"workflow not found"}\n'
    exit 66
    ;;
  garbage)
    printf 'REGISTRY-RAW-GARBAGE traceback line one\nline two\n'
    exit 70
    ;;
  slow)
    sleep 3
    printf '{"ok":true,"op":"slow"}\n'
    ;;
  hang)
    sleep 10
    printf '{"ok":true,"op":"hang"}\n'
    ;;
esac
FAKE
chmod 700 "$FAKE_REGISTRY"

# launch_gateway DIR [KEY=VAL ...] — starts one gateway on an ephemeral
# loopback port with per-instance fake-registry plumbing; prints the port.
launch_gateway() {
  local dir=$1
  shift
  mkdir -p "$dir/tmp" "$dir/state" "$dir/ctrl"
  : >"$dir/registry.log"
  : >"$dir/registry.stdin"
  printf 'success\n' >"$dir/ctrl/mode"
  env \
    HOME="$dir/state" \
    XDG_STATE_HOME="$dir/state" \
    TMPDIR="$dir/tmp" \
    GW_REG_LOG="$dir/registry.log" \
    GW_REG_STDIN="$dir/registry.stdin" \
    GW_REG_CTRL="$dir/ctrl" \
    WORKFLOW_GATEWAY_REGISTRY="$FAKE_REGISTRY" \
    WORKFLOW_GATEWAY_ALLOWLIST="$ALLOWLIST" \
    WORKFLOW_GATEWAY_AUDIT_LOG="$dir/audit.log" \
    WORKFLOW_GATEWAY_STATIC_DIR="$STATIC_DIR" \
    WORKFLOW_GATEWAY_SERVE_HOST="$SERVE_HOST" \
    "$@" \
    "$GATEWAY" --port 0 >"$dir/gateway.stdout" 2>"$dir/gateway.stderr" &
  printf '%s\n' "$!" >"$dir/pid"
  local i port=
  for ((i = 0; i < 100; i++)); do
    port=$(head -n 1 "$dir/gateway.stdout" 2>/dev/null | jq -r '.port // empty' 2>/dev/null || true)
    [[ -n $port ]] && break
    sleep 0.1
  done
  [[ -n $port ]] || return 1
  printf '%s\n' "$port"
}

GW_DIR="$SUITE/gw-main"
GW_PORT=$(launch_gateway "$GW_DIR" || true)

REG_LOG="$GW_DIR/registry.log"
REG_STDIN="$GW_DIR/registry.stdin"
AUDIT="$GW_DIR/audit.log"
GW_TMP="$GW_DIR/tmp"

reset_registry() {
  : >"$REG_LOG"
  : >"$REG_STDIN"
  printf 'success\n' >"$GW_DIR/ctrl/mode"
}
set_mode() { printf '%s\n' "$1" >"$GW_DIR/ctrl/mode"; }
call_count() { grep -c '^CALL$' "$REG_LOG" 2>/dev/null || true; }
assert_arg() { grep -Fqx -- $'ARG\t'"$1" "$REG_LOG"; }
arg_value_after() {
  awk -F '\t' -v key="$1" '
    $1 == "ARG" && $2 == key { grab = 1; next }
    grab && $1 == "ARG" { print $2; exit }
  ' "$REG_LOG"
}

# request METHOD PATH [curl args...] — sets STATUS, BODY, HDRS.
request() {
  local method=$1 path=$2
  shift 2
  BODY="$CASE/body"
  HDRS="$CASE/headers"
  : >"$BODY"
  : >"$HDRS"
  STATUS=$(curl -s --max-time 20 --path-as-is -o "$BODY" -D "$HDRS" \
    -w '%{http_code}' -X "$method" -H 'Expect:' "$@" \
    "http://127.0.0.1:$GW_PORT$path" 2>/dev/null) || STATUS=${STATUS:-}
  [[ -n $STATUS ]] || STATUS=000
}
areq() {
  local method=$1 path=$2
  shift 2
  request "$method" "$path" -H "Tailscale-User-Login: $LOGIN" "$@"
}

setup_case() {
  CASE="$SUITE/case-$((PASS_COUNT + FAIL_COUNT + 1))"
  mkdir -p "$CASE"
  reset_registry
}

run_test() {
  local name=$1
  shift
  setup_case
  if "$@"; then
    pass "$name"
  else
    fail "$name" "status=${STATUS:-?} body=$(tr '\n' ' ' <"${BODY:-/dev/null}" 2>/dev/null | head -c 300 || true)"
  fi
}

assert_security_headers() {
  grep -iq '^cache-control: *no-store' "$HDRS" || return 1
  grep -iq '^content-security-policy:' "$HDRS" || return 1
  grep -iq '^x-content-type-options: *nosniff' "$HDRS" || return 1
  grep -iq '^referrer-policy: *no-referrer' "$HDRS"
}

assert_bounded_error() {
  local wanted=$1
  (( $(wc -c <"$BODY" | tr -d ' ') <= 4096 )) || return 1
  jq -e --arg e "$wanted" '.ok == false and .error == $e' <"$BODY" >/dev/null
}

# --- startup and bind ------------------------------------------------------

test_gateway_starts_loopback_only() {
  [[ -n $GW_PORT ]] || return 1
  head -n 1 "$GW_DIR/gateway.stdout" \
    | jq -e '.ok == true and .host == "127.0.0.1" and (.port | type) == "number"' >/dev/null || return 1
  # AF_INET 127.0.0.1 bind: the IPv6 loopback must refuse the connection.
  ! curl -s --max-time 3 -o /dev/null "http://[::1]:$GW_PORT/api/v1/workflows" \
    -H "Tailscale-User-Login: $LOGIN"
}

# --- identity --------------------------------------------------------------

test_missing_identity_is_403() {
  request GET /api/v1/workflows
  [[ $STATUS == 403 ]] || return 1
  assert_bounded_error forbidden || return 1
  assert_security_headers || return 1
  [[ $(call_count) -eq 0 ]]
}

test_unknown_identity_is_403() {
  request GET /api/v1/workflows -H 'Tailscale-User-Login: mallory@evil.example'
  [[ $STATUS == 403 ]] || return 1
  assert_bounded_error forbidden || return 1
  [[ $(call_count) -eq 0 ]]
}

test_duplicated_identity_is_403() {
  request GET /api/v1/workflows \
    -H "Tailscale-User-Login: $LOGIN" \
    -H "Tailscale-User-Login: $LOGIN"
  [[ $STATUS == 403 ]] || return 1
  assert_bounded_error forbidden || return 1
  [[ $(call_count) -eq 0 ]]
}

test_world_readable_allowlist_fails_closed() {
  local dir="$SUITE/gw-perm" port loose="$SUITE/allowlist-loose"
  printf '%s\n' "$LOGIN" >"$loose"
  chmod 644 "$loose"
  port=$(launch_gateway "$dir" WORKFLOW_GATEWAY_ALLOWLIST="$loose") || return 1
  BODY="$CASE/body"; HDRS="$CASE/headers"
  STATUS=$(curl -s --max-time 20 -o "$BODY" -D "$HDRS" -w '%{http_code}' \
    -H "Tailscale-User-Login: $LOGIN" \
    "http://127.0.0.1:$port/api/v1/workflows" 2>/dev/null) || STATUS=000
  [[ $STATUS == 403 ]] || return 1
  assert_bounded_error forbidden
}

# --- read routes: registry parity -----------------------------------------

test_list_maps_to_one_registry_op() {
  areq GET /api/v1/workflows
  [[ $STATUS == 200 ]] || return 1
  [[ $(call_count) -eq 1 ]] || return 1
  assert_arg list || return 1
  assert_contains "$BODY" '"op":"list"'
}

test_inspect_maps_to_one_registry_op() {
  areq GET "/api/v1/workflows/$WF"
  [[ $STATUS == 200 ]] || return 1
  [[ $(call_count) -eq 1 ]] || return 1
  assert_arg inspect || return 1
  assert_arg "$WF"
}

test_invalid_workflow_id_is_400_without_exec() {
  local bad
  for bad in 'wf-evil%3Btouch%20PWNED' 'wf-UPPER-20260711T151201Z-9f3c' 'not-a-workflow'; do
    areq GET "/api/v1/workflows/$bad"
    [[ $STATUS == 400 ]] || return 1
    assert_bounded_error invalid-argument || return 1
    [[ $(call_count) -eq 0 ]] || return 1
  done
}

test_wait_caps_timeout_and_returns_cursor() {
  set_mode wait
  areq GET "/api/v1/workflows/$WF/wait?cursor=jrn-fixture:0&timeout=300"
  [[ $STATUS == 200 ]] || return 1
  [[ $(call_count) -eq 1 ]] || return 1
  assert_arg wait || return 1
  [[ $(arg_value_after --cursor) == 'jrn-fixture:0' ]] || return 1
  [[ $(arg_value_after --timeout) == '55' ]] || return 1
  # Continuation: the registry cursor rides back to the client verbatim.
  assert_contains "$BODY" 'jrn-fixture:9'
}

test_wait_small_timeout_passes_through() {
  set_mode wait
  areq GET "/api/v1/workflows/$WF/wait?cursor=jrn-fixture:4&timeout=10"
  [[ $STATUS == 200 ]] || return 1
  [[ $(arg_value_after --timeout) == '10' ]]
}

test_wait_invalid_cursor_or_timeout_is_400() {
  areq GET "/api/v1/workflows/$WF/wait?cursor=evil%20cursor&timeout=10"
  [[ $STATUS == 400 ]] || return 1
  [[ $(call_count) -eq 0 ]] || return 1
  areq GET "/api/v1/workflows/$WF/wait?cursor=jrn-fixture:0&timeout=abc"
  [[ $STATUS == 400 ]] || return 1
  [[ $(call_count) -eq 0 ]]
}

# --- send: prompt body -> 0600 tempfile -> stdin ---------------------------

test_send_prompt_travels_stdin_only() {
  local payload="$CASE/payload" digest
  printf '%s\nline two\n' "$PROMPT_CANARY" >"$payload"
  digest=$(shasum -a 256 "$payload" | awk '{print $1}')
  areq POST "/api/v1/workflows/$WF/send?requestId=req-send-0001" \
    --data-binary "@$payload"
  [[ $STATUS == 200 ]] || return 1
  [[ $(call_count) -eq 1 ]] || return 1
  assert_arg send || return 1
  assert_arg "$WF" || return 1
  [[ $(arg_value_after --request-id) == 'req-send-0001' ]] || return 1
  [[ $(arg_value_after --payload-sha256) == "$digest" ]] || return 1
  # Prompt bytes reach the registry via stdin, never argv.
  cmp -s "$REG_STDIN" "$payload" || return 1
  assert_lacks "$REG_LOG" "$PROMPT_CANARY" || return 1
  assert_contains "$BODY" 'req-send-0001' || return 1
  # The 0600 spool file is deleted after the exec.
  [[ -z $(find "$GW_TMP" -type f 2>/dev/null) ]]
}

test_send_forwards_ack_event() {
  printf 'ack payload\n' >"$CASE/payload"
  areq POST "/api/v1/workflows/$WF/send?requestId=req-ack-0001&ackEvent=7" \
    --data-binary "@$CASE/payload"
  [[ $STATUS == 200 ]] || return 1
  [[ $(arg_value_after --ack-event) == '7' ]]
}

test_send_requires_valid_request_id() {
  printf 'x\n' >"$CASE/payload"
  areq POST "/api/v1/workflows/$WF/send" --data-binary "@$CASE/payload"
  [[ $STATUS == 400 ]] || return 1
  [[ $(call_count) -eq 0 ]] || return 1
  areq POST "/api/v1/workflows/$WF/send?requestId=bad%20id" --data-binary "@$CASE/payload"
  [[ $STATUS == 400 ]] || return 1
  [[ $(call_count) -eq 0 ]] || return 1
  areq POST "/api/v1/workflows/$WF/send?requestId=a&requestId=b" --data-binary "@$CASE/payload"
  [[ $STATUS == 400 ]] || return 1
  [[ $(call_count) -eq 0 ]]
}

test_send_enforces_64k_cap() {
  head -c 65537 /dev/zero | tr '\0' 'a' >"$CASE/huge"
  areq POST "/api/v1/workflows/$WF/send?requestId=req-huge-0001" \
    --data-binary "@$CASE/huge"
  [[ $STATUS == 413 ]] || return 1
  assert_bounded_error payload-too-large || return 1
  [[ $(call_count) -eq 0 ]]
}

# The spool must be unreachable by path for the entire registry exec: a
# SIGKILL mid-exec runs no cleanup code, so an implementation that relies on
# a finally-block unlink leaks the 0600 prompt file into TMPDIR.  This test
# catches the gateway mid-exec (registry hung after consuming stdin) and
# fails any path-visible or kill-surviving spool.
test_spool_unreachable_by_path_and_survives_no_kill() {
  local dir="$SUITE/gw-spool" port tmp gw_pid curl_pid i
  port=$(launch_gateway "$dir") || return 1
  printf 'hang\n' >"$dir/ctrl/mode"
  tmp="$dir/tmp"
  gw_pid=$(head -n 1 "$dir/pid")
  printf '%s spool survival\n' "$PROMPT_CANARY" >"$CASE/payload"
  curl -s --max-time 20 -o /dev/null -X POST -H 'Expect:' \
    -H "Tailscale-User-Login: $LOGIN" \
    --data-binary "@$CASE/payload" \
    "http://127.0.0.1:$port/api/v1/workflows/$WF/send?requestId=req-spool-01" \
    2>/dev/null &
  curl_pid=$!
  # Sync point: the registry copies its stdin before hanging, so the canary
  # in registry.stdin proves the exec is in flight with the prompt consumed.
  for ((i = 0; i < 200; i++)); do
    grep -Fq "$PROMPT_CANARY" "$dir/registry.stdin" 2>/dev/null && break
    sleep 0.05
  done
  if ! grep -Fq "$PROMPT_CANARY" "$dir/registry.stdin" 2>/dev/null; then
    kill "$curl_pid" 2>/dev/null || true
    return 1
  fi
  # Mid-exec: no prompt-bearing file may be reachable by path in TMPDIR.
  if [[ -n $(find "$tmp" -type f 2>/dev/null) ]]; then
    kill "$curl_pid" 2>/dev/null || true
    return 1
  fi
  # Abnormal termination mid-exec: SIGKILL runs no finally blocks.
  kill -9 "$gw_pid" 2>/dev/null || true
  wait "$curl_pid" 2>/dev/null || true
  [[ -z $(find "$tmp" -type f 2>/dev/null) ]] || return 1
  ! grep -Frq "$PROMPT_CANARY" "$tmp" 2>/dev/null
}

test_cancel_pending_is_same_send_op() {
  areq POST "/api/v1/workflows/$WF/cancel-pending?requestId=req-cancel-01"
  [[ $STATUS == 200 ]] || return 1
  [[ $(call_count) -eq 1 ]] || return 1
  assert_arg send || return 1
  assert_arg '--cancel-pending' || return 1
  [[ $(arg_value_after --request-id) == 'req-cancel-01' ]] || return 1
  assert_lacks "$REG_LOG" '--payload-sha256'
}

# --- lifecycle + mirror mutations ------------------------------------------

test_lifecycle_mutations_map_once() {
  local route op
  for route in interrupt kill release reveal sync; do
    reset_registry
    case $route in
      sync) op=request-mirror-sync ;;
      *) op=$route ;;
    esac
    areq POST "/api/v1/workflows/$WF/$route?requestId=req-$route-01"
    [[ $STATUS == 200 ]] || return 1
    [[ $(call_count) -eq 1 ]] || return 1
    assert_arg "$op" || return 1
    assert_arg "$WF" || return 1
    [[ $(arg_value_after --request-id) == "req-$route-01" ]] || return 1
    assert_contains "$BODY" "req-$route-01" || return 1
  done
}

test_mirror_cancel_maps_to_one_registry_op() {
  areq POST '/api/v1/mirror-jobs/job-17/cancel?requestId=req-mc-0001'
  [[ $STATUS == 200 ]] || return 1
  [[ $(call_count) -eq 1 ]] || return 1
  assert_arg mirror-cancel || return 1
  assert_arg job-17 || return 1
  [[ $(arg_value_after --request-id) == 'req-mc-0001' ]]
}

test_start_uses_fixed_atoms_only() {
  areq POST '/api/v1/workflows/start?project=orchestration&planId=selected&requestId=req-start-01'
  [[ $STATUS == 200 ]] || return 1
  [[ $(call_count) -eq 1 ]] || return 1
  assert_arg start-conductor || return 1
  assert_arg orchestration || return 1
  assert_arg selected || return 1
  [[ $(arg_value_after --request-id) == 'req-start-01' ]] || return 1
  # No route accepts a host, path, command, or tmux target: every exec'd
  # atom is a closed token, so no argument may contain a slash.
  ! grep -q $'^ARG\t.*/' "$REG_LOG"
}

test_start_rejects_unknown_project() {
  areq POST '/api/v1/workflows/start?project=evilproj&planId=selected&requestId=req-start-02'
  [[ $STATUS == 400 ]] || return 1
  assert_bounded_error invalid-argument || return 1
  [[ $(call_count) -eq 0 ]]
}

# --- registry refusals surface bounded -------------------------------------

test_mutex_held_surfaces_as_409() {
  set_mode mutex-held
  areq POST "/api/v1/workflows/$WF/kill?requestId=req-kill-409"
  [[ $STATUS == 409 ]] || return 1
  assert_bounded_error mutex-held || return 1
  assert_security_headers
}

test_queue_full_surfaces_as_409() {
  set_mode queue-full
  printf 'queued input\n' >"$CASE/payload"
  areq POST "/api/v1/workflows/$WF/send?requestId=req-qf-0001" \
    --data-binary "@$CASE/payload"
  [[ $STATUS == 409 ]] || return 1
  assert_bounded_error queue-full
}

test_registry_not_found_surfaces_as_404() {
  set_mode not-found
  areq GET "/api/v1/workflows/$WF"
  [[ $STATUS == 404 ]] || return 1
  assert_bounded_error not-found
}

test_garbage_registry_output_is_502_and_not_echoed() {
  set_mode garbage
  areq GET /api/v1/workflows
  [[ $STATUS == 502 ]] || return 1
  jq -e '.ok == false' <"$BODY" >/dev/null || return 1
  assert_lacks "$BODY" 'REGISTRY-RAW-GARBAGE'
}

test_registry_timeout_is_504_bounded() {
  local dir="$SUITE/gw-timeout" port
  port=$(launch_gateway "$dir" WORKFLOW_GATEWAY_EXEC_TIMEOUT=1) || return 1
  printf 'slow\n' >"$dir/ctrl/mode"
  BODY="$CASE/body"; HDRS="$CASE/headers"
  STATUS=$(curl -s --max-time 20 -o "$BODY" -D "$HDRS" -w '%{http_code}' \
    -H "Tailscale-User-Login: $LOGIN" \
    "http://127.0.0.1:$port/api/v1/workflows" 2>/dev/null) || STATUS=000
  [[ $STATUS == 504 ]] || return 1
  jq -e '.ok == false' <"$BODY" >/dev/null
}

# --- Origin / Host discipline ----------------------------------------------

test_cross_origin_mutation_is_403() {
  areq POST "/api/v1/workflows/$WF/kill?requestId=req-orig-01" \
    -H 'Origin: https://evil.example'
  [[ $STATUS == 403 ]] || return 1
  assert_bounded_error forbidden || return 1
  [[ $(call_count) -eq 0 ]]
}

test_same_origin_and_serve_host_allowed() {
  areq POST "/api/v1/workflows/$WF/kill?requestId=req-orig-02" \
    -H "Origin: http://127.0.0.1:$GW_PORT"
  [[ $STATUS == 200 ]] || return 1
  reset_registry
  areq POST "/api/v1/workflows/$WF/kill?requestId=req-orig-03" \
    -H "Host: $SERVE_HOST" -H "Origin: https://$SERVE_HOST"
  [[ $STATUS == 200 ]] || return 1
  [[ $(call_count) -eq 1 ]]
}

test_foreign_host_is_403() {
  areq POST "/api/v1/workflows/$WF/kill?requestId=req-host-01" \
    -H 'Host: evil.example'
  [[ $STATUS == 403 ]] || return 1
  [[ $(call_count) -eq 0 ]]
}

# --- headers, static whitelist, method discipline --------------------------

test_security_headers_on_every_response() {
  areq GET /api/v1/workflows
  [[ $STATUS == 200 ]] || return 1
  assert_security_headers || return 1
  areq GET /api/v1/no-such-route
  [[ $STATUS == 404 ]] || return 1
  assert_security_headers || return 1
  request GET /api/v1/workflows
  [[ $STATUS == 403 ]] || return 1
  assert_security_headers
}

test_static_whitelist_serves_only_app_shell() {
  areq GET /
  [[ $STATUS == 200 ]] || return 1
  assert_contains "$BODY" 'GATEWAY-APP-SHELL' || return 1
  grep -iq '^content-type: *text/html' "$HDRS" || return 1
  assert_security_headers || return 1
  areq GET /evil.plist
  [[ $STATUS == 404 ]] || return 1
  areq GET /notlisted.txt
  [[ $STATUS == 404 ]] || return 1
  areq GET /../allowlist
  [[ $STATUS == 400 || $STATUS == 404 ]] || return 1
  assert_lacks "$BODY" "$LOGIN" || return 1
  [[ $(call_count) -eq 0 ]]
}

test_method_discipline() {
  areq POST /api/v1/workflows
  [[ $STATUS == 405 ]] || return 1
  [[ $(call_count) -eq 0 ]] || return 1
  areq GET "/api/v1/workflows/$WF/kill?requestId=req-method-01"
  [[ $STATUS == 405 ]] || return 1
  [[ $(call_count) -eq 0 ]] || return 1
  areq DELETE "/api/v1/workflows/$WF"
  [[ $STATUS == 405 ]] || return 1
  [[ $(call_count) -eq 0 ]] || return 1
  areq GET /api/v1/frontier
  [[ $STATUS == 404 ]] || return 1
  assert_bounded_error not-found || return 1
  [[ $(call_count) -eq 0 ]]
}

# Methods without a do_* handler (OPTIONS, TRACE) are answered by the
# server machinery itself; they too must carry the full security header
# set and a bounded JSON body, never the stdlib HTML error page.
test_unhandled_methods_get_security_headers() {
  areq OPTIONS /api/v1/workflows
  [[ $STATUS == 501 ]] || return 1
  assert_security_headers || return 1
  assert_bounded_error not-implemented || return 1
  [[ $(call_count) -eq 0 ]] || return 1
  areq TRACE "/api/v1/workflows/$WF"
  [[ $STATUS == 501 ]] || return 1
  assert_security_headers || return 1
  assert_bounded_error not-implemented || return 1
  [[ $(call_count) -eq 0 ]]
}

# --- audit: labels only -----------------------------------------------------

test_audit_log_is_labels_only() {
  printf '%s\n' "$PROMPT_CANARY" >"$CASE/payload"
  areq POST "/api/v1/workflows/$WF/send?requestId=req-audit-01" \
    --data-binary "@$CASE/payload"
  [[ $STATUS == 200 ]] || return 1
  [[ -f $AUDIT ]] || return 1
  [[ $(perm_of "$AUDIT") == 600 ]] || return 1
  assert_contains "$AUDIT" "$LOGIN" || return 1
  assert_contains "$AUDIT" 'req-audit-01' || return 1
  assert_lacks "$AUDIT" "$PROMPT_CANARY" || return 1
  assert_lacks "$GW_DIR/gateway.stderr" "$PROMPT_CANARY"
}

# --- the gateway never orchestrates ----------------------------------------

test_one_exec_per_request() {
  areq GET /api/v1/workflows
  areq GET "/api/v1/workflows/$WF"
  areq POST "/api/v1/workflows/$WF/kill?requestId=req-burst-01"
  [[ $(call_count) -eq 3 ]]
}

test_source_never_orchestrates() {
  local forbidden
  [[ -f $GATEWAY ]] || return 1
  for forbidden in \
    'run-codex-impl' 'run-codex-verify' 'run-grok-impl' 'run-grok-verify' \
    'plan-utils' 'set-frontier' 'start-step' 'record-verdict' \
    'mini-workflow.json' '.temp/plan-mode' 'tmux' \
    'shell=True' 'os.system' 'getoutput'; do
    assert_lacks "$GATEWAY" "$forbidden" || return 1
  done
}

run_test 'gateway starts on an ephemeral loopback-only port' test_gateway_starts_loopback_only
run_test 'missing identity header is a bounded 403 without exec' test_missing_identity_is_403
run_test 'unknown identity is a bounded 403 without exec' test_unknown_identity_is_403
run_test 'duplicated identity headers are a bounded 403' test_duplicated_identity_is_403
run_test 'world-readable allowlist fails closed with 403' test_world_readable_allowlist_fails_closed
run_test 'list maps to exactly one registry list op' test_list_maps_to_one_registry_op
run_test 'inspect maps to exactly one registry inspect op' test_inspect_maps_to_one_registry_op
run_test 'invalid workflowId atoms 400 before any exec' test_invalid_workflow_id_is_400_without_exec
run_test 'wait caps the registry timeout at 55s and relays the cursor' test_wait_caps_timeout_and_returns_cursor
run_test 'wait passes a small timeout through unchanged' test_wait_small_timeout_passes_through
run_test 'wait rejects invalid cursor and timeout atoms with 400' test_wait_invalid_cursor_or_timeout_is_400
run_test 'send spools the prompt to stdin only and deletes the tempfile' test_send_prompt_travels_stdin_only
run_test 'send forwards --ack-event as a fixed atom' test_send_forwards_ack_event
run_test 'send requires exactly one valid requestId' test_send_requires_valid_request_id
run_test 'send refuses payloads over 64 KiB with a bounded 413' test_send_enforces_64k_cap
run_test 'send spool is path-unreachable mid-exec and survives no SIGKILL' \
  test_spool_unreachable_by_path_and_survives_no_kill
run_test 'cancel-pending is the same idempotent send op' test_cancel_pending_is_same_send_op
run_test 'interrupt kill release reveal sync each map to one registry op' test_lifecycle_mutations_map_once
run_test 'mirror-cancel maps to one registry mirror-cancel op' test_mirror_cancel_maps_to_one_registry_op
run_test 'start relays fixed atoms and never a path or host' test_start_uses_fixed_atoms_only
run_test 'start rejects a project outside the closed set' test_start_rejects_unknown_project
run_test 'mutex-held registry refusal surfaces as a bounded 409' test_mutex_held_surfaces_as_409
run_test 'queue-full registry refusal surfaces as a bounded 409' test_queue_full_surfaces_as_409
run_test 'registry not-found surfaces as a bounded 404' test_registry_not_found_surfaces_as_404
run_test 'unparseable registry output is a bounded 502 never echoed' test_garbage_registry_output_is_502_and_not_echoed
run_test 'registry exec timeout is a bounded 504' test_registry_timeout_is_504_bounded
run_test 'cross-origin mutation is refused 403 before exec' test_cross_origin_mutation_is_403
run_test 'same-origin and serve-host mutations are allowed' test_same_origin_and_serve_host_allowed
run_test 'foreign Host header is refused 403 before exec' test_foreign_host_is_403
run_test 'no-store CSP nosniff no-referrer ride every response' test_security_headers_on_every_response
run_test 'static whitelist serves the app shell and 404s everything else' test_static_whitelist_serves_only_app_shell
run_test 'method discipline: 405 on wrong method 404 on unknown route' test_method_discipline
run_test 'OPTIONS and TRACE get security headers and bounded JSON' \
  test_unhandled_methods_get_security_headers
run_test 'audit log is 0600 labels-only and never sees prompt text' test_audit_log_is_labels_only
run_test 'each request execs the registry exactly once' test_one_exec_per_request
run_test 'gateway source contains no orchestration or shell interpolation' test_source_never_orchestrates

printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
