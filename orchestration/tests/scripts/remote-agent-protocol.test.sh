#!/usr/bin/env bash
set -euo pipefail

# Hermetic contract for the Mini-side authority used by remote-agent.sh.  The
# implementation is intentionally absent in the RED step; keep the executable
# gate after the fixture self-test so a missing backend is the only failure.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PROTOCOL="$SCRIPT_DIR/../../scripts/remote-agent-v1"
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
  REMOTE_ROOT="$CASE/worktree"
  TRACE_ROOT="$CASE/trace"
  AUTHORITY_PATH="$STATE_ROOT/orchestration/remote-agent"
  AUTHORITY_TOKEN=authority-root-v1
  STDOUT="$CASE/stdout"
  STDERR="$CASE/stderr"
  mkdir -p "$HOME_DIR" "$STATE_ROOT" "$REMOTE_ROOT" "$TRACE_ROOT"
  chmod 700 "$HOME_DIR" "$STATE_ROOT" "$REMOTE_ROOT" "$TRACE_ROOT"
  printf 'base\n' >"$REMOTE_ROOT/tracked.txt"
  : >"$STDOUT"
  : >"$STDERR"
}

run_protocol() {
  set +e
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_ROOT" \
    PATH="/usr/bin:/bin" \
    REMOTE_AGENT_ROOT_MIOSPOT="$REMOTE_ROOT" \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$REMOTE_ROOT" \
    REMOTE_AGENT_TRACE_ROOT="$TRACE_ROOT" \
    REMOTE_AGENT_TEST_FAULT="${REMOTE_AGENT_TEST_FAULT:-}" \
    REMOTE_AGENT_TEST_CAPTURE_FILE="${REMOTE_AGENT_TEST_CAPTURE_FILE:-}" \
    "$PROTOCOL" "$@" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
}

expect_success() { run_protocol "$@"; [[ $STATUS -eq 0 ]]; }
expect_failure() { run_protocol "$@"; [[ $STATUS -ne 0 ]]; }

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

all_modes_are() {
  local kind=$1 expected=$2 path mode
  while IFS= read -r path; do
    if [[ $kind == file ]]; then
      mode=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path")
    else
      mode=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path")
    fi
    [[ $mode == "$expected" ]] || return 1
  done < <(find "$STATE_ROOT" "$TRACE_ROOT" -type "$kind" -print)
}

private_state_fingerprint() {
  local path mode
  while IFS= read -r path; do
    mode=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path")
    if [[ -f $path ]]; then
      printf 'file %s %s ' "$mode" "$path"
      cksum "$path"
    else
      printf 'dir %s %s\n' "$mode" "$path"
    fi
  done < <(find "$STATE_ROOT" "$TRACE_ROOT" -mindepth 1 -print | LC_ALL=C sort)
}

test_closed_vocabulary_and_private_authority() {
  expect_failure unknown-operation || return 1
  assert_contains "$STDERR" 'usage' || return 1
  expect_failure probe manifest-nul other-project session main head common "$AUTHORITY_TOKEN" || return 1
  expect_failure probe manifest-nul miospot remote-agent--miospot--claude main head common "$AUTHORITY_PATH" || return 1
  assert_contains "$STDERR" 'authority root mismatch' || return 1
  expect_failure probe manifest-nul miospot remote-agent--miospot--claude main head common other-authority || return 1
  assert_contains "$STDERR" 'authority root mismatch' || return 1
  expect_success probe manifest-nul miospot remote-agent--miospot--claude main head common "$AUTHORITY_TOKEN" || return 1
  all_modes_are d 700 || return 1
  all_modes_are f 600
}

test_probe_classifies_all_relations() {
  expect_success adopt miospot common || return 1
  expect_success probe manifest-nul miospot remote-agent--miospot--claude main head common "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDOUT" '"relation":"equal"' || return 1
  expect_success probe manifest-nul miospot remote-agent--miospot--claude main head local-change "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDOUT" '"relation":"local-only"' || return 1
  expect_success stage $'umask 077\nmode=0700' miospot outbound "$AUTHORITY_TOKEN" || return 1
  printf 'remote-change\n' >"$REMOTE_ROOT/.remote-agent-stage/tracked.txt"
  expect_success restore-journal mode=0600 miospot || return 1
  expect_success stage-verify miospot remote-change || return 1
  expect_success apply-exact miospot remote-change || return 1
  expect_success probe manifest-nul miospot remote-agent--miospot--claude main head common "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDOUT" '"relation":"remote-only"' || return 1
  expect_success probe manifest-nul miospot remote-agent--miospot--claude main head local-change "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDOUT" '"relation":"diverged"'
}

test_mutex_is_atomic_under_concurrency() {
  local first=$CASE/first second=$CASE/second
  set +e
  env HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_ROOT" REMOTE_AGENT_ROOT_MIOSPOT="$REMOTE_ROOT" \
    "$PROTOCOL" mutex-acquire miospot owner-one "$AUTHORITY_TOKEN" >"$first" 2>&1 &
  local first_pid=$!
  env HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_ROOT" REMOTE_AGENT_ROOT_MIOSPOT="$REMOTE_ROOT" \
    "$PROTOCOL" mutex-acquire miospot owner-two "$AUTHORITY_TOKEN" >"$second" 2>&1 &
  local second_pid=$!
  wait "$first_pid"; local first_status=$?
  wait "$second_pid"; local second_status=$?
  set -e
  (( (first_status == 0) + (second_status == 0) == 1 )) || return 1
  assert_contains "$first" '"mutex"' || assert_contains "$second" '"mutex"'
}

test_generation_cas_never_clobbers() {
  expect_success adopt miospot common || return 1
  expect_success generation-check miospot 0 "$AUTHORITY_TOKEN" || return 1
  expect_failure generation-check miospot 1 "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDERR" 'generation mismatch' || return 1
  expect_success common-state-cas temp-rename miospot 0 "$AUTHORITY_TOKEN" || return 1
  expect_success generation-check miospot 1 "$AUTHORITY_TOKEN" || return 1
  expect_failure common-state-cas temp-rename miospot 0 "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDERR" 'generation' || assert_contains "$STDOUT" '"cas":"lost"'
}

test_staging_apply_and_verified_restore() {
  expect_success stage $'umask 077\nmode=0700' miospot outbound "$AUTHORITY_TOKEN" || return 1
  [[ -d $REMOTE_ROOT/.remote-agent-stage ]] || return 1
  printf 'replacement\n' >"$REMOTE_ROOT/.remote-agent-stage/tracked.txt"
  expect_success restore-journal mode=0600 miospot || return 1
  expect_success stage-verify miospot staged-digest || return 1
  REMOTE_AGENT_TEST_FAULT=apply-after-first-file run_protocol apply-exact miospot staged-digest
  [[ $STATUS -ne 0 ]] || return 1
  assert_contains "$STDOUT" '"restore":"verified"' || return 1
  [[ $(<"$REMOTE_ROOT/tracked.txt") == base ]]
}

test_operation_trace_is_private_and_ordered() {
  expect_success stage $'umask 077\nmode=0700' miospot outbound "$AUTHORITY_TOKEN" || return 1
  expect_success deletion-inventory miospot digest || return 1
  expect_success inventory-path miospot tracked.txt || return 1
  expect_success restore-journal mode=0600 miospot || return 1
  local trace
  trace=$(find "$TRACE_ROOT" -type f -print -quit)
  [[ -n $trace ]] || return 1
  assert_contains "$trace" 'stage' || return 1
  assert_contains "$trace" 'deletion-inventory' || return 1
  assert_contains "$trace" 'inventory-path' || return 1
  assert_contains "$trace" 'restore-journal' || return 1
  all_modes_are d 700 && all_modes_are f 600
}

test_lease_lifecycle_is_provisional_then_active() {
  local session=remote-agent--miospot--claude
  expect_success adopt miospot common || return 1
  expect_failure lease-provisional temp-rename miospot "$session" 0 owner other-authority || return 1
  assert_contains "$STDERR" 'authority root mismatch' || return 1
  expect_success lease-provisional temp-rename miospot "$session" 0 owner "$AUTHORITY_TOKEN" || return 1
  expect_success probe manifest-nul miospot "$session" main head common "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDOUT" '"lease":"provisional"' || return 1
  assert_contains "$STDOUT" '"writer":"provisional"' || return 1
  assert_lacks "$STDOUT" '"session"' || return 1
  expect_success lease-commit temp-rename miospot "$session" 0 "$AUTHORITY_TOKEN" || return 1
  expect_success probe manifest-nul miospot "$session" main head common "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDOUT" '"lease":"active"' || return 1
  assert_contains "$STDOUT" '"writer":"live"' || return 1
  assert_lacks "$STDOUT" '"session"'
}

test_lease_abort_clears_only_matching_provisional_state() {
  local session=remote-agent--miospot--claude trace state
  state="$AUTHORITY_PATH/projects/miospot"
  expect_success adopt miospot common || return 1
  expect_success lease-provisional temp-rename miospot "$session" 0 owner "$AUTHORITY_TOKEN" || return 1
  printf 'preserve-me\n' >"$state/unrelated-evidence"

  expect_failure lease-abort temp-rename miospot "$session" 0 other-authority || return 1
  assert_contains "$STDERR" 'authority root mismatch' || return 1
  expect_failure lease-abort temp-rename miospot remote-agent--miospot--codex 0 "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDERR" 'lease session mismatch' || return 1
  expect_failure lease-abort temp-rename miospot "$session" 1 "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDERR" 'lease generation mismatch' || return 1

  expect_success lease-abort temp-rename miospot "$session" 0 "$AUTHORITY_TOKEN" || return 1
  [[ ! -e $state/lease-state && ! -e $state/lease-session ]] || return 1
  [[ ! -e $state/lease-owner && ! -e $state/lease-generation ]] || return 1
  [[ $(<"$state/unrelated-evidence") == preserve-me ]] || return 1
  trace="$TRACE_ROOT/miospot.trace"
  [[ $(tail -n 1 "$trace") == lease-abort ]] || return 1
  [[ $(grep -Fc lease-abort "$trace") -eq 1 ]] || return 1
  assert_lacks "$trace" "$session" || return 1
  assert_lacks "$trace" owner || return 1

  expect_failure lease-abort temp-rename miospot "$session" 0 "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDERR" 'no provisional lease' || return 1
  expect_success lease-provisional temp-rename miospot "$session" 0 owner "$AUTHORITY_TOKEN" || return 1
  expect_success lease-commit temp-rename miospot "$session" 0 "$AUTHORITY_TOKEN" || return 1
  expect_failure lease-abort temp-rename miospot "$session" 0 "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDERR" 'provisional lease required' || return 1
  [[ $(<"$state/lease-state") == active ]]
}

test_quiescence_precedes_release_and_release_is_last() {
  local session=remote-agent--miospot--claude trace state=$AUTHORITY_PATH/projects/miospot
  expect_failure quiescent "$session" "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDERR" 'active lease required' || return 1
  expect_success adopt miospot common || return 1
  expect_success lease-provisional temp-rename miospot "$session" 0 owner "$AUTHORITY_TOKEN" || return 1
  expect_failure quiescent "$session" "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDERR" 'active lease required' || return 1
  expect_success lease-commit temp-rename miospot "$session" 0 "$AUTHORITY_TOKEN" || return 1
  expect_failure lease-release temp-rename miospot "$session" "$AUTHORITY_TOKEN" || return 1
  expect_failure quiescent "$session" other-authority || return 1
  assert_contains "$STDERR" 'authority root mismatch' || return 1
  expect_failure quiescent remote-agent--miospot--codex "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDERR" 'lease session mismatch' || return 1
  [[ ! -e $state/quiescent ]] || return 1
  expect_success quiescent "$session" "$AUTHORITY_TOKEN" || return 1
  expect_success quiescent "$session" "$AUTHORITY_TOKEN" || return 1
  expect_success probe manifest-nul miospot "$session" main head common "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDOUT" '"writer":"quiescent"' || return 1
  expect_success post-sync-verify miospot common || return 1
  expect_success lease-release temp-rename miospot "$session" "$AUTHORITY_TOKEN" || return 1
  trace=$(find "$TRACE_ROOT" -type f -print -quit)
  [[ $(tail -n 1 "$trace") == *lease-release* ]] || return 1
  expect_success probe manifest-nul miospot "$session" main head common "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDOUT" '"writer":"none"'
}

test_release_only_verification_preserves_common_and_remote() {
  local session=remote-agent--miospot--codex state=$AUTHORITY_PATH/projects/miospot
  expect_success adopt miospot common || return 1
  expect_success lease-provisional temp-rename miospot "$session" 0 owner "$AUTHORITY_TOKEN" || return 1
  expect_success lease-commit temp-rename miospot "$session" 0 "$AUTHORITY_TOKEN" || return 1
  expect_success quiescent "$session" "$AUTHORITY_TOKEN" || return 1

  printf 'remote-drift\n' >"$state/remote"
  expect_failure release-only-verify miospot "$session" "$AUTHORITY_TOKEN" || return 1
  assert_contains "$STDERR" 'remote state does not match common state' || return 1
  [[ ! -e $state/post-sync-verified ]] || return 1
  printf 'common\n' >"$state/remote"
  expect_success release-only-verify miospot "$session" "$AUTHORITY_TOKEN" || return 1
  [[ $(<"$state/common") == common ]] || return 1
  [[ $(<"$state/remote") == common ]] || return 1
  [[ $(<"$state/post-sync-verified") == common ]] || return 1
  expect_success lease-release temp-rename miospot "$session" "$AUTHORITY_TOKEN" || return 1
}

test_capture_is_exact_and_bounded() {
  local session=remote-agent--miospot--grok capture=$CASE/capture
  for index in $(seq 1 120); do printf 'line-%03d xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' "$index"; done >"$capture"
  REMOTE_AGENT_TEST_CAPTURE_FILE="$capture" run_protocol capture "$session"
  [[ $STATUS -eq 0 ]] || return 1
  [[ $(wc -l <"$STDOUT" | tr -d ' ') -le 40 ]] || return 1
  [[ $(wc -c <"$STDOUT" | tr -d ' ') -le 4096 ]] || return 1
  assert_contains "$STDOUT" 'line-120' || return 1
  assert_lacks "$STDOUT" 'line-001'
}

test_exact_session_atoms_only() {
  expect_success capture remote-agent--orchestration--codex || return 1
  expect_failure capture remote-agent--orchestration || return 1
  expect_failure capture remote-agent--orchestration--codex-extra || return 1
  expect_failure capture 'remote-agent--miospot--claude;touch-pwned'
}

test_lifecycle_wait_and_reveal_are_not_sync_protocol_operations() {
  local before after session=remote-agent--miospot--claude
  expect_success adopt miospot common || return 1
  before=$(private_state_fingerprint) || return 1
  expect_failure wait "$session" epoch-1:0 30 || return 1
  assert_contains "$STDERR" 'usage' || return 1
  expect_failure enqueue "$REMOTE_ROOT" '%7' main stop || return 1
  assert_contains "$STDERR" 'usage' || return 1
  expect_failure reveal "$session" || return 1
  assert_contains "$STDERR" 'usage' || return 1
  after=$(private_state_fingerprint) || return 1
  [[ $after == "$before" ]]
}

# Prove the shell fixture itself before checking the deliberately missing file.
setup_case fixture-self-test
printf 'fixture-ok\n' >"$REMOTE_ROOT/tracked.txt"
if [[ $(<"$REMOTE_ROOT/tracked.txt") == fixture-ok ]] && all_modes_are d 700; then
  pass 'hermetic protocol fixture self-test'
else
  fail 'hermetic protocol fixture self-test' 'private fixture could not be initialized'
fi

if [[ ! -x $PROTOCOL ]]; then
  fail 'Mini protocol executable exists' "missing executable: $PROTOCOL"
  printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
  exit 1
fi

run_test 'vocabulary is closed and authoritative state is private' test_closed_vocabulary_and_private_authority
run_test 'probe classifies equal, local-only, remote-only, and diverged' test_probe_classifies_all_relations
run_test 'the project mutex has exactly one concurrent winner' test_mutex_is_atomic_under_concurrency
run_test 'generation CAS fails closed without clobbering state' test_generation_cas_never_clobbers
run_test 'private staging applies exactly and restores on failure' test_staging_apply_and_verified_restore
run_test 'the private operation trace records ordered mutations' test_operation_trace_is_private_and_ordered
run_test 'a lease advances from provisional to active/live' test_lease_lifecycle_is_provisional_then_active
run_test 'lease abort is exact, value-free, and provisional-only' test_lease_abort_clears_only_matching_provisional_state
run_test 'quiescence and verification precede release-last' test_quiescence_precedes_release_and_release_is_last
run_test 'release-only verification preserves common and remote fingerprints' test_release_only_verification_preserves_common_and_remote
run_test 'capture exposes only the newest 40 lines and 4 KiB' test_capture_is_exact_and_bounded
run_test 'session controls accept only exact project/harness names' test_exact_session_atoms_only
run_test 'wait, enqueue, and reveal never enter sync/lease authority' test_lifecycle_wait_and_reveal_are_not_sync_protocol_operations

printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
