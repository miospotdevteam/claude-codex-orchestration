#!/usr/bin/env bash
set -euo pipefail

# Stateless desktop relay for the Mini-resident workflow registry.  Every verb
# maps to exactly one serialized registry operation over SSH; the registry owns
# every workflow decision.  This helper keeps no local state, holds no waits,
# and never orchestrates.
umask 077

readonly MAX_PROMPT_BYTES=65536
readonly MAX_OUTPUT_BYTES=4096

usage() {
  cat >&2 <<'EOF'
usage: remote-agent.sh [--host HOST] VERB [ARGUMENTS]
verbs:
  list
  inspect WORKFLOW_ID
  wait WORKFLOW_ID --cursor CURSOR --timeout SECONDS
  start-conductor PROJECT PLAN_ID
  send WORKFLOW_ID (--prompt-file FILE [--ack-event SEQ] | --cancel-pending)
  interrupt WORKFLOW_ID
  kill WORKFLOW_ID
  release WORKFLOW_ID
  reveal WORKFLOW_ID
  sync WORKFLOW_ID [--cancel MIRROR_JOB]
       [--seed [--include-ignored PATH --approve-ignored PATH]]
  diagnostic ACTION PROJECT HARNESS [--prompt-file FILE]
    (ACTION: start, inspect, send, interrupt, kill, release)
every mutation accepts --request-id ID to replay one exact request
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

valid_request_id() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$ ]]
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

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum <"$1" | awk '{print $1}'
  else
    shasum -a 256 <"$1" | awk '{print $1}'
  fi
}

mint_request_id() {
  local stamp rand
  stamp=$(date -u '+%Y%m%dT%H%M%SZ')
  rand=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
  printf 'req-%s-%s\n' "$stamp" "$rand"
}

serialize_ssh_command() {
  local argument escaped separator=''
  REPLY=''
  [[ $# -gt 0 ]] || die 'internal empty registry command'
  for argument in "$@"; do
    # POSIX shells represent one apostrophe inside single quotes as '\''.
    escaped=${argument//\'/\'\\\'\'}
    REPLY+="${separator}'${escaped}'"
    separator=' '
  done
}

# One serialized registry operation per invocation.  The response is passed
# through bounded; the exit status is the registry's own.  SSH transport
# failure (255) is reported as mini-unreachable without any retry or cleanup.
# Every network-path outcome goes to stdout as one bounded envelope; raw SSH
# transport stderr is never exposed.
run_registry() {
  local stdin_source=$1 remote_command response status=0
  shift
  serialize_ssh_command "$registry_bin" "$@"
  remote_command=$REPLY
  # Payload bytes travel only on stdin; argv carries labels and digests.
  # shellcheck disable=SC2029
  if response=$(ssh "$host" "$remote_command" <"$stdin_source" 2>/dev/null); then
    status=0
  else
    status=$?
  fi
  if [[ -n $response ]]; then
    printf '%s\n' "${response:0:MAX_OUTPUT_BYTES}"
  fi
  if [[ $status -eq 255 ]]; then
    printf 'remote-agent: mini-unreachable: the Mini registry did not answer\n'
  fi
  return "$status"
}

relay_read() {
  run_registry /dev/null "$@"
}

# The requestId is minted (or reused) before the network send and printed in
# every outcome so a retry can replay the identical request.
relay_mutation() {
  local stdin_source=$1
  shift
  if [[ -z $request_id ]]; then
    request_id=$(mint_request_id)
  fi
  printf 'remote-agent: requestId=%s\n' "$request_id"
  run_registry "$stdin_source" "$@" --request-id "$request_id"
}

take_request_id() {
  [[ -n ${1:-} && -z $request_id ]] || die 'invalid --request-id'
  valid_request_id "$1" || die 'invalid --request-id'
  request_id=$1
}

prepare_prompt() {
  local file=$1 bytes
  [[ -f $file && ! -L $file && -r $file ]] || die 'prompt file must be a readable regular non-symlink file'
  bytes=$(wc -c <"$file" | tr -d ' ')
  [[ $bytes -le $MAX_PROMPT_BYTES ]] || die "prompt exceeds the ${MAX_PROMPT_BYTES}-byte relay bound"
  prompt_digest=$(sha256_file "$file")
}

# Seed consent is the single ignored-path exception and is checked against the
# local checkout before anything crosses the network.
seed_local_root() {
  local workflow_id=$1 project
  [[ $workflow_id =~ ^wf-([a-z0-9][a-z0-9-]{0,47})-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}$ ]] \
    || die 'seed consent requires a canonical workflow id'
  project=${BASH_REMATCH[1]}
  case $project in
    miospot) local_root=${LOCAL_MIOSPOT_ROOT:-"$HOME/Projects/miospot"} ;;
    orchestration) local_root=${LOCAL_ORCHESTRATION_ROOT:-"$HOME/Projects/orchestration"} ;;
    *) die 'seed consent requires a configured local checkout' ;;
  esac
  [[ -d $local_root && ! -L $local_root ]] || die 'local checkout for seed consent is missing'
}

host=''
if [[ ${1:-} == --host ]]; then
  [[ $# -ge 2 ]] || { usage; exit 2; }
  host=$2
  shift 2
fi

[[ $# -ge 1 ]] || { usage; exit 2; }
verb=$1
shift

case $verb in
  list|inspect|wait|start-conductor|send|interrupt|kill|release|reveal|sync|diagnostic) ;;
  *) usage; exit 2 ;;
esac

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

registry_bin=${REMOTE_REGISTRY_BIN:-workflow-registry}
request_id=''
prompt_digest=''
local_root=''

case $verb in
  list)
    [[ $# -eq 0 ]] || die 'list takes no arguments'
    relay_read list
    ;;
  inspect)
    [[ $# -eq 1 ]] || die 'inspect requires exactly one workflow id'
    valid_atom "$1" || die 'invalid workflow id'
    relay_read inspect "$1"
    ;;
  wait)
    [[ $# -eq 5 && ${2:-} == --cursor && ${4:-} == --timeout ]] \
      || die 'wait requires WORKFLOW_ID --cursor CURSOR --timeout SECONDS'
    valid_atom "$1" || die 'invalid workflow id'
    [[ $3 =~ ^[A-Za-z0-9._-]+:[0-9]+$ ]] || die 'invalid wait cursor'
    if [[ ! $5 =~ ^[0-9]{1,3}$ ]] || (( $5 > 300 )); then
      die 'wait timeout must be an integer from 0 through 300'
    fi
    relay_read wait "$1" --cursor "$3" --timeout "$5"
    ;;
  start-conductor)
    positional=()
    while [[ $# -gt 0 ]]; do
      case $1 in
        --request-id) take_request_id "${2:-}"; shift 2 ;;
        --*) die "unknown option: $1" ;;
        *) positional+=("$1"); shift ;;
      esac
    done
    [[ ${#positional[@]} -eq 2 ]] || die 'start-conductor requires PROJECT PLAN_ID'
    valid_atom "${positional[0]}" || die 'invalid project'
    valid_atom "${positional[1]}" || die 'invalid plan selector'
    relay_mutation /dev/null start-conductor "${positional[0]}" "${positional[1]}"
    ;;
  send)
    [[ $# -ge 1 && ${1:0:2} != -- ]] || die 'send requires a workflow id'
    workflow=$1
    shift
    valid_atom "$workflow" || die 'invalid workflow id'
    prompt_file=''
    ack_event=''
    cancel_pending=0
    while [[ $# -gt 0 ]]; do
      case $1 in
        --prompt-file)
          [[ $# -ge 2 && -z $prompt_file ]] || die 'invalid --prompt-file'
          prompt_file=$2
          shift 2
          ;;
        --ack-event)
          [[ $# -ge 2 && -z $ack_event ]] || die 'invalid --ack-event'
          ack_event=$2
          shift 2
          ;;
        --cancel-pending)
          [[ $cancel_pending -eq 0 ]] || die 'duplicate --cancel-pending'
          cancel_pending=1
          shift
          ;;
        --request-id) take_request_id "${2:-}"; shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    if [[ $cancel_pending -eq 1 ]]; then
      [[ -z $prompt_file && -z $ack_event ]] || die 'cancel-pending takes no payload options'
      relay_mutation /dev/null send "$workflow" --cancel-pending
    else
      [[ -n $prompt_file ]] || die 'send requires --prompt-file or --cancel-pending'
      [[ -z $ack_event || $ack_event =~ ^[0-9]+$ ]] || die 'ack-event must be numeric'
      prepare_prompt "$prompt_file"
      if [[ -n $ack_event ]]; then
        relay_mutation "$prompt_file" send "$workflow" \
          --payload-sha256 "$prompt_digest" --ack-event "$ack_event"
      else
        relay_mutation "$prompt_file" send "$workflow" --payload-sha256 "$prompt_digest"
      fi
    fi
    ;;
  interrupt|kill|release|reveal)
    [[ $# -ge 1 && ${1:0:2} != -- ]] || die "$verb requires a workflow id"
    workflow=$1
    shift
    valid_atom "$workflow" || die 'invalid workflow id'
    while [[ $# -gt 0 ]]; do
      case $1 in
        --request-id) take_request_id "${2:-}"; shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    relay_mutation /dev/null "$verb" "$workflow"
    ;;
  sync)
    [[ $# -ge 1 && ${1:0:2} != -- ]] || die 'sync requires a workflow id'
    workflow=$1
    shift
    valid_atom "$workflow" || die 'invalid workflow id'
    cancel_job=''
    seed=0
    include_ignored=''
    approve_ignored=''
    while [[ $# -gt 0 ]]; do
      case $1 in
        --cancel)
          [[ $# -ge 2 && -z $cancel_job ]] || die 'invalid --cancel'
          valid_atom "$2" || die 'invalid mirror job id'
          cancel_job=$2
          shift 2
          ;;
        --seed)
          [[ $seed -eq 0 ]] || die 'duplicate --seed'
          seed=1
          shift
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
        --request-id) take_request_id "${2:-}"; shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    if [[ -n $cancel_job ]]; then
      [[ $seed -eq 0 && -z $include_ignored && -z $approve_ignored ]] \
        || die 'sync --cancel takes no seed options'
      relay_mutation /dev/null mirror-cancel "$workflow" "$cancel_job"
    elif [[ -n $include_ignored || -n $approve_ignored ]]; then
      [[ $seed -eq 1 ]] || die 'ignored-path handoff is only valid on a seed sync'
      [[ -n $include_ignored && $include_ignored == "$approve_ignored" ]] \
        || die 'ignored path needs identical explicit approval'
      valid_relative_path "$include_ignored" || die 'invalid ignored path'
      contains_glob "$include_ignored" && die 'ignored approval must name one literal path'
      seed_local_root "$workflow"
      git -C "$local_root" check-ignore -- "$include_ignored" >/dev/null 2>&1 \
        || die 'approved seed path must be ignored'
      relay_mutation /dev/null request-mirror-sync "$workflow" --seed \
        --include-ignored "$include_ignored" --approve-ignored "$include_ignored"
    elif [[ $seed -eq 1 ]]; then
      relay_mutation /dev/null request-mirror-sync "$workflow" --seed
    else
      relay_mutation /dev/null request-mirror-sync "$workflow"
    fi
    ;;
  diagnostic)
    [[ $# -ge 3 ]] || die 'diagnostic requires ACTION PROJECT HARNESS'
    action=$1
    project=$2
    diag_harness=$3
    shift 3
    case $action in
      start|inspect|send|interrupt|kill|release) ;;
      *) die "unknown diagnostic action: $action" ;;
    esac
    valid_atom "$project" || die 'invalid project'
    valid_atom "$diag_harness" || die 'invalid harness'
    prompt_file=''
    while [[ $# -gt 0 ]]; do
      case $1 in
        --prompt-file)
          [[ $action == send && $# -ge 2 && -z $prompt_file ]] || die 'invalid --prompt-file'
          prompt_file=$2
          shift 2
          ;;
        --request-id) take_request_id "${2:-}"; shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    case $action in
      inspect)
        relay_read diagnostic-inspect "$project" "$diag_harness"
        ;;
      send)
        [[ -n $prompt_file ]] || die 'diagnostic send requires --prompt-file'
        prepare_prompt "$prompt_file"
        relay_mutation "$prompt_file" diagnostic-send "$project" "$diag_harness" \
          --payload-sha256 "$prompt_digest"
        ;;
      *)
        relay_mutation /dev/null "diagnostic-$action" "$project" "$diag_harness"
        ;;
    esac
    ;;
esac
