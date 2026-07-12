#!/usr/bin/env bash
set -euo pipefail

# RED worker contract.  These are the step-1 start/reclaim apply-and-verify
# fidelity assertions re-hosted from remote-agent.test.sh.  The desktop relay
# no longer performs any checkout, bundle, alignment, or reclaim work.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
MIRROR_WORKER="$SCRIPT_DIR/../../scripts/mirror-worker"
PASS_COUNT=0
FAIL_COUNT=0
SUITE=$(mktemp -d)
SUITE=$(cd "$SUITE" && pwd -P)
trap 'rm -rf "$SUITE"' EXIT

pass() { printf 'PASS %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_contains() { grep -Fq -- "$2" "$1"; }
assert_lacks() { ! grep -Fq -- "$2" "$1"; }
require_worker() {
  [[ -x $MIRROR_WORKER ]] || {
    printf 'mirror-worker: missing executable: %s\n' "$MIRROR_WORKER" >&2
    return 1
  }
}

setup_case() {
  local name=$1
  CASE="$SUITE/$name"
  HOME_DIR="$CASE/home"
  STATE_DIR="$CASE/state"
  LOCAL_ROOT="$CASE/local-project"
  FAKE_BIN="$CASE/bin"
  COMMAND_LOG="$CASE/commands.log"
  GIT_REF_LOG="$CASE/git-ref-operations.log"
  GIT_STATUS_FILE="$CASE/git-status.nul"
  SSH_STDIN="$CASE/ssh.stdin"
  STDOUT="$CASE/stdout"
  STDERR="$CASE/stderr"
  mkdir -p "$HOME_DIR" "$STATE_DIR" "$LOCAL_ROOT" "$FAKE_BIN"
  mkdir -p "$LOCAL_ROOT/node_modules" "$HOME_DIR/Projects/miospot"
  printf '.env\nnode_modules/\n' >"$LOCAL_ROOT/.gitignore"
  printf 'tracked\n' >"$LOCAL_ROOT/README.md"
  printf 'untracked\n' >"$LOCAL_ROOT/notes.txt"
  printf 'ignored secret\n' >"$LOCAL_ROOT/.env"
  printf 'dependency\n' >"$LOCAL_ROOT/node_modules/dependency.js"
  cp "$LOCAL_ROOT/.gitignore" "$HOME_DIR/Projects/miospot/.gitignore"
  cp "$LOCAL_ROOT/README.md" "$HOME_DIR/Projects/miospot/README.md"
  cp "$LOCAL_ROOT/notes.txt" "$HOME_DIR/Projects/miospot/notes.txt"
  : >"$COMMAND_LOG"
  : >"$GIT_REF_LOG"
  : >"$GIT_STATUS_FILE"
  : >"$SSH_STDIN"
  : >"$STDOUT"
  : >"$STDERR"

  cat >"$FAKE_BIN/ssh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
: "${COMMAND_LOG:?}" "${SSH_STDIN:?}"
host=${1:-}
shift || true
remote_command=$*
parsed=$(mktemp "${TMPDIR:-/tmp}/mirror-argv.XXXXXX")
/bin/sh -c "set -- $remote_command
printf '%s\\0' \"\$@\"" >"$parsed"
argv=()
while IFS= read -r -d '' argument; do argv+=("$argument"); done <"$parsed"
rm -f "$parsed"
printf 'ssh <%s>' "$host" >>"$COMMAND_LOG"
for argument in "${argv[@]}"; do printf ' <%s>' "$argument" >>"$COMMAND_LOG"; done
printf '\n' >>"$COMMAND_LOG"
cat >>"$SSH_STDIN"

# Optional: forward mirror-next to a real workflow-registry (diverged proof).
if [[ ${USE_REAL_REGISTRY:-0} == 1 && ${argv[0]:-} == workflow-registry && ${argv[1]:-} == mirror-next ]]; then
  : "${REAL_REGISTRY:?}" "${REAL_REGISTRY_ENV_DIR:?}"
  # shellcheck disable=SC1090
  source "$REAL_REGISTRY_ENV_DIR/env.sh"
  set +e
  out=$("$REAL_REGISTRY" "${argv[@]:1}" 2>"$REAL_REGISTRY_ENV_DIR/stderr")
  st=$?
  set -e
  printf '%s\n' "$out"
  if [[ -s $REAL_REGISTRY_ENV_DIR/stderr ]]; then
    cat "$REAL_REGISTRY_ENV_DIR/stderr" >&2
  fi
  exit "$st"
fi

operation=
claim_project_arg=
for argument in "${argv[@]}"; do
  case $argument in
    mirror-next|mirror-ack|git-align|populate-inbound|stage|deletion-inventory|inventory-path|restore-journal|apply-exact|stage-verify|restore-verify|recovery-required|lease-release|probe)
      operation=$argument
      ;;
    miospot|orchestration)
      if [[ $operation == mirror-next && -z $claim_project_arg ]]; then
        claim_project_arg=$argument
      fi
      ;;
  esac
done

# Loop-mode counter for multi-job scenarios (same process, consecutive claims).
claim_count_file=${CLAIM_COUNT_FILE:-}
if [[ $operation == mirror-next && -n $claim_count_file ]]; then
  count=0
  [[ -f $claim_count_file ]] && count=$(cat "$claim_count_file")
  count=$((count + 1))
  printf '%s\n' "$count" >"$claim_count_file"
fi

case $operation in
  mirror-next)
    case ${WORKER_SCENARIO:-outbound} in
      outbound|local-only|network-failure|apply-fail-restore-verified|apply-fail-restore-failed|align-fail-restore-verified|align-fail-restore-failed|deletion-limitation)
        printf '%s\n' '{"ok":true,"jobId":"job-outbound","workflowId":"wf-miospot-20260711T151201Z-9f3c","project":"miospot","direction":"outbound","claimToken":"ct-test-outbound","branch":"feature/handoff","head":"1111111111111111111111111111111111111111"}'
        ;;
      inbound|remote-only|non-fast-forward|post-mismatch)
        printf '%s\n' '{"ok":true,"jobId":"job-inbound","workflowId":"wf-miospot-20260711T151201Z-9f3c","project":"miospot","direction":"inbound","claimToken":"ct-test-inbound","branch":"main","head":"fedcba9876543210fedcba9876543210fedcba98"}'
        ;;
      ignored-exception)
        printf '%s\n' '{"ok":true,"jobId":"job-seed","workflowId":"wf-miospot-20260711T151201Z-9f3c","project":"miospot","direction":"outbound","claimToken":"ct-test-seed","branch":"main","head":"0123456789abcdef0123456789abcdef01234567","includeIgnored":".env","approveIgnored":".env"}'
        ;;
      tokenless)
        printf '%s\n' '{"ok":true,"jobId":"job-tokenless","workflowId":"wf-miospot-20260711T151201Z-9f3c","project":"miospot","direction":"outbound","branch":"main","head":"0123456789abcdef0123456789abcdef01234567"}'
        ;;
      stage-path-missing)
        printf '%s\n' '{"ok":true,"jobId":"job-stage","workflowId":"wf-miospot-20260711T151201Z-9f3c","project":"miospot","direction":"outbound","claimToken":"ct-test-stage","branch":"main","head":"0123456789abcdef0123456789abcdef01234567"}'
        ;;
      empty-queue)
        printf '%s\n' '{"ok":true,"jobId":null,"status":"empty"}'
        ;;
      empty-miospot-then-orchestration)
        # miospot empty; orchestration has the only pending job. Proves drain_once
        # advances past an empty project instead of stranding the whole loop.
        if [[ ${claim_project_arg:-} == orchestration ]]; then
          printf '%s\n' '{"ok":true,"jobId":"job-orch-1","workflowId":"wf-orch-20260711T151201Z-9f3c","project":"orchestration","direction":"outbound","claimToken":"ct-orch-1","branch":"main","head":"1111111111111111111111111111111111111111"}'
        else
          printf '%s\n' '{"ok":true,"jobId":null,"status":"empty"}'
        fi
        ;;
      loop-inbound)
        count=$(cat "$claim_count_file")
        if [[ $count -eq 1 ]]; then
          printf '%s\n' '{"ok":true,"jobId":"job-inbound-1","workflowId":"wf-miospot-20260711T151201Z-9f3c","project":"miospot","direction":"inbound","claimToken":"ct-loop-1","branch":"main","head":"fedcba9876543210fedcba9876543210fedcba98"}'
        elif [[ $count -eq 2 ]]; then
          # Second project in PROJECTS gets empty on first drain; count 2 is
          # miospot again on the second drain_once iteration.
          printf '%s\n' '{"ok":true,"jobId":"job-inbound-2","workflowId":"wf-miospot-20260711T151201Z-9f3c","project":"miospot","direction":"inbound","claimToken":"ct-loop-2","branch":"main","head":"fedcba9876543210fedcba9876543210fedcba98"}'
        else
          printf '%s\n' '{"ok":true,"jobId":null,"status":"empty"}'
        fi
        ;;
      diverged|cas-lost|recovery-required|live-writer)
        printf '{"ok":false,"error":"%s"}\n' "$WORKER_SCENARIO"
        exit 65
        ;;
    esac
    ;;
  stage)
    if [[ ${WORKER_SCENARIO:-} == stage-path-missing ]]; then
      printf '%s\n' '{"ok":true,"status":"staged"}'
    else
      printf '%s\n' '{"stagePath":"/tmp/orchestration-test-stage/miospot"}'
    fi
    ;;
  apply-exact)
    case ${WORKER_SCENARIO:-} in
      apply-fail-restore-verified)
        printf '%s\n' '{"apply":"failed","restore":"verified"}'
        exit 1
        ;;
      apply-fail-restore-failed)
        printf '%s\n' '{"apply":"failed","restore":"failed"}'
        exit 1
        ;;
      *)
        printf '%s\n' '{"ok":true,"apply":"verified"}'
        ;;
    esac
    ;;
  git-align)
    case ${WORKER_SCENARIO:-} in
      align-fail-restore-verified)
        printf '%s\n' '{"align":"failed","restore":"verified"}'
        exit 1
        ;;
      align-fail-restore-failed)
        printf '%s\n' '{"align":"failed","restore":"failed"}'
        exit 1
        ;;
      *)
        printf '%s\n' '{"ok":true,"align":"verified"}'
        ;;
    esac
    ;;
  recovery-required)
    printf '%s\n' '{"ok":true,"status":"recovery-required"}'
    ;;
  restore-verify)
    printf '%s\n' '{"ok":true,"restore":"verified"}'
    ;;
  mirror-ack)
    if [[ ${WORKER_SCENARIO:-} == post-mismatch ]]; then
      printf '%s\n' '{"ok":false,"error":"post-sync-mismatch","paths":["tampered.txt"]}'
      exit 65
    fi
    printf '%s\n' '{"ok":true,"status":"verified"}'
    ;;
  *) printf '%s\n' '{"ok":true,"status":"verified"}' ;;
esac
MOCK
  chmod +x "$FAKE_BIN/ssh"

  cat >"$FAKE_BIN/rsync" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'rsync' >>"$COMMAND_LOG"
for argument in "$@"; do printf ' <%s>' "$argument" >>"$COMMAND_LOG"; done
printf '\n' >>"$COMMAND_LOG"
[[ ${RSYNC_FAIL:-0} == 0 ]]
MOCK
  chmod +x "$FAKE_BIN/rsync"

  cat >"$FAKE_BIN/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
: "${COMMAND_LOG:?}" "${GIT_REF_LOG:?}"
printf 'git cwd=<%s>' "$PWD" >>"$COMMAND_LOG"
for argument in "$@"; do printf ' <%s>' "$argument" >>"$COMMAND_LOG"; done
printf '\n' >>"$COMMAND_LOG"

case "$*" in
  'rev-parse --show-toplevel')
    [[ $PWD != ${MOCK_GIT_FAIL_ROOT:-} ]] || exit 128
    printf '%s\n' "${MOCK_GIT_TOPLEVEL:-$PWD}"
    ;;
  'rev-parse --abbrev-ref HEAD'|'symbolic-ref --quiet --short HEAD') printf '%s\n' "${MOCK_GIT_BRANCH:-main}" ;;
  'rev-parse HEAD') printf '%s\n' "${MOCK_GIT_HEAD:-0123456789abcdef0123456789abcdef01234567}" ;;
  'symbolic-ref --quiet HEAD') printf 'refs/heads/%s\n' "${MOCK_GIT_BRANCH:-main}" ;;
  'status --porcelain=v1 -z') cat "$GIT_STATUS_FILE" ;;
  'ls-files -z') printf 'README.md\0.gitignore\0' ;;
  'ls-files --others --exclude-standard -z') printf 'notes.txt\0' ;;
  'check-ignore '*) [[ ${*: -1} == .env || ${*: -1} == node_modules/* ]] ;;
  'merge-base --is-ancestor '*) [[ ${MOCK_GIT_ANCESTOR:-1} == 1 ]] || exit 1 ;;
  'bundle create '*) : >"${3:?bundle destination}" ;;
  'bundle list-heads '*) printf '%s refs/heads/%s\n' "$REMOTE_GIT_HEAD" "$REMOTE_GIT_BRANCH" ;;
  'bundle verify '*) ;;
esac

case ${1:-} in
  update-ref|reset|fetch|checkout|switch)
    printf 'git' >>"$GIT_REF_LOG"
    for argument in "$@"; do printf ' <%s>' "$argument" >>"$GIT_REF_LOG"; done
    printf '\n' >>"$GIT_REF_LOG"
    ;;
  symbolic-ref)
    if [[ ${2:-} != --quiet ]]; then
      printf 'git' >>"$GIT_REF_LOG"
      for argument in "$@"; do printf ' <%s>' "$argument" >>"$GIT_REF_LOG"; done
      printf '\n' >>"$GIT_REF_LOG"
    fi
    ;;
esac
MOCK
  chmod +x "$FAKE_BIN/git"

  for command in shasum sha256sum; do
    cat >"$FAKE_BIN/$command" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
name=${0##*/}
printf '%s cwd=<%s>' "$name" "$PWD" >>"$COMMAND_LOG"
for argument in "$@"; do printf ' <%s>' "$argument" >>"$COMMAND_LOG"; done
printf '\n' >>"$COMMAND_LOG"
printf '%s  -\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
MOCK
    chmod +x "$FAKE_BIN/$command"
  done
}

run_worker() {
  local scenario=$1
  local worker_root
  local -a root_environment=()
  shift || true
  worker_root=${WORKER_ROOT_OVERRIDE:-$LOCAL_ROOT}
  if [[ ${WORKER_USE_DEFAULT_ROOT:-0} != 1 ]]; then
    root_environment+=(
      "LOCAL_MIOSPOT_ROOT=$worker_root"
      "LOCAL_ORCHESTRATION_ROOT=$worker_root"
      "LOCAL_ROOT=$worker_root"
    )
  fi
  : >"$COMMAND_LOG"
  : >"$GIT_REF_LOG"
  : >"$SSH_STDIN"
  : >"$STDOUT"
  : >"$STDERR"
  set +e
  # root_environment may be empty (default-root case); expand safely under set -u.
  env -i \
    HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_DIR" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    REMOTE_AGENT_HOST=fixture-mini \
    COMMAND_LOG="$COMMAND_LOG" \
    GIT_REF_LOG="$GIT_REF_LOG" \
    GIT_STATUS_FILE="$GIT_STATUS_FILE" \
    SSH_STDIN="$SSH_STDIN" \
    WORKER_SCENARIO="$scenario" \
    MOCK_GIT_FAIL_ROOT="${MOCK_GIT_FAIL_ROOT:-}" \
    MOCK_GIT_TOPLEVEL="${MOCK_GIT_TOPLEVEL:-$worker_root}" \
    MOCK_GIT_BRANCH="${MOCK_GIT_BRANCH:-main}" \
    MOCK_GIT_HEAD="${MOCK_GIT_HEAD:-0123456789abcdef0123456789abcdef01234567}" \
    MOCK_GIT_ANCESTOR="${MOCK_GIT_ANCESTOR:-1}" \
    REMOTE_GIT_BRANCH="${REMOTE_GIT_BRANCH:-main}" \
    REMOTE_GIT_HEAD="${REMOTE_GIT_HEAD:-fedcba9876543210fedcba9876543210fedcba98}" \
    RSYNC_FAIL="${RSYNC_FAIL:-0}" \
    WORKER_ROOT_OVERRIDE="${WORKER_ROOT_OVERRIDE:-}" \
    CLAIM_COUNT_FILE="${CLAIM_COUNT_FILE:-}" \
    USE_REAL_REGISTRY="${USE_REAL_REGISTRY:-0}" \
    REAL_REGISTRY="${REAL_REGISTRY:-}" \
    REAL_REGISTRY_ENV_DIR="${REAL_REGISTRY_ENV_DIR:-}" \
    MIRROR_WORKER_MAX_JOBS="${MIRROR_WORKER_MAX_JOBS:-}" \
    MIRROR_WORKER_LOOP_SLEEP="${MIRROR_WORKER_LOOP_SLEEP:-0}" \
    ${root_environment[@]+"${root_environment[@]}"} \
    "$MIRROR_WORKER" --host fixture-mini "$@" >"$STDOUT" 2>"$STDERR"
  STATUS=$?
  set -e
}

expect_success() {
  local scenario=$1
  shift || true
  run_worker "$scenario" --once "$@"
  [[ $STATUS -eq 0 ]]
}

expect_failure() {
  local scenario=$1
  shift || true
  run_worker "$scenario" --once "$@"
  [[ $STATUS -ne 0 ]]
}

run_test() {
  local name=$1
  shift
  setup_case "test-$((PASS_COUNT + FAIL_COUNT + 1))"
  STATUS=0
  if "$@"; then pass "$name"; else fail "$name" "status=$STATUS stdout=$(tr '\n' ' ' <"$STDOUT") stderr=$(tr '\n' ' ' <"$STDERR")"; fi
}

test_worker_roots_default_and_invalid_refusals() {
  require_worker || return 1
  local default_root="$HOME_DIR/Projects/miospot"
  WORKER_USE_DEFAULT_ROOT=1 MOCK_GIT_TOPLEVEL="$default_root" \
    expect_success local-only || return 1
  assert_contains "$COMMAND_LOG" "git cwd=<$default_root> <rev-parse> <--show-toplevel>" || return 1

  : >"$COMMAND_LOG"
  local symlink_root="$CASE/symlink-root"
  ln -s "$LOCAL_ROOT" "$symlink_root"
  WORKER_ROOT_OVERRIDE="$symlink_root" expect_failure local-only || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1

  : >"$COMMAND_LOG"
  local non_git_root="$CASE/non-git-root"
  mkdir -p "$non_git_root"
  WORKER_ROOT_OVERRIDE="$non_git_root" MOCK_GIT_FAIL_ROOT="$non_git_root" \
    expect_failure local-only || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1

  : >"$COMMAND_LOG"
  local parent_root="$CASE/parent-root" nested_root="$CASE/parent-root/nested"
  mkdir -p "$nested_root"
  WORKER_ROOT_OVERRIDE="$nested_root" MOCK_GIT_TOPLEVEL="$parent_root" \
    expect_failure local-only || return 1
  assert_lacks "$COMMAND_LOG" 'rsync'
}

test_snapshot_is_strong_and_nul_safe() {
  require_worker || return 1
  expect_success local-only || return 1
  assert_contains "$COMMAND_LOG" '<rev-parse> <HEAD>' || return 1
  assert_contains "$COMMAND_LOG" '<rev-parse> <--abbrev-ref> <HEAD>' || return 1
  assert_contains "$COMMAND_LOG" '<ls-files> <-z>' || return 1
  # Strong digest is a local stream hash of the snapshot payload, never a
  # fabricated remote-agent-v1 "fingerprint" verb outside the closed vocabulary.
  { assert_contains "$COMMAND_LOG" 'shasum' || assert_contains "$COMMAND_LOG" 'sha256sum'; } || return 1
  assert_lacks "$COMMAND_LOG" '<fingerprint>' || return 1
  assert_lacks "$COMMAND_LOG" '<remote-agent-v1> <fingerprint>' || return 1
  assert_contains "$COMMAND_LOG" '<--local-digest>' || return 1
  assert_lacks "$COMMAND_LOG" '--ignore-times'
}

test_transfer_universe_and_deletions() {
  require_worker || return 1
  local evidence="$CASE/transfer-evidence"
  expect_success local-only || return 1
  cat "$COMMAND_LOG" "$SSH_STDIN" >"$evidence"
  assert_contains "$evidence" 'README.md' || return 1
  assert_contains "$evidence" 'notes.txt' || return 1
  assert_contains "$COMMAND_LOG" '<deletion-inventory>' || return 1
  assert_lacks "$evidence" 'node_modules' || return 1
  assert_lacks "$evidence" '.env'
}

test_private_staging_and_restore_journal() {
  require_worker || return 1
  expect_success local-only || return 1
  assert_contains "$COMMAND_LOG" 'umask 077' || return 1
  assert_contains "$COMMAND_LOG" '<stage-verify>' || return 1
  assert_contains "$COMMAND_LOG" '<restore-journal>' || return 1
  assert_contains "$COMMAND_LOG" 'mode=0600' || return 1
  assert_contains "$COMMAND_LOG" '<apply-exact>'
}

test_network_staging_failure_stops_before_apply() {
  require_worker || return 1
  RSYNC_FAIL=1 run_worker network-failure --once
  [[ $STATUS -ne 0 ]] || return 1
  assert_contains "$COMMAND_LOG" 'rsync' || return 1
  assert_lacks "$COMMAND_LOG" '<stage-verify>' || return 1
  assert_lacks "$COMMAND_LOG" '<apply-exact>' || return 1
  assert_lacks "$COMMAND_LOG" '<mirror-ack>' || return 1
  assert_lacks "$COMMAND_LOG" '<lease-release>'
}

test_claim_direction_is_computed_at_claim_time() {
  require_worker || return 1
  expect_success local-only || return 1
  assert_contains "$COMMAND_LOG" '<mirror-next>' || return 1
  assert_contains "$COMMAND_LOG" '<git-align>' || return 1

  : >"$COMMAND_LOG"
  expect_success remote-only || return 1
  assert_contains "$COMMAND_LOG" '<mirror-next>' || return 1
  assert_contains "$COMMAND_LOG" '<populate-inbound>' || return 1

  : >"$COMMAND_LOG"
  expect_failure diverged || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1
  assert_lacks "$COMMAND_LOG" '<lease-release>'
}

test_claim_refusal_precedes_worker_transfer() {
  require_worker || return 1
  expect_failure live-writer || return 1
  assert_contains "$STDERR" 'live-writer' || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1
  assert_lacks "$COMMAND_LOG" '<git-align>' || return 1
  assert_lacks "$COMMAND_LOG" '<populate-inbound>' || return 1
  assert_lacks "$COMMAND_LOG" '<mirror-ack>' || return 1
  assert_lacks "$COMMAND_LOG" '<lease-release>'
}

test_post_sync_mismatch_keeps_lease() {
  require_worker || return 1
  expect_failure post-mismatch || return 1
  assert_contains "$COMMAND_LOG" '<mirror-ack>' || return 1
  assert_contains "$STDERR" 'tampered.txt' || return 1
  assert_lacks "$COMMAND_LOG" '<lease-release>'
}

# Re-hosted verbatim from the step-1 behavior suite: the command under test is
# now the worker's outbound claim, but every fidelity assertion is unchanged.
test_outbound_handoff_requests_bundle_and_exact_git_alignment() {
  require_worker || return 1
  MOCK_GIT_BRANCH=feature/handoff
  MOCK_GIT_HEAD=1111111111111111111111111111111111111111
  printf ' M README.md\0?? notes.txt\0' >"$GIT_STATUS_FILE"
  expect_success outbound || return 1
  assert_contains "$COMMAND_LOG" '<bundle> <create>' || return 1
  assert_contains "$COMMAND_LOG" '<git-align> <miospot> <feature/handoff> <1111111111111111111111111111111111111111>' || return 1
  assert_contains "$COMMAND_LOG" '<status> <--porcelain=v1> <-z>'
}

# Re-hosted verbatim from the step-1 inbound behavior suite.
test_reclaim_fast_forwards_branch_and_resets_index_mixed() {
  require_worker || return 1
  local mini_head=fedcba9876543210fedcba9876543210fedcba98
  MOCK_GIT_BRANCH=main
  MOCK_GIT_HEAD=0123456789abcdef0123456789abcdef01234567
  REMOTE_GIT_BRANCH=main
  REMOTE_GIT_HEAD=$mini_head
  expect_success inbound || return 1
  assert_contains "$COMMAND_LOG" "<populate-inbound> <miospot> <main> <$mini_head>" || return 1
  assert_contains "$COMMAND_LOG" "<merge-base> <--is-ancestor> <0123456789abcdef0123456789abcdef01234567> <$mini_head>" || return 1
  assert_contains "$GIT_REF_LOG" "<update-ref> <refs/heads/main> <$mini_head>" || return 1
  assert_contains "$GIT_REF_LOG" "<reset> <--mixed> <$mini_head>"
}

test_reclaim_stages_before_local_apply() {
  require_worker || return 1
  expect_success remote-only || return 1
  local network_line verify_line local_apply_line
  network_line=$(grep -n '^rsync .*fixture-mini:' "$COMMAND_LOG" | head -1 | cut -d: -f1)
  verify_line=$(grep -n '<stage-verify>' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  local_apply_line=$(grep -n '^rsync .*inbound-stage/.*local-project/' "$COMMAND_LOG" | tail -1 | cut -d: -f1)
  [[ -n $network_line && -n $verify_line && -n $local_apply_line ]] || return 1
  [[ $network_line -lt $verify_line && $verify_line -lt $local_apply_line ]] || return 1
  ! sed -n "${network_line}p" "$COMMAND_LOG" | grep -Fq -- "$LOCAL_ROOT/"
}

test_reclaim_refuses_non_fast_forward_without_ref_mutation() {
  require_worker || return 1
  MOCK_GIT_ANCESTOR=0 run_worker non-fast-forward --once
  [[ $STATUS -ne 0 ]] || return 1
  assert_contains "$STDERR" 'fast-forward' || return 1
  [[ ! -s $GIT_REF_LOG ]]
}

test_refusal_paths_never_mutate_git_refs_or_index() {
  require_worker || return 1
  expect_failure diverged || return 1
  [[ ! -s $GIT_REF_LOG ]] || return 1
  : >"$GIT_REF_LOG"
  expect_failure cas-lost || return 1
  [[ ! -s $GIT_REF_LOG ]] || return 1
  : >"$GIT_REF_LOG"
  expect_failure recovery-required || return 1
  [[ ! -s $GIT_REF_LOG ]]
}

# Finding #2: missing stagePath must fail closed (never fall back to a fixed /tmp path).
test_missing_stage_path_fails_closed() {
  require_worker || return 1
  expect_failure stage-path-missing || return 1
  assert_contains "$STDERR" 'stagePath' || assert_contains "$STDERR" 'stage-path' || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1
  assert_lacks "$COMMAND_LOG" '<apply-exact>' || return 1
  assert_lacks "$COMMAND_LOG" '/tmp/orchestration-mirror-stage/' || return 1
  assert_lacks "$COMMAND_LOG" '<mirror-ack>'
}

# Finding #3: --local-digest is required so the real registry can refuse diverged.
test_real_registry_diverged_refusal_uses_local_digest() {
  require_worker || return 1
  local registry="$SCRIPT_DIR/../../scripts/workflow-registry"
  [[ -x $registry ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local reg_home="$CASE/reg-home" reg_state="$CASE/reg-state"
  local checkout="$CASE/mini-checkout" plan_id=mirror-worker-div-plan
  local plan_dir="$checkout/.temp/plan-mode/active/$plan_id"
  local project=miospot hostname=mini-test-host
  local protocol_dir="$reg_state/orchestration/remote-agent/projects/$project"
  mkdir -p "$reg_home" "$reg_state" "$checkout" "$plan_dir" "$protocol_dir"
  chmod 700 "$reg_home" "$reg_state" "$checkout"
  printf '%s\n' '{"planId":"mirror-worker-div-plan","frozen":true}' >"$plan_dir/plan.json"
  printf '%s\n' '{"planId":"mirror-worker-div-plan","steps":{}}' >"$plan_dir/progress.json"
  printf '# plan\n' >"$plan_dir/masterPlan.md"
  # Diverged: local (worker digest mock = 64×a) ≠ common ≠ remote.
  printf 'digest-common\n' >"$protocol_dir/common"
  printf 'digest-mini-other\n' >"$protocol_dir/remote"
  printf '0\n' >"$protocol_dir/generation"

  REAL_REGISTRY_ENV_DIR="$CASE/reg-env"
  mkdir -p "$REAL_REGISTRY_ENV_DIR"
  cat >"$REAL_REGISTRY_ENV_DIR/env.sh" <<ENV
export HOME="$reg_home"
export XDG_STATE_HOME="$reg_state"
export HOSTNAME="$hostname"
export WORKFLOW_REGISTRY_TEST=1
export REMOTE_AGENT_ROOT_ORCHESTRATION="$checkout"
export REMOTE_AGENT_ROOT_MIOSPOT="$checkout"
ENV

  local mint_out mint_err wf_id
  mint_out=$CASE/mint.out mint_err=$CASE/mint.err
  env -i HOME="$reg_home" XDG_STATE_HOME="$reg_state" PATH="/usr/bin:/bin:$(dirname "$(command -v jq)")" \
    HOSTNAME="$hostname" WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$checkout" REMOTE_AGENT_ROOT_MIOSPOT="$checkout" \
    "$registry" mint "$project" "$plan_id" "$checkout" "$hostname" >"$mint_out" 2>"$mint_err" || return 1
  wf_id=$(sed -n 's/.*"workflowId":"\([^"]*\)".*/\1/p' "$mint_out" | head -n 1)
  [[ -n $wf_id ]] || return 1
  env -i HOME="$reg_home" XDG_STATE_HOME="$reg_state" PATH="/usr/bin:/bin:$(dirname "$(command -v jq)")" \
    HOSTNAME="$hostname" WORKFLOW_REGISTRY_TEST=1 \
    REMOTE_AGENT_ROOT_ORCHESTRATION="$checkout" REMOTE_AGENT_ROOT_MIOSPOT="$checkout" \
    "$registry" request-mirror-sync "$wf_id" --request-id req-div-worker >"$CASE/req.out" 2>"$CASE/req.err" || return 1

  USE_REAL_REGISTRY=1 REAL_REGISTRY="$registry" REAL_REGISTRY_ENV_DIR="$REAL_REGISTRY_ENV_DIR" \
    run_worker outbound --once
  [[ $STATUS -ne 0 ]] || return 1
  assert_contains "$COMMAND_LOG" '<--local-digest>' || return 1
  assert_contains "$STDERR" 'diverged' || assert_contains "$STDOUT" 'diverged' || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1
  assert_lacks "$COMMAND_LOG" '<apply-exact>' || return 1
  # Job must remain pending (real registry never claimed under diverged).
  local jf
  jf=$(find "$reg_state/orchestration/workflows/$wf_id/mirror-queue" -type f -name '*.json' | head -n 1)
  [[ -f $jf ]] || return 1
  grep -Fq '"state":"pending"' "$jf" || return 1
  ! grep -Fq '"direction"' "$jf"
}

# Finding #4: includeIgnored/approveIgnored from the claim response enter the universe.
test_claim_ignored_exception_is_transferred() {
  require_worker || return 1
  local evidence="$CASE/transfer-evidence"
  expect_success ignored-exception || return 1
  cat "$COMMAND_LOG" "$SSH_STDIN" >"$evidence"
  assert_contains "$evidence" '.env' || return 1
  assert_contains "$COMMAND_LOG" '<deletion-inventory>' || return 1
  assert_lacks "$evidence" 'node_modules'
}

# Finding #5: token-less claims refuse before any staging.
test_tokenless_claim_refused_before_stage() {
  require_worker || return 1
  expect_failure tokenless || return 1
  assert_contains "$STDERR" 'claimToken' || assert_contains "$STDERR" 'claim-token' || return 1
  assert_lacks "$COMMAND_LOG" '<stage>' || return 1
  assert_lacks "$COMMAND_LOG" 'rsync' || return 1
  assert_lacks "$COMMAND_LOG" '<apply-exact>' || return 1
  assert_lacks "$COMMAND_LOG" '<mirror-ack>' || return 1
  assert_lacks "$COMMAND_LOG" 'worker-local'
}

# Finding #6: loop mode processes two consecutive inbound jobs without work-dir collision.
test_loop_mode_two_consecutive_inbound_jobs() {
  require_worker || return 1
  CLAIM_COUNT_FILE="$CASE/claim-count"
  printf '0\n' >"$CLAIM_COUNT_FILE"
  MIRROR_WORKER_MAX_JOBS=2 MIRROR_WORKER_LOOP_SLEEP=0 \
    run_worker loop-inbound
  [[ $STATUS -eq 0 ]] || return 1
  assert_contains "$COMMAND_LOG" 'job-inbound-1' || assert_contains "$STDOUT" 'job-inbound-1' || return 1
  assert_contains "$COMMAND_LOG" 'job-inbound-2' || assert_contains "$STDOUT" 'job-inbound-2' || return 1
  # Two populate-inbound calls prove both jobs completed transfer (not stranded).
  local inbound_count
  inbound_count=$(grep -c '<populate-inbound>' "$COMMAND_LOG" || true)
  [[ $inbound_count -eq 2 ]] || return 1
  local ack_count
  ack_count=$(grep -c '<mirror-ack>' "$COMMAND_LOG" || true)
  [[ $ack_count -eq 2 ]]
}

# CRITICAL: empty miospot must not strand orchestration jobs (errexit on empty claim).
test_loop_skips_empty_miospot_and_claims_orchestration() {
  require_worker || return 1
  MIRROR_WORKER_MAX_JOBS=1 MIRROR_WORKER_LOOP_SLEEP=0 \
    run_worker empty-miospot-then-orchestration
  [[ $STATUS -eq 0 ]] || return 1
  assert_contains "$STDOUT" 'job-orch-1' || assert_contains "$COMMAND_LOG" 'job-orch-1' || return 1
  assert_contains "$COMMAND_LOG" '<mirror-next>' || return 1
  assert_contains "$COMMAND_LOG" '<apply-exact>' || return 1
  assert_contains "$COMMAND_LOG" '<mirror-ack>' || return 1
  # Must have claimed orchestration, not only polled miospot.
  assert_contains "$COMMAND_LOG" '<orchestration>' || assert_contains "$STDOUT" '"project":"orchestration"' || return 1
  local ack_count
  ack_count=$(grep -c '<mirror-ack>' "$COMMAND_LOG" || true)
  [[ $ack_count -eq 1 ]]
}

# Empty queue with --once is a normal outcome (exit 0), not a hard failure.
test_once_on_empty_queue_exits_zero() {
  require_worker || return 1
  run_worker empty-queue --once
  [[ $STATUS -eq 0 ]] || return 1
  assert_lacks "$COMMAND_LOG" '<stage>' || return 1
  assert_lacks "$COMMAND_LOG" '<apply-exact>' || return 1
  assert_lacks "$COMMAND_LOG" '<mirror-ack>' || return 1
  assert_contains "$COMMAND_LOG" '<mirror-next>'
}

# Guarded apply failure: restore verified via journal; bounded apply-failed label.
test_apply_exact_failure_restores_via_journal() {
  require_worker || return 1
  expect_failure apply-fail-restore-verified || return 1
  assert_contains "$COMMAND_LOG" '<restore-journal>' || return 1
  assert_contains "$COMMAND_LOG" '<apply-exact>' || return 1
  assert_contains "$COMMAND_LOG" '<restore-verify>' || return 1
  assert_contains "$STDERR" 'apply-failed' || return 1
  assert_lacks "$COMMAND_LOG" '<mirror-ack>' || return 1
  assert_lacks "$COMMAND_LOG" '<lease-release>'
}

# Guarded apply failure with restore-failed retains recovery-required.
test_apply_exact_restore_failed_retains_recovery_required() {
  require_worker || return 1
  expect_failure apply-fail-restore-failed || return 1
  assert_contains "$COMMAND_LOG" '<apply-exact>' || return 1
  assert_contains "$COMMAND_LOG" '<recovery-required>' || return 1
  assert_contains "$STDERR" 'apply-failed' || return 1
  assert_contains "$STDERR" 'recovery-required' || return 1
  assert_lacks "$COMMAND_LOG" '<mirror-ack>' || return 1
  assert_lacks "$COMMAND_LOG" '<lease-release>'
}

# Guarded git-align failure restores prior refs (restore-verify path).
test_git_align_failure_restores_prior_refs() {
  require_worker || return 1
  expect_failure align-fail-restore-verified || return 1
  assert_contains "$COMMAND_LOG" '<apply-exact>' || return 1
  assert_contains "$COMMAND_LOG" '<git-align>' || return 1
  assert_contains "$COMMAND_LOG" '<restore-verify>' || return 1
  assert_contains "$STDERR" 'align-failed' || return 1
  assert_lacks "$COMMAND_LOG" '<mirror-ack>' || return 1
  assert_lacks "$COMMAND_LOG" '<lease-release>'
}

# Align restore-failed: recovery-required retained; never mapped to success.
test_git_align_restore_failed_retains_recovery_required() {
  require_worker || return 1
  expect_failure align-fail-restore-failed || return 1
  assert_contains "$COMMAND_LOG" '<git-align>' || return 1
  assert_contains "$COMMAND_LOG" '<recovery-required>' || return 1
  assert_contains "$STDERR" 'align-failed' || return 1
  assert_contains "$STDERR" 'recovery-required' || return 1
  assert_lacks "$COMMAND_LOG" '<mirror-ack>' || return 1
  assert_lacks "$COMMAND_LOG" '<lease-release>'
}

# Documented limitation: outbound deletion inventory is source-side only (paths
# from the local transfer universe). Destination-only orphans are never listed,
# so apply-exact cannot delete Mini paths that vanished from the MacBook tree.
# Remote digest still advances to the local universe fingerprint — honest as a
# "last staged content" marker, not as full destination-tree equality.
test_deletion_inventory_is_source_side_only_limitation() {
  require_worker || return 1
  expect_success deletion-limitation || return 1
  assert_contains "$COMMAND_LOG" '<deletion-inventory>' || return 1
  # Inventoried paths are only from the local transfer universe.
  assert_contains "$COMMAND_LOG" '<inventory-path>' || return 1
  assert_contains "$COMMAND_LOG" '<README.md>' || return 1
  assert_contains "$COMMAND_LOG" '<notes.txt>' || return 1
  # Worker never invents destination-only paths for deletion candidates.
  assert_lacks "$COMMAND_LOG" '<orphan-on-mini-only.txt>' || return 1
  # Digest/ack still complete — content that was staged is verified; orphans
  # on Mini are an explicit non-goal of this worker step.
  assert_contains "$COMMAND_LOG" '<apply-exact>' || return 1
  assert_contains "$COMMAND_LOG" '<mirror-ack>' || return 1
  assert_contains "$COMMAND_LOG" '<--fingerprint>' || assert_contains "$COMMAND_LOG" 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
}

if [[ ! -x $MIRROR_WORKER ]]; then
  fail 'mirror-worker executable exists' "missing executable: $MIRROR_WORKER"
else
  pass 'mirror-worker executable exists'
fi

run_test 'outbound worker ships a bundle and requests exact branch HEAD alignment' test_outbound_handoff_requests_bundle_and_exact_git_alignment
run_test 'worker resolves the default root and refuses symlink non-Git and nested roots' test_worker_roots_default_and_invalid_refusals
run_test 'worker fingerprint is branch HEAD content-strong and NUL-safe' test_snapshot_is_strong_and_nul_safe
run_test 'worker transfer universe includes tracked and ordinary untracked but excludes ignored paths' test_transfer_universe_and_deletions
run_test 'worker stages privately with a restore journal before exact apply' test_private_staging_and_restore_journal
run_test 'network staging failure stops before verify apply ack or release' test_network_staging_failure_stops_before_apply
run_test 'mirror claim computes outbound inbound and divergent directions at claim time' test_claim_direction_is_computed_at_claim_time
run_test 'live-writer claim refusal happens before any worker transfer' test_claim_refusal_precedes_worker_transfer
run_test 'post-sync mismatch keeps the lease and refuses the mirror ack' test_post_sync_mismatch_keeps_lease
run_test 'inbound worker fast-forwards the MacBook branch and rebuilds a mixed index' test_reclaim_fast_forwards_branch_and_resets_index_mixed
run_test 'inbound worker verifies private staging before local apply' test_reclaim_stages_before_local_apply
run_test 'non-fast-forward inbound worker refuses without mutating refs or index' test_reclaim_refuses_non_fast_forward_without_ref_mutation
run_test 'divergence CAS loss and recovery-required worker paths never mutate Git' test_refusal_paths_never_mutate_git_refs_or_index
run_test 'missing stagePath fails closed without a fixed /tmp fallback' test_missing_stage_path_fails_closed
run_test 'real registry diverged refusal fires via --local-digest' test_real_registry_diverged_refusal_uses_local_digest
run_test 'claim includeIgnored approveIgnored exception is transferred' test_claim_ignored_exception_is_transferred
run_test 'token-less claim is refused before any staging' test_tokenless_claim_refused_before_stage
run_test 'loop mode drains two consecutive inbound jobs without work-dir collision' test_loop_mode_two_consecutive_inbound_jobs
run_test 'loop mode skips empty miospot and claims pending orchestration job' test_loop_skips_empty_miospot_and_claims_orchestration
run_test 'once mode on fully empty queue exits zero' test_once_on_empty_queue_exits_zero
run_test 'apply-exact failure restores via journal and reports apply-failed' test_apply_exact_failure_restores_via_journal
run_test 'apply-exact restore-failed retains recovery-required' test_apply_exact_restore_failed_retains_recovery_required
run_test 'git-align failure restores prior refs via journal' test_git_align_failure_restores_prior_refs
run_test 'git-align restore-failed retains recovery-required' test_git_align_restore_failed_retains_recovery_required
run_test 'deletion inventory is source-side only documented limitation' test_deletion_inventory_is_source_side_only_limitation

printf '%d tests passed, %d tests failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
