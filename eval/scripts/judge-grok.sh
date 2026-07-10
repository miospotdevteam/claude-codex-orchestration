#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: judge-grok.sh --task-id <id> [--track <track>] (--bundle-file <path> | --bundle <text>) (--rubric-file <path> | --rubric <text>)

The Grok judge must return JSON with scores.A, scores.B, scores.C, and rationale.
This helper validates and normalizes that output to:
{ "judge": "grok", "taskId": "...", "track": "...", "scores": {"A": n, "B": n, "C": n}, "rationale": "..." }.
USAGE
}

die_usage() {
  printf 'judge-grok: %s\n' "$*" >&2
  usage
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'judge-grok: required command not found on PATH: %s\n' "$1" >&2
    exit 4
  fi
}

task_id=""
track="unknown"
bundle_file=""
bundle_text=""
rubric_file=""
rubric_text=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)
      [[ $# -ge 2 ]] || die_usage "missing value for --task-id"
      task_id="$2"
      shift 2
      ;;
    --track)
      [[ $# -ge 2 ]] || die_usage "missing value for --track"
      track="$2"
      shift 2
      ;;
    --bundle-file)
      [[ $# -ge 2 ]] || die_usage "missing value for --bundle-file"
      bundle_file="$2"
      shift 2
      ;;
    --bundle)
      [[ $# -ge 2 ]] || die_usage "missing value for --bundle"
      bundle_text="$2"
      shift 2
      ;;
    --rubric-file)
      [[ $# -ge 2 ]] || die_usage "missing value for --rubric-file"
      rubric_file="$2"
      shift 2
      ;;
    --rubric)
      [[ $# -ge 2 ]] || die_usage "missing value for --rubric"
      rubric_text="$2"
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
if [[ -n "$bundle_file" && -n "$bundle_text" ]]; then
  die_usage "pass only one of --bundle-file or --bundle"
fi
if [[ -z "$bundle_file" && -z "$bundle_text" ]]; then
  die_usage "one of --bundle-file or --bundle is required"
fi
if [[ -n "$rubric_file" && -n "$rubric_text" ]]; then
  die_usage "pass only one of --rubric-file or --rubric"
fi
if [[ -z "$rubric_file" && -z "$rubric_text" ]]; then
  die_usage "one of --rubric-file or --rubric is required"
fi
if [[ -n "$bundle_file" && ! -f "$bundle_file" ]]; then
  die_usage "--bundle-file does not exist: $bundle_file"
fi
if [[ -n "$bundle_file" && ! -s "$bundle_file" ]]; then
  die_usage "--bundle-file is empty: $bundle_file"
fi
if [[ -n "$rubric_file" && ! -f "$rubric_file" ]]; then
  die_usage "--rubric-file does not exist: $rubric_file"
fi
if [[ -n "$rubric_file" && ! -s "$rubric_file" ]]; then
  die_usage "--rubric-file is empty: $rubric_file"
fi

require_cmd jq
require_cmd grok
require_cmd python3

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
extractor="$script_dir/extract-judge-json.py"

sandbox="$(mktemp -d)"
sandbox="$(cd "$sandbox" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT

prompt_file="$sandbox/prompt.txt"
output_file="$sandbox/output.txt"
extracted_file="$sandbox/extracted.json"
stderr_file="$sandbox/stderr.txt"
bundle_input="$sandbox/bundle.txt"
rubric_input="$sandbox/rubric.txt"

if [[ -n "$bundle_file" ]]; then
  cp "$bundle_file" "$bundle_input"
else
  printf '%s\n' "$bundle_text" >"$bundle_input"
fi
if [[ -n "$rubric_file" ]]; then
  cp "$rubric_file" "$rubric_input"
else
  printf '%s\n' "$rubric_text" >"$rubric_input"
fi

bundle_text="$(cat "$bundle_input")"
rubric_text="$(cat "$rubric_input")"

{
  cat <<EOF
You are a blind routing-eval judge. Score candidates A, B, and C against the
rubric for task "$task_id" on track "$track".

OUTPUT RULES (STRICT):
- Return ONLY a single JSON object and NOTHING else: no prose, no explanation,
  no markdown, no code fences.
- Exact shape: {"scores":{"A":<number>,"B":<number>,"C":<number>},"rationale":"<short reason>"}
- Each score is that candidate's OVERALL quality as ONE number on a 0.0 to 5.0
  scale (5 = excellent). Do NOT sum per-dimension points; give a single overall
  0-5 value per candidate.

Rubric:
$rubric_text

Anonymized candidate bundle:
$bundle_text
EOF
} >"$prompt_file"

# grok often wraps its JSON in prose/markdown; extract the score object robustly
# and retry once if the CLI errors or emits nothing parseable.
run_and_extract() {
  set +e
  (
    cd "$sandbox"
    grok \
      --prompt-file prompt.txt \
      --cwd "$sandbox" \
      --deny 'Write' \
      --deny 'Edit' \
      --deny 'Bash' \
      >output.txt 2>stderr.txt
  )
  local status=$?
  set -e
  [[ "$status" -eq 0 ]] || { cat "$stderr_file" >&2; return 1; }
  python3 "$extractor" <"$output_file" >"$extracted_file" 2>>"$stderr_file"
}

if ! run_and_extract; then
  if ! run_and_extract; then
    printf 'judge-grok: model output was not valid judge JSON (after retry)\n' >&2
    exit 3
  fi
fi

if ! jq -e \
  'def valid_score: type == "number" and . >= 0 and . <= 5;
   type == "object"
   and (.scores | type == "object")
   and (.scores.A | valid_score)
   and (.scores.B | valid_score)
   and (.scores.C | valid_score)
   and (.rationale | type == "string")' \
  "$extracted_file" >/dev/null; then
  printf 'judge-grok: extracted output failed schema validation\n' >&2
  exit 3
fi

jq \
  --arg judge "grok" \
  --arg taskId "$task_id" \
  --arg track "$track" \
  '{judge: $judge, taskId: $taskId, track: $track, scores: {A: .scores.A, B: .scores.B, C: .scores.C}, rationale: .rationale}' \
  "$extracted_file"
