#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: bare-grok.sh --task-id <id> (--spec-file <path> | --spec <text>) [--workdir <dir>]

Runs grok in an isolated working directory (never the caller's cwd) so any files
the model produces are captured there rather than polluting the caller. With
--workdir <dir> the model's produced files persist in that directory (created if
absent) for the caller to score; without it, an ephemeral workdir is used and
discarded.

Emits JSON: { "model": "grok", "track": "bare", "taskId": "...", "output": "<raw stdout>" }.
USAGE
}

die_usage() {
  printf 'bare-grok: %s\n' "$*" >&2
  usage
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'bare-grok: required command not found on PATH: %s\n' "$1" >&2
    exit 4
  fi
}

task_id=""
spec_file=""
spec_text=""
workdir_arg=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)
      [[ $# -ge 2 ]] || die_usage "missing value for --task-id"
      task_id="$2"
      shift 2
      ;;
    --spec-file)
      [[ $# -ge 2 ]] || die_usage "missing value for --spec-file"
      spec_file="$2"
      shift 2
      ;;
    --spec)
      [[ $# -ge 2 ]] || die_usage "missing value for --spec"
      spec_text="$2"
      shift 2
      ;;
    --workdir)
      [[ $# -ge 2 ]] || die_usage "missing value for --workdir"
      workdir_arg="$2"
      shift 2
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      die_usage "unknown argument: $1"
      ;;
  esac
done

[[ -n "$task_id" ]] || die_usage "--task-id is required"
if [[ -n "$spec_file" && -n "$spec_text" ]]; then
  die_usage "pass only one of --spec-file or --spec"
fi
if [[ -z "$spec_file" && -z "$spec_text" ]]; then
  die_usage "one of --spec-file or --spec is required"
fi
if [[ -n "$spec_file" && ! -f "$spec_file" ]]; then
  die_usage "--spec-file does not exist: $spec_file"
fi

require_cmd jq
require_cmd grok

# Meta dir holds prompt/output/stderr; always discarded. Kept separate from the
# workdir so these files never land among the model's produced (scorable) files.
meta="$(mktemp -d)"
if [[ -n "$workdir_arg" ]]; then
  mkdir -p "$workdir_arg"
  workdir="$workdir_arg"
  trap 'rm -rf "$meta"' EXIT
else
  workdir="$(mktemp -d)"
  trap 'rm -rf "$meta" "$workdir"' EXIT
fi

prompt_file="$meta/prompt.txt"
output_file="$meta/output.txt"
stderr_file="$meta/stderr.txt"

if [[ -n "$spec_file" ]]; then
  spec_text="$(cat "$spec_file")"
fi

{
  printf 'Complete the following task.\n\n'
  printf '%s\n' "$spec_text"
} >"$prompt_file"

set +e
( cd "$workdir" && grok --prompt-file "$prompt_file" ) >"$output_file" 2>"$stderr_file"
grok_status=$?
set -e

if [[ "$grok_status" -ne 0 ]]; then
  cat "$stderr_file" >&2
  exit 2
fi

jq -n \
  --arg model "grok" \
  --arg track "bare" \
  --arg taskId "$task_id" \
  --rawfile output "$output_file" \
  '{model: $model, track: $track, taskId: $taskId, output: $output}'
