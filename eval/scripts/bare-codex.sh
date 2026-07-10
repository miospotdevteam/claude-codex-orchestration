#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: bare-codex.sh --task-id <id> (--spec-file <path> | --spec <text>) [--workdir <dir>]

Runs codex in an isolated working directory (never the caller's cwd) so any files
the model produces are captured there rather than polluting the caller. With
--workdir <dir> the model's produced files persist in that directory (created if
absent) for the caller to score; without it, an ephemeral workdir is used and
discarded. Passes --skip-git-repo-check so codex runs in a non-git workdir.

Emits JSON: { "model": "codex", "track": "bare", "taskId": "...", "output": "<raw stdout>" }.
USAGE
}

die_usage() {
  printf 'bare-codex: %s\n' "$*" >&2
  usage
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'bare-codex: required command not found on PATH: %s\n' "$1" >&2
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
if [[ -n "$spec_file" && ! -s "$spec_file" ]]; then
  die_usage "--spec-file is empty: $spec_file"
fi

require_cmd jq
require_cmd codex

# Meta dir holds prompt/output/stderr; always discarded. Kept separate from the
# workdir so these files never land among the model's produced (scorable) files.
meta="$(mktemp -d)"
meta="$(cd "$meta" && pwd -P)"
if [[ -n "$workdir_arg" ]]; then
  mkdir -p "$workdir_arg"
  workdir="$(cd "$workdir_arg" && pwd -P)"
  trap 'rm -rf "$meta"' EXIT
else
  workdir="$(mktemp -d)"
  workdir="$(cd "$workdir" && pwd -P)"
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
# -C/-s/--skip-git-repo-check are execution-environment flags (same as the real
# wrapper) so the model can actually write files into the isolated workdir. They
# are NOT prompt scaffolding — the prompt itself stays bare (no header, no skill).
codex exec \
  -C "$workdir" \
  -s workspace-write \
  --skip-git-repo-check \
  - \
  <"$prompt_file" >"$output_file" 2>"$stderr_file"
codex_status=$?
set -e

if [[ "$codex_status" -ne 0 ]]; then
  cat "$stderr_file" >&2
  exit 2
fi

jq -n \
  --arg model "codex" \
  --arg track "bare" \
  --arg taskId "$task_id" \
  --rawfile output "$output_file" \
  '{model: $model, track: $track, taskId: $taskId, output: $output}'
