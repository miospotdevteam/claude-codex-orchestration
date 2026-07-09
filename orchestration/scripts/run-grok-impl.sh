#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: run-grok-impl.sh --plan-id <id> --step-id <id> --root-dir <absolute-path> [--skill <name>]
USAGE
}

die_usage() {
  printf 'run-grok-impl: %s\n' "$*" >&2
  usage
  exit 1
}

die_missing_grok() {
  printf 'run-grok-impl: grok binary not found on PATH\n' >&2
  exit 4
}

plan_id=""
step_id=""
root_dir=""
skill=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-id)
      [[ $# -ge 2 ]] || die_usage "missing value for --plan-id"
      plan_id="$2"
      shift 2
      ;;
    --step-id)
      [[ $# -ge 2 ]] || die_usage "missing value for --step-id"
      step_id="$2"
      shift 2
      ;;
    --root-dir)
      [[ $# -ge 2 ]] || die_usage "missing value for --root-dir"
      root_dir="$2"
      shift 2
      ;;
    --skill)
      [[ $# -ge 2 ]] || die_usage "missing value for --skill"
      skill="$2"
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

[[ -n "$plan_id" ]] || die_usage "--plan-id is required"
[[ -n "$step_id" ]] || die_usage "--step-id is required"
[[ -n "$root_dir" ]] || die_usage "--root-dir is required"
[[ "$root_dir" = /* ]] || die_usage "--root-dir must be an absolute path"
[[ -d "$root_dir" ]] || die_usage "--root-dir does not exist: $root_dir"

if ! command -v grok >/dev/null 2>&1; then
  die_missing_grok
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
parser="$script_dir/parse-contract.sh"
[[ -x "$parser" ]] || die_usage "missing executable parser: $parser"

step_block="$(cat)"
logs_dir="$root_dir/.temp/plan-mode/active/$plan_id/logs"
log_file="$logs_dir/grok-impl-$step_id.log"
mkdir -p "$logs_dir"

prompt_file="$(mktemp "$logs_dir/prompt.XXXXXX")"
parse_err="$(mktemp "$logs_dir/parse-error.XXXXXX")"
trap 'rm -f "$prompt_file" "$parse_err"' EXIT

{
  cat <<EOF
You are Grok Build running in IMPLEMENT mode for the
orchestration plugin. You will edit files in $root_dir to satisfy
the step described below. You may not change tests in a way that
hides failures. You must finish with the contract block.

Honor engineering-discipline while executing this implementation step.
EOF

  if [[ -n "$skill" ]]; then
    printf '\nHonor the step-specific skill %s while executing this implementation step.\n' "$skill"
  fi

  printf '\n%s\n\n' "$step_block"

  cat <<'EOF'
Your final output must end with the contract block in the exact shape specified. Do not omit any field. Do not emit anything after === END-CONTRACT ===.
EOF
} >"$prompt_file"

set +e
grok \
  --prompt-file "$prompt_file" \
  --cwd "$root_dir" \
  -m grok-build \
  --always-approve \
  --max-turns 40 \
  >"$log_file" 2>&1
grok_status=$?
set -e

if [[ $grok_status -ne 0 ]]; then
  exit 2
fi

if ! "$parser" <"$log_file" 2>"$parse_err"; then
  cat "$parse_err" >&2
  exit 3
fi
