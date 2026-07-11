#!/usr/bin/env bash
set -euo pipefail

# --max-turns is capped at 80 (raised from 40, which exhausted on realistic
# workloads 2026-07-10); exhaustion surfaces as exit 2 plus a diagnostic log.

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
case "$plan_id" in */* | *..*) die_usage "--plan-id must be a plain identifier (no / or ..)" ;; esac
case "$step_id" in */* | *..*) die_usage "--step-id must be a plain identifier (no / or ..)" ;; esac
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
# Real plans keep logs beside plan.json; synthetic/out-of-band ids must not
# mkdir plan-less debris under active/.
if [[ -f "$root_dir/.temp/plan-mode/active/$plan_id/plan.json" ]]; then
  logs_dir="$root_dir/.temp/plan-mode/active/$plan_id/logs"
else
  logs_dir="$root_dir/.temp/plan-mode/logs/$plan_id"
fi
log_file="$logs_dir/grok-impl-$step_id.log"
mkdir -p "$logs_dir"
# Recheck after mkdir: if archive-plan moved the plan between the
# plan.json check and mkdir, drop the recreated debris dir and fall
# back to the out-of-band location.
if [[ "$logs_dir" == "$root_dir/.temp/plan-mode/active/"* && ! -f "$root_dir/.temp/plan-mode/active/$plan_id/plan.json" ]]; then
  rmdir "$logs_dir" 2>/dev/null || true
  rmdir "$root_dir/.temp/plan-mode/active/$plan_id" 2>/dev/null || true
  logs_dir="$root_dir/.temp/plan-mode/logs/$plan_id"
  log_file="$logs_dir/grok-impl-$step_id.log"
  mkdir -p "$logs_dir"
fi

prompt_file="$(mktemp "$logs_dir/prompt.XXXXXX")"
parse_err="$(mktemp "$logs_dir/parse-error.XXXXXX")"
stdout_file="$(mktemp "$logs_dir/stdout.XXXXXX")"
stderr_file="$(mktemp "$logs_dir/stderr.XXXXXX")"
contract_file="$(mktemp "$logs_dir/contract.XXXXXX")"
trap 'rm -f "$prompt_file" "$parse_err" "$stdout_file" "$stderr_file" "$contract_file"' EXIT

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

The block must be plain text: no markdown bold, exact field labels, both sentinel lines mandatory, nothing after the closing sentinel.

=== ORCHESTRATION-CONTRACT ===
Summary: <one paragraph, at most 6 sentences, plain prose>
Verdict: PASS | FINDINGS | FAIL
Findings:
- <one-line finding, or omit on PASS>
FilesTouched:
=== END-CONTRACT ===
EOF
} >"$prompt_file"

# Capture stdout and stderr separately and parse stdout only, so a CLI footer or
# late stderr diagnostic cannot force a spurious exit 3. A merged copy is written
# to the log dir for human debugging.
set +e
grok \
  --prompt-file "$prompt_file" \
  --cwd "$root_dir" \
  -m grok-4.5 \
  --always-approve \
  --max-turns 80 \
  >"$stdout_file" 2>"$stderr_file"
grok_status=$?
set -e

{
  printf '%s\n' '--- grok stdout ---'
  cat "$stdout_file"
  printf '%s\n' '--- grok stderr ---'
  cat "$stderr_file"
} >"$log_file"

if [[ $grok_status -ne 0 ]]; then
  exit 2
fi

parse_input="$stdout_file"
if awk '
  BEGIN {
    open_sentinel = "=== ORCHESTRATION-CONTRACT ==="
    close_sentinel = "=== END-CONTRACT ==="
  }
  {
    comparison = $0
    sub(/\r$/, "", comparison)

    if (comparison == open_sentinel) {
      capturing = 1
      block = $0 ORS
      next
    }

    if (capturing) {
      block = block $0 ORS
      if (comparison == close_sentinel) {
        last_complete = block
        found_complete = 1
        capturing = 0
      }
    }
  }
  END {
    if (!found_complete) {
      exit 1
    }
    printf "%s", last_complete
  }
' "$stdout_file" >"$contract_file"; then
  parse_input="$contract_file"
fi

if ! "$parser" <"$parse_input" 2>"$parse_err"; then
  cat "$parse_err" >&2
  exit 3
fi
