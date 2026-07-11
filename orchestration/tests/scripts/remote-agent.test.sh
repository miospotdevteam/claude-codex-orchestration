#!/usr/bin/env bash
set -euo pipefail

# Behavior contract for scripts/remote-agent.sh. This test intentionally carries
# a little more fixture machinery than the other shell suites: PATH, HOME, state,
# the SSH transport, agent-supervisor, tmux, Git, hashing, and file transfer are
# all private to each case. A missing helper is checked only after the fixture
# proves that its fake transport works.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REMOTE_AGENT="$SCRIPT_DIR/../../scripts/remote-agent.sh"
REAL_BASH=$(command -v bash)

PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
SUITE=$(cd "$SUITE" && pwd -P)
trap 'rm -rf "$SUITE"' EXIT

pass() { printf 'PASS %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

assert_contains() { grep -Fq -- "$2" "$1"; }
assert_lacks() { ! grep -Fq -- "$2" "$1"; }
assert_count() { [[ $(grep -Fc -- "$2" "$1" || true) -eq $3 ]]; }

write_mock() {
  local name=$1
  cat >"$FAKE_BIN/$name"
  chmod +x "$FAKE_BIN/$name"
}

seed_checkout() {
  local root=$1 marker=${2:-}
  mkdir -p "$root/.temp/plan-mode/active/selected"
  printf 'tracked\n' >"$root/README.md"
  printf 'untracked\n' >"$root/notes.txt"
  if [[ -n $marker ]]; then
    printf '%s\n' "$marker" >"$root/$marker-only.txt"
  fi
  printf '{}\n' >"$root/.temp/plan-mode/active/selected/plan.json"
  printf '{}\n' >"$root/.temp/plan-mode/active/selected/progress.json"
  printf '# plan\n' >"$root/.temp/plan-mode/active/selected/masterPlan.md"
}

setup_case() {
  local name=$1
  CASE="$SUITE/$name"
  TEST_HOME="$CASE/home"
  TEST_STATE="$CASE/state"
  LOCAL_ROOT="$CASE/local-project"
  DECOY_ROOT="$CASE/decoy orchestration checkout"
  REMOTE_ROOT="$CASE/remote-project"
  REMOTE_HOME="$CASE/remote-home"
  REMOTE_STATE="$CASE/remote-state"
  REMOTE_BIN="$CASE/remote-bin"
  FAKE_BIN="$CASE/bin"
  COMMAND_LOG="$CASE/commands.log"
  GIT_REF_LOG="$CASE/git-ref-operations.log"
  GIT_STATUS_FILE="$CASE/git-status.nul"
  SSH_STDIN="$CASE/ssh.stdin"
  STDOUT="$CASE/stdout"
  STDERR="$CASE/stderr"
  mkdir -p "$TEST_HOME" "$TEST_STATE" "$LOCAL_ROOT" "$DECOY_ROOT" "$REMOTE_ROOT" "$REMOTE_HOME" "$REMOTE_STATE" "$REMOTE_BIN" "$FAKE_BIN"
  : >"$COMMAND_LOG"
  : >"$GIT_REF_LOG"
  : >"$GIT_STATUS_FILE"
  : >"$SSH_STDIN"
  : >"$STDOUT"
  : >"$STDERR"

  write_mock ssh <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
: "${COMMAND_LOG:?}" "${SSH_STDIN:?}"
host=${1:-}
shift || true
remote_command=$*
parsed_argv="${REMOTE_STATE:-${TMPDIR:-/tmp}}/fake-ssh-argv.$$.nul"
/bin/sh -c "set -- $remote_command
printf '%s\\0' \"\$@\"" >"$parsed_argv"
remote_arguments=()
while IFS= read -r -d '' argument; do
  remote_arguments+=("$argument")
done <"$parsed_argv"
rm -f "$parsed_argv"
set -- "$host" "${remote_arguments[@]}"
printf 'ssh' >>"$COMMAND_LOG"
for argument in "$@"; do printf ' <%q>' "$argument" >>"$COMMAND_LOG"; done
printf '\n' >>"$COMMAND_LOG"
cat >>"$SSH_STDIN"

if [[ "${SUPERVISOR_STRICT:-0}" == 1 ]]; then
  if [[ " $* " == *' agent-supervisor launch '* ]]; then
    printf 'agent-supervisor: unsupported command launch\n' >&2
    exit 64
  fi
  if [[ " $* " == *' mini-agent '* ]]; then
    printf 'mini-agent: command not found\n' >&2
    exit 127
  fi
fi

if [[ " $* " == *' agent-supervisor capture '* ]]; then
  printf '%s\n' "${REMOTE_CAPTURE_OUTPUT:-bounded-capture}"
  exit 0
fi

if [[ " $* " == *' agent-supervisor wait '* ]]; then
  if [[ -n ${REMOTE_WAIT_OUTPUT:-} ]]; then
    printf '%s\n' "$REMOTE_WAIT_OUTPUT"
  else
    printf '%s\n' '{"epoch":"epoch-1","cursor":1,"session":"remote-agent--miospot--claude","wake":"event","scope":"main","kind":"completed"}'
  fi
  exit 0
fi

if [[ " $* " == *' agent-supervisor start '* && -n ${REMOTE_SUPERVISOR_START_OUTPUT:-} ]]; then
  printf '%s\n' "$REMOTE_SUPERVISOR_START_OUTPUT"
  exit 0
fi

if [[ " $* " == *' agent-supervisor start '* && ${REMOTE_SUPERVISOR_START_FAIL:-0} -ne 0 ]]; then
  printf 'agent-supervisor: injected start failure\n' >&2
  exit "$REMOTE_SUPERVISOR_START_FAIL"
fi

if [[ " $* " == *' agent-supervisor status '* ]]; then
  if [[ -n ${REMOTE_SUPERVISOR_STATUS_OUTPUT:-} ]]; then
    printf '%s\n' "$REMOTE_SUPERVISOR_STATUS_OUTPUT"
  elif [[ ${REMOTE_SCENARIO:-equal} == live-writer ]]; then
    printf '%s\n' '{"session":"running","name":"remote-agent--miospot--claude","epoch":"epoch-1","cursor":0,"bootstrapCursor":"epoch-1:0"}'
  else
    printf '%s\n' '{"session":"absent","name":"remote-agent--miospot--claude"}'
  fi
  exit 0
fi

if [[ ${2:-} == remote-agent-v1 && ${3:-} == stage ]]; then
  printf '{"stagePath":"%s/orchestration/remote-agent/projects/%s/stage"}\n' "$REMOTE_STATE" "$5"
  exit 0
fi

case "${REMOTE_SCENARIO:-equal}" in
  fixture-self-test) printf 'fixture-ok\n' ;;
  no-session) printf '{"relation":"equal","writer":"none","generation":7}\n' ;;
  live-writer) printf '{"relation":"equal","writer":"live","generation":7}\n' ;;
  provisional-writer) printf '{"relation":"equal","writer":"provisional","lease":"provisional","generation":7}\n' ;;
  equal-quiescent) printf '{"relation":"equal","writer":"quiescent","generation":7}\n' ;;
  local-only-quiescent) printf '{"relation":"local-only","writer":"quiescent","generation":7}\n' ;;
  unknown-writer) printf '{"relation":"equal","writer":"unexpected","generation":7}\n' ;;
  local-only) printf '{"relation":"local-only","generation":7}\n' ;;
  remote-only)
    printf '{"relation":"remote-only","generation":7,"remoteBranch":"%s","remoteHead":"%s"}\n' \
      "${REMOTE_GIT_BRANCH:-mini-work}" "${REMOTE_GIT_HEAD:-fedcba9876543210fedcba9876543210fedcba98}"
    ;;
  diverged) printf '{"relation":"diverged","paths":["left.txt","right.txt"]}\n' ;;
  post-mismatch) printf '{"relation":"mismatch","paths":["tampered.txt"],"generation":7}\n' ;;
  lock-held) printf '{"mutex":"held","owner":"other-client:4321"}\n' ;;
  cas-lost) printf '{"cas":"lost","expected":7,"actual":8}\n' ;;
  apply-fails-restored) printf '{"apply":"failed","restore":"verified","generation":7}\n' ;;
  apply-fails-recovery) printf '{"apply":"failed","restore":"failed","recoveryRequired":true,"generation":7}\n' ;;
  apply-command-fails-restored)
    if [[ " $* " == *' apply-exact '* ]]; then
      printf '{"apply":"failed","restore":"verified","generation":7}\n'
      exit 42
    fi
    printf '{"relation":"local-only","generation":7}\n'
    ;;
  plan-mutated) printf '{"planSnapshot":"changed","path":"progress.json"}\n' ;;
  *) printf '{"relation":"equal","writer":"none","generation":7}\n' ;;
esac
MOCK

  write_mock rsync <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'rsync' >>"$COMMAND_LOG"
for argument in "$@"; do printf ' <%q>' "$argument" >>"$COMMAND_LOG"; done
printf '\n' >>"$COMMAND_LOG"
[[ "${RSYNC_FAIL:-0}" == 0 ]]
MOCK

  for command in git tmux agent-supervisor mini-agent scp tar shasum sha256sum security; do
    cat >"$FAKE_BIN/$command" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
name=${0##*/}
printf '%s cwd=<%s>' "$name" "$PWD" >>"$COMMAND_LOG"
for argument in "$@"; do printf ' <%q>' "$argument" >>"$COMMAND_LOG"; done
printf '\n' >>"$COMMAND_LOG"
case "$name $*" in
  'git rev-parse --show-toplevel')
    [[ $PWD != "${MOCK_GIT_FAIL_ROOT:-}" ]] || exit 128
    printf '%s\n' "${MOCK_GIT_TOPLEVEL_OVERRIDE:-$PWD}"
    ;;
  'git rev-parse --abbrev-ref HEAD') printf '%s\n' "${MOCK_GIT_BRANCH:-main}" ;;
  'git rev-parse HEAD') printf '%s\n' "${MOCK_GIT_HEAD:-0123456789abcdef0123456789abcdef01234567}" ;;
  'git symbolic-ref --quiet --short HEAD') printf '%s\n' "${MOCK_GIT_BRANCH:-main}" ;;
  'git symbolic-ref --quiet HEAD') printf 'refs/heads/%s\n' "${MOCK_GIT_BRANCH:-main}" ;;
  'git status --porcelain=v1 -z') cat "$MOCK_GIT_STATUS_FILE" ;;
  'git merge-base --is-ancestor '*) [[ ${MOCK_GIT_ANCESTOR:-1} == 1 ]] || exit 1 ;;
  'git bundle create '*) : >"${3:?bundle destination}" ;;
  'git bundle list-heads '*) printf '%s refs/heads/%s\n' "$REMOTE_GIT_HEAD" "$REMOTE_GIT_BRANCH" ;;
  'git bundle verify '*) ;;
  'git ls-files -z')
    printf 'README.md\0src/app.ts\0'
    case $PWD in
      "${MOCK_MIOSPOT_ROOT:-/nonexistent}") printf 'miospot-only.txt\0' ;;
      "${MOCK_ORCHESTRATION_ROOT:-/nonexistent}") printf 'orchestration-only.txt\0' ;;
      "${MOCK_DECOY_ROOT:-/nonexistent}") printf 'decoy-only.txt\0' ;;
    esac
    [[ -z ${MOCK_SAFE_PATH:-} ]] || printf '%s\0' "$MOCK_SAFE_PATH"
    ;;
  'git ls-files --others --exclude-standard -z') printf 'notes.txt\0' ;;
  'git check-ignore '*) [[ "${MOCK_IGNORED:-}" == *"${*: -1}"* ]] ;;
  'shasum '*|'sha256sum '*)
    case $PWD in
      "${MOCK_MIOSPOT_ROOT:-/nonexistent}") digest=1111111111111111111111111111111111111111111111111111111111111111 ;;
      "${MOCK_ORCHESTRATION_ROOT:-/nonexistent}") digest=2222222222222222222222222222222222222222222222222222222222222222 ;;
      "${MOCK_DECOY_ROOT:-/nonexistent}") digest=3333333333333333333333333333333333333333333333333333333333333333 ;;
      *) digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
    esac
    printf '%s  -\n' "$digest"
    ;;
esac

case "$name ${1:-}" in
  'git update-ref'|'git reset'|'git fetch'|'git checkout'|'git switch')
    printf 'git' >>"$GIT_REF_LOG"
    for argument in "$@"; do printf ' <%q>' "$argument" >>"$GIT_REF_LOG"; done
    printf '\n' >>"$GIT_REF_LOG"
    ;;
  'git symbolic-ref')
    if [[ ${2:-} != --quiet ]]; then
      printf 'git' >>"$GIT_REF_LOG"
      for argument in "$@"; do printf ' <%q>' "$argument" >>"$GIT_REF_LOG"; done
      printf '\n' >>"$GIT_REF_LOG"
    fi
    ;;
esac
MOCK
    chmod +x "$FAKE_BIN/$command"
  done

  seed_checkout "$LOCAL_ROOT" miospot
  seed_checkout "$DECOY_ROOT" decoy
}

run_helper() {
  local scenario=$1
  local caller_root mapped_miospot_root mapped_orchestration_root
  shift
  caller_root=${CALLER_ROOT_OVERRIDE:-$LOCAL_ROOT}
  mapped_miospot_root=${LOCAL_MIOSPOT_ROOT_OVERRIDE-$LOCAL_ROOT}
  mapped_orchestration_root=${LOCAL_ORCHESTRATION_ROOT_OVERRIDE-$LOCAL_ROOT}
  set +e
  (cd "$caller_root" && env -i \
    HOME="$TEST_HOME" \
    XDG_STATE_HOME="$TEST_STATE" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    COMMAND_LOG="$COMMAND_LOG" \
    GIT_REF_LOG="$GIT_REF_LOG" \
    MOCK_GIT_STATUS_FILE="$GIT_STATUS_FILE" \
    SSH_STDIN="$SSH_STDIN" \
    LOCAL_ROOT="${GENERIC_LOCAL_ROOT_OVERRIDE:-}" \
    LOCAL_MIOSPOT_ROOT="$mapped_miospot_root" \
    LOCAL_ORCHESTRATION_ROOT="$mapped_orchestration_root" \
    MOCK_MIOSPOT_ROOT="$mapped_miospot_root" \
    MOCK_ORCHESTRATION_ROOT="$mapped_orchestration_root" \
    MOCK_DECOY_ROOT="$DECOY_ROOT" \
    MOCK_GIT_FAIL_ROOT="${MOCK_GIT_FAIL_ROOT:-}" \
    MOCK_GIT_TOPLEVEL_OVERRIDE="${MOCK_GIT_TOPLEVEL_OVERRIDE:-}" \
    MOCK_GIT_BRANCH="${MOCK_GIT_BRANCH:-main}" \
    MOCK_GIT_HEAD="${MOCK_GIT_HEAD:-0123456789abcdef0123456789abcdef01234567}" \
    MOCK_GIT_ANCESTOR="${MOCK_GIT_ANCESTOR:-1}" \
    REMOTE_ROOT="$REMOTE_ROOT" \
    REMOTE_SCENARIO="$scenario" \
    REMOTE_GIT_BRANCH="${REMOTE_GIT_BRANCH:-mini-work}" \
    REMOTE_GIT_HEAD="${REMOTE_GIT_HEAD:-fedcba9876543210fedcba9876543210fedcba98}" \
    REMOTE_AGENT_HOST="${REMOTE_AGENT_HOST_OVERRIDE:-fixture-mini}" \
    MOCK_IGNORED="${MOCK_IGNORED:-}" \
    MOCK_SAFE_PATH="${MOCK_SAFE_PATH:-}" \
    RSYNC_FAIL="${RSYNC_FAIL:-0}" \
    SUPERVISOR_STRICT="${SUPERVISOR_STRICT:-0}" \
    REMOTE_CAPTURE_OUTPUT="${REMOTE_CAPTURE_OUTPUT:-}" \
    REMOTE_WAIT_OUTPUT="${REMOTE_WAIT_OUTPUT:-}" \
    REMOTE_SUPERVISOR_START_OUTPUT="${REMOTE_SUPERVISOR_START_OUTPUT:-}" \
    REMOTE_SUPERVISOR_START_FAIL="${REMOTE_SUPERVISOR_START_FAIL:-0}" \
    REMOTE_SUPERVISOR_STATUS_OUTPUT="${REMOTE_SUPERVISOR_STATUS_OUTPUT:-}" \
    REMOTE_HOME="$REMOTE_HOME" \
    REMOTE_STATE="$REMOTE_STATE" \
    REMOTE_BIN="$REMOTE_BIN" \
    REAL_PROTOCOL="$SCRIPT_DIR/../../scripts/remote-agent-v1" \
    REAL_SUPERVISOR="$SCRIPT_DIR/../../scripts/agent-supervisor" \
    "$REAL_BASH" "$REMOTE_AGENT" "$@" >"$STDOUT" 2>"$STDERR")
  STATUS=$?
  set -e
}

expect_success() {
  local scenario=$1
  shift
  run_helper "$scenario" "$@"
  [[ $STATUS -eq 0 ]]
}

expect_failure() {
  local scenario=$1
  shift
  run_helper "$scenario" "$@"
  [[ $STATUS -ne 0 ]]
}

run_test() {
  local name=$1
  shift
  setup_case "test-$((PASS_COUNT + FAIL_COUNT + 1))"
  if "$@"; then pass "$name"; else fail "$name" "status=$STATUS stdout=$(tr '\n' ' ' <"$STDOUT" 2>/dev/null || true) stderr=$(tr '\n' ' ' <"$STDERR" 2>/dev/null || true)"; fi
}

# The fixture self-test runs before the RED gate. It uses a non-production host
# and demonstrates that command capture/stdin capture are functional.
setup_case fixture-self-test
REMOTE_SCENARIO=fixture-self-test COMMAND_LOG="$COMMAND_LOG" SSH_STDIN="$SSH_STDIN" \
  "$FAKE_BIN/ssh" fixture-mini fixture-probe >"$STDOUT"
if [[ $(<"$STDOUT") != fixture-ok ]] || ! assert_contains "$COMMAND_LOG" '<fixture-mini>'; then
  fail 'hermetic fixture self-test' 'fake ssh did not execute correctly'
  printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
  exit 1
fi
pass 'hermetic fixture self-test'

if [[ ! -x "$REMOTE_AGENT" ]]; then
  fail 'remote-agent helper exists' "missing executable: $REMOTE_AGENT"
  printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
  exit 1
fi

test_validation() {
  expect_failure equal || return 1
  assert_contains "$STDERR" 'usage' || return 1
  expect_failure equal dance miospot claude || return 1
  expect_failure equal start other-project claude || return 1
  expect_failure equal start miospot other-harness
}

test_closed_mapping_and_host_precedence() {
  expect_success equal --host cli-mini status miospot || return 1
  assert_contains "$COMMAND_LOG" '<cli-mini>' || return 1
  : >"$COMMAND_LOG"
  printf 'config-mini\n' >"$TEST_STATE/orchestration-remote-host"
  REMOTE_AGENT_HOST_OVERRIDE=env-mini run_helper equal status miospot
  [[ $STATUS -eq 0 ]] || return 1
  assert_contains "$COMMAND_LOG" '<env-mini>' || return 1
  assert_lacks "$COMMAND_LOG" 'livingroom-mini'
}

test_project_mapping_ignores_decoy_git_cwd() {
  local miospot_root="$CASE/MioSpot checkout with spaces"
  local orchestration_root="$CASE/orchestration checkout with spaces"
  local escaped_miospot_root escaped_orchestration_root
  seed_checkout "$miospot_root" miospot
  seed_checkout "$orchestration_root" orchestration
  printf -v escaped_miospot_root '%q' "$miospot_root/"
  printf -v escaped_orchestration_root '%q' "$orchestration_root/"

  CALLER_ROOT_OVERRIDE="$DECOY_ROOT" \
    LOCAL_MIOSPOT_ROOT_OVERRIDE="$miospot_root" \
    LOCAL_ORCHESTRATION_ROOT_OVERRIDE="$orchestration_root" \
    GENERIC_LOCAL_ROOT_OVERRIDE="$DECOY_ROOT" \
    expect_success local-only start miospot claude || return 1
  assert_contains "$COMMAND_LOG" "git cwd=<$miospot_root> <rev-parse> <--show-toplevel>" || return 1
  assert_contains "$COMMAND_LOG" "git cwd=<$miospot_root> <ls-files> <-z>" || return 1
  assert_contains "$COMMAND_LOG" "sha256sum cwd=<$miospot_root>" || return 1
  assert_contains "$COMMAND_LOG" '<miospot-only.txt>' || return 1
  assert_contains "$COMMAND_LOG" '1111111111111111111111111111111111111111111111111111111111111111' || return 1
  assert_contains "$COMMAND_LOG" "<$escaped_miospot_root>" || return 1
  assert_lacks "$COMMAND_LOG" "cwd=<$DECOY_ROOT>" || return 1
  assert_lacks "$COMMAND_LOG" "<$DECOY_ROOT/>" || return 1

  : >"$COMMAND_LOG"
  CALLER_ROOT_OVERRIDE="$miospot_root" \
    LOCAL_MIOSPOT_ROOT_OVERRIDE="$miospot_root" \
    LOCAL_ORCHESTRATION_ROOT_OVERRIDE="$orchestration_root" \
    GENERIC_LOCAL_ROOT_OVERRIDE="$miospot_root" \
    expect_success local-only start orchestration grok || return 1
  assert_contains "$COMMAND_LOG" "git cwd=<$orchestration_root> <rev-parse> <--show-toplevel>" || return 1
  assert_contains "$COMMAND_LOG" "git cwd=<$orchestration_root> <ls-files> <-z>" || return 1
  assert_contains "$COMMAND_LOG" "sha256sum cwd=<$orchestration_root>" || return 1
  assert_contains "$COMMAND_LOG" '<orchestration-only.txt>' || return 1
  assert_contains "$COMMAND_LOG" '2222222222222222222222222222222222222222222222222222222222222222' || return 1
  assert_contains "$COMMAND_LOG" "<$escaped_orchestration_root>" || return 1
  assert_lacks "$COMMAND_LOG" "cwd=<$miospot_root>" || return 1
  assert_lacks "$COMMAND_LOG" "<$miospot_root/>"
}

test_project_mapping_defaults_and_rejects_invalid_roots() {
  local default_miospot="$TEST_HOME/Projects/miospot"
  local default_orchestration="$TEST_HOME/Projects/orchestration"
  local valid_root="$CASE/valid checkout"
  local symlink_root="$CASE/symlink checkout"
  local non_git_root="$CASE/non Git checkout"
  local git_parent="$CASE/parent checkout"
  local nested_root="$git_parent/nested"
  seed_checkout "$default_miospot" miospot
  seed_checkout "$default_orchestration" orchestration
  seed_checkout "$valid_root" miospot
  seed_checkout "$non_git_root" miospot
  seed_checkout "$nested_root" miospot
  ln -s "$valid_root" "$symlink_root"

  LOCAL_MIOSPOT_ROOT_OVERRIDE='' CALLER_ROOT_OVERRIDE="$DECOY_ROOT" \
    expect_success equal status miospot claude || return 1
  assert_contains "$COMMAND_LOG" "git cwd=<$default_miospot> <rev-parse> <--show-toplevel>" || return 1
  : >"$COMMAND_LOG"
  LOCAL_ORCHESTRATION_ROOT_OVERRIDE='' CALLER_ROOT_OVERRIDE="$DECOY_ROOT" \
    expect_success equal status orchestration claude || return 1
  assert_contains "$COMMAND_LOG" "git cwd=<$default_orchestration> <rev-parse> <--show-toplevel>" || return 1

  : >"$COMMAND_LOG"
  LOCAL_MIOSPOT_ROOT_OVERRIDE="$symlink_root" expect_failure equal status miospot claude || return 1
  assert_contains "$STDERR" 'real directory' || return 1
  assert_lacks "$COMMAND_LOG" 'ssh' || return 1

  : >"$COMMAND_LOG"
  LOCAL_MIOSPOT_ROOT_OVERRIDE="$non_git_root" MOCK_GIT_FAIL_ROOT="$non_git_root" \
    expect_failure equal status miospot claude || return 1
  assert_contains "$STDERR" 'Git worktree' || return 1
  assert_lacks "$COMMAND_LOG" 'ssh' || return 1

  : >"$COMMAND_LOG"
  LOCAL_MIOSPOT_ROOT_OVERRIDE="$nested_root" MOCK_GIT_TOPLEVEL_OVERRIDE="$git_parent" \
    expect_failure equal status miospot claude || return 1
  assert_contains "$STDERR" 'Git toplevel' || return 1
  assert_lacks "$COMMAND_LOG" 'ssh'
}

test_relative_prompt_file_is_independent_of_mapped_root() {
  local miospot_root="$CASE/mapped checkout"
  local prompt_name='prompt outside mapped checkout.txt'
  local secret='MAPPED-ROOT-PROMPT-STDIN-CANARY'
  seed_checkout "$miospot_root" miospot
  printf '%s\n' "$secret" >"$DECOY_ROOT/$prompt_name"

  CALLER_ROOT_OVERRIDE="$DECOY_ROOT" LOCAL_MIOSPOT_ROOT_OVERRIDE="$miospot_root" \
    expect_success equal start miospot claude --prompt-file "$prompt_name" || return 1
  assert_contains "$SSH_STDIN" "$secret" || return 1
  assert_lacks "$COMMAND_LOG" "$secret" || return 1
  assert_lacks "$STDOUT" "$secret" || return 1
  assert_lacks "$STDERR" "$secret"
}

test_hostile_argv_is_data() {
  local marker="$CASE/PWNED"
  expect_failure equal --host 'mini; touch PWNED' start '../miospot' "claude\$(touch PWNED)" || return 1
  [[ ! -e "$marker" ]] || return 1
  assert_lacks "$COMMAND_LOG" 'touch PWNED'
}

test_exact_sessions() {
  expect_success equal status miospot || return 1
  assert_contains "$COMMAND_LOG" 'remote-agent--miospot--claude' || return 1
  assert_lacks "$COMMAND_LOG" 'persistence-demo'
}

test_inspect_captures_without_sync() {
  expect_success live-writer inspect miospot claude || return 1
  assert_contains "$COMMAND_LOG" '<agent-supervisor> <capture> <remote-agent--miospot--claude>' || return 1
  assert_lacks "$COMMAND_LOG" '<remote-agent-v1> <capture>' || return 1
  assert_lacks "$COMMAND_LOG" 'rsync'
}

test_inspect_capture_is_visible() {
  REMOTE_CAPTURE_OUTPUT='VISIBLE-CAPTURE-LINE' expect_success live-writer inspect miospot claude || return 1
  assert_contains "$STDOUT" 'VISIBLE-CAPTURE-LINE' || return 1
  [[ $(wc -l <"$STDOUT" | tr -d ' ') -le 40 ]] || return 1
  [[ $(wc -c <"$STDOUT" | tr -d ' ') -le 4096 ]]
}

test_continue_captures_before_send() {
  printf 'continue after checking state\n' >"$CASE/prompt"
  expect_success live-writer continue miospot claude --prompt-file "$CASE/prompt" || return 1
  local capture_line send_line
  capture_line=$(grep -n 'capture' "$COMMAND_LOG" | head -1 | cut -d: -f1)
  send_line=$(grep -n 'send' "$COMMAND_LOG" | head -1 | cut -d: -f1)
  [[ -n "$capture_line" && -n "$send_line" && $capture_line -lt $send_line ]] || return 1
  assert_lacks "$COMMAND_LOG" 'rsync'
}

test_wait_requires_a_bounded_cursor_and_timeout() {
  expect_failure equal wait miospot claude || return 1
  assert_lacks "$COMMAND_LOG" '<agent-supervisor> <wait>' || return 1
  expect_failure equal wait miospot claude --cursor 'epoch-1:0;touch-pwned' --timeout 30 || return 1
  assert_lacks "$COMMAND_LOG" 'touch-pwned' || return 1
  expect_failure equal wait miospot claude --cursor epoch-1:0 --timeout 0 || return 1
  expect_failure equal wait miospot claude --cursor epoch-1:0 --timeout 301 || return 1
  expect_failure equal wait miospot claude --cursor epoch-1:0 --timeout not-a-number
}

test_wait_delegates_exact_sessions_for_every_harness() {
  local harness session
  for harness in claude codex grok; do
    session="remote-agent--orchestration--$harness"
    : >"$COMMAND_LOG"
    REMOTE_WAIT_OUTPUT="{\"epoch\":\"epoch-7\",\"cursor\":42,\"session\":\"$session\",\"wake\":\"timeout\"}" \
      expect_success equal wait orchestration "$harness" --cursor epoch-7:41 --timeout 30 || return 1
    assert_contains "$COMMAND_LOG" "<agent-supervisor> <wait> <$session> <epoch-7:41> <30>" || return 1
    assert_count "$COMMAND_LOG" '<agent-supervisor> <wait>' 1 || return 1
    assert_lacks "$COMMAND_LOG" '<remote-agent-v1>' || return 1
    assert_lacks "$COMMAND_LOG" 'rsync' || return 1
    assert_lacks "$COMMAND_LOG" 'git <' || return 1
    assert_contains "$STDOUT" '"wake":"timeout"' || return 1
    assert_contains "$STDOUT" "\"session\":\"$session\"" || return 1
  done
}

test_wait_surfaces_timeout_exit_and_event_wakes() {
  local wake payload
  for wake in timeout exit event; do
    case $wake in
      timeout) payload='{"epoch":"epoch-8","cursor":8,"session":"remote-agent--miospot--claude","wake":"timeout"}' ;;
      exit) payload='{"epoch":"epoch-8","cursor":9,"session":"remote-agent--miospot--claude","wake":"exit"}' ;;
      event) payload='{"epoch":"epoch-8","cursor":10,"session":"remote-agent--miospot--claude","wake":"event","scope":"subagent","kind":"completed"}' ;;
    esac
    : >"$COMMAND_LOG"
    REMOTE_WAIT_OUTPUT="$payload" expect_success equal wait miospot claude --cursor epoch-8:7 --timeout 1 || return 1
    assert_contains "$STDOUT" "\"wake\":\"$wake\"" || return 1
    assert_contains "$STDOUT" '"epoch":"epoch-8"' || return 1
    assert_lacks "$COMMAND_LOG" 'rsync' || return 1
    assert_lacks "$COMMAND_LOG" 'lease-' || return 1
    if [[ $wake == exit ]]; then
      assert_contains "$COMMAND_LOG" '<remote-agent-v1> <mutex-acquire>' || return 1
      assert_contains "$COMMAND_LOG" '<agent-supervisor> <status> <remote-agent--miospot--claude>' || return 1
      assert_contains "$COMMAND_LOG" '<remote-agent-v1> <quiescent> <remote-agent--miospot--claude> <authority-root-v1>' || return 1
      assert_contains "$COMMAND_LOG" '<remote-agent-v1> <mutex-release>' || return 1
    else
      assert_lacks "$COMMAND_LOG" 'mutex-' || return 1
      assert_lacks "$COMMAND_LOG" '<quiescent>' || return 1
    fi
  done
}

test_wait_exit_recheck_refuses_a_restarted_session() {
  local session=remote-agent--miospot--claude
  REMOTE_WAIT_OUTPUT="{\"epoch\":\"epoch-8\",\"cursor\":9,\"session\":\"$session\",\"wake\":\"exit\"}" \
    REMOTE_SUPERVISOR_STATUS_OUTPUT="{\"session\":\"running\",\"name\":\"$session\",\"epoch\":\"epoch-9\",\"cursor\":0,\"bootstrapCursor\":\"epoch-9:0\"}" \
    expect_failure equal wait miospot claude --cursor epoch-8:7 --timeout 1 || return 1
  assert_contains "$COMMAND_LOG" '<agent-supervisor> <status>' || return 1
  assert_lacks "$COMMAND_LOG" '<quiescent>' || return 1
  assert_contains "$COMMAND_LOG" '<remote-agent-v1> <mutex-release>'
}

test_wait_preserves_monotonic_restart_aware_cursors() {
  REMOTE_WAIT_OUTPUT='{"epoch":"epoch-12","cursor":100,"session":"remote-agent--miospot--claude","wake":"event","scope":"main","kind":"completed"}' \
    expect_success equal wait miospot claude --cursor epoch-12:99 --timeout 20 || return 1
  assert_contains "$STDOUT" '"cursor":100' || return 1
  : >"$COMMAND_LOG"
  REMOTE_WAIT_OUTPUT='{"epoch":"epoch-12","cursor":101,"session":"remote-agent--miospot--claude","wake":"event","scope":"main","kind":"failed"}' \
    expect_success equal wait miospot claude --cursor epoch-12:100 --timeout 20 || return 1
  assert_contains "$COMMAND_LOG" '<epoch-12:100>' || return 1
  assert_contains "$STDOUT" '"cursor":101' || return 1
  : >"$COMMAND_LOG"
  REMOTE_WAIT_OUTPUT='{"epoch":"epoch-13","cursor":0,"session":"remote-agent--miospot--claude","wake":"timeout"}' \
    expect_success equal wait miospot claude --cursor epoch-12:101 --timeout 20 || return 1
  assert_contains "$COMMAND_LOG" '<epoch-12:101>' || return 1
  assert_contains "$STDOUT" '"epoch":"epoch-13"'
}

test_start_and_status_expose_direct_wait_bootstrap_without_leakage() {
  local session=remote-agent--miospot--claude
  local bootstrap_file=$CASE/bootstrap.json bootstrap canary='PANE-EVENT-CANARY-8013'
  REMOTE_SUPERVISOR_START_OUTPUT="{\"session\":\"running\",\"name\":\"$session\",\"epoch\":\"epoch-start-1\",\"cursor\":7,\"bootstrapCursor\":\"epoch-start-1:7\"}" \
    REMOTE_CAPTURE_OUTPUT="$canary" expect_success equal start miospot claude || return 1
  cp "$STDOUT" "$bootstrap_file"
  bootstrap=$(sed -n 's/.*"bootstrapCursor":"\([^"]*\)".*/\1/p' "$bootstrap_file")
  [[ $bootstrap == epoch-start-1:7 ]] || return 1
  [[ $(wc -l <"$bootstrap_file" | tr -d ' ') -eq 1 ]] || return 1
  [[ $(wc -c <"$bootstrap_file" | tr -d ' ') -le 4096 ]] || return 1
  assert_lacks "$bootstrap_file" "$canary" || return 1
  assert_lacks "$bootstrap_file" '"authority"' || return 1
  assert_lacks "$bootstrap_file" '"scope"' || return 1
  assert_lacks "$bootstrap_file" '"kind"' || return 1

  : >"$COMMAND_LOG"
  REMOTE_WAIT_OUTPUT="{\"epoch\":\"epoch-start-1\",\"cursor\":7,\"session\":\"$session\",\"wake\":\"timeout\"}" \
    expect_success equal wait miospot claude --cursor "$bootstrap" --timeout 1 || return 1
  assert_contains "$COMMAND_LOG" "<agent-supervisor> <wait> <$session> <$bootstrap> <1>" || return 1
  assert_lacks "$COMMAND_LOG" '<remote-agent-v1>' || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1

  REMOTE_SUPERVISOR_STATUS_OUTPUT="{\"session\":\"running\",\"name\":\"$session\",\"epoch\":\"epoch-restart-2\",\"cursor\":7,\"bootstrapCursor\":\"epoch-restart-2:7\"}" \
    REMOTE_CAPTURE_OUTPUT="$canary" expect_success live-writer status miospot claude || return 1
  [[ $(wc -l <"$STDOUT" | tr -d ' ') -eq 1 ]] || return 1
  assert_contains "$STDOUT" '{"authority":{"relation":"equal","writer":"live","generation":7},"supervisor":{"session":"running"' || return 1
  assert_contains "$STDOUT" '"bootstrapCursor":"epoch-restart-2:7"' || return 1
  assert_lacks "$STDOUT" "$canary" || return 1
  assert_lacks "$COMMAND_LOG" 'rsync'
}

test_wait_capture_is_visible_bounded_and_not_persisted_locally() {
  local capture=$CASE/wake-output
  {
    printf '%s\n' '{"epoch":"epoch-4","cursor":5,"session":"remote-agent--miospot--claude","wake":"event","scope":"main","kind":"completed"}'
    for index in $(seq 81 120); do printf 'wake-capture-%03d zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n' "$index"; done
  } >"$capture"
  REMOTE_WAIT_OUTPUT="$(<"$capture")" expect_success equal wait miospot claude --cursor epoch-4:4 --timeout 20 || return 1
  [[ $(wc -l <"$STDOUT" | tr -d ' ') -le 41 ]] || return 1
  [[ $(wc -c <"$STDOUT" | tr -d ' ') -le 4096 ]] || return 1
  assert_contains "$STDOUT" 'wake-capture-120' || return 1
  assert_lacks "$COMMAND_LOG" 'wake-capture-' || return 1
  ! grep -R -Fq -- 'wake-capture-120' "$TEST_HOME" "$TEST_STATE"
}

test_reveal_delegates_exact_terminal_attachment_without_mutation() {
  local harness session secret='REVEAL-PROMPT-CANARY-8842'
  printf '%s\n' "$secret" >"$CASE/prompt"
  for harness in claude codex grok; do
    session="remote-agent--miospot--$harness"
    : >"$COMMAND_LOG"
    expect_success equal reveal miospot "$harness" || return 1
    assert_contains "$COMMAND_LOG" "<agent-supervisor> <reveal> <$session>" || return 1
    assert_count "$COMMAND_LOG" '<agent-supervisor> <reveal>' 1 || return 1
    assert_lacks "$COMMAND_LOG" "$secret" || return 1
    assert_lacks "$STDOUT" "$secret" || return 1
    assert_lacks "$STDERR" "$secret" || return 1
    assert_lacks "$COMMAND_LOG" '<remote-agent-v1>' || return 1
    assert_lacks "$COMMAND_LOG" 'rsync' || return 1
    assert_lacks "$COMMAND_LOG" '<start>' || return 1
    assert_lacks "$COMMAND_LOG" '<send>' || return 1
    assert_lacks "$COMMAND_LOG" '<kill>' || return 1
    assert_lacks "$COMMAND_LOG" '<interrupt>' || return 1
    assert_lacks "$COMMAND_LOG" 'new-session' || return 1
    assert_lacks "$COMMAND_LOG" 'respawn-pane' || return 1
    assert_lacks "$COMMAND_LOG" 'kill-pane' || return 1
  done
  : >"$COMMAND_LOG"
  expect_failure equal reveal miospot claude --prompt-file "$CASE/prompt" || return 1
  assert_lacks "$COMMAND_LOG" "$secret" || return 1
  assert_lacks "$COMMAND_LOG" '<agent-supervisor> <reveal>'
}

test_prompt_is_bounded_and_redacted() {
  local secret='CANARY-secret-42'
  printf '%s\n' "$secret" >"$CASE/prompt"
  expect_success live-writer send miospot claude --prompt-file "$CASE/prompt" || return 1
  assert_lacks "$COMMAND_LOG" "$secret" || return 1
  assert_lacks "$STDOUT" "$secret" || return 1
  assert_lacks "$STDERR" "$secret" || return 1
  assert_contains "$SSH_STDIN" "$secret" || return 1
  : >"$COMMAND_LOG"
  printf '%65537s' '' >"$CASE/oversized-prompt"
  expect_failure live-writer send miospot claude --prompt-file "$CASE/oversized-prompt" || return 1
  assert_lacks "$COMMAND_LOG" 'ssh'
}

test_control_lifecycle() {
  expect_success live-writer interrupt miospot claude || return 1
  assert_contains "$COMMAND_LOG" 'interrupt' || return 1
  : >"$COMMAND_LOG"
  expect_success live-writer kill miospot claude || return 1
  assert_contains "$COMMAND_LOG" 'kill' || return 1
  assert_contains "$COMMAND_LOG" 'quiescent'
}

test_start_local_only_transfer() {
  expect_success local-only start miospot codex || return 1
  assert_contains "$COMMAND_LOG" 'mutex-acquire' || return 1
  assert_contains "$COMMAND_LOG" 'stage' || return 1
  assert_contains "$COMMAND_LOG" 'restore-journal' || return 1
  assert_contains "$COMMAND_LOG" 'lease-commit' || return 1
  [[ ! -e $REMOTE_ROOT/.remote-agent-stage ]] || return 1
  assert_lacks "$COMMAND_LOG" "$REMOTE_ROOT/.remote-agent-stage/" || return 1
  assert_contains "$COMMAND_LOG" 'remote-agent--miospot--codex'
  local apply_line baseline_line provisional_line
  apply_line=$(grep -n 'apply-exact' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  baseline_line=$(grep -n 'post-sync-verify' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  provisional_line=$(grep -n 'lease-provisional' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  [[ -n $apply_line && -n $baseline_line && -n $provisional_line ]] || return 1
  [[ $apply_line -lt $baseline_line && $baseline_line -lt $provisional_line ]]
}

test_start_accepts_optional_prompt() {
  local secret='START-PROMPT-CANARY'
  printf '%s\n' "$secret" >"$CASE/prompt"
  expect_success equal start miospot claude --prompt-file "$CASE/prompt" || return 1
  local commit_line send_line
  commit_line=$(grep -n 'lease-commit' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  send_line=$(grep -n 'agent-supervisor.*send' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  [[ -n "$commit_line" && -n "$send_line" && $commit_line -lt $send_line ]] || return 1
  assert_lacks "$COMMAND_LOG" "$secret" || return 1
  assert_contains "$SSH_STDIN" "$secret"
}

test_supervisor_rejects_legacy_launch_verb() {
  SUPERVISOR_STRICT=1 expect_success equal start miospot claude || return 1
  assert_contains "$COMMAND_LOG" '<agent-supervisor> <start>' || return 1
  assert_lacks "$COMMAND_LOG" '<agent-supervisor> <launch>'
}

test_codex_uses_shared_supervisor() {
  SUPERVISOR_STRICT=1 expect_success equal start miospot codex || return 1
  assert_contains "$COMMAND_LOG" '<agent-supervisor> <start>' || return 1
  assert_lacks "$COMMAND_LOG" 'mini-agent'
}

test_start_forwards_yolo_exactly() {
  expect_success equal start orchestration grok || return 1
  assert_contains "$COMMAND_LOG" '<agent-supervisor> <start> <remote-agent--orchestration--grok> <grok>' || return 1
  assert_contains "$COMMAND_LOG" '<project-root-v1:orchestration>' || return 1
  assert_count "$COMMAND_LOG" '<--yolo>' 1
}

test_failed_supervisor_start_aborts_provisional_lease() {
  REMOTE_SUPERVISOR_START_FAIL=47 run_helper equal start miospot claude
  [[ $STATUS -eq 47 ]] || return 1
  local provisional_line start_line abort_line release_line
  provisional_line=$(grep -n 'lease-provisional' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  start_line=$(grep -n 'agent-supervisor.*start' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  abort_line=$(grep -n 'lease-abort' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  release_line=$(grep -n 'mutex-release' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  [[ -n $provisional_line && -n $start_line && -n $abort_line && -n $release_line ]] || return 1
  [[ $provisional_line -lt $start_line && $start_line -lt $abort_line && $abort_line -lt $release_line ]] || return 1
  assert_lacks "$COMMAND_LOG" 'lease-commit'
}

test_supervisor_prompt_transport_is_stdin_only() {
  local secret='HELPER-STDIN-ONLY-CANARY'
  printf '%s\n' "$secret" >"$CASE/prompt"
  expect_success live-writer send miospot grok --prompt-file "$CASE/prompt" || return 1
  assert_contains "$COMMAND_LOG" '<agent-supervisor> <send> <remote-agent--miospot--grok>' || return 1
  assert_lacks "$COMMAND_LOG" "$secret" || return 1
  assert_lacks "$STDOUT" "$secret" || return 1
  assert_lacks "$STDERR" "$secret" || return 1
  assert_contains "$SSH_STDIN" "$secret"
}

test_start_refuses_live_writer_and_divergence() {
  expect_failure live-writer start miospot claude || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1
  : >"$COMMAND_LOG"
  expect_failure diverged start miospot claude || return 1
  assert_contains "$STDERR" 'left.txt' || return 1
  assert_contains "$STDERR" 'right.txt'
}

test_first_contact_rules() {
  expect_success equal start orchestration grok || return 1
  assert_contains "$COMMAND_LOG" 'adopt' || return 1
  : >"$COMMAND_LOG"
  expect_failure live-writer start orchestration grok || return 1
  assert_lacks "$COMMAND_LOG" 'lease-commit'
}

test_snapshot_is_strong_and_nul_safe() {
  expect_success equal status miospot || return 1
  assert_contains "$COMMAND_LOG" 'rev-parse' || return 1
  assert_contains "$COMMAND_LOG" 'ls-files' || return 1
  assert_contains "$COMMAND_LOG" 'sha256' || return 1
  assert_contains "$COMMAND_LOG" 'manifest-nul' || return 1
  assert_lacks "$COMMAND_LOG" '--ignore-times'
}

test_divergence_matrix() {
  expect_success equal start miospot claude || return 1
  : >"$COMMAND_LOG"
  expect_success local-only start miospot claude || return 1
  : >"$COMMAND_LOG"
  expect_failure remote-only start miospot claude || return 1
  : >"$COMMAND_LOG"
  expect_failure diverged reclaim miospot claude || return 1
  assert_lacks "$COMMAND_LOG" 'lease-release'
}

test_remote_lease_mutex_and_cas() {
  expect_failure lock-held start miospot claude || return 1
  assert_lacks "$COMMAND_LOG" 'mutex-break' || return 1
  : >"$COMMAND_LOG"
  expect_failure cas-lost start miospot claude || return 1
  assert_lacks "$COMMAND_LOG" 'lease-commit' || return 1
  assert_contains "$COMMAND_LOG" '<fixture-mini>'
}

test_writer_records_fail_closed_without_stale_inference() {
  expect_failure provisional-writer start miospot claude || return 1
  assert_contains "$STDERR" 'active' || return 1
  assert_lacks "$COMMAND_LOG" 'lease-provisional' || return 1
  : >"$COMMAND_LOG"
  expect_failure equal-quiescent start miospot claude || return 1
  assert_contains "$STDERR" 'safe reclaim' || return 1
  assert_lacks "$COMMAND_LOG" 'lease-provisional' || return 1
  : >"$COMMAND_LOG"
  expect_failure unknown-writer start miospot claude || return 1
  assert_contains "$STDERR" 'unrecognized active' || return 1
  assert_lacks "$COMMAND_LOG" 'lease-provisional' || return 1
  assert_lacks "$REMOTE_AGENT" 'heartbeat' || return 1
  assert_lacks "$REMOTE_AGENT" 'kill -0'
}

test_transfer_universe_and_deletions() {
  expect_success local-only start miospot claude --active-plan selected || return 1
  assert_contains "$COMMAND_LOG" 'README.md' || return 1
  assert_contains "$COMMAND_LOG" 'notes.txt' || return 1
  assert_contains "$COMMAND_LOG" 'plan.json' || return 1
  assert_contains "$COMMAND_LOG" 'progress.json' || return 1
  assert_contains "$COMMAND_LOG" 'masterPlan.md' || return 1
  assert_contains "$COMMAND_LOG" 'deletion-inventory' || return 1
  for excluded in '.git' 'node_modules' '.env' 'logs' 'panel' 'stdout'; do
    assert_lacks "$COMMAND_LOG" "$excluded" || return 1
  done
}

test_ignored_paths_need_exact_consent() {
  MOCK_IGNORED='.env.local' expect_failure local-only start miospot claude --include-ignored '.env*' || return 1
  : >"$COMMAND_LOG"
  MOCK_IGNORED='.env.local' expect_success local-only start miospot claude --include-ignored '.env.local' --approve-ignored '.env.local' || return 1
  assert_contains "$COMMAND_LOG" '.env.local'
}

test_active_plan_is_bounded_and_stable() {
  expect_failure plan-mutated start orchestration claude --active-plan selected || return 1
  assert_lacks "$COMMAND_LOG" 'lease-commit' || return 1
  assert_lacks "$COMMAND_LOG" 'resolved' || return 1
  assert_lacks "$COMMAND_LOG" 'raw-output'
}

test_private_staging_and_restore_journal() {
  expect_success local-only start miospot claude || return 1
  assert_contains "$COMMAND_LOG" 'umask 077' || return 1
  assert_contains "$COMMAND_LOG" 'stage-verify' || return 1
  assert_contains "$COMMAND_LOG" 'restore-journal' || return 1
  assert_contains "$COMMAND_LOG" 'mode=0600' || return 1
  assert_contains "$COMMAND_LOG" 'apply-exact'
}

test_network_staging_failure_stops_before_apply() {
  RSYNC_FAIL=1 expect_failure local-only start miospot claude || return 1
  assert_contains "$COMMAND_LOG" 'rsync' || return 1
  assert_lacks "$COMMAND_LOG" 'stage-verify' || return 1
  assert_lacks "$COMMAND_LOG" 'apply-exact' || return 1
  assert_lacks "$COMMAND_LOG" 'lease-provisional' || return 1
  assert_lacks "$COMMAND_LOG" 'lease-commit' || return 1
  assert_lacks "$COMMAND_LOG" 'recovery-required' || return 1
  assert_contains "$COMMAND_LOG" 'mutex-release'
}

test_failed_apply_restores_before_state_change() {
  expect_failure apply-fails-restored start miospot claude || return 1
  assert_contains "$COMMAND_LOG" 'restore-verify' || return 1
  assert_lacks "$COMMAND_LOG" 'lease-commit' || return 1
  assert_contains "$STDERR" 'restored'
}

test_nonzero_apply_status_restores_before_state_change() {
  expect_failure apply-command-fails-restored start miospot claude || return 1
  assert_contains "$COMMAND_LOG" 'restore-verify' || return 1
  assert_lacks "$COMMAND_LOG" 'lease-commit' || return 1
  assert_contains "$STDERR" 'restored'
}

test_failed_restore_preserves_recovery_evidence() {
  expect_failure apply-fails-recovery start miospot claude || return 1
  assert_contains "$COMMAND_LOG" 'recovery-required' || return 1
  assert_lacks "$COMMAND_LOG" 'mutex-release' || return 1
  assert_lacks "$COMMAND_LOG" 'lease-commit'
}

test_reclaim_remote_only_release_last() {
  expect_success remote-only reclaim miospot claude || return 1
  local verify_line release_line
  assert_contains "$COMMAND_LOG" '<generation-check> <miospot> <7>' || return 1
  assert_lacks "$COMMAND_LOG" '<common-state-cas>' || return 1
  verify_line=$(grep -n 'post-sync-verify' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  release_line=$(grep -n 'lease-release' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  [[ -n "$verify_line" && -n "$release_line" && $verify_line -lt $release_line ]]
}

test_outbound_handoff_requests_bundle_and_exact_git_alignment() {
  MOCK_GIT_BRANCH=feature/handoff
  MOCK_GIT_HEAD=1111111111111111111111111111111111111111
  printf ' M README.md\0?? notes.txt\0' >"$GIT_STATUS_FILE"
  expect_success local-only start miospot claude || return 1
  assert_contains "$COMMAND_LOG" '<bundle> <create>' || return 1
  assert_contains "$COMMAND_LOG" '<git-align> <miospot> <feature/handoff> <1111111111111111111111111111111111111111>' || return 1
  assert_contains "$COMMAND_LOG" '<status> <--porcelain=v1> <-z>'
}

test_reclaim_fast_forwards_branch_and_resets_index_mixed() {
  local mini_head=fedcba9876543210fedcba9876543210fedcba98
  MOCK_GIT_BRANCH=main
  MOCK_GIT_HEAD=0123456789abcdef0123456789abcdef01234567
  REMOTE_GIT_BRANCH=main
  REMOTE_GIT_HEAD=$mini_head
  expect_success remote-only reclaim miospot claude || return 1
  assert_contains "$COMMAND_LOG" "<populate-inbound> <miospot> <main> <$mini_head>" || return 1
  assert_contains "$COMMAND_LOG" "<merge-base> <--is-ancestor> <0123456789abcdef0123456789abcdef01234567> <$mini_head>" || return 1
  assert_contains "$GIT_REF_LOG" "<update-ref> <refs/heads/main> <$mini_head>" || return 1
  assert_contains "$GIT_REF_LOG" "<reset> <--mixed> <$mini_head>"
}

test_reclaim_refuses_non_fast_forward_without_ref_mutation() {
  MOCK_GIT_ANCESTOR=0 run_helper remote-only reclaim miospot claude
  [[ $STATUS -ne 0 ]] || return 1
  assert_contains "$STDERR" 'fast-forward' || return 1
  [[ ! -s $GIT_REF_LOG ]]
}

test_refusal_paths_never_mutate_git_refs_or_index() {
  expect_failure diverged start miospot claude || return 1
  [[ ! -s $GIT_REF_LOG ]] || return 1
  : >"$GIT_REF_LOG"
  expect_failure cas-lost start miospot claude || return 1
  [[ ! -s $GIT_REF_LOG ]] || return 1
  : >"$GIT_REF_LOG"
  expect_failure apply-fails-recovery start miospot claude || return 1
  [[ ! -s $GIT_REF_LOG ]]
}

test_equal_quiescent_reclaim_releases_without_transfer() {
  expect_success equal-quiescent reclaim miospot claude || return 1
  assert_contains "$COMMAND_LOG" '<generation-check> <miospot> <7>' || return 1
  assert_lacks "$COMMAND_LOG" '<common-state-cas>' || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1
  assert_lacks "$COMMAND_LOG" 'stage' || return 1
  assert_lacks "$COMMAND_LOG" 'apply-exact' || return 1
  assert_contains "$COMMAND_LOG" 'lease-release'
}

test_local_only_quiescent_reclaim_releases_without_transfer() {
  expect_success local-only-quiescent reclaim miospot claude || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1
  assert_lacks "$COMMAND_LOG" 'stage' || return 1
  assert_lacks "$COMMAND_LOG" 'apply-exact' || return 1
  assert_lacks "$COMMAND_LOG" 'post-sync-verify' || return 1
  assert_contains "$COMMAND_LOG" '<release-only-verify> <miospot>' || return 1
  assert_contains "$COMMAND_LOG" 'lease-release'
}

test_real_backend_adapter_over_fake_ssh() {
  local real_protocol=$SCRIPT_DIR/../../scripts/remote-agent-v1
  local real_supervisor=$SCRIPT_DIR/../../scripts/agent-supervisor
  [[ -x $real_protocol ]] || { printf 'missing real protocol: %s\n' "$real_protocol" >&2; return 1; }
  [[ -x $real_supervisor ]] || { printf 'missing real supervisor: %s\n' "$real_supervisor" >&2; return 1; }

  write_mock tmux <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'remote-tmux' >>"$COMMAND_LOG"
for argument in "$@"; do printf ' <%q>' "$argument" >>"$COMMAND_LOG"; done
printf '\n' >>"$COMMAND_LOG"
case "${1:-}" in
  has-session)
    target=''
    while [[ $# -gt 0 ]]; do
      if [[ $1 == -t ]]; then target=${2:-}; break; fi
      shift
    done
    [[ -f "$XDG_STATE_HOME/adapter.session" && $(<"$XDG_STATE_HOME/adapter.session") == "$target" ]]
    ;;
  new-session)
    session=''
    arguments=("$@")
    while [[ $# -gt 0 ]]; do
      if [[ $1 == -s ]]; then session=${2:-}; fi
      [[ $1 == -- ]] && break
      shift
    done
    [[ -n $session ]] || exit 64
    printf '%s\n' "$session" >"$XDG_STATE_HOME/adapter.session"
    printf '%s\n' '%91' >"$XDG_STATE_HOME/adapter.pane"
    set -- "${arguments[@]}"
    while [[ $# -gt 0 && $1 != -- ]]; do shift; done
    if [[ ${1:-} == -- ]]; then shift; fi
    if [[ $# -gt 0 ]]; then "$@" </dev/null >/dev/null 2>&1; fi
    ;;
  display-message|list-panes) cat "$XDG_STATE_HOME/adapter.pane" ;;
  respawn-pane)
    while [[ $# -gt 0 && $1 != -- ]]; do shift; done
    [[ ${1:-} == -- ]] || exit 64
    shift
    "$@" </dev/null >/dev/null 2>&1
    ;;
  load-buffer) cat >"$XDG_STATE_HOME/adapter-delivered.stdin" ;;
  paste-buffer|send-keys) exit 0 ;;
  kill-session) rm -f "$XDG_STATE_HOME/adapter.session" ;;
esac
MOCK
  cp "$FAKE_BIN/tmux" "$REMOTE_BIN/tmux"
  write_mock claude <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'remote-claude' >>"$COMMAND_LOG"
for argument in "$@"; do printf ' <%q>' "$argument" >>"$COMMAND_LOG"; done
printf '\n' >>"$COMMAND_LOG"
cat >/dev/null
MOCK
  cp "$FAKE_BIN/claude" "$REMOTE_BIN/claude"

  write_mock remote-agent-v1 <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case ${1:-} in
  stage)
    printf '%s' "$2" >"$XDG_STATE_HOME/adapter-received-privacy"
    printf '%s' "$5" >"$XDG_STATE_HOME/adapter-received-authority"
    ;;
  inventory-path)
    case $3 in *PWNED*) printf '%s' "$3" >"$XDG_STATE_HOME/adapter-received-path" ;; esac
    ;;
  lease-provisional)
    printf '%s' "$4" >"$XDG_STATE_HOME/adapter-received-session"
    printf '%s' "$6" >"$XDG_STATE_HOME/adapter-received-owner"
    printf '%s' "$7" >"$XDG_STATE_HOME/adapter-received-authority"
    ;;
  git-align)
    printf '%s %s %s' "$2" "$3" "$4" >"$XDG_STATE_HOME/adapter-received-git-align"
    printf '%s\n' '{"align":"verified"}'
    exit 0
    ;;
esac
exec "$REAL_PROTOCOL" "$@"
MOCK
  cp "$FAKE_BIN/remote-agent-v1" "$REMOTE_BIN/remote-agent-v1"
  write_mock agent-supervisor <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == start ]]; then
  printf '%s' "$2" >"$XDG_STATE_HOME/adapter-received-supervisor-session"
  printf '%s' "$4" >"$XDG_STATE_HOME/adapter-received-root"
fi
exec "$REAL_SUPERVISOR" "$@"
MOCK
  cp "$FAKE_BIN/agent-supervisor" "$REMOTE_BIN/agent-supervisor"

  write_mock ssh <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
: "${COMMAND_LOG:?}" "${REAL_PROTOCOL:?}" "${REAL_SUPERVISOR:?}"
printf 'adapter-ssh' >>"$COMMAND_LOG"
for argument in "$@"; do printf ' <%q>' "$argument" >>"$COMMAND_LOG"; done
printf '\n' >>"$COMMAND_LOG"
shift
# OpenSSH joins all command operands with spaces, then the remote login shell
# parses that one string. Execute that exact boundary instead of preserving the
# caller's local argv array.
remote_command=$*
tee -a "$REMOTE_STATE/adapter-ssh.stdin" | \
  env -i HOME="$REMOTE_HOME" XDG_STATE_HOME="$REMOTE_STATE" PATH="$REMOTE_BIN:/usr/bin:/bin" \
    COMMAND_LOG="$COMMAND_LOG" REAL_PROTOCOL="$REAL_PROTOCOL" REAL_SUPERVISOR="$REAL_SUPERVISOR" \
    REMOTE_AGENT_ROOT_MIOSPOT="$REMOTE_ROOT" \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$REMOTE_ROOT" /bin/sh -c "$remote_command"
MOCK

  local secret='REAL-ADAPTER-STDIN-CANARY'
  local session=remote-agent--miospot--claude
  local safe_path="safe dir/O'Brien \$(touch PWNED).txt"
  REMOTE_ROOT="$REMOTE_HOME/Projects/miospot"
  mkdir -p "$REMOTE_ROOT" "$LOCAL_ROOT/${safe_path%/*}"
  mkdir -p "$REMOTE_ROOT/.remote-agent-stage"
  printf 'legacy\n' >"$REMOTE_ROOT/.remote-agent-stage/legacy.txt"
  printf 'quoted path\n' >"$LOCAL_ROOT/$safe_path"
  local authority_project="$REMOTE_STATE/orchestration/remote-agent/projects/miospot"
  mkdir -p "$authority_project"
  printf 'prior-common\n' >"$authority_project/common"
  printf 'prior-common\n' >"$authority_project/remote"
  printf '0\n' >"$authority_project/generation"
  printf '%s\n' "$secret" >"$CASE/prompt"
  MOCK_SAFE_PATH="$safe_path" expect_success equal start miospot claude --prompt-file "$CASE/prompt" || return 1
  [[ ! -e $REMOTE_ROOT/.remote-agent-stage ]] || return 1
  assert_lacks "$COMMAND_LOG" "$REMOTE_ROOT/.remote-agent-stage/" || return 1
  [[ ! -e $LOCAL_ROOT/PWNED ]] || return 1
  [[ $(<"$REMOTE_STATE/adapter.session") == "$session" ]] || return 1
  [[ $(<"$authority_project/lease-session") == "$session" ]] || return 1
  [[ $(<"$REMOTE_STATE/adapter-received-owner") == "$(<"$authority_project/lease-owner")" ]] || return 1
  [[ $(<"$REMOTE_STATE/adapter-received-owner") == host=*' pid='*' operation=start started='* ]] || return 1
  [[ $(<"$REMOTE_STATE/adapter-received-privacy") == $'umask 077\nmode=0700' ]] || return 1
  [[ $(<"$REMOTE_STATE/adapter-received-path") == "$safe_path" ]] || return 1
  [[ $(<"$REMOTE_STATE/adapter-received-session") == "$session" ]] || return 1
  [[ $(<"$REMOTE_STATE/adapter-received-git-align") == 'miospot main 0123456789abcdef0123456789abcdef01234567' ]] || return 1
  [[ $(<"$REMOTE_STATE/adapter-received-supervisor-session") == "$session" ]] || return 1
  [[ $(<"$REMOTE_STATE/adapter-received-root") == project-root-v1:miospot ]] || return 1
  [[ $(<"$REMOTE_STATE/adapter-received-authority") == authority-root-v1 ]] || return 1
  [[ $(<"$authority_project/inventory") == *"$safe_path"* ]] || return 1
  local canonical_remote_root
  canonical_remote_root=$(cd "$REMOTE_ROOT" && pwd -P)
  [[ $(<"$REMOTE_STATE/orchestration/agent-supervisor/sessions/$session/root") == "$canonical_remote_root" ]] || return 1
  assert_contains "$COMMAND_LOG" "remote-tmux <new-session> <-d> <-s> <$session>" || return 1
  assert_contains "$COMMAND_LOG" 'remote-claude <--yolo>' || return 1
  assert_lacks "$COMMAND_LOG" 'XDG_STATE_HOME' || return 1
  local trace="$REMOTE_STATE/orchestration/remote-agent/trace/miospot.trace"
  assert_contains "$trace" 'stage' || return 1
  assert_contains "$trace" 'mutex-acquire' || return 1
  assert_contains "$trace" 'lease-commit' || return 1
  cp "$authority_project/remote" "$authority_project/common"
  MOCK_SAFE_PATH="$safe_path" expect_success equal status miospot claude || return 1
  [[ $(wc -l <"$STDOUT" | tr -d ' ') -eq 1 ]] || return 1
  [[ $(wc -c <"$STDOUT" | tr -d ' ') -le 4096 ]] || return 1
  assert_contains "$STDOUT" '"relation":"equal"' || return 1
  assert_contains "$STDOUT" '"session":"running"' || return 1
  local status_epoch status_cursor status_bootstrap
  status_epoch=$(sed -n 's/.*"epoch":"\([^"]*\)".*/\1/p' "$STDOUT")
  status_cursor=$(sed -n 's/.*"cursor":\([0-9][0-9]*\).*/\1/p' "$STDOUT")
  status_bootstrap=$(sed -n 's/.*"bootstrapCursor":"\([^"]*\)".*/\1/p' "$STDOUT")
  [[ -n $status_epoch && -n $status_cursor && $status_bootstrap == "$status_epoch:$status_cursor" ]] || return 1
  assert_lacks "$STDOUT" '"scope"' || return 1
  assert_lacks "$STDOUT" '"kind"' || return 1
  expect_success equal send miospot claude --prompt-file "$CASE/prompt" || return 1
  assert_count "$trace" 'mutex-acquire' 2 || return 1
  assert_contains "$REMOTE_STATE/adapter-ssh.stdin" "$secret" || return 1
  assert_contains "$REMOTE_STATE/adapter-delivered.stdin" "$secret" || return 1
  assert_lacks "$COMMAND_LOG" "$secret" || return 1
  assert_lacks "$STDOUT" "$secret" || return 1
  assert_lacks "$STDERR" "$secret"
}

test_reclaim_stages_before_local_apply() {
  expect_success remote-only reclaim miospot claude || return 1
  local network_line verify_line local_apply_line
  network_line=$(grep -n '^rsync .*fixture-mini:' "$COMMAND_LOG" | head -1 | cut -d: -f1)
  verify_line=$(grep -n 'stage-verify' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  local_apply_line=$(grep -n '^rsync .*remote-agent\..*/inbound-stage/.*local-project/' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  [[ -n "$network_line" && -n "$verify_line" && -n "$local_apply_line" ]] || return 1
  [[ $network_line -lt $verify_line && $verify_line -lt $local_apply_line ]] || return 1
  ! sed -n "${network_line}p" "$COMMAND_LOG" | grep -Fq -- "$LOCAL_ROOT/"
}

test_reclaim_refuses_live_writer_before_transfer() {
  expect_failure live-writer reclaim miospot claude || return 1
  assert_contains "$STDERR" 'live exact project writer' || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1
  assert_lacks "$COMMAND_LOG" 'lease-release'
}

test_post_sync_mismatch_keeps_lease() {
  expect_failure post-mismatch reclaim miospot claude || return 1
  assert_contains "$STDERR" 'tampered.txt' || return 1
  assert_lacks "$COMMAND_LOG" 'lease-release'
}

run_test 'validates command, project, and harness' test_validation
run_test 'CLI host beats environment and config without production fallback' test_closed_mapping_and_host_precedence
run_test 'PROJECT mapping ignores decoy Git cwd for probes manifests digests and paths' test_project_mapping_ignores_decoy_git_cwd
run_test 'PROJECT mapping defaults safely and rejects symlink non-Git and nested roots' test_project_mapping_defaults_and_rejects_invalid_roots
run_test 'relative prompt files stay independent of the mapped local checkout' test_relative_prompt_file_is_independent_of_mapped_root
run_test 'hostile argv is rejected as data' test_hostile_argv_is_data
run_test 'project and harness map to an exact non-prefix session' test_exact_sessions
run_test 'inspect captures and never synchronizes' test_inspect_captures_without_sync
run_test 'inspect returns its bounded capture to the caller' test_inspect_capture_is_visible
run_test 'continue captures before sending and never synchronizes' test_continue_captures_before_send
run_test 'wait requires one safe cursor and a bounded timeout' test_wait_requires_a_bounded_cursor_and_timeout
run_test 'wait delegates every harness to its exact supervisor session' test_wait_delegates_exact_sessions_for_every_harness
run_test 'wait surfaces distinct timeout, exit, and lifecycle-event wakes' test_wait_surfaces_timeout_exit_and_event_wakes
run_test 'wait exit recheck refuses to quiesce a restarted session' test_wait_exit_recheck_refuses_a_restarted_session
run_test 'wait preserves monotonic cursors across supervisor restart epochs' test_wait_preserves_monotonic_restart_aware_cursors
run_test 'start and status expose a bounded restart-aware cursor usable directly by wait' test_start_and_status_expose_direct_wait_bootstrap_without_leakage
run_test 'wait returns bounded ephemeral capture without local persistence' test_wait_capture_is_visible_bounded_and_not_persisted_locally
run_test 'reveal attaches Terminal to the exact existing pane without mutation' test_reveal_delegates_exact_terminal_attachment_without_mutation
run_test 'prompt body is bounded to stdin and redacted from output and logs' test_prompt_is_bounded_and_redacted
run_test 'interrupt and kill cover control lifecycle and quiescence' test_control_lifecycle
run_test 'start stages local-only work then launches and commits the lease' test_start_local_only_transfer
run_test 'start accepts one bounded prompt and sends it after lease commit' test_start_accepts_optional_prompt
run_test 'the real supervisor vocabulary rejects the legacy launch verb' test_supervisor_rejects_legacy_launch_verb
run_test 'Codex control uses the shared supervisor rather than mini-agent' test_codex_uses_shared_supervisor
run_test 'start forwards exactly one --yolo to the supervisor' test_start_forwards_yolo_exactly
run_test 'failed supervisor start aborts the provisional lease before mutex release' test_failed_supervisor_start_aborts_provisional_lease
run_test 'helper-to-supervisor prompts travel only on stdin' test_supervisor_prompt_transport_is_stdin_only
run_test 'start refuses live writers and two-sided divergence with evidence' test_start_refuses_live_writer_and_divergence
run_test 'first contact adopts equality only without a live writer' test_first_contact_rules
run_test 'snapshots bind branch HEAD and NUL-safe strong content fingerprints' test_snapshot_is_strong_and_nul_safe
run_test 'equal, local-only, remote-only, and divergent states follow the matrix' test_divergence_matrix
run_test 'Mini authoritative mutex and generation CAS fail closed' test_remote_lease_mutex_and_cas
run_test 'writer records fail closed without stale-process inference' test_writer_records_fail_closed_without_stale_inference
run_test 'transfer universe, exclusions, plan bound, and exact deletions are explicit' test_transfer_universe_and_deletions
run_test 'ignored files require literal per-path approval' test_ignored_paths_need_exact_consent
run_test 'active plan mutation aborts and extra artifacts stay excluded' test_active_plan_is_bounded_and_stable
run_test 'payload staging and restore journal are private and verified' test_private_staging_and_restore_journal
run_test 'failed network staging releases the mutex before apply or lease commit' test_network_staging_failure_stops_before_apply
run_test 'failed destination apply restores before ownership can advance' test_failed_apply_restores_before_state_change
run_test 'nonzero apply status restores before ownership can advance' test_nonzero_apply_status_restores_before_state_change
run_test 'failed restore preserves authoritative recovery and mutex evidence' test_failed_restore_preserves_recovery_evidence
run_test 'reclaim pulls remote-only work and releases ownership last' test_reclaim_remote_only_release_last
run_test 'outbound handoff ships a bundle and requests exact branch HEAD alignment' test_outbound_handoff_requests_bundle_and_exact_git_alignment
run_test 'reclaim fast-forwards the MacBook branch and rebuilds a mixed index' test_reclaim_fast_forwards_branch_and_resets_index_mixed
run_test 'non-fast-forward reclaim refuses without mutating refs or index' test_reclaim_refuses_non_fast_forward_without_ref_mutation
run_test 'divergence CAS loss and recovery-required paths never mutate Git' test_refusal_paths_never_mutate_git_refs_or_index
run_test 'equal quiescent reclaim is release-only with zero transfer' test_equal_quiescent_reclaim_releases_without_transfer
run_test 'local-only quiescent reclaim is release-only with zero transfer' test_local_only_quiescent_reclaim_releases_without_transfer
run_test 'reclaim receives into verified private staging before local apply' test_reclaim_stages_before_local_apply
run_test 'reclaim refuses a live writer before transfer' test_reclaim_refuses_live_writer_before_transfer
run_test 'post-sync mismatch preserves the remote lease' test_post_sync_mismatch_keeps_lease
run_test 'real helper adapts to real protocol and supervisor over fake SSH' test_real_backend_adapter_over_fake_ssh

printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
