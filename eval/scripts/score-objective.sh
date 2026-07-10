#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: score-objective.sh --candidate-dir <dir> --tests-dir <dir> --task-id <id> --model <model> --track <track>

Scores a candidate output directory against a task's hidden tests.

Required flags:
  --candidate-dir <dir>  Directory containing the candidate's produced files.
  --tests-dir <dir>      Directory containing the task's hidden tests/run.sh.
  --task-id <id>         Task identity, for example backend/url-shortener.
  --model <model>        Candidate model identity, for example codex.
  --track <track>        Invocation track identity, for example A or B.

Contract:
  tests/run.sh is invoked as: tests/run.sh <candidate_dir>
  Its final stdout line must be exactly: RESULT <passed> <total>
  <passed> and <total> must be non-negative integers, and total must be > 0.
  Exit status must be 0 exactly when passed equals total.
USAGE
}

die() {
  printf 'score-objective: %s\n' "$*" >&2
  exit 1
}

need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    die "jq is required but was not found in PATH"
  fi
}

candidate_dir=""
tests_dir=""
task_id=""
model=""
track=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --candidate-dir)
      [[ $# -ge 2 ]] || die "--candidate-dir requires a value"
      candidate_dir=$2
      shift 2
      ;;
    --tests-dir)
      [[ $# -ge 2 ]] || die "--tests-dir requires a value"
      tests_dir=$2
      shift 2
      ;;
    --task-id)
      [[ $# -ge 2 ]] || die "--task-id requires a value"
      task_id=$2
      shift 2
      ;;
    --model)
      [[ $# -ge 2 ]] || die "--model requires a value"
      model=$2
      shift 2
      ;;
    --track)
      [[ $# -ge 2 ]] || die "--track requires a value"
      track=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

need_jq

[[ -n "$candidate_dir" ]] || die "missing required flag: --candidate-dir"
[[ -n "$tests_dir" ]] || die "missing required flag: --tests-dir"
[[ -n "$task_id" ]] || die "missing required flag: --task-id"
[[ -n "$model" ]] || die "missing required flag: --model"
[[ -n "$track" ]] || die "missing required flag: --track"

[[ -d "$candidate_dir" ]] || die "candidate directory not found: $candidate_dir"
[[ -d "$tests_dir" ]] || die "tests directory not found: $tests_dir"
[[ -f "$tests_dir/run.sh" ]] || die "tests/run.sh not found in: $tests_dir"
[[ -x "$tests_dir/run.sh" ]] || die "tests/run.sh is not executable: $tests_dir/run.sh"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

staged_candidate="$sandbox/candidate"
staged_tests="$sandbox/tests"
mkdir -p "$staged_candidate" "$staged_tests"
cp -R "$candidate_dir"/. "$staged_candidate"/
cp -R "$tests_dir"/. "$staged_tests"/

run_stdout="$sandbox/run.stdout"
run_stderr="$sandbox/run.stderr"

set +e
(
  cd "$sandbox"
  ./tests/run.sh "$staged_candidate"
) >"$run_stdout" 2>"$run_stderr"
run_status=$?
set -e

result_line="$(tail -n 1 "$run_stdout" 2>/dev/null || true)"
if [[ ! "$result_line" =~ ^RESULT\ ([0-9]+)\ ([0-9]+)$ ]]; then
  if [[ -s "$run_stderr" ]]; then
    die "tests/run.sh emitted no final RESULT line; exit status $run_status; stderr: $(<"$run_stderr")"
  fi
  die "tests/run.sh emitted no final RESULT line; exit status $run_status"
fi

passed="${BASH_REMATCH[1]}"
total="${BASH_REMATCH[2]}"

if ((total == 0)); then
  die "zero tests reported by tests/run.sh"
fi

if ((passed > total)); then
  die "invalid RESULT line: passed exceeds total ($passed > $total)"
fi

if ((passed == total && run_status != 0)); then
  die "exit status $run_status contradicts full-pass RESULT $passed $total"
fi

if ((passed < total && run_status == 0)); then
  die "exit status 0 contradicts partial RESULT $passed $total"
fi

jq -n \
  --arg taskId "$task_id" \
  --arg model "$model" \
  --arg track "$track" \
  --argjson passed "$passed" \
  --argjson total "$total" \
  '{
    taskId: $taskId,
    model: $model,
    track: $track,
    passed: $passed,
    total: $total,
    correctness: ($passed / $total)
  }'
