#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: run-codex-impl.sh --plan-id <id> --step-id <id> --root-dir <absolute-path> [--scenario <planning|exploration|implementation|design|bulk|review>] [--skill <name>]
USAGE
}

die_usage() {
  printf 'run-codex-impl: %s\n' "$*" >&2
  usage
  exit 1
}

plan_id=""
step_id=""
root_dir=""
skill=""
scenario="implementation"

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
    --scenario)
      [[ $# -ge 2 ]] || die_usage "missing value for --scenario"
      scenario="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die_usage "unknown argument: $1"
      ;;
  esac
done

[[ -n "$plan_id" ]] || die_usage "--plan-id is required"
case "$plan_id" in */* | *..*) die_usage "--plan-id must be a plain identifier (no / or ..)" ;; esac
case "$step_id" in */* | *..*) die_usage "--step-id must be a plain identifier (no / or ..)" ;; esac
[[ -n "$step_id" ]] || die_usage "--step-id is required"
[[ -n "$root_dir" ]] || die_usage "--root-dir is required"
[[ "$root_dir" = /* ]] || die_usage "--root-dir must be an absolute path"
[[ -d "$root_dir" ]] || die_usage "--root-dir does not exist: $root_dir"
case "$scenario" in
  planning|design)
    reasoning_effort="xhigh"
    ;;
  exploration|implementation|review)
    reasoning_effort="high"
    ;;
  bulk)
    reasoning_effort="medium"
    ;;
  *)
    die_usage "invalid --scenario: $scenario"
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
parser="$script_dir/parse-contract.sh"
[[ -x "$parser" ]] || die_usage "missing executable parser: $parser"

step_block="$(cat)"
# Real plans keep logs beside plan.json; synthetic/out-of-band ids must not
# mkdir plan-less debris under active/.
if [[ -f "$root_dir/.temp/plan-mode/active/$plan_id/plan.json" ]]; then
  logs_dir="$root_dir/.temp/plan-mode/active/$plan_id/logs"
else
  logs_dir="$root_dir/.temp/plan-mode/logs/$plan_id"
fi
log_file="$logs_dir/codex-impl-$step_id.log"
mkdir -p "$logs_dir"
# Recheck after mkdir: if archive-plan moved the plan between the
# plan.json check and mkdir, drop the recreated debris dir and fall
# back to the out-of-band location.
if [[ "$logs_dir" == "$root_dir/.temp/plan-mode/active/"* && ! -f "$root_dir/.temp/plan-mode/active/$plan_id/plan.json" ]]; then
  rmdir "$logs_dir" 2>/dev/null || true
  rmdir "$root_dir/.temp/plan-mode/active/$plan_id" 2>/dev/null || true
  logs_dir="$root_dir/.temp/plan-mode/logs/$plan_id"
  log_file="$logs_dir/codex-impl-$step_id.log"
  mkdir -p "$logs_dir"
fi

last_message_file="$(mktemp "$logs_dir/last-message.XXXXXX")"
prompt_file="$(mktemp "$logs_dir/prompt.XXXXXX")"
parse_err="$(mktemp "$logs_dir/parse-error.XXXXXX")"
stdout_file="$(mktemp "$logs_dir/stdout.XXXXXX")"
stderr_file="$(mktemp "$logs_dir/stderr.XXXXXX")"
trap 'rm -f "$last_message_file" "$prompt_file" "$parse_err" "$stdout_file" "$stderr_file"' EXIT

{
  cat <<EOF
You are Codex running in IMPLEMENT mode for the
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

=== ORCHESTRATION-CONTRACT ===
Summary: <one paragraph, at most 6 sentences, plain prose>
Verdict: PASS | FINDINGS | FAIL
Findings:
- <one-line finding, or omit on PASS>
FilesTouched:
=== END-CONTRACT ===
EOF
} >"$prompt_file"

# Capture stdout and stderr separately, and parse Codex's output-last-message
# file when it is non-empty. The merged log is retained for human debugging.
set +e
codex exec \
  -C "$root_dir" \
  -s workspace-write \
  -c "model_reasoning_effort=\"$reasoning_effort\"" \
  --skip-git-repo-check \
  -o "$last_message_file" \
  - \
  <"$prompt_file" \
  >"$stdout_file" 2>"$stderr_file"
codex_status=$?
set -e

{
  printf '%s\n' '--- codex stdout ---'
  cat "$stdout_file"
  printf '%s\n' '--- codex stderr ---'
  cat "$stderr_file"
} >"$log_file"

if [[ $codex_status -ne 0 ]]; then
  exit 2
fi

parse_source="$last_message_file"
if [[ ! -s "$parse_source" ]]; then
  parse_source="$stdout_file"
fi

if ! "$parser" <"$parse_source" 2>"$parse_err"; then
  cat "$parse_err" >&2
  exit 3
fi
