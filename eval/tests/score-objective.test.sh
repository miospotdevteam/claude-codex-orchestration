#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCORER="$SCRIPT_DIR/../scripts/score-objective.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf 'PASS %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

make_candidate() {
  local dir=$1
  mkdir -p "$dir"
  printf 'candidate output\n' >"$dir/output.txt"
}

make_tests() {
  local dir=$1
  local passed=$2
  local total=$3
  local exit_code=$4

  mkdir -p "$dir"
  cat >"$dir/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

candidate_dir=\${1:?candidate dir required}
[[ -f "\$candidate_dir/output.txt" ]]
printf 'test harness detail line\n'
printf 'RESULT %d %d\n' "$passed" "$total"
exit "$exit_code"
EOF
  chmod +x "$dir/run.sh"
}

run_scorer() {
  local candidate_dir=$1
  local tests_dir=$2
  local stdout=$3
  local stderr=$4

  "$SCORER" \
    --candidate-dir "$candidate_dir" \
    --tests-dir "$tests_dir" \
    --task-id "backend/fixture" \
    --model "codex" \
    --track "A" \
    >"$stdout" 2>"$stderr"
}

assert_json_score() {
  local name=$1
  local file=$2
  local passed=$3
  local total=$4
  local correctness=$5

  if ! jq -e \
    --arg task_id "backend/fixture" \
    --arg model "codex" \
    --arg track "A" \
    --argjson passed "$passed" \
    --argjson total "$total" \
    --argjson correctness "$correctness" \
    '.taskId == $task_id
      and .model == $model
      and .track == $track
      and .passed == $passed
      and .total == $total
      and .correctness == $correctness' \
    "$file" >/dev/null; then
    fail "$name" "unexpected score JSON: $(<"$file")"
    return 1
  fi
}

expect_score() {
  local name=$1
  local passed=$2
  local total=$3
  local exit_code=$4
  local correctness=$5
  local fixture="$TMP_DIR/$name"
  local stdout="$fixture/stdout.json"
  local stderr="$fixture/stderr.txt"

  mkdir -p "$fixture"
  make_candidate "$fixture/candidate"
  make_tests "$fixture/tests" "$passed" "$total" "$exit_code"

  if ! run_scorer "$fixture/candidate" "$fixture/tests" "$stdout" "$stderr"; then
    fail "$name" "expected scorer success, got failure: $(<"$stderr")"
    return
  fi

  if [[ -s "$stderr" ]]; then
    fail "$name" "expected empty stderr, got: $(<"$stderr")"
    return
  fi

  assert_json_score "$name" "$stdout" "$passed" "$total" "$correctness" || return
  pass "$name"
}

expect_failure() {
  local name=$1
  local candidate_dir=$2
  local tests_dir=$3
  local expected_message=$4
  local fixture="$TMP_DIR/$name"
  local stdout="$fixture/stdout.txt"
  local stderr="$fixture/stderr.txt"

  mkdir -p "$fixture"

  if run_scorer "$candidate_dir" "$tests_dir" "$stdout" "$stderr"; then
    fail "$name" "expected scorer failure, got success: $(<"$stdout")"
    return
  fi

  if [[ -s "$stdout" ]]; then
    fail "$name" "expected empty stdout on failure, got: $(<"$stdout")"
    return
  fi

  if ! grep -Fq "$expected_message" "$stderr"; then
    fail "$name" "stderr did not contain '$expected_message': $(<"$stderr")"
    return
  fi

  pass "$name"
}

expect_score "all-pass fixture scores 1.0" 3 3 0 1
expect_score "partial-pass fixture preserves nonzero failure score" 2 5 1 0.4
expect_score "all-fail fixture scores 0.0" 0 4 1 0

missing_fixture="$TMP_DIR/missing-tests"
mkdir -p "$missing_fixture"
make_candidate "$missing_fixture/candidate"
expect_failure \
  "missing tests dir is explicit error" \
  "$missing_fixture/candidate" \
  "$missing_fixture/tests" \
  "tests directory not found"

zero_fixture="$TMP_DIR/zero-tests"
mkdir -p "$zero_fixture"
make_candidate "$zero_fixture/candidate"
make_tests "$zero_fixture/tests" 0 0 0
expect_failure \
  "zero tests is explicit error" \
  "$zero_fixture/candidate" \
  "$zero_fixture/tests" \
  "zero tests"

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
