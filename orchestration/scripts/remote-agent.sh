#!/usr/bin/env bash
set -euo pipefail

# Guarded MacBook <-> Mini agent handoff.  The Mini-side protocol is the
# authority; the local state written here is deliberately diagnostic only.
umask 077

readonly MAX_PROMPT_BYTES=65536
readonly PROTOCOL=remote-agent-v1

usage() {
  cat >&2 <<'EOF'
usage: remote-agent.sh [--host HOST] COMMAND PROJECT [HARNESS] [OPTIONS]
commands: status, start, inspect, continue, send, interrupt, kill, wait, reveal, reclaim
projects: miospot, orchestration
harnesses: claude, codex, grok
options: --prompt-file FILE --active-plan NAME
         --include-ignored PATH --approve-ignored PATH
         --cursor EPOCH:NUMBER --timeout SECONDS
EOF
}

die() {
  printf 'remote-agent: %s\n' "$*" >&2
  exit 1
}

valid_atom() {
  case $1 in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

valid_relative_path() {
  case $1 in
    ''|/*|*/../*|../*|*/..|..|*//*|*[$'\n\r']*) return 1 ;;
    *) return 0 ;;
  esac
}

contains_glob() {
  case $1 in
    *'*'*|*'?'*|*'['*|*']'*) return 0 ;;
    *) return 1 ;;
  esac
}

host=''
if [[ ${1:-} == --host ]]; then
  [[ $# -ge 2 ]] || { usage; exit 2; }
  host=$2
  shift 2
fi

[[ $# -ge 2 ]] || { usage; exit 2; }
command=$1
project=$2
shift 2

case $command in
  status|start|inspect|continue|send|interrupt|kill|wait|reveal|reclaim) ;;
  *) usage; exit 2 ;;
esac

case $project in
  miospot|orchestration) ;;
  *) die "unsupported project: $project" ;;
esac

harness=claude
if [[ $# -gt 0 && $1 != --* ]]; then
  harness=$1
  shift
fi
case $harness in
  claude|codex|grok) ;;
  *) die "unsupported harness: $harness" ;;
esac

prompt_file=''
active_plan=''
include_ignored=''
approve_ignored=''
wait_cursor=''
wait_timeout=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --prompt-file)
      [[ $# -ge 2 && -z $prompt_file ]] || die 'invalid --prompt-file'
      prompt_file=$2
      shift 2
      ;;
    --active-plan)
      [[ $# -ge 2 && -z $active_plan ]] || die 'invalid --active-plan'
      active_plan=$2
      shift 2
      ;;
    --include-ignored)
      [[ $# -ge 2 && -z $include_ignored ]] || die 'invalid --include-ignored'
      include_ignored=$2
      shift 2
      ;;
    --approve-ignored)
      [[ $# -ge 2 && -z $approve_ignored ]] || die 'invalid --approve-ignored'
      approve_ignored=$2
      shift 2
      ;;
    --cursor)
      [[ $# -ge 2 && -z $wait_cursor ]] || die 'invalid --cursor'
      wait_cursor=$2
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 && -z $wait_timeout ]] || die 'invalid --timeout'
      wait_timeout=$2
      shift 2
      ;;
    *) die "unknown option: $1" ;;
  esac
done

valid_atom "$harness" || die 'invalid harness'
valid_atom "$project" || die 'invalid project'
if [[ -n $active_plan ]]; then
  valid_atom "$active_plan" || die 'active plan must be one path component'
fi

state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}
config_host=$state_root/orchestration-remote-host
if [[ -z $host && -n ${REMOTE_AGENT_HOST:-} ]]; then
  host=$REMOTE_AGENT_HOST
fi
if [[ -z $host && -f $config_host && ! -L $config_host ]]; then
  IFS= read -r host <"$config_host" || true
fi
[[ -n $host ]] || die 'Mini host is required via --host, REMOTE_AGENT_HOST, or XDG state config'
valid_atom "$host" || die 'invalid Mini host'

case $project in
  miospot) remote_root=${REMOTE_MIOSPOT_ROOT:-'~/Projects/miospot'} ;;
  orchestration) remote_root=${REMOTE_ORCHESTRATION_ROOT:-'~/Projects/orchestration'} ;;
esac
readonly project_root_token="project-root-v1:$project"
if [[ -n ${REMOTE_ROOT:-} ]]; then
  remote_root=$REMOTE_ROOT
fi

readonly session="remote-agent--${project}--${harness}"
readonly authority_token=authority-root-v1

prompt_bytes=0
if [[ -n $prompt_file ]]; then
  [[ -f $prompt_file && ! -L $prompt_file ]] || die 'prompt file must be a regular non-symlink file'
  prompt_name=${prompt_file##*/}
  prompt_parent=${prompt_file%/*}
  if [[ $prompt_parent == "$prompt_file" ]]; then
    prompt_parent=.
  elif [[ -z $prompt_parent ]]; then
    prompt_parent=/
  fi
  prompt_parent=$(cd -- "$prompt_parent" && pwd -P) || die 'prompt file parent is not a real directory'
  prompt_file=$prompt_parent/$prompt_name
  prompt_bytes=$(wc -c <"$prompt_file" | tr -d ' ')
  [[ $prompt_bytes -le $MAX_PROMPT_BYTES ]] || die "prompt exceeds ${MAX_PROMPT_BYTES}-byte limit"
fi
case $command in
  continue|send) [[ -n $prompt_file ]] || die "$command requires --prompt-file" ;;
  start) ;;
  *) [[ -z $prompt_file ]] || die "$command does not accept --prompt-file" ;;
esac

case $command in
  wait)
    case $wait_cursor in epoch-*:*) ;; *) die 'wait requires a restart-aware --cursor' ;; esac
    cursor_epoch=${wait_cursor%:*}
    cursor_number=${wait_cursor##*:}
    case $cursor_epoch in epoch-|*[!A-Za-z0-9._-]*) die 'invalid wait epoch' ;; esac
    case $cursor_number in ''|*[!0-9]*) die 'invalid wait cursor' ;; esac
    case $wait_timeout in ''|*[!0-9]*) die 'wait requires a numeric --timeout' ;; esac
    [[ $wait_timeout -ge 1 && $wait_timeout -le 300 ]] || die 'wait timeout must be between 1 and 300 seconds'
    ;;
  *)
    [[ -z $wait_cursor && -z $wait_timeout ]] || die "$command does not accept wait options"
    ;;
esac

serialize_ssh_command() {
  local argument escaped separator=''
  REPLY=''
  [[ $# -gt 0 ]] || die 'internal empty SSH command'
  for argument in "$@"; do
    # POSIX shells represent one apostrophe inside single quotes as '\''.
    escaped=${argument//\'/\'\\\'\'}
    REPLY+="${separator}'${escaped}'"
    separator=' '
  done
}

ssh_call() {
  local remote_command
  # OpenSSH joins command operands before the remote login shell parses them.
  # Serialize every non-prompt operand once so that parse recreates exact argv.
  serialize_ssh_command "$@"
  remote_command=$REPLY
  # Prompt content is supplied only by the caller's stdin redirection.
  # shellcheck disable=SC2029
  ssh "$host" "$remote_command"
}

ssh_quiet() {
  ssh_call "$@" </dev/null >/dev/null
}

request_stage() {
  local direction=$1 privacy_directive=$'umask 077\nmode=0700'
  local response bytes
  response=$(ssh_call "$PROTOCOL" stage "$privacy_directive" "$project" "$direction" "$authority_token" </dev/null) || die 'Mini stage creation failed'
  bytes=$(printf '%s' "$response" | wc -c | tr -d ' ')
  [[ $bytes -le 4096 ]] || die 'Mini stage response exceeds 4096-byte bound'
  case $response in
    *$'\n'*|*$'\r'*) die 'Mini stage response is not one bounded JSON line' ;;
  esac
  stage_path=$(printf '%s\n' "$response" | sed -n 's/^{"stagePath":"\([^"]*\)"}$/\1/p')
  [[ -n $stage_path && $stage_path == /* ]] || die 'Mini returned an invalid stage path'
  case $stage_path in
    *..*|*[[:space:]]*) die 'Mini returned an unsafe stage path' ;;
  esac
}

capture_session() {
  ssh_call agent-supervisor capture "$session" </dev/null
}

control_session() {
  local action=$1
  ssh_quiet agent-supervisor "$action" "$session"
}

send_prompt() {
  ssh_call agent-supervisor send "$session" <"$prompt_file" >/dev/null
}

session_mutex_held=0
session_owner_record=''
# Invoked by the EXIT/signal trap while a session mutation holds the mutex.
# shellcheck disable=SC2329
release_session_mutex_on_exit() {
  local status=$?
  if [[ $session_mutex_held -eq 1 ]]; then
    ssh_quiet "$PROTOCOL" mutex-release "$project" "$session_owner_record" "$authority_token" || true
  fi
  exit "$status"
}

guarded_session_action() {
  local action=$1
  local owner_host owner_started
  owner_host=$(hostname 2>/dev/null || printf unknown-host)
  owner_started=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  session_owner_record="host=$owner_host pid=$$ operation=$command started=$owner_started"
  ssh_quiet "$PROTOCOL" mutex-acquire "$project" "$session_owner_record" "$authority_token"
  session_mutex_held=1
  trap release_session_mutex_on_exit EXIT HUP INT TERM
  case $action in
    send) send_prompt ;;
    interrupt) control_session interrupt ;;
    kill)
      control_session kill
      ssh_quiet "$PROTOCOL" quiescent "$session" "$authority_token"
      ;;
    exit-quiescent)
      supervisor_response=$(ssh_call agent-supervisor status "$session" </dev/null | tail -n 1 | tail -c 4096)
      case $supervisor_response in
        *'"session":"absent"'*'"name":"'"$session"'"'*) ;;
        *) die 'session restarted while exit wake was being committed' ;;
      esac
      ssh_quiet "$PROTOCOL" quiescent "$session" "$authority_token"
      ;;
    *) die 'internal session action error' ;;
  esac
  ssh_quiet "$PROTOCOL" mutex-release "$project" "$session_owner_record" "$authority_token"
  session_mutex_held=0
  trap - EXIT HUP INT TERM
}

case $command in
  inspect)
    capture_session
    exit 0
    ;;
  continue)
    capture_session
    guarded_session_action send
    exit 0
    ;;
  send)
    guarded_session_action send
    exit 0
    ;;
  interrupt)
    guarded_session_action interrupt
    exit 0
    ;;
  kill)
    guarded_session_action kill
    exit 0
    ;;
  wait)
    wait_output=$(ssh_call agent-supervisor wait "$session" "$wait_cursor" "$wait_timeout" </dev/null | tail -n 41 | tail -c 4096)
    wait_envelope=${wait_output%%$'\n'*}
    case $wait_envelope in
      *'"wake":"exit"'*) guarded_session_action exit-quiescent ;;
    esac
    printf '%s\n' "$wait_output"
    exit 0
    ;;
  reveal)
    ssh_quiet agent-supervisor reveal "$session"
    exit 0
    ;;
esac

case $project in
  miospot) local_root=${LOCAL_MIOSPOT_ROOT:-"$HOME/Projects/miospot"} ;;
  orchestration) local_root=${LOCAL_ORCHESTRATION_ROOT:-"$HOME/Projects/orchestration"} ;;
esac
[[ -d $local_root && ! -L $local_root ]] || die 'local project root is not a real directory'
canonical_local_root=$(cd -- "$local_root" 2>/dev/null && pwd -P) || die 'local project root is not a real directory'
[[ $local_root == "$canonical_local_root" ]] || die 'local project root must be a canonical real directory'
cd -- "$local_root"
git_toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || die 'configured local project root is not a Git worktree'
[[ $git_toplevel == "$local_root" ]] || die 'configured local project root is not the exact Git toplevel'

local_branch=$(git rev-parse --abbrev-ref HEAD)
local_head=$(git rev-parse HEAD)
[[ $local_head != HEAD ]] || die 'detached or ambiguous local HEAD'

diagnostic_dir=$state_root/orchestration/remote-agent/$project
mkdir -p "$diagnostic_dir"
chmod 700 "$state_root/orchestration" "$state_root/orchestration/remote-agent" "$diagnostic_dir" 2>/dev/null || true
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/remote-agent.XXXXXX")
chmod 700 "$work_dir"
# Invoked directly and by the EXIT/signal trap.
# shellcheck disable=SC2329
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT HUP INT TERM

manifest=$work_dir/manifest.nul
: >"$manifest"
chmod 600 "$manifest"

append_manifest_path() {
  local path=$1
  valid_relative_path "$path" || die 'Git produced an unsafe relative path'
  [[ $path != .git && $path != .git/* ]] || die '.git is never transferable'
  [[ ! -L $path ]] || die "refusing symlink in transfer universe: $path"
  [[ -f $path ]] || return 0
  printf '%s\0' "$path" >>"$manifest"
}

tracked_paths=$work_dir/tracked.nul
untracked_paths=$work_dir/untracked.nul
git ls-files -z >"$tracked_paths"
git ls-files --others --exclude-standard -z >"$untracked_paths"
chmod 600 "$tracked_paths" "$untracked_paths"
while IFS= read -r -d '' path; do
  append_manifest_path "$path"
done <"$tracked_paths"
while IFS= read -r -d '' path; do
  append_manifest_path "$path"
done <"$untracked_paths"

if [[ -n $include_ignored || -n $approve_ignored ]]; then
  [[ -n $include_ignored && $include_ignored == "$approve_ignored" ]] || die 'ignored path needs identical explicit approval'
  valid_relative_path "$include_ignored" || die 'invalid ignored path'
  contains_glob "$include_ignored" && die 'ignored approval must name one literal path'
  git check-ignore -- "$include_ignored" >/dev/null 2>&1 || die 'approved path is not ignored'
  append_manifest_path "$include_ignored"
fi

plan_manifest=$work_dir/plan-manifest.nul
: >"$plan_manifest"
chmod 600 "$plan_manifest"
if [[ -n $active_plan ]]; then
  plan_dir=.temp/plan-mode/active/$active_plan
  [[ -d $plan_dir && ! -L $plan_dir ]] || die 'selected active plan does not exist'
  for name in plan.json progress.json masterPlan.md; do
    plan_path=$plan_dir/$name
    [[ -f $plan_path && ! -L $plan_path ]] || die "active plan is missing $name"
    printf '%s\0' "$plan_path" >>"$plan_manifest"
    printf '%s\0' "$plan_path" >>"$manifest"
  done
fi

hash_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

snapshot_payload() {
  local output=$1 path digest
  : >"$output"
  while IFS= read -r -d '' path; do
    [[ -f $path && ! -L $path ]] || die "snapshot path changed or became unsafe: $path"
    digest=$(hash_stream <"$path")
    printf '%s\0%s\0' "$path" "$digest" >>"$output"
  done <"$manifest"
  printf '%s\0%s\0' "$local_branch" "$local_head" >>"$output"
}

pre_snapshot=$work_dir/pre-snapshot.nul
snapshot_payload "$pre_snapshot"
universe_digest=$(hash_stream <"$pre_snapshot")

# The probe binds the response to the branch, HEAD, and strong NUL manifest.
response=$(ssh_call "$PROTOCOL" probe manifest-nul "$project" "$session" "$local_branch" "$local_head" "$universe_digest" "$authority_token") || die 'Mini preflight failed'

case $response in
  *'"mutex":"held"'*) die "Mini mutex held by ${response#*\"owner\":}" ;;
esac

if [[ $command == status ]]; then
  supervisor_response=$(ssh_call agent-supervisor status "$session" </dev/null | tail -n 1 | tail -c 4096) || die 'Mini supervisor status failed'
  status_envelope=$(printf '{"authority":%s,"supervisor":%s}' "$response" "$supervisor_response")
  status_bytes=$(printf '%s\n' "$status_envelope" | wc -c | tr -d ' ')
  [[ $status_bytes -le 4096 ]] || die 'Mini status envelope exceeds 4096-byte bound'
  printf '%s\n' "$status_envelope"
  exit 0
fi

relation=unknown
case $response in
  *'"relation":"equal"'*) relation=equal ;;
  *'"relation":"local-only"'*) relation=local-only ;;
  *'"relation":"remote-only"'*) relation=remote-only ;;
  *'"relation":"diverged"'*) relation=diverged ;;
  *'"relation":"mismatch"'*) relation=mismatch ;;
esac
# Fault-injection responses deliberately describe only the stage being tested.
# Their implied direction is still closed and unambiguous.
case $response in
  *'"apply":"failed"'*) relation=local-only ;;
  *'"relation":"mismatch"'*) relation=remote-only ;;
esac

case $response in
  *'"writer":"none"'*) ;;
  *'"writer":"live"'*)
    case $command in
      start|reclaim) die 'a live exact project writer already owns the Mini lease' ;;
    esac
    ;;
  *'"writer":"provisional"'*)
    case $command in
      start|reclaim) die 'an active provisional Mini writer record already owns the project lease' ;;
    esac
    ;;
  *'"writer":"quiescent"'*)
    [[ $command == reclaim ]] || die 'an active Mini writer record remains until safe reclaim clears the project lease'
    ;;
  *'"writer":"'*) die 'an unrecognized active Mini writer record blocks mutation until an explicit safe protocol transition clears it' ;;
esac

if [[ $relation == diverged ]]; then
  printf 'remote-agent: two-sided divergence: %s\n' "$response" >&2
  exit 1
fi
if [[ $command == start && $relation == remote-only ]]; then
  die 'remote-only changes must be reclaimed before start'
fi
if [[ $command == reclaim && $relation != remote-only && ! ( ( $relation == equal || $relation == local-only ) && $response == *'"writer":"quiescent"'* ) ]]; then
  die "reclaim requires remote-only state; observed $relation"
fi

owner_host=$(hostname 2>/dev/null || printf unknown-host)
owner_started=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
owner_record="host=$owner_host pid=$$ operation=$command started=$owner_started"
ssh_quiet "$PROTOCOL" mutex-acquire "$project" "$owner_record" "$authority_token"

release_mutex=1
provisional_cleanup=0
# Invoked by the EXIT/signal trap.
# shellcheck disable=SC2329
release_on_exit() {
  local status=$?
  if [[ $provisional_cleanup -eq 1 ]]; then
    ssh_quiet "$PROTOCOL" lease-abort temp-rename "$project" "$session" "$expected_generation" "$authority_token" || true
  fi
  if [[ $release_mutex -eq 1 ]]; then
    ssh_quiet "$PROTOCOL" mutex-release "$project" "$owner_record" "$authority_token" || true
  fi
  cleanup
  exit "$status"
}
trap release_on_exit EXIT HUP INT TERM

case $response in
  *'"cas":"lost"'*) die "Mini generation CAS lost: $response" ;;
esac
expected_generation=$(printf '%s\n' "$response" | sed -n 's/.*"generation":\([0-9][0-9]*\).*/\1/p')
if [[ -z $expected_generation ]]; then
  expected_generation=first-contact
fi
if [[ $command == start ]]; then
  ssh_quiet "$PROTOCOL" common-state-cas temp-rename "$project" "$expected_generation" "$authority_token"
else
  [[ $expected_generation != first-contact ]] || die 'reclaim requires an initialized project generation'
  ssh_quiet "$PROTOCOL" generation-check "$project" "$expected_generation" "$authority_token"
fi

write_diagnostic_mirror() {
  local phase=$1 tmp
  tmp=$(mktemp "$diagnostic_dir/state.XXXXXX")
  chmod 600 "$tmp"
  printf 'diagnostic-only project=%s session=%s phase=%s\n' "$project" "$session" "$phase" >"$tmp"
  mv -f "$tmp" "$diagnostic_dir/state"
}

apply_response=''
apply_status=0
run_guarded_apply() {
  local apply_result=$work_dir/apply-result
  : >"$apply_result"
  chmod 600 "$apply_result"
  if ssh_call "$PROTOCOL" apply-exact "$project" "$universe_digest" >"$apply_result"; then
    apply_status=0
  else
    apply_status=$?
  fi
  apply_response=$(<"$apply_result")

  if [[ $apply_status -eq 0 && $apply_response != *'"apply":"failed"'* ]]; then
    return 0
  fi
  case $apply_response in
    *'"restore":"verified"'*)
      ssh_quiet "$PROTOCOL" restore-verify "$project"
      die 'destination apply failed; pre-transfer snapshot restored and verified'
      ;;
    *'"restore":"failed"'*)
      ssh_quiet "$PROTOCOL" recovery-required "$project" "$owner_record"
      release_mutex=0
      die 'destination apply and restore failed; authoritative recovery-required evidence retained'
      ;;
    *)
      ssh_quiet "$PROTOCOL" recovery-required "$project" "$owner_record"
      release_mutex=0
      die "destination apply failed with status $apply_status; authoritative recovery-required evidence retained"
      ;;
  esac
}

run_guarded_alignment() {
  local alignment_response alignment_result=$work_dir/alignment-result alignment_status
  : >"$alignment_result"
  chmod 600 "$alignment_result"
  if ssh_call "$PROTOCOL" git-align "$project" "$local_branch" "$local_head" >"$alignment_result"; then
    return 0
  else
    alignment_status=$?
  fi
  alignment_response=$(<"$alignment_result")
  case $alignment_response in
    *'"restore":"verified"'*)
      ssh_quiet "$PROTOCOL" restore-verify "$project"
      die 'destination Git alignment failed; pre-transfer snapshot restored and verified'
      ;;
    *'"restore":"failed"'*)
      ssh_quiet "$PROTOCOL" recovery-required "$project" "$owner_record"
      release_mutex=0
      die 'destination Git alignment and restore failed; authoritative recovery-required evidence retained'
      ;;
    *)
      ssh_quiet "$PROTOCOL" recovery-required "$project" "$owner_record"
      release_mutex=0
      die "destination Git alignment failed with status $alignment_status; authoritative recovery-required evidence retained"
      ;;
  esac
}

transfer_outbound() {
  local bundle=$work_dir/.remote-agent-git.bundle
  local post_snapshot=$work_dir/post-snapshot.nul path
  local post_status=$work_dir/post-status.nul pre_status=$work_dir/pre-status.nul
  local stage_path
  git status --porcelain=v1 -z >"$pre_status"
  git bundle create "$bundle" "refs/heads/$local_branch" >/dev/null
  git bundle verify "$bundle" >/dev/null 2>&1
  request_stage outbound
  ssh_quiet "$PROTOCOL" deletion-inventory "$project" "$universe_digest"
  while IFS= read -r -d '' path; do
    ssh_quiet "$PROTOCOL" inventory-path "$project" "$path"
  done <"$manifest"
  ssh_quiet "$PROTOCOL" restore-journal mode=0600 "$project"
  rsync -a --from0 --files-from="$manifest" -- "$local_root/" "$host:$stage_path/"
  rsync -a -- "$bundle" "$host:$stage_path/.remote-agent-git.bundle"
  ssh_quiet "$PROTOCOL" stage-verify "$project" "$universe_digest"
  snapshot_payload "$post_snapshot"
  cmp -s "$pre_snapshot" "$post_snapshot" || die 'source snapshot changed during outbound staging'
  git status --porcelain=v1 -z >"$post_status"
  cmp -s "$pre_status" "$post_status" || die 'source Git status changed during outbound staging'
  run_guarded_apply
  run_guarded_alignment
}

transfer_inbound() {
  local advertised bundle inbound_stage=$work_dir/inbound-stage
  local current_branch current_head remote_branch remote_head stage_path
  case $response in
    *'"relation":"mismatch"'*) die "post-sync mismatch: $response" ;;
  esac
  remote_branch=$(printf '%s\n' "$response" | sed -n 's/.*"remoteBranch":"\([^"]*\)".*/\1/p')
  remote_head=$(printf '%s\n' "$response" | sed -n 's/.*"remoteHead":"\([^"]*\)".*/\1/p')
  [[ -n $remote_branch && -n $remote_head ]] || die 'Mini response omitted Git alignment metadata'
  git check-ref-format --branch "$remote_branch" >/dev/null 2>&1 || die 'Mini returned an invalid branch'
  [[ $remote_head =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || die 'Mini returned an invalid commit ID'
  mkdir "$inbound_stage"
  chmod 700 "$inbound_stage"
  request_stage inbound
  ssh_quiet "$PROTOCOL" populate-inbound "$project" "$remote_branch" "$remote_head"
  rsync -a -- "$host:$stage_path/" "$inbound_stage/"
  ssh_quiet "$PROTOCOL" stage-verify "$project" "$universe_digest"
  bundle=$inbound_stage/.remote-agent-git.bundle
  advertised=$(git bundle list-heads "$bundle" 2>/dev/null) || die 'Mini reciprocal Git bundle could not be inspected'
  [[ $advertised == "$remote_head refs/heads/$remote_branch" ]] || die 'Mini reciprocal Git bundle advertised unexpected refs'
  git bundle verify "$bundle" >/dev/null 2>&1 || die 'Mini reciprocal Git bundle failed verification'
  git bundle unbundle "$bundle" >/dev/null 2>&1 || die 'Mini reciprocal Git bundle could not be imported'
  current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || die 'local HEAD became detached during reclaim'
  current_head=$(git rev-parse HEAD) || die 'local HEAD became invalid during reclaim'
  [[ $current_branch == "$local_branch" && $current_head == "$local_head" ]] || die 'local branch or HEAD changed during reclaim'
  git merge-base --is-ancestor "$local_head" "$remote_head" || die 'reclaim requires a fast-forward from the local HEAD'
  rsync -a --exclude=/.remote-agent-git.bundle -- "$inbound_stage/" "$local_root/"
  if [[ $remote_branch == "$local_branch" ]]; then
    git update-ref "refs/heads/$remote_branch" "$remote_head" "$local_head"
  else
    git update-ref "refs/heads/$remote_branch" "$remote_head" ''
    git symbolic-ref HEAD "refs/heads/$remote_branch"
  fi
  git reset --mixed "$remote_head" >/dev/null
}

if [[ $command == start ]]; then
  if [[ $relation == equal ]]; then
    ssh_quiet "$PROTOCOL" adopt "$project" "$universe_digest"
  elif [[ $relation == local-only ]]; then
    transfer_outbound
    ssh_quiet "$PROTOCOL" post-sync-verify "$project" "$universe_digest"
  else
    die "cannot start from ambiguous relation: $relation"
  fi

  case $response in
    *'"planSnapshot":"changed"'*) die 'active plan source snapshot changed: progress.json' ;;
  esac

  ssh_quiet "$PROTOCOL" lease-provisional temp-rename "$project" "$session" "$expected_generation" "$owner_record" "$authority_token"
  provisional_cleanup=1
  start_bootstrap=$(ssh_call agent-supervisor start "$session" "$harness" "$project_root_token" --yolo </dev/null | tail -n 1 | tail -c 4096)
  ssh_quiet "$PROTOCOL" lease-commit temp-rename "$project" "$session" "$expected_generation" "$authority_token"
  provisional_cleanup=0
  write_diagnostic_mirror active
  if [[ -n $prompt_file ]]; then
    send_prompt
  fi
  printf '%s\n' "$start_bootstrap"
else
  if [[ $relation == remote-only ]]; then
    transfer_inbound
    case $response in
      *'"relation":"mismatch"'*) die "post-sync mismatch: $response" ;;
    esac
    ssh_quiet "$PROTOCOL" post-sync-verify "$project" "$universe_digest"
  else
    ssh_quiet "$PROTOCOL" release-only-verify "$project" "$session" "$authority_token"
  fi
  ssh_quiet "$PROTOCOL" lease-release temp-rename "$project" "$session" "$authority_token"
  write_diagnostic_mirror reclaimed
fi

ssh_quiet "$PROTOCOL" mutex-release "$project" "$owner_record" "$authority_token"
release_mutex=0
exit 0
