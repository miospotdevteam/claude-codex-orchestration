#!/usr/bin/env bash
set -euo pipefail

# RED/GREEN contract for Mini APNs push sender over the durable outbox
# (nativeIosCorrection / notificationTransport / G4 / C3).
# Targets orchestration/scripts/apns-sender against a stub APNs endpoint
# (fake curl --http2) and the real workflow-registry outbox.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SENDER="$SCRIPT_DIR/../../scripts/apns-sender"
REGISTRY="$SCRIPT_DIR/../../scripts/workflow-registry"
PLIST="$SCRIPT_DIR/../../templates/mini-relay/com.orchestration.apns-sender.plist"
PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
trap 'rm -rf "$SUITE"' EXIT

REAL_JQ=$(command -v jq || true)
REAL_OPENSSL=$(command -v openssl || true)
JQ_DIR=
OPENSSL_DIR=
if [[ -n $REAL_JQ ]]; then
  JQ_DIR=$(cd "$(dirname "$REAL_JQ")" && pwd -P)
fi
if [[ -n $REAL_OPENSSL ]]; then
  OPENSSL_DIR=$(cd "$(dirname "$REAL_OPENSSL")" && pwd -P)
fi
BASE_PATH="/usr/bin:/bin"
if [[ -n $JQ_DIR && $JQ_DIR != /usr/bin && $JQ_DIR != /bin ]]; then
  BASE_PATH="$JQ_DIR:$BASE_PATH"
fi
if [[ -n $OPENSSL_DIR && $OPENSSL_DIR != /usr/bin && $OPENSSL_DIR != /bin ]]; then
  BASE_PATH="$OPENSSL_DIR:$BASE_PATH"
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
  PLAN_ID="apns-sender-plan"
  PLAN_DIR="$CHECKOUT/.temp/plan-mode/active/$PLAN_ID"
  HOSTNAME_FIXTURE="mini-test-host"
  PROJECT=orchestration
  WF_ROOT="$STATE_ROOT/orchestration/workflows"
  APNS_ROOT="$STATE_ROOT/orchestration/apns"
  FAKE_BIN="$CASE/bin"
  CURL_LOG="$CASE/curl.log"
  CURL_BODIES="$CASE/curl.bodies"
  CURL_URLS="$CASE/curl.urls"
  CURL_HEADERS="$CASE/curl.headers"
  STDOUT="$CASE/stdout"
  STDERR="$CASE/stderr"
  STATUS_FILE="$CASE/status"
  mkdir -p "$HOME_DIR" "$STATE_ROOT" "$CHECKOUT" "$PLAN_DIR" "$FAKE_BIN" "$CURL_BODIES"
  chmod 700 "$HOME_DIR" "$STATE_ROOT" "$CHECKOUT"
  printf '%s\n' '{"planId":"apns-sender-plan","frozen":true}' >"$PLAN_DIR/plan.json"
  printf '%s\n' '{"planId":"apns-sender-plan","steps":{}}' >"$PLAN_DIR/progress.json"
  printf '# apns-sender plan\n' >"$PLAN_DIR/masterPlan.md"
  : >"$CURL_LOG"
  : >"$CURL_URLS"
  : >"$CURL_HEADERS"
  : >"$STDOUT"
  : >"$STDERR"
  : >"$STATUS_FILE"

  # Stub APNs endpoint: records curl --http2 posts, never contacts Apple.
  # Supports --config (secrets stay out of argv) and -H @file.
  # shellcheck disable=SC2016
  cat >"$FAKE_BIN/curl" <<'CURL_STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl' >>"$CURL_LOG"
for a in "$@"; do printf ' <%s>' "$a" >>"$CURL_LOG"; done
printf '\n' >>"$CURL_LOG"

has_http2=0
url=
body_file=
out_file=
write_fmt=
dump_header=
i=0
args=("$@")

# Apply one curl --config line (url = "..." / header = "...").
apply_curl_config_line() {
  local line=$1
  local val
  line=${line%%#*}
  line=${line#"${line%%[![:space:]]*}"}
  line=${line%"${line##*[![:space:]]}"}
  [[ -n $line ]] || return 0
  case "$line" in
    url[[:space:]]*=*)
      val=${line#*=}
      val=${val#"${val%%[![:space:]]*}"}
      val=${val#\"}
      val=${val%\"}
      url=$val
      ;;
    header[[:space:]]*=*)
      val=${line#*=}
      val=${val#"${val%%[![:space:]]*}"}
      val=${val#\"}
      val=${val%\"}
      printf '%s\n' "$val" >>"$CURL_HEADERS"
      ;;
  esac
}

while (( i < ${#args[@]} )); do
  a=${args[$i]}
  case "$a" in
    --http2) has_http2=1 ;;
    --data-binary|--data|-d)
      i=$((i + 1))
      body_file=${args[$i]:-}
      body_file=${body_file#@}
      ;;
    -o|--output)
      i=$((i + 1))
      out_file=${args[$i]:-}
      ;;
    -w|--write-out)
      i=$((i + 1))
      write_fmt=${args[$i]:-}
      ;;
    -D|--dump-header)
      i=$((i + 1))
      dump_header=${args[$i]:-}
      ;;
    -K|--config)
      i=$((i + 1))
      cfg=${args[$i]:-}
      # Accept regular files and process-sub fifos (/dev/fd/N) — secrets must
      # never require an on-disk curl config.
      if [[ -n $cfg && -e $cfg ]]; then
        while IFS= read -r cfg_line || [[ -n $cfg_line ]]; do
          apply_curl_config_line "$cfg_line"
        done <"$cfg"
      fi
      ;;
    -H|--header)
      i=$((i + 1))
      h=${args[$i]:-}
      if [[ $h == @* && -e ${h#@} ]]; then
        h=$(cat "${h#@}")
      fi
      printf '%s\n' "$h" >>"$CURL_HEADERS"
      ;;
    https://*|http://*)
      url=$a
      ;;
  esac
  i=$((i + 1))
done

[[ $has_http2 -eq 1 ]] || { printf 'stub-curl: missing --http2\n' >&2; exit 2; }
[[ -n $url ]] || { printf 'stub-curl: missing url\n' >&2; exit 2; }
printf '%s\n' "$url" >>"$CURL_URLS"

n=$(wc -l <"$CURL_URLS" | tr -d ' ')
if [[ -n $body_file && -e $body_file ]]; then
  cat "$body_file" >"$CURL_BODIES/body-$n.json"
else
  : >"$CURL_BODIES/body-$n.json"
fi

status=200
if [[ -n ${APNS_STUB_STATUS:-} ]]; then
  IFS=',' read -r -a codes <<<"$APNS_STUB_STATUS"
  idx=$((n - 1))
  if (( idx >= 0 && idx < ${#codes[@]} )); then
    status=${codes[$idx]}
  else
    status=${codes[${#codes[@]}-1]}
  fi
fi

reason=${APNS_STUB_REASON:-}
if [[ $status == 410 && -z $reason ]]; then
  reason=Unregistered
fi

resp_body=
if [[ $status == 200 ]]; then
  resp_body=
else
  if [[ -n $reason ]]; then
    resp_body=$(printf '{"reason":"%s"}' "$reason")
  else
    resp_body='{"reason":"InternalServerError"}'
  fi
fi

if [[ -n $out_file ]]; then
  printf '%s' "$resp_body" >"$out_file"
else
  printf '%s' "$resp_body"
fi

if [[ -n $dump_header ]]; then
  printf 'HTTP/2 %s\r\n\r\n' "$status" >"$dump_header"
fi

if [[ -n $write_fmt ]]; then
  # Support %{http_code} only (what the sender uses).
  out=$write_fmt
  out=${out//\%\{http_code\}/$status}
  printf '%s' "$out"
fi
exit 0
CURL_STUB
  chmod +x "$FAKE_BIN/curl"
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

expect_registry() {
  run_registry "$@"
  [[ $STATUS -eq 0 ]]
}

run_sender() {
  set +e
  if [[ ! -x $SENDER ]]; then
    STATUS=127
    : >"$STDOUT"
    printf 'missing executable: %s\n' "$SENDER" >"$STDERR"
    set -e
    return 0
  fi
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    WORKFLOW_REGISTRY="$REGISTRY" \
    WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    APNS_KEY_ID="${APNS_KEY_ID:-TESTKEY1}" \
    APNS_TEAM_ID="${APNS_TEAM_ID:-TEAMID12}" \
    APNS_TOPIC="${APNS_TOPIC:-com.orchestration.minirelay}" \
    APNS_STUB_STATUS="${APNS_STUB_STATUS:-}" \
    APNS_STUB_REASON="${APNS_STUB_REASON:-}" \
    CURL_LOG="$CURL_LOG" \
    CURL_URLS="$CURL_URLS" \
    CURL_HEADERS="$CURL_HEADERS" \
    CURL_BODIES="$CURL_BODIES" \
    "$SENDER" "$@" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
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

mint_workflow() {
  expect_registry mint orchestration "$PLAN_ID" "$CHECKOUT" "$HOSTNAME_FIXTURE" || return 1
  WORKFLOW_ID=$(json_string "$STDOUT" workflowId)
  [[ -n $WORKFLOW_ID ]] || return 1
}

gen_p8() {
  local dest=$1
  [[ -n $REAL_OPENSSL ]] || return 1
  local pem=$CASE/ec.pem
  "$REAL_OPENSSL" ecparam -name prime256v1 -genkey -noout -out "$pem" 2>/dev/null || return 1
  "$REAL_OPENSSL" pkcs8 -topk8 -nocrypt -in "$pem" -out "$dest" 2>/dev/null || return 1
  chmod 600 "$dest"
}

install_apns_key() {
  local p8=$CASE/AuthKey_TESTKEY1.p8
  gen_p8 "$p8" || return 1
  run_sender install-key --p8 "$p8" --key-id "${APNS_KEY_ID:-TESTKEY1}" --team-id "${APNS_TEAM_ID:-TEAMID12}" || return 1
  [[ $STATUS -eq 0 ]] || return 1
}

register_device() {
  local device=$1 cred=$2 build=$3 token=$4
  expect_registry device-register \
    --device-id "$device" \
    --credential "$cred" \
    --build-type "$build" \
    --request-id "req-reg-$device-$$" || return 1
  run_sender set-device-token --device-id "$device" --token "$token" || return 1
  [[ $STATUS -eq 0 ]] || return 1
}

# ── structural ─────────────────────────────────────────────────────────────

test_script_and_plist_exist() {
  [[ -x $SENDER ]] || return 1
  [[ -f $PLIST ]] || return 1
  assert_contains "$PLIST" 'com.orchestration.apns-sender' || return 1
  assert_contains "$PLIST" 'KeepAlive' || return 1
  assert_contains "$PLIST" 'apns-sender' || return 1
  # Supervised in GUI session (user LaunchAgent shape — no Root / no system daemon).
  assert_lacks "$PLIST" 'UserName' || return 1
  return 0
}

# ── outbox consume + JWT + http2 ───────────────────────────────────────────

test_consumes_outbox_acks_and_uses_http2_jwt() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1

  local device=dev-phone-a cred=cred-phone-a token=aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899
  register_device "$device" "$cred" sandbox "$token" || return 1

  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 10 || return 1

  APNS_STUB_STATUS=200 run_sender once || return 1
  [[ $STATUS -eq 0 ]] || return 1

  # curl --http2 must have been used
  assert_contains "$CURL_LOG" '--http2' || return 1
  # sandbox host
  assert_contains "$CURL_URLS" 'api.sandbox.push.apple.com' || return 1
  assert_contains "$CURL_URLS" "/3/device/$token" || return 1

  # JWT authorization present and never logs the .p8 material
  assert_contains "$CURL_HEADERS" 'authorization: bearer ' || assert_contains "$CURL_HEADERS" 'Authorization: bearer ' || \
    assert_contains "$CURL_HEADERS" 'authorization: Bearer ' || assert_contains "$CURL_HEADERS" 'Authorization: Bearer ' || return 1
  assert_lacks "$STDOUT" 'BEGIN PRIVATE KEY' || return 1
  assert_lacks "$STDERR" 'BEGIN PRIVATE KEY' || return 1
  assert_lacks "$STDOUT" "$token" || return 1
  assert_lacks "$STDERR" "$token" || return 1

  # Ack advanced durable cursor — fetch no longer returns seq 10
  expect_registry outbox-fetch --device-id "$device" --credential "$cred" --cursor 0 || return 1
  jq -e '[(.records // [])[] | select((.seq // 0 | tonumber) == 10)] | length == 0' "$STDOUT" >/dev/null || return 1

  # Payload body is privacy-safe
  local body=$CURL_BODIES/body-1.json
  [[ -f $body ]] || return 1
  jq -e '
    .aps.badge != null
    and (.class // .aps.alert.title) != null
    and (
      (.entityId // .ref // .aps.alert.body // empty) | length > 0
    )
  ' "$body" >/dev/null || return 1
  # Forbidden authority / secret fields
  jq -e '
    (keys | map(select(. == "action" or . == "command" or . == "approve" or . == "prompt" or . == "transcript" or . == "authority")) | length) == 0
    and ((.aps // {}) | keys | map(select(. == "action" or . == "command")) | length) == 0
  ' "$body" >/dev/null || return 1

  return 0
}

test_delivery_failure_never_erases_events() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-fail cred=cred-fail token=11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration failed-recovery "$WORKFLOW_ID" 20 || return 1

  APNS_STUB_STATUS=500 run_sender once || true
  # Event still fetchable
  expect_registry outbox-fetch --device-id "$device" --credential "$cred" --cursor 0 || return 1
  jq -e '[(.records // [])[] | select((.seq // 0 | tonumber) == 20)] | length == 1' "$STDOUT" >/dev/null || return 1
  return 0
}

test_jwt_es256_kid_team_and_refresh_window() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-jwt cred=cred-jwt token=99aabbccddeeff00112233445566778899aabbccddeeff001122334455667788
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration completed "$WORKFLOW_ID" 30 || return 1

  APNS_STUB_STATUS=200 run_sender once || return 1
  [[ $STATUS -eq 0 ]] || return 1

  # Extract bearer token from headers
  local auth jwt hdr_b64 claims_b64
  auth=$(grep -i '^authorization:' "$CURL_HEADERS" | head -n 1 | sed 's/.*[Bb]earer //')
  [[ -n $auth ]] || return 1
  jwt=$auth
  hdr_b64=${jwt%%.*}
  rest=${jwt#*.}
  claims_b64=${rest%%.*}
  # base64url decode
  decode_b64url() {
    local s=$1 pad
    s=${s//-/+}
    s=${s//_/\/}
    pad=$(( (4 - ${#s} % 4) % 4 ))
    printf '%s%s' "$s" "$(printf '%*s' "$pad" '' | tr ' ' '=')" | openssl base64 -d -A 2>/dev/null
  }
  local hdr_json claims_json
  hdr_json=$(decode_b64url "$hdr_b64")
  claims_json=$(decode_b64url "$claims_b64")
  printf '%s' "$hdr_json" | jq -e '.alg == "ES256" and .kid == "TESTKEY1"' >/dev/null || return 1
  printf '%s' "$claims_json" | jq -e '.iss == "TEAMID12" and (.iat | type == "number")' >/dev/null || return 1

  # Refresh window is 20–60 min (constants + clamp in source). No durable disk cache
  # (choice b: in-memory for process lifetime; each `once` re-mints — TTL makes this cheap).
  grep -Eq 'JWT_MIN_TTL=1200' "$SENDER" || return 1
  grep -Eq 'JWT_MAX_TTL=3600' "$SENDER" || return 1
  grep -Eq 'JWT_DEFAULT_TTL=2400|ttl=\$\{APNS_JWT_TTL' "$SENDER" || return 1
  # Clamp logic present
  grep -Eq 'ttl < JWT_MIN_TTL|JWT_MIN_TTL' "$SENDER" || return 1
  grep -Eq 'ttl > JWT_MAX_TTL|JWT_MAX_TTL' "$SENDER" || return 1

  # Second once still mints a valid ES256 JWT (may differ — no plaintext disk cache).
  expect_registry feed-append orchestration released "$WORKFLOW_ID" 31 || return 1
  : >"$CURL_HEADERS"
  APNS_STUB_STATUS=200 run_sender once || return 1
  local auth2
  auth2=$(grep -i '^authorization:' "$CURL_HEADERS" | head -n 1 | sed 's/.*[Bb]earer //')
  [[ -n $auth2 ]] || return 1
  hdr_b64=${auth2%%.*}
  rest=${auth2#*.}
  claims_b64=${rest%%.*}
  hdr_json=$(decode_b64url "$hdr_b64")
  claims_json=$(decode_b64url "$claims_b64")
  printf '%s' "$hdr_json" | jq -e '.alg == "ES256" and .kid == "TESTKEY1"' >/dev/null || return 1
  printf '%s' "$claims_json" | jq -e '.iss == "TEAMID12" and (.iat | type == "number")' >/dev/null || return 1
  # No plaintext bearer cache on disk
  [[ ! -f $APNS_ROOT/jwt.cache ]] || return 1
  return 0
}

# ── host routing ───────────────────────────────────────────────────────────

test_sandbox_host_for_dev_install() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-sb cred=cred-sb token=aa11bb22cc33dd44ee55ff6677889900aa11bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 40 || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  assert_contains "$CURL_URLS" 'https://api.sandbox.push.apple.com/' || return 1
  assert_lacks "$CURL_URLS" 'https://api.push.apple.com/' || return 1
  return 0
}

test_production_host_for_testflight() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-prod cred=cred-prod token=bb11bb22cc33dd44ee55ff6677889900bb11bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" production "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 41 || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  assert_contains "$CURL_URLS" 'https://api.push.apple.com/' || return 1
  assert_lacks "$CURL_URLS" 'api.sandbox.push.apple.com' || return 1
  return 0
}

# ── privacy / badge / C3 prefs ─────────────────────────────────────────────

test_payload_class_opaque_ref_only_and_badge() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-priv cred=cred-priv token=cc11bb22cc33dd44ee55ff6677889900cc11bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration awaiting-approval "$WORKFLOW_ID" 50 || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  local body=$CURL_BODIES/body-1.json
  [[ -f $body ]] || return 1
  # Allowed top-level keys: aps, class, entityId (or ref) only
  jq -e '
    (keys | sort) as $k
    | ($k - ["aps","class","entityId","ref"] | length) == 0
    and .class == "awaiting-approval"
    and ((.entityId // .ref) | tostring | length) > 0
    and (.aps.badge | type == "number")
    and (.aps.badge >= 1)
  ' "$body" >/dev/null || return 1
  # No secret-looking content
  assert_lacks "$body" 'prompt' || return 1
  assert_lacks "$body" 'transcript' || return 1
  assert_lacks "$body" 'BEGIN PRIVATE' || return 1
  assert_lacks "$body" 'SECRET' || return 1
  return 0
}

test_chat_reply_completed_default_off_c3() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-c3 cred=cred-c3 token=dd11bb22cc33dd44ee55ff6677889900dd11bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  # Lifecycle class should send; chat-reply-completed should not (default-off).
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 60 || return 1
  expect_registry feed-append orchestration chat-reply-completed "chat-xyz" 61 || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  # Exactly one push (needs-input only)
  local n
  n=$(wc -l <"$CURL_URLS" | tr -d ' ')
  [[ $n -eq 1 ]] || return 1
  jq -e '.class == "needs-input"' "$CURL_BODIES/body-1.json" >/dev/null || return 1

  # Enabling per-class pref sends chat-reply-completed
  local device_dir=$WF_ROOT/outbox/$device
  printf '%s\n' '{"classes":{"chat-reply-completed":true}}' >"$device_dir/prefs.json"
  chmod 600 "$device_dir/prefs.json"
  : >"$CURL_URLS"
  rm -f "$CURL_BODIES"/body-*.json
  APNS_STUB_STATUS=200 run_sender once || return 1
  n=$(wc -l <"$CURL_URLS" | tr -d ' ')
  [[ $n -eq 1 ]] || return 1
  jq -e '.class == "chat-reply-completed"' "$CURL_BODIES/body-1.json" >/dev/null || return 1
  return 0
}

test_per_chat_pref_overrides_class_default() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-chatpref cred=cred-chatpref token=ee11bb22cc33dd44ee55ff6677889900ee11bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  local device_dir=$WF_ROOT/outbox/$device
  printf '%s\n' '{"classes":{"chat-reply-completed":false},"chats":{"chat-on":{"chat-reply-completed":true}}}' \
    >"$device_dir/prefs.json"
  chmod 600 "$device_dir/prefs.json"
  expect_registry feed-append orchestration chat-reply-completed "chat-on" 70 || return 1
  expect_registry feed-append orchestration chat-reply-completed "chat-off" 71 || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  local n
  n=$(wc -l <"$CURL_URLS" | tr -d ' ')
  [[ $n -eq 1 ]] || return 1
  jq -e '.class == "chat-reply-completed" and ((.entityId // .ref) == "chat-on")' \
    "$CURL_BODIES/body-1.json" >/dev/null || return 1
  return 0
}

# ── credentials / revocation / G4 ──────────────────────────────────────────

test_p8_and_token_are_0600_encrypted_never_printed() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-sec cred=cred-sec token=SECRETTOKEN0000111122223333444455556666777788889999aaaabbbbcccc
  register_device "$device" "$cred" sandbox "$token" || return 1

  # Encrypted capability files exist with mode 0600
  local key_enc token_enc
  key_enc=$(find "$APNS_ROOT" -type f \( -name '*.p8.enc' -o -name 'AuthKey*.enc' -o -name 'p8.enc' \) | head -n 1)
  [[ -n $key_enc && -f $key_enc ]] || return 1
  [[ $(file_mode "$key_enc") == 600 ]] || return 1
  # Must not be plaintext PEM
  assert_lacks "$key_enc" 'BEGIN PRIVATE KEY' || return 1

  token_enc=$(find "$WF_ROOT/outbox/$device" -type f \( -name 'apns-token*' -o -name 'token*' \) | head -n 1)
  [[ -n $token_enc && -f $token_enc ]] || return 1
  [[ $(file_mode "$token_enc") == 600 ]] || return 1
  # Encrypted: plaintext token must not appear as raw file content
  assert_lacks "$token_enc" "$token" || return 1

  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 80 || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  assert_lacks "$STDOUT" "$token" || return 1
  assert_lacks "$STDERR" "$token" || return 1
  assert_lacks "$STDOUT" 'BEGIN PRIVATE KEY' || return 1
  assert_lacks "$STDERR" 'BEGIN PRIVATE KEY' || return 1
  # Bounded log must not leak either
  if [[ -d $APNS_ROOT ]]; then
    if grep -RFq -- "$token" "$APNS_ROOT" 2>/dev/null; then
      # only the encrypted token file may contain ciphertext that coincidentally
      # shares substrings — require no plaintext PEM and no full token in logs
      if find "$APNS_ROOT" -type f -name '*.log' | grep -q .; then
        ! grep -RFq -- "$token" "$APNS_ROOT"/*.log 2>/dev/null || return 1
      fi
    fi
  fi
  return 0
}

test_revoked_device_sends_nothing() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-rev cred=cred-rev token=ff11bb22cc33dd44ee55ff6677889900ff11bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 90 || return 1
  expect_registry device-revoke --device-id "$device" --request-id "req-rev-$$" || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  # No APNs post
  [[ ! -s $CURL_URLS ]] || return 1
  return 0
}

test_410_unregistered_auto_revokes_retains_events_g4() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-g4 cred=cred-g4 token=0011bb22cc33dd44ee55ff66778899000011bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 100 || return 1

  APNS_STUB_STATUS=410 APNS_STUB_REASON=Unregistered run_sender once || true

  # Device is revoked
  local meta=$WF_ROOT/outbox/$device/meta.json
  [[ -f $meta ]] || return 1
  jq -e '.revoked == true' "$meta" >/dev/null || return 1

  # Auto-revoke is journaled
  local journal
  journal=$(find "$APNS_ROOT" -type f \( -name '*journal*' -o -name '*.ndjson' \) 2>/dev/null | head -n 1)
  [[ -n $journal && -f $journal ]] || return 1
  assert_contains "$journal" 'auto-revoke' || assert_contains "$journal" 'Unregistered' || \
    assert_contains "$journal" '410' || return 1

  # Outbox event retained (feed + failure marker; not erased)
  local feed_hits
  feed_hits=$(find "$WF_ROOT/notifications" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  [[ ${feed_hits:-0} -ge 1 ]] || return 1
  # Second drain sends nothing (revoked)
  : >"$CURL_URLS"
  APNS_STUB_STATUS=200 run_sender once || return 1
  [[ ! -s $CURL_URLS ]] || return 1
  return 0
}

test_push_is_notification_only_no_authority() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-auth cred=cred-auth token=2211bb22cc33dd44ee55ff66778899002211bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration awaiting-approval "$WORKFLOW_ID" 110 || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  local body=$CURL_BODIES/body-1.json
  # Structural: cannot carry workflow authority triggers
  jq -e '
    (.approve // .action // .command // .workflowAuthority // .authority // null) == null
    and ((.aps.category // "") | test("APPROVE|AUTHORITY|EXECUTE") | not)
  ' "$body" >/dev/null || return 1
  # Sender must not call registry ops that exercise authority (send/deliver/phase-set)
  assert_lacks "$STDERR" 'phase-set' || return 1
  return 0
}

test_failures_logged_bounded() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-log cred=cred-log token=3311bb22cc33dd44ee55ff66778899003311bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 120 || return 1
  APNS_STUB_STATUS=500 run_sender once || true
  # Bounded log file exists and is not huge
  local log
  log=$(find "$APNS_ROOT" -type f -name '*.log' 2>/dev/null | head -n 1)
  [[ -n $log && -f $log ]] || return 1
  local sz
  sz=$(wc -c <"$log" | tr -d ' ')
  [[ $sz -lt 65536 ]] || return 1
  assert_lacks "$log" 'BEGIN PRIVATE KEY' || return 1
  return 0
}

# ── FIX-UP red cases (Codex findings) ──────────────────────────────────────

# Finding 1: revoke failure must not be journaled as success; endpoint stays ACTIVE.
test_410_revoke_failure_not_false_success() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-revfail cred=cred-revfail token=4411bb22cc33dd44ee55ff66778899004411bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 130 || return 1

  # Proxy registry: fail only device-revoke; forward everything else.
  local real_reg=$REGISTRY proxy=$FAKE_BIN/workflow-registry-proxy
  cat >"$proxy" <<PROXY
#!/usr/bin/env bash
set -euo pipefail
if [[ \${1:-} == device-revoke ]]; then
  printf '%s\n' '{"ok":false,"error":"forced-revoke-failure"}' >&2
  exit 1
fi
exec "$real_reg" "\$@"
PROXY
  chmod +x "$proxy"

  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    WORKFLOW_REGISTRY="$proxy" \
    WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    APNS_KEY_ID="${APNS_KEY_ID:-TESTKEY1}" \
    APNS_TEAM_ID="${APNS_TEAM_ID:-TEAMID12}" \
    APNS_TOPIC="${APNS_TOPIC:-com.orchestration.minirelay}" \
    APNS_STUB_STATUS=410 \
    APNS_STUB_REASON=Unregistered \
    CURL_LOG="$CURL_LOG" \
    CURL_URLS="$CURL_URLS" \
    CURL_HEADERS="$CURL_HEADERS" \
    CURL_BODIES="$CURL_BODIES" \
    "$SENDER" once >"$STDOUT" 2>"$STDERR"
  set -e

  local meta=$WF_ROOT/outbox/$device/meta.json
  # Device must remain ACTIVE when revoke fails
  jq -e '.revoked == false or .revoked == null' "$meta" >/dev/null || return 1

  local journal
  journal=$(find "$APNS_ROOT" -type f \( -name '*journal*' -o -name '*.ndjson' \) 2>/dev/null | head -n 1)
  [[ -n $journal && -f $journal ]] || return 1
  # Must journal failure honestly — never a bare success auto-revoke.
  assert_contains "$journal" 'auto-revoke-failed' || return 1
  if grep -Fq '"event":"auto-revoke"' "$journal" 2>/dev/null; then
    return 1
  fi
  return 0
}

# Finding 2: stable requestId (no PID); ack failure fail-closed (event stays unacked).
test_stable_ack_request_id_and_ack_fail_closed() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-ackid cred=cred-ackid token=5511bb22cc33dd44ee55ff66778899005511bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 140 || return 1

  APNS_STUB_STATUS=200 run_sender once || return 1
  [[ $STATUS -eq 0 ]] || return 1

  local req_dir=$WF_ROOT/outbox/$device/requests
  [[ -d $req_dir ]] || return 1
  local req_file req_id
  req_file=$(find "$req_dir" -type f -name '*.json' | head -n 1)
  [[ -n $req_file && -f $req_file ]] || return 1
  req_id=$(jq -r '.requestId // empty' "$req_file")
  [[ -n $req_id ]] || return 1
  # Must not embed a PID suffix (old: ...-$$)
  [[ $req_id != *"-$$" ]] || return 1
  [[ $req_id =~ ^req-apns-ack- ]] || return 1

  # Deterministic: same identity → same requestId (recompute expected digest)
  local expected dig
  dig=$(printf '%s|%s|%s|%s' "$device" "needs-input" "$WORKFLOW_ID" "140" \
    | openssl dgst -sha256 2>/dev/null | awk '{print $NF}')
  expected="req-apns-ack-${dig:0:32}"
  [[ $req_id == "$expected" ]] || return 1

  # Ack-failure fail-closed: delivery "succeeds" but ack is refused → event stays unacked.
  local real_reg=$REGISTRY proxy=$FAKE_BIN/workflow-registry-ackfail
  cat >"$proxy" <<PROXY
#!/usr/bin/env bash
set -euo pipefail
if [[ \${1:-} == outbox-ack ]]; then
  printf '%s\n' '{"ok":false,"error":"forced-ack-failure"}' >&2
  exit 1
fi
exec "$real_reg" "\$@"
PROXY
  chmod +x "$proxy"

  expect_registry feed-append orchestration completed "$WORKFLOW_ID" 141 || return 1
  : >"$CURL_URLS"
  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    WORKFLOW_REGISTRY="$proxy" \
    WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    APNS_KEY_ID="${APNS_KEY_ID:-TESTKEY1}" \
    APNS_TEAM_ID="${APNS_TEAM_ID:-TEAMID12}" \
    APNS_TOPIC="${APNS_TOPIC:-com.orchestration.minirelay}" \
    APNS_STUB_STATUS=200 \
    CURL_LOG="$CURL_LOG" \
    CURL_URLS="$CURL_URLS" \
    CURL_HEADERS="$CURL_HEADERS" \
    CURL_BODIES="$CURL_BODIES" \
    "$SENDER" once >"$STDOUT" 2>"$STDERR"
  set -e

  # Event 141 must still be fetchable (not acked)
  expect_registry outbox-fetch --device-id "$device" --credential "$cred" --cursor 0 || return 1
  jq -e '[(.records // [])[] | select((.seq // 0 | tonumber) == 141)] | length == 1' "$STDOUT" >/dev/null \
    || return 1
  return 0
}

# Finding 3: JWT binds material (kid/team/key); changing them forces a remint.
# Choice (b): no durable jwt.cache — each process mints; material change still reflected.
test_jwt_cache_invalidates_on_material_change() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-jwtmat cred=cred-jwtmat token=6611bb22cc33dd44ee55ff66778899006611bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration completed "$WORKFLOW_ID" 150 || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  local auth1
  auth1=$(grep -i '^authorization:' "$CURL_HEADERS" | head -n 1 | sed 's/.*[Bb]earer //')
  [[ -n $auth1 ]] || return 1
  # In-memory JWT only — no plaintext disk cache.
  [[ ! -f $APNS_ROOT/jwt.cache ]] || return 1
  # Source still binds cache validity to material digest (for in-process reuse).
  grep -Eq 'jwt_material_digest|APNS_JWT_MATERIAL' "$SENDER" || return 1

  # Change kid+team → must mint with new claims
  jq -cn --arg kid 'NEWKEY99' --arg team 'NEWTEAM99' '{keyId:$kid,teamId:$team}' >"$APNS_ROOT/key-meta.json"
  chmod 600 "$APNS_ROOT/key-meta.json"
  expect_registry feed-append orchestration released "$WORKFLOW_ID" 151 || return 1
  : >"$CURL_HEADERS"
  APNS_KEY_ID=NEWKEY99 APNS_TEAM_ID=NEWTEAM99 APNS_STUB_STATUS=200 run_sender once || return 1
  local auth2
  auth2=$(grep -i '^authorization:' "$CURL_HEADERS" | head -n 1 | sed 's/.*[Bb]earer //')
  [[ -n $auth2 && $auth1 != "$auth2" ]] || return 1

  # Decode and confirm new kid/team
  local hdr_b64 rest claims_b64
  hdr_b64=${auth2%%.*}
  rest=${auth2#*.}
  claims_b64=${rest%%.*}
  decode_b64url() {
    local s=$1 pad
    s=${s//-/+}
    s=${s//_/\/}
    pad=$(( (4 - ${#s} % 4) % 4 ))
    printf '%s%s' "$s" "$(printf '%*s' "$pad" '' | tr ' ' '=')" | openssl base64 -d -A 2>/dev/null
  }
  printf '%s' "$(decode_b64url "$hdr_b64")" | jq -e '.kid == "NEWKEY99"' >/dev/null || return 1
  printf '%s' "$(decode_b64url "$claims_b64")" | jq -e '.iss == "NEWTEAM99"' >/dev/null || return 1
  return 0
}

# Finding 5: LaunchAgent logs must be bounded/rotated (not unbounded persistent).
test_plist_bounds_or_rotates_launchd_logs() {
  [[ -f $PLIST ]] || return 1
  # Paths declared for launchd stdout/stderr
  assert_contains "$PLIST" 'StandardOutPath' || return 1
  assert_contains "$PLIST" 'StandardErrorPath' || return 1
  # Either /dev/null, or script-owned logs that apns-sender bounds
  if grep -Fq '/dev/null' "$PLIST"; then
    return 0
  fi
  # Script must rotate/bound the launchd log basenames referenced by the plist
  assert_contains "$SENDER" 'launchd' || assert_contains "$SENDER" 'LOG_MAX_BYTES' || return 1
  grep -Eq 'launchd\.(out|err)\.log|bound_launchd|rotate.*log' "$SENDER" || return 1
  # Artifact must be tracked (finding 4)
  local repo_root
  repo_root=$(cd "$SCRIPT_DIR/../../.." && pwd -P)
  if command -v git >/dev/null 2>&1 && [[ -d $repo_root/.git || -f $repo_root/.git ]]; then
    git -C "$repo_root" ls-files --error-unmatch \
      orchestration/templates/mini-relay/com.orchestration.apns-sender.plist >/dev/null 2>&1 \
      || return 1
  fi
  return 0
}

# Shared harness: launch sender as process-group leader, wait for a phase flag,
# group-TERM, assert signal-death + no secret material under TMPDIR.
# Mirrors R2 signing harness — bare `kill $pid` is insufficient (group no-op).
_assert_no_secrets_in_tmpdir() {
  local tmp_home=$1 token=${2:-}
  if grep -RFq -- 'BEGIN PRIVATE KEY' "$tmp_home" 2>/dev/null; then
    return 1
  fi
  if grep -RFq -- 'BEGIN EC PRIVATE' "$tmp_home" 2>/dev/null; then
    return 1
  fi
  if grep -RFq -- 'BEGIN PRIVATE' "$tmp_home" 2>/dev/null; then
    return 1
  fi
  if [[ -n $token ]] && grep -RFq -- "$token" "$tmp_home" 2>/dev/null; then
    return 1
  fi
  # Bearer JWT / authorization lines must never land on disk in TMPDIR
  if grep -RFi -- 'authorization: bearer' "$tmp_home" 2>/dev/null; then
    return 1
  fi
  if grep -RFi -- 'authorization:bearer' "$tmp_home" 2>/dev/null; then
    return 1
  fi
  # Signature-material residue (DER / raw R||S temps) must not remain.
  if find "$tmp_home" -type f \( -name 'apns.sig.*' -o -name 'apns.raw.*' -o -name 'apns.sig*' -o -name 'apns.raw*' \) 2>/dev/null | grep -q .; then
    return 1
  fi
  return 0
}

# Launch once under set -m; writes pid to pid_file; wait status to st_file.
_launch_sender_pgroup() {
  local tmp_home=$1 pid_file=$2 st_file=$3
  set +e
  bash -c '
    set -m
    env -i \
      HOME="'"$HOME_DIR"'" \
      XDG_STATE_HOME="'"$STATE_ROOT"'" \
      TMPDIR="'"$tmp_home"'" \
      PATH="'"$FAKE_BIN:$BASE_PATH"'" \
      HOSTNAME="'"$HOSTNAME_FIXTURE"'" \
      WORKFLOW_REGISTRY="'"${WORKFLOW_REGISTRY_OVERRIDE:-$REGISTRY}"'" \
      WORKFLOW_REGISTRY_TEST=1 \
      REMOTE_AGENT_ROOT_ORCHESTRATION="'"$CHECKOUT"'" \
      REMOTE_AGENT_ROOT_MIOSPOT="'"$CHECKOUT"'" \
      APNS_KEY_ID="'"${APNS_KEY_ID:-TESTKEY1}"'" \
      APNS_TEAM_ID="'"${APNS_TEAM_ID:-TEAMID12}"'" \
      APNS_TOPIC="'"${APNS_TOPIC:-com.orchestration.minirelay}"'" \
      APNS_STUB_STATUS="'"${APNS_STUB_STATUS:-}"'" \
      APNS_STUB_REASON="'"${APNS_STUB_REASON:-}"'" \
      CURL_LOG="'"$CURL_LOG"'" \
      CURL_URLS="'"$CURL_URLS"'" \
      CURL_HEADERS="'"$CURL_HEADERS"'" \
      CURL_BODIES="'"$CURL_BODIES"'" \
      "'"$SENDER"'" once >"'"$STDOUT"'" 2>"'"$STDERR"'" &
    pid=$!
    printf "%s\n" "$pid" >"'"$pid_file"'"
    wait "$pid"
    printf "%s\n" "$?" >"'"$st_file"'"
  ' &
  HARNESS_PID=$!
  set -e
}

_group_term_and_assert_signal_death() {
  local pid_file=$1 st_file=$2 harness=$3
  local waited=0 pid pgid st
  while (( waited < 100 )); do
    [[ -s $pid_file ]] && break
    sleep 0.1
    waited=$((waited + 1))
  done
  [[ -s $pid_file ]] || return 1
  pid=$(tr -d ' \n' <"$pid_file")
  [[ -n $pid && $pid =~ ^[0-9]+$ ]] || return 1
  pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
  [[ -n $pgid && $pgid == "$pid" ]] || return 1
  sleep 0.1
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM -"$pid" 2>/dev/null || true
  set +e
  wait "$harness" 2>/dev/null
  set -e
  sleep 0.25
  st=0
  if [[ -s $st_file ]]; then
    st=$(tr -d ' \n' <"$st_file")
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL -- "-$pid" 2>/dev/null || true
    return 1
  fi
  if [[ -z $st || $st == 0 ]]; then
    return 1
  fi
  return 0
}

# Finding 6 / FIX-UP R3: MID-POST group SIGTERM must leave no device-token / JWT
# on disk. Same harness as R2 signing (process group + signal-death proof).
test_interrupted_run_leaves_no_plaintext_secrets() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-int cred=cred-int token=7711bb22cc33dd44ee55ff66778899007711bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 160 || return 1

  local tmp_home=$CASE/tmp-int
  mkdir -p "$tmp_home"
  chmod 700 "$tmp_home"
  local post_flag=$CASE/post-entered
  local pid_file=$CASE/sender.pid
  local st_file=$CASE/sender.st
  rm -f "$post_flag" "$pid_file" "$st_file"

  # Hang at curl POST so JWT + device-token URL are already in flight.
  cat >"$FAKE_BIN/curl" <<CURL_HANG
#!/usr/bin/env bash
set -euo pipefail
: >"$post_flag"
printf 'curl-hang\n' >>"\${CURL_LOG:-/dev/null}" 2>/dev/null || true
# Hold long enough for the group TERM to land mid-POST.
sleep 20
exit 0
CURL_HANG
  chmod +x "$FAKE_BIN/curl"

  _launch_sender_pgroup "$tmp_home" "$pid_file" "$st_file"
  local harness=$HARNESS_PID

  local waited=0
  while (( waited < 100 )); do
    [[ -f $post_flag && -s $pid_file ]] && break
    sleep 0.1
    waited=$((waited + 1))
  done
  [[ -f $post_flag ]] || return 1

  _group_term_and_assert_signal_death "$pid_file" "$st_file" "$harness" || return 1
  _assert_no_secrets_in_tmpdir "$tmp_home" "$token" || return 1
  return 0
}

# General red: group SIGTERM during every phase leaves no secret material in TMPDIR.
test_group_sigterm_no_secrets_decrypt_phase() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-dec cred=cred-dec token=aa22bb22cc33dd44ee55ff6677889900aa22bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 200 || return 1

  local tmp_home=$CASE/tmp-dec
  mkdir -p "$tmp_home"
  chmod 700 "$tmp_home"
  local dec_flag=$CASE/decrypt-entered
  local pid_file=$CASE/sender.pid
  local st_file=$CASE/sender.st
  rm -f "$dec_flag" "$pid_file" "$st_file"

  # openssl wrapper: hang on decrypt (enc -d) — first secret-touching phase.
  cat >"$FAKE_BIN/openssl" <<OPENSSL_WRAP
#!/usr/bin/env bash
set -euo pipefail
real_openssl="$REAL_OPENSSL"
is_dec=0
for a in "\$@"; do
  if [[ \$a == -d ]]; then is_dec=1; fi
done
if [[ \$is_dec -eq 1 ]]; then
  : >"$dec_flag"
  sleep 20
  exit 1
fi
exec "\$real_openssl" "\$@"
OPENSSL_WRAP
  chmod +x "$FAKE_BIN/openssl"

  # Force JWT remint (no in-memory cache across processes) so decrypt path is exercised.
  # Choice (b): durable jwt.cache is not used; ensure none is planted.
  rm -f "$APNS_ROOT/jwt.cache" 2>/dev/null || true

  _launch_sender_pgroup "$tmp_home" "$pid_file" "$st_file"
  local harness=$HARNESS_PID
  local waited=0
  while (( waited < 100 )); do
    [[ -f $dec_flag && -s $pid_file ]] && break
    sleep 0.1
    waited=$((waited + 1))
  done
  [[ -f $dec_flag ]] || return 1
  _group_term_and_assert_signal_death "$pid_file" "$st_file" "$harness" || return 1
  _assert_no_secrets_in_tmpdir "$tmp_home" "$token" || return 1
  return 0
}

test_group_sigterm_no_secrets_sign_phase() {
  # Covered structurally by R2 signing test; re-assert token/JWT absence too.
  test_interrupt_during_signing_leaves_no_plaintext_key || return 1
  return 0
}

test_group_sigterm_no_secrets_post_phase() {
  # Mid-POST is the primary fix target for the curl-config stranding bug.
  test_interrupted_run_leaves_no_plaintext_secrets || return 1
  return 0
}

test_group_sigterm_no_secrets_ack_phase() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-ackint cred=cred-ackint token=bb22bb22cc33dd44ee55ff6677889900bb22bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 210 || return 1

  local tmp_home=$CASE/tmp-ack
  mkdir -p "$tmp_home"
  chmod 700 "$tmp_home"
  local ack_flag=$CASE/ack-entered
  local pid_file=$CASE/sender.pid
  local st_file=$CASE/sender.st
  rm -f "$ack_flag" "$pid_file" "$st_file"

  # Successful POST, hang on outbox-ack (post-POST phase).
  local real_reg=$REGISTRY proxy=$FAKE_BIN/workflow-registry-ackhang
  cat >"$proxy" <<PROXY
#!/usr/bin/env bash
set -euo pipefail
if [[ \${1:-} == outbox-ack ]]; then
  : >"$ack_flag"
  sleep 20
  exit 1
fi
exec "$real_reg" "\$@"
PROXY
  chmod +x "$proxy"

  WORKFLOW_REGISTRY_OVERRIDE=$proxy
  export WORKFLOW_REGISTRY_OVERRIDE
  APNS_STUB_STATUS=200
  export APNS_STUB_STATUS

  _launch_sender_pgroup "$tmp_home" "$pid_file" "$st_file"
  local harness=$HARNESS_PID
  unset WORKFLOW_REGISTRY_OVERRIDE
  unset APNS_STUB_STATUS

  local waited=0
  while (( waited < 150 )); do
    [[ -f $ack_flag && -s $pid_file ]] && break
    sleep 0.1
    waited=$((waited + 1))
  done
  [[ -f $ack_flag ]] || return 1
  _group_term_and_assert_signal_death "$pid_file" "$st_file" "$harness" || return 1
  _assert_no_secrets_in_tmpdir "$tmp_home" "$token" || return 1
  return 0
}

# Delivered markers whose seq left feed retention must not accumulate forever.
test_delivered_markers_bounded_trim() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-trim cred=cred-trim token=cc22bb22cc33dd44ee55ff6677889900cc22bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1

  local device_dir=$WF_ROOT/outbox/$device
  local del_dir=$device_dir/delivered
  mkdir -p -m 700 "$del_dir"
  # Plant orphan markers for seqs that will never be in the feed.
  local i
  for i in 1 2 3 4 5 9001 9002 9003; do
    printf '%s\n' "{\"seq\":$i,\"class\":\"needs-input\",\"entityId\":\"orphan\",\"status\":200}" \
      >"$del_dir/$i.json"
    chmod 600 "$del_dir/$i.json"
  done
  local before
  before=$(find "$del_dir" -type f -name '*.json' | wc -l | tr -d ' ')
  [[ $before -eq 8 ]] || return 1

  # Drain with no matching feed events — reconcile must drop orphans.
  run_sender once || return 1
  [[ $STATUS -eq 0 ]] || return 1

  local after
  after=$(find "$del_dir" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  # Orphans whose seq is not in feed retention must be gone.
  [[ $after -eq 0 ]] || return 1

  # Hard cap: plant more than the bound and ensure trim keeps ≤ bound.
  # Notifications exist so seqs are "retained", but all are pre-acked so drain
  # does not POST hundreds of events — only reconcile/trim runs.
  local cap=256
  local notif=$WF_ROOT/notifications
  mkdir -p "$notif"
  local acked_json='['
  for i in $(seq 1 $((cap + 40))); do
    printf '%s\n' "{\"seq\":$i,\"class\":\"needs-input\",\"entityId\":\"x\",\"status\":200}" \
      >"$del_dir/$i.json"
    chmod 600 "$del_dir/$i.json"
    printf '%s\n' "{\"class\":\"needs-input\",\"entityId\":\"x\",\"seq\":$i}" \
      >"$notif/$(printf '%010d' "$i").json"
    if [[ $i -eq 1 ]]; then
      acked_json+="$i"
    else
      acked_json+=",$i"
    fi
  done
  acked_json+=']'
  printf '%s\n' "$acked_json" >"$device_dir/acked.json"
  chmod 600 "$device_dir/acked.json"
  run_sender once || return 1
  after=$(find "$del_dir" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  [[ $after -le $cap ]] || return 1
  return 0
}

# ── FIX-UP ROUND 2 red cases ───────────────────────────────────────────────

# R2-F1: 200 + injected ack failure → next drain must NOT re-POST (exactly one APNs POST).
test_ack_failure_does_not_repost_delivered_event() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-dedupe cred=cred-dedupe token=8811bb22cc33dd44ee55ff66778899008811bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 170 || return 1

  # Proxy: force every outbox-ack to fail.
  local real_reg=$REGISTRY proxy=$FAKE_BIN/workflow-registry-ackfail-r2
  cat >"$proxy" <<PROXY
#!/usr/bin/env bash
set -euo pipefail
if [[ \${1:-} == outbox-ack ]]; then
  printf '%s\n' '{"ok":false,"error":"forced-ack-failure-r2"}' >&2
  exit 1
fi
exec "$real_reg" "\$@"
PROXY
  chmod +x "$proxy"

  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    WORKFLOW_REGISTRY="$proxy" \
    WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    APNS_KEY_ID="${APNS_KEY_ID:-TESTKEY1}" \
    APNS_TEAM_ID="${APNS_TEAM_ID:-TEAMID12}" \
    APNS_TOPIC="${APNS_TOPIC:-com.orchestration.minirelay}" \
    APNS_STUB_STATUS=200 \
    CURL_LOG="$CURL_LOG" \
    CURL_URLS="$CURL_URLS" \
    CURL_HEADERS="$CURL_HEADERS" \
    CURL_BODIES="$CURL_BODIES" \
    "$SENDER" once >"$STDOUT" 2>"$STDERR"
  set -e

  local posts1
  posts1=$(wc -l <"$CURL_URLS" | tr -d ' ')
  [[ $posts1 -eq 1 ]] || return 1

  # Event still fetchable (ack failed)
  expect_registry outbox-fetch --device-id "$device" --credential "$cred" --cursor 0 || return 1
  jq -e '[(.records // [])[] | select((.seq // 0 | tonumber) == 170)] | length == 1' "$STDOUT" >/dev/null \
    || return 1

  # Durable DELIVERED marker must exist so retry skips APNs
  local marker
  marker=$(find "$WF_ROOT/outbox/$device" "$APNS_ROOT" -type f \( -path '*/delivered/*' -o -name '*delivered*' \) 2>/dev/null | head -n 1)
  [[ -n $marker && -f $marker ]] || return 1

  # Second drain: must NOT re-post (ack retry only)
  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    WORKFLOW_REGISTRY="$proxy" \
    WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    APNS_KEY_ID="${APNS_KEY_ID:-TESTKEY1}" \
    APNS_TEAM_ID="${APNS_TEAM_ID:-TEAMID12}" \
    APNS_TOPIC="${APNS_TOPIC:-com.orchestration.minirelay}" \
    APNS_STUB_STATUS=200 \
    CURL_LOG="$CURL_LOG" \
    CURL_URLS="$CURL_URLS" \
    CURL_HEADERS="$CURL_HEADERS" \
    CURL_BODIES="$CURL_BODIES" \
    "$SENDER" once >"$STDOUT" 2>"$STDERR"
  set -e

  local posts2
  posts2=$(wc -l <"$CURL_URLS" | tr -d ' ')
  [[ $posts2 -eq 1 ]] || return 1
  return 0
}

# R2-F2 / FIX-UP R3: interrupt DURING openssl signing → no plaintext key material.
# ROOT CAUSE of illusory green: `kill -TERM -- "-$pid"` is a no-op when the
# background job is NOT a process-group leader; only the parent died and the
# subshell openssl-failure path wiped the temp. This test MUST:
#   (1) run the sender as its own process-group leader (set -m),
#   (2) deliver TERM to the whole group,
#   (3) prove the process died from the signal,
#   (4) assert NO plaintext key material remains under TMPDIR.
test_interrupt_during_signing_leaves_no_plaintext_key() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-signint cred=cred-signint token=9911bb22cc33dd44ee55ff66778899009911bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 180 || return 1

  local tmp_home=$CASE/tmp-sign
  mkdir -p "$tmp_home"
  chmod 700 "$tmp_home"
  local sign_flag=$CASE/signing-entered
  local pid_file=$CASE/sender.pid
  local st_file=$CASE/sender.st
  rm -f "$sign_flag" "$pid_file" "$st_file"

  # openssl wrapper: hang on dgst -sign (plaintext key must NOT be on disk at all).
  cat >"$FAKE_BIN/openssl" <<OPENSSL_WRAP
#!/usr/bin/env bash
set -euo pipefail
real_openssl="$REAL_OPENSSL"
is_sign=0
prev=
for a in "\$@"; do
  if [[ \$prev == -sign ]]; then
    is_sign=1
  fi
  prev=\$a
done
if [[ \$is_sign -eq 1 ]]; then
  : >"$sign_flag"
  # Bounded hang — test delivers group TERM; do not rely on failure-path wipe.
  sleep 20
  exit 1
fi
exec "\$real_openssl" "\$@"
OPENSSL_WRAP
  chmod +x "$FAKE_BIN/openssl"

  # Launch sender as process-group leader via bash job control (set -m).
  # setsid is not portable on macOS; set -m makes bg job pgid == pid.
  set +e
  bash -c '
    set -m
    env -i \
      HOME="'"$HOME_DIR"'" \
      XDG_STATE_HOME="'"$STATE_ROOT"'" \
      TMPDIR="'"$tmp_home"'" \
      PATH="'"$FAKE_BIN:$BASE_PATH"'" \
      HOSTNAME="'"$HOSTNAME_FIXTURE"'" \
      WORKFLOW_REGISTRY="'"$REGISTRY"'" \
      WORKFLOW_REGISTRY_TEST=1 \
      REMOTE_AGENT_ROOT_ORCHESTRATION="'"$CHECKOUT"'" \
      REMOTE_AGENT_ROOT_MIOSPOT="'"$CHECKOUT"'" \
      APNS_KEY_ID="'"${APNS_KEY_ID:-TESTKEY1}"'" \
      APNS_TEAM_ID="'"${APNS_TEAM_ID:-TEAMID12}"'" \
      APNS_TOPIC="'"${APNS_TOPIC:-com.orchestration.minirelay}"'" \
      CURL_LOG="'"$CURL_LOG"'" \
      CURL_URLS="'"$CURL_URLS"'" \
      CURL_HEADERS="'"$CURL_HEADERS"'" \
      CURL_BODIES="'"$CURL_BODIES"'" \
      "'"$SENDER"'" once >"'"$STDOUT"'" 2>"'"$STDERR"'" &
    pid=$!
    printf "%s\n" "$pid" >"'"$pid_file"'"
    wait "$pid"
    printf "%s\n" "$?" >"'"$st_file"'"
  ' &
  local harness=$!
  set -e

  local waited=0
  while (( waited < 100 )); do
    [[ -f $sign_flag && -s $pid_file ]] && break
    sleep 0.1
    waited=$((waited + 1))
  done
  [[ -f $sign_flag ]] || return 1
  [[ -s $pid_file ]] || return 1

  local pid pgid
  pid=$(tr -d ' \n' <"$pid_file")
  [[ -n $pid && $pid =~ ^[0-9]+$ ]] || return 1
  pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
  # Must be process-group leader — otherwise group kill is a no-op / wrong target.
  [[ -n $pgid && $pgid == "$pid" ]] || return 1

  # Deliver TERM to the entire process group (parent + command-sub + openssl hang).
  sleep 0.1
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM -"$pid" 2>/dev/null || true
  set +e
  wait "$harness" 2>/dev/null
  set -e
  sleep 0.25

  # (a) Process must have died from the signal (not a clean openssl-failure wipe path).
  local st=0
  if [[ -s $st_file ]]; then
    st=$(tr -d ' \n' <"$st_file")
  fi
  if kill -0 "$pid" 2>/dev/null; then
    # Still alive — force-kill leftovers and fail the invariant check setup.
    kill -KILL -- "-$pid" 2>/dev/null || true
    return 1
  fi
  # 143 = 128+SIGTERM from trap; >=128 means killed by signal; non-zero also accepted
  # when job-control wait status is coarse but process is gone after group TERM.
  if [[ -z $st || $st == 0 ]]; then
    return 1
  fi

  # (b) NO plaintext key material anywhere under TMPDIR after group interrupt.
  if grep -RFq -- 'BEGIN PRIVATE KEY' "$tmp_home" 2>/dev/null; then
    return 1
  fi
  if grep -RFq -- 'BEGIN EC PRIVATE' "$tmp_home" 2>/dev/null; then
    return 1
  fi
  if grep -RFq -- 'BEGIN PRIVATE' "$tmp_home" 2>/dev/null; then
    return 1
  fi
  if grep -RFq -- 'BEGIN PRIVATE KEY' "$APNS_ROOT" 2>/dev/null; then
    return 1
  fi
  return 0
}

# R2-F3: copy-truncate so LIVE open descriptor stops growing unbounded (not mv).
test_copy_truncate_live_fd_stops_growing() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  # Touch dirs/logs via idle drain
  run_sender once || true

  local log=$APNS_ROOT/logs/apns-sender.launchd.out.log
  [[ -f $log ]] || { mkdir -p "$(dirname "$log")"; : >"$log"; chmod 600 "$log"; }

  # Pre-fill past LOG_MAX_BYTES (32768)
  head -c 40000 /dev/zero | tr '\0' 'A' >"$log"
  chmod 600 "$log"
  local pre_sz
  pre_sz=$(wc -c <"$log" | tr -d ' ')
  [[ $pre_sz -gt 32768 ]] || return 1

  local ready=$CASE/fd-ready wrote=$CASE/fd-wrote
  rm -f "$ready" "$wrote"

  # Hold an open write FD (simulates launchd) across rotation, then append marker bytes.
  (
    exec 9>>"$log"
    : >"$ready"
    # Wait until parent signals that bound/rotation ran
    local w=0
    while [[ ! -f $CASE/rotated-done ]] && (( w < 100 )); do
      sleep 0.05
      w=$((w + 1))
    done
    # Write distinctive payload via the held FD
    head -c 20000 /dev/zero | tr '\0' 'B' >&9
    : >"$wrote"
    sleep 0.3
  ) &
  local holder=$!

  local w=0
  while [[ ! -f $ready ]] && (( w < 50 )); do sleep 0.05; w=$((w + 1)); done
  [[ -f $ready ]] || { kill "$holder" 2>/dev/null || true; return 1; }

  # Trigger bound_launchd_logs via another once cycle
  run_sender once || true
  : >"$CASE/rotated-done"

  w=0
  while [[ ! -f $wrote ]] && (( w < 100 )); do sleep 0.05; w=$((w + 1)); done
  wait "$holder" 2>/dev/null || true

  # With copy-truncate: FD writes land on the same inode → path contains 'B'.
  # With mv-rotation: FD writes go to the unlinked inode → path has no 'B'.
  grep -Fq 'B' "$log" || return 1

  local post_sz
  post_sz=$(wc -c <"$log" | tr -d ' ')
  # Must not keep the full 40KB of A's plus 20KB of B's unbounded (≈60KB).
  # After copy-truncate to half (~16KB) + 20KB B ≈ ≤45KB.
  [[ $post_sz -lt 50000 ]] || return 1
  # And the live path must have been reduced from the original 40KB bulk of A's.
  # (half retention means far fewer than 40000 leading A's remain)
  local a_count
  a_count=$(tr -cd 'A' <"$log" | wc -c | tr -d ' ')
  [[ $a_count -lt 25000 ]] || return 1
  return 0
}

# R2-F4: template keeps placeholders; install-launchagent substitutes+writes; not silently installed.
test_plist_placeholders_and_install_launchagent() {
  [[ -f $PLIST ]] || return 1
  # Template must document / retain placeholders (not pre-expanded).
  assert_contains "$PLIST" '@PLUGIN_ROOT@' || return 1
  assert_contains "$PLIST" '@STATE_HOME@' || return 1
  # Comment or usage must make clear it is a template until install-launchagent.
  grep -Eq 'install-launchagent|placeholder|substituted|NOT installed|template' "$PLIST" || \
    grep -Eq 'install-launchagent' "$SENDER" || return 1

  # install-launchagent substitutes into a destination under HOME (test-friendly).
  local dest_dir=$HOME_DIR/Library/LaunchAgents
  mkdir -p "$dest_dir"
  run_sender install-launchagent \
    --plugin-root "/opt/plugin-test-root" \
    --dest "$dest_dir/com.orchestration.apns-sender.plist" || return 1
  [[ $STATUS -eq 0 ]] || return 1

  local installed=$dest_dir/com.orchestration.apns-sender.plist
  [[ -f $installed ]] || return 1
  assert_contains "$installed" '/opt/plugin-test-root/scripts/apns-sender' || return 1
  assert_contains "$installed" "$STATE_ROOT/orchestration/apns/logs" || \
    assert_contains "$installed" 'orchestration/apns/logs' || return 1
  assert_lacks "$installed" '@PLUGIN_ROOT@' || return 1
  assert_lacks "$installed" '@STATE_HOME@' || return 1

  # Template itself must remain unsubstituted (tracked source of truth).
  assert_contains "$PLIST" '@PLUGIN_ROOT@' || return 1
  return 0
}

# ── FIX-UP ROUND 3 (adversarial scope-away) ────────────────────────────────

# R3-F1: NEVER plaintext bearer JWT on disk under state dir (choice b: no disk cache).
test_no_plaintext_bearer_jwt_under_state_dir() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-jwtdisk cred=cred-jwtdisk token=aa33bb22cc33dd44ee55ff6677889900aa33bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 300 || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  [[ $STATUS -eq 0 ]] || return 1

  # Must have actually minted a JWT (headers captured by stub).
  local auth
  auth=$(grep -i '^authorization:' "$CURL_HEADERS" | head -n 1 | sed 's/.*[Bb]earer //' | tr -d ' \r\n')
  [[ -n $auth && $auth == *.* ]] || return 1

  # Choice (b): no durable jwt.cache file at all.
  [[ ! -f $APNS_ROOT/jwt.cache ]] || return 1

  # No three-segment base64url JWT (eyJ…eyJ…sig) and no exact bearer string under APNS state.
  local f found=0
  while IFS= read -r f; do
    [[ -f $f ]] || continue
    if grep -Eq 'eyJ[A-Za-z0-9_-]+[.]eyJ[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+' "$f" 2>/dev/null; then
      found=1
      break
    fi
    if grep -Fq -- "$auth" "$f" 2>/dev/null; then
      found=1
      break
    fi
  done < <(find "$APNS_ROOT" -type f 2>/dev/null || true)
  [[ $found -eq 0 ]] || return 1
  return 0
}

# R3-F2: delivered/ trim must NEVER evict unacked markers (overflow → no re-POST).
test_unacked_delivered_overflow_never_evicts_or_reposts() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-ovf cred=cred-ovf token=bb33bb22cc33dd44ee55ff6677889900bb33bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1

  local device_dir=$WF_ROOT/outbox/$device
  local del_dir=$device_dir/delivered
  local notif=$WF_ROOT/notifications/orchestration
  mkdir -p -m 700 "$del_dir" "$notif"
  # acked empty → every planted marker is UNACKED
  printf '%s\n' '[]' >"$device_dir/acked.json"
  chmod 600 "$device_dir/acked.json"

  local cap=256
  local n=$((cap + 40))
  local i
  for i in $(seq 1 "$n"); do
    printf '%s\n' "{\"seq\":$i,\"class\":\"needs-input\",\"entityId\":\"wf-ovf\",\"status\":200}" \
      >"$del_dir/$i.json"
    chmod 600 "$del_dir/$i.json"
    printf '%s\n' "{\"class\":\"needs-input\",\"entityId\":\"wf-ovf\",\"seq\":$i}" \
      >"$notif/$(printf '%010d' "$i").json"
  done
  local before
  before=$(find "$del_dir" -type f -name '*.json' | wc -l | tr -d ' ')
  [[ $before -eq $n ]] || return 1

  # Proxy: outbox-ack always fails so markers stay unacked after drain.
  local real_reg=$REGISTRY proxy=$FAKE_BIN/workflow-registry-ackfail-ovf
  cat >"$proxy" <<PROXY
#!/usr/bin/env bash
set -euo pipefail
if [[ \${1:-} == outbox-ack ]]; then
  printf '%s\n' '{"ok":false,"error":"forced-ack-failure-ovf"}' >&2
  exit 1
fi
exec "$real_reg" "\$@"
PROXY
  chmod +x "$proxy"

  # Drain 1: reconcile + ack-retry only (markers present). Must NOT drop unacked, NOT POST.
  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    WORKFLOW_REGISTRY="$proxy" \
    WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    APNS_KEY_ID="${APNS_KEY_ID:-TESTKEY1}" \
    APNS_TEAM_ID="${APNS_TEAM_ID:-TEAMID12}" \
    APNS_TOPIC="${APNS_TOPIC:-com.orchestration.minirelay}" \
    APNS_STUB_STATUS=200 \
    CURL_LOG="$CURL_LOG" \
    CURL_URLS="$CURL_URLS" \
    CURL_HEADERS="$CURL_HEADERS" \
    CURL_BODIES="$CURL_BODIES" \
    "$SENDER" once >"$STDOUT" 2>"$STDERR"
  set -e

  local posts1 after1
  posts1=$(wc -l <"$CURL_URLS" | tr -d ' ')
  [[ $posts1 -eq 0 ]] || return 1
  after1=$(find "$del_dir" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  # Unacked markers must not be hard-cap evicted (all $n remain).
  [[ $after1 -eq $n ]] || return 1
  # Oldest unacked marker (seq 1) still present
  [[ -f $del_dir/1.json ]] || return 1

  # Drain 2: still no POST (markers retained → ack-retry path only).
  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="$FAKE_BIN:$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    WORKFLOW_REGISTRY="$proxy" \
    WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    APNS_KEY_ID="${APNS_KEY_ID:-TESTKEY1}" \
    APNS_TEAM_ID="${APNS_TEAM_ID:-TEAMID12}" \
    APNS_TOPIC="${APNS_TOPIC:-com.orchestration.minirelay}" \
    APNS_STUB_STATUS=200 \
    CURL_LOG="$CURL_LOG" \
    CURL_URLS="$CURL_URLS" \
    CURL_HEADERS="$CURL_HEADERS" \
    CURL_BODIES="$CURL_BODIES" \
    "$SENDER" once >"$STDOUT" 2>"$STDERR"
  set -e

  local posts2
  posts2=$(wc -l <"$CURL_URLS" | tr -d ' ')
  [[ $posts2 -eq 0 ]] || return 1
  [[ -f $del_dir/1.json ]] || return 1
  return 0
}

# R3-F3: ECDSA DER/raw signature material must not strand under TMPDIR (pipe-only).
# Phase greps also detect apns.sig./apns.raw. residue so a future regression cannot go green.
test_signing_leaves_no_signature_material_in_tmpdir() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-sigres cred=cred-sigres token=cc33bb22cc33dd44ee55ff6677889900cc33bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 310 || return 1

  local tmp_home=$CASE/tmp-sigres
  mkdir -p "$tmp_home"
  chmod 700 "$tmp_home"

  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    TMPDIR="$tmp_home" \
    PATH="$FAKE_BIN:$BASE_PATH" \
    HOSTNAME="$HOSTNAME_FIXTURE" \
    WORKFLOW_REGISTRY="$REGISTRY" \
    WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$CHECKOUT" \
    REMOTE_AGENT_ROOT_MIOSPOT="$CHECKOUT" \
    APNS_KEY_ID="${APNS_KEY_ID:-TESTKEY1}" \
    APNS_TEAM_ID="${APNS_TEAM_ID:-TEAMID12}" \
    APNS_TOPIC="${APNS_TOPIC:-com.orchestration.minirelay}" \
    APNS_STUB_STATUS=200 \
    CURL_LOG="$CURL_LOG" \
    CURL_URLS="$CURL_URLS" \
    CURL_HEADERS="$CURL_HEADERS" \
    CURL_BODIES="$CURL_BODIES" \
    "$SENDER" once >"$STDOUT" 2>"$STDERR"
  set -e
  [[ $STATUS -eq 0 ]] || return 1
  # Successful POST proves signing ran.
  local posts
  posts=$(wc -l <"$CURL_URLS" | tr -d ' ')
  [[ $posts -eq 1 ]] || return 1

  # No signature temp basenames left under TMPDIR.
  if find "$tmp_home" -type f \( -name 'apns.sig.*' -o -name 'apns.raw.*' -o -name 'apns.sig*' -o -name 'apns.raw*' \) 2>/dev/null | grep -q .; then
    return 1
  fi
  # No private key material either.
  if grep -RFq -- 'BEGIN PRIVATE KEY' "$tmp_home" 2>/dev/null; then
    return 1
  fi
  # Source must not mktemp apns.sig / apns.raw (pipe-only signing path).
  if grep -E 'mktemp.*apns\.(sig|raw)' "$SENDER" 2>/dev/null; then
    return 1
  fi
  return 0
}

# R3-F4: cryptographic verify of minted ES256 JWT against the public key.
test_jwt_cryptographically_verifies_es256() {
  [[ -n $REAL_JQ && -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local p8=$CASE/AuthKey_TESTKEY1.p8
  [[ -f $p8 ]] || return 1
  local device=dev-crypt cred=cred-crypt token=dd33bb22cc33dd44ee55ff6677889900dd33bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration completed "$WORKFLOW_ID" 320 || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  [[ $STATUS -eq 0 ]] || return 1

  local jwt hdr_b64 claims_b64 sig_b64 rest
  jwt=$(grep -i '^authorization:' "$CURL_HEADERS" | head -n 1 | sed 's/.*[Bb]earer //' | tr -d ' \r\n')
  [[ -n $jwt ]] || return 1
  hdr_b64=${jwt%%.*}
  rest=${jwt#*.}
  claims_b64=${rest%%.*}
  sig_b64=${rest#*.}
  [[ -n $hdr_b64 && -n $claims_b64 && -n $sig_b64 && $sig_b64 != *.* ]] || return 1

  decode_b64url_to_file() {
    local s=$1 dest=$2 pad
    s=${s//-/+}
    s=${s//_/\/}
    pad=$(( (4 - ${#s} % 4) % 4 ))
    printf '%s%s' "$s" "$(printf '%*s' "$pad" '' | tr ' ' '=')" | openssl base64 -d -A >"$dest" 2>/dev/null
  }

  # Raw R||S (64 bytes) → DER for openssl dgst -verify.
  local raw=$CASE/jwt.sig.raw der=$CASE/jwt.sig.der pub=$CASE/jwt.pub.pem msg=$CASE/jwt.msg
  decode_b64url_to_file "$sig_b64" "$raw" || return 1
  local raw_len
  raw_len=$(wc -c <"$raw" | tr -d ' ')
  [[ $raw_len -eq 64 ]] || return 1

  # Build DER SEQUENCE { INTEGER r, INTEGER s } with high-bit pad.
  local r_hex s_hex
  r_hex=$(od -An -tx1 -N 32 -v "$raw" | tr -d ' \n' | tr 'A-F' 'a-f')
  s_hex=$(od -An -tx1 -j 32 -N 32 -v "$raw" | tr -d ' \n' | tr 'A-F' 'a-f')
  # Strip leading zeros but keep at least one byte; add 00 if high bit set.
  while [[ ${#r_hex} -gt 2 && ${r_hex:0:2} == 00 && $((16#${r_hex:2:2})) -lt 128 ]]; do
    r_hex=${r_hex:2}
  done
  while [[ ${#s_hex} -gt 2 && ${s_hex:0:2} == 00 && $((16#${s_hex:2:2})) -lt 128 ]]; do
    s_hex=${s_hex:2}
  done
  if (( 16#${r_hex:0:2} >= 128 )); then r_hex=00$r_hex; fi
  if (( 16#${s_hex:0:2} >= 128 )); then s_hex=00$s_hex; fi
  local r_len=$(( ${#r_hex} / 2 )) s_len=$(( ${#s_hex} / 2 ))
  local seq_len=$(( 2 + r_len + 2 + s_len ))
  local der_hex
  der_hex=$(printf '30%02x02%02x%s02%02x%s' "$seq_len" "$r_len" "$r_hex" "$s_len" "$s_hex")
  if command -v xxd >/dev/null 2>&1; then
    printf '%s' "$der_hex" | xxd -r -p >"$der"
  else
    local pair hx=$der_hex
    : >"$der"
    while [[ -n $hx ]]; do
      pair=${hx:0:2}
      hx=${hx:2}
      printf "\\x$pair" >>"$der"
    done
  fi

  printf '%s.%s' "$hdr_b64" "$claims_b64" >"$msg"
  openssl pkey -in "$p8" -pubout -out "$pub" 2>/dev/null || return 1
  openssl dgst -sha256 -verify "$pub" -signature "$der" "$msg" >/dev/null 2>&1 || return 1
  return 0
}

# R3-F5: apns-collapse-id present (collapses at-least-once window duplicates); residual documented.
test_apns_collapse_id_and_residual_window_documented() {
  [[ -n $REAL_OPENSSL ]] || return 1
  mint_workflow || return 1
  install_apns_key || return 1
  local device=dev-collapse cred=cred-collapse token=ee33bb22cc33dd44ee55ff6677889900ee33bb22cc33dd44ee55ff6677889900
  register_device "$device" "$cred" sandbox "$token" || return 1
  expect_registry feed-append orchestration needs-input "$WORKFLOW_ID" 330 || return 1
  APNS_STUB_STATUS=200 run_sender once || return 1
  [[ $STATUS -eq 0 ]] || return 1

  # Header must carry apns-collapse-id (stable per event identity).
  grep -Eiq '^apns-collapse-id:' "$CURL_HEADERS" || \
    grep -Eiq 'apns-collapse-id:' "$CURL_HEADERS" || return 1
  local cid
  cid=$(grep -Ei 'apns-collapse-id:' "$CURL_HEADERS" | head -n 1 | sed 's/.*[Cc]ollapse-[Ii]d:[[:space:]]*//' | tr -d ' \r\n')
  [[ -n $cid && ${#cid} -le 64 ]] || return 1

  # Residual at-least-once window (POST-200 before mark_delivered) must be documented.
  grep -Eq 'at-least-once|residual.*(window|crash)|collapse-id.*residual|crash between POST' "$SENDER" || return 1
  return 0
}

# ── runner ─────────────────────────────────────────────────────────────────

run_test 'script + LaunchAgent plist supervise apns-sender' \
  test_script_and_plist_exist
run_test 'consumes durable outbox, acks, curl --http2 + JWT path' \
  test_consumes_outbox_acks_and_uses_http2_jwt
run_test 'delivery failure never erases outbox events' \
  test_delivery_failure_never_erases_events
run_test 'ES256 JWT carries kid+team; refresh within 20-60 min window' \
  test_jwt_es256_kid_team_and_refresh_window
run_test 'sandbox build type routes to api.sandbox.push.apple.com' \
  test_sandbox_host_for_dev_install
run_test 'production build type routes to api.push.apple.com' \
  test_production_host_for_testflight
run_test 'payload is class + opaque ref only with badge' \
  test_payload_class_opaque_ref_only_and_badge
run_test 'chat-reply-completed default-off (C3); class pref enables it' \
  test_chat_reply_completed_default_off_c3
run_test 'per-chat pref overrides class default for chat-reply-completed' \
  test_per_chat_pref_overrides_class_default
run_test '.p8 and device tokens are 0600 encrypted; never printed' \
  test_p8_and_token_are_0600_encrypted_never_printed
run_test 'revoked device sends nothing' \
  test_revoked_device_sends_nothing
run_test 'APNs 410/Unregistered auto-revokes; events retained (G4)' \
  test_410_unregistered_auto_revokes_retains_events_g4
run_test 'push is notification only — no workflow authority' \
  test_push_is_notification_only_no_authority
run_test 'failures logged bounded without secret material' \
  test_failures_logged_bounded
run_test '410 revoke failure is not journaled as success (endpoint stays active)' \
  test_410_revoke_failure_not_false_success
run_test 'stable outbox-ack requestId; ack failure fail-closed' \
  test_stable_ack_request_id_and_ack_fail_closed
run_test 'jwt.cache invalidates when key material/kid/team change' \
  test_jwt_cache_invalidates_on_material_change
run_test 'plist bounds/rotates LaunchAgent logs and is tracked' \
  test_plist_bounds_or_rotates_launchd_logs
run_test 'interrupted mid-POST group-TERM leaves no token/JWT on disk' \
  test_interrupted_run_leaves_no_plaintext_secrets
run_test 'group SIGTERM decrypt phase leaves no secrets in TMPDIR' \
  test_group_sigterm_no_secrets_decrypt_phase
run_test 'group SIGTERM sign phase leaves no secrets in TMPDIR' \
  test_group_sigterm_no_secrets_sign_phase
run_test 'group SIGTERM post phase leaves no secrets in TMPDIR' \
  test_group_sigterm_no_secrets_post_phase
run_test 'group SIGTERM ack phase leaves no secrets in TMPDIR' \
  test_group_sigterm_no_secrets_ack_phase
run_test 'delivered markers trimmed when seq leaves feed retention' \
  test_delivered_markers_bounded_trim
run_test 'R2: 200+ack-fail next drain does not re-POST (delivered marker)' \
  test_ack_failure_does_not_repost_delivered_event
run_test 'R2: interrupt during signing leaves no plaintext .p8' \
  test_interrupt_during_signing_leaves_no_plaintext_key
run_test 'R2: copy-truncate live FD stops growing (not mv)' \
  test_copy_truncate_live_fd_stops_growing
run_test 'R2: plist placeholders + install-launchagent substitution' \
  test_plist_placeholders_and_install_launchagent
run_test 'R3: no plaintext bearer JWT under state dir (no jwt.cache)' \
  test_no_plaintext_bearer_jwt_under_state_dir
run_test 'R3: unacked delivered overflow never evicts or re-POSTs' \
  test_unacked_delivered_overflow_never_evicts_or_reposts
run_test 'R3: signing leaves no DER/raw signature material in TMPDIR' \
  test_signing_leaves_no_signature_material_in_tmpdir
run_test 'R3: minted ES256 JWT cryptographically verifies against .p8 pubkey' \
  test_jwt_cryptographically_verifies_es256
run_test 'R3: apns-collapse-id set; residual at-least-once window documented' \
  test_apns_collapse_id_and_residual_window_documented

printf '\n%s\n' "apns-sender tests: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi
exit 0
