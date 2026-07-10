#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/../scripts"
ORIGINAL_PATH="$PATH"

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

run_test() {
  local name="$1"
  shift
  if "$@"; then
    :
  else
    fail "$name" "assertion failed"
  fi
}

assert_jq() {
  local file="$1"
  local filter="$2"
  jq -e "$filter" "$file" >/dev/null
}

assert_file_lacks() {
  local file="$1"
  local pattern="$2"
  ! grep -Fq -- "$pattern" "$file"
}

assert_argv_lacks_line() {
  local file="$1"
  local unexpected="$2"
  ! grep -qx -- "$unexpected" "$file"
}

assert_argv_has_pair() {
  local file="$1"
  local flag="$2"
  local value="$3"
  awk -v flag="$flag" -v value="$value" \
    '$0 == flag { getline; if ($0 == value) found = 1 } END { exit !found }' "$file"
}

write_mock_clis() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"

  cat >"$bin_dir/codex" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

: "${HELPER_MOCK_ARGV:?}"
: "${HELPER_MOCK_PROMPT:?}"
: "${HELPER_MOCK_CWD:?}"

printf '%s\n' "$@" >"$HELPER_MOCK_ARGV"
pwd -P >"$HELPER_MOCK_CWD"
cat >"$HELPER_MOCK_PROMPT"

if [[ "${HELPER_MOCK_REQUIRE_LOCAL_INPUTS:-0}" == "1" ]]; then
  [[ -s bundle.txt && -s rubric.txt ]] || exit 98
  printf '%s\n' "$(pwd -P)/bundle.txt" "$(pwd -P)/rubric.txt" >"${HELPER_MOCK_INPUTS:?}"
fi

case "${HELPER_MOCK_KIND:?}" in
  bare-codex)
    printf 'codex raw answer for %s\n' "${HELPER_MOCK_TASK_ID:-unknown}"
    ;;
  judge-codex)
    if [[ -n "${HELPER_MOCK_JUDGE_OUTPUT:-}" ]]; then
      printf '%s\n' "$HELPER_MOCK_JUDGE_OUTPUT"
    else
      printf '%s\n' '{"scores":{"A":4.1,"B":3,"C":5},"rationale":"Codex judge rationale."}'
    fi
    ;;
  *)
    printf 'unexpected codex mock kind: %s\n' "$HELPER_MOCK_KIND" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "$bin_dir/codex"

  cat >"$bin_dir/grok" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

: "${HELPER_MOCK_ARGV:?}"
: "${HELPER_MOCK_PROMPT:?}"
: "${HELPER_MOCK_CWD:?}"

printf '%s\n' "$@" >"$HELPER_MOCK_ARGV"
pwd -P >"$HELPER_MOCK_CWD"

prompt_file=""
while (($# > 0)); do
  case "$1" in
    --prompt-file)
      prompt_file="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "$prompt_file" ]]; then
  cat "$prompt_file" >"$HELPER_MOCK_PROMPT"
else
  cat >"$HELPER_MOCK_PROMPT"
fi

if [[ "${HELPER_MOCK_REQUIRE_LOCAL_INPUTS:-0}" == "1" ]]; then
  [[ -s bundle.txt && -s rubric.txt ]] || exit 98
  printf '%s\n' "$(pwd -P)/bundle.txt" "$(pwd -P)/rubric.txt" >"${HELPER_MOCK_INPUTS:?}"
fi

case "${HELPER_MOCK_KIND:?}" in
  bare-grok)
    printf 'grok raw answer for %s\n' "${HELPER_MOCK_TASK_ID:-unknown}"
    ;;
  judge-grok)
    if [[ -n "${HELPER_MOCK_JUDGE_OUTPUT:-}" ]]; then
      printf '%s\n' "$HELPER_MOCK_JUDGE_OUTPUT"
    else
      printf '%s\n' '{"scores":{"A":2,"B":4.5,"C":3.25},"rationale":"Grok judge rationale."}'
    fi
    ;;
  *)
    printf 'unexpected grok mock kind: %s\n' "$HELPER_MOCK_KIND" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "$bin_dir/grok"
}

run_helper() {
  local kind="$1"
  local script="$2"
  local output_file="$3"
  shift 3

  local case_dir="$TMP_DIR/$kind"
  local bin_dir="$case_dir/bin"
  local argv_file="$case_dir/argv.txt"
  local prompt_file="$case_dir/prompt.txt"
  local cwd_file="$case_dir/cwd.txt"
  local inputs_file="$case_dir/inputs.txt"
  local stderr_file="$case_dir/stderr.txt"
  local status

  mkdir -p "$case_dir"
  write_mock_clis "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    HELPER_MOCK_KIND="$kind" \
    HELPER_MOCK_TASK_ID="backend/example" \
    HELPER_MOCK_ARGV="$argv_file" \
    HELPER_MOCK_PROMPT="$prompt_file" \
    HELPER_MOCK_CWD="$cwd_file" \
    HELPER_MOCK_INPUTS="$inputs_file" \
    "$script" "$@" >"$output_file" 2>"$stderr_file"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    fail "$kind" "expected exit 0, got $status; stderr=$(<"$stderr_file")"
    return 1
  fi
  if [[ ! -s "$argv_file" ]]; then
    fail "$kind" "mock CLI was not invoked"
    return 1
  fi
  if [[ ! -s "$prompt_file" ]]; then
    fail "$kind" "mock CLI received empty prompt"
    return 1
  fi

  RUN_ARGV_FILE="$argv_file"
  RUN_PROMPT_FILE="$prompt_file"
  RUN_CWD_FILE="$cwd_file"
  RUN_INPUTS_FILE="$inputs_file"
  return 0
}

expect_invalid_file() {
  local name="$1"
  local kind="$2"
  local script="$3"
  shift 3

  local case_dir="$TMP_DIR/invalid-${kind}-${name// /-}"
  local bin_dir="$case_dir/bin"
  local stdout_file="$case_dir/stdout.txt"
  local stderr_file="$case_dir/stderr.txt"
  local argv_file="$case_dir/argv.txt"
  local status

  mkdir -p "$case_dir"
  write_mock_clis "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    HELPER_MOCK_KIND="$kind" \
    HELPER_MOCK_ARGV="$argv_file" \
    HELPER_MOCK_PROMPT="$case_dir/prompt.txt" \
    HELPER_MOCK_CWD="$case_dir/cwd.txt" \
    "$script" "$@" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e

  if [[ "$status" -ne 1 ]]; then
    fail "$name" "expected usage exit 1, got $status; stderr=$(<"$stderr_file")"
    return
  fi
  if [[ -e "$argv_file" ]]; then
    fail "$name" "model CLI was invoked for invalid input"
    return
  fi
  if ! grep -Fq "empty" "$stderr_file"; then
    fail "$name" "usage error did not identify empty input: $(<"$stderr_file")"
    return
  fi

  pass "$name"
}

expect_invalid_judge_output() {
  local name="$1"
  local kind="$2"
  local script="$3"
  local case_dir="$TMP_DIR/invalid-output-$kind"
  local bin_dir="$case_dir/bin"
  local stdout_file="$case_dir/stdout.txt"
  local stderr_file="$case_dir/stderr.txt"
  local status

  mkdir -p "$case_dir"
  write_mock_clis "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    HELPER_MOCK_KIND="$kind" \
    HELPER_MOCK_ARGV="$case_dir/argv.txt" \
    HELPER_MOCK_PROMPT="$case_dir/prompt.txt" \
    HELPER_MOCK_CWD="$case_dir/cwd.txt" \
    HELPER_MOCK_JUDGE_OUTPUT='{"scores":{"A":6,"B":3,"C":5},"rationale":"invalid"}' \
    "$script" --task-id x --bundle "A/B/C" --rubric "score" \
    >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e

  if [[ "$status" -ne 3 ]]; then
    fail "$name" "expected invalid-output exit 3, got $status; stdout=$(<"$stdout_file")"
    return
  fi
  if [[ -s "$stdout_file" ]]; then
    fail "$name" "expected empty stdout on invalid judge output"
    return
  fi

  pass "$name"
}

test_bare_codex_file_spec() {
  local name="bare-codex emits bare envelope for spec file"
  local spec="$TMP_DIR/spec.md"
  local output="$TMP_DIR/bare-codex.json"
  printf 'Implement a URL shortener.\n' >"$spec"

  run_helper "bare-codex" "$SCRIPTS_DIR/bare-codex.sh" "$output" \
    --task-id "backend/example" --spec-file "$spec" || return

  assert_jq "$output" \
    '.model == "codex"
     and .track == "bare"
     and .taskId == "backend/example"
     and .output == "codex raw answer for backend/example\n"' || {
    fail "$name" "output JSON shape was wrong: $(<"$output")"
    return
  }
  assert_file_lacks "$RUN_PROMPT_FILE" "IMPLEMENT mode" || {
    fail "$name" "prompt contains direction header"
    return
  }
  assert_file_lacks "$RUN_PROMPT_FILE" "Honor engineering-discipline" || {
    fail "$name" "prompt contains skill injection"
    return
  }
  assert_file_lacks "$RUN_PROMPT_FILE" "ORCHESTRATION-CONTRACT" || {
    fail "$name" "prompt requests wrapper contract"
    return
  }
  assert_argv_lacks_line "$RUN_ARGV_FILE" "--model" || {
    fail "$name" "codex argv unexpectedly passed --model"
    return
  }
  assert_argv_lacks_line "$RUN_ARGV_FILE" "-m" || {
    fail "$name" "codex argv unexpectedly passed -m"
    return
  }

  pass "$name"
}

test_bare_grok_text_spec() {
  local name="bare-grok emits bare envelope for inline spec"
  local output="$TMP_DIR/bare-grok.json"

  run_helper "bare-grok" "$SCRIPTS_DIR/bare-grok.sh" "$output" \
    --task-id "backend/example" --spec "Implement a rate limiter." || return

  assert_jq "$output" \
    '.model == "grok"
     and .track == "bare"
     and .taskId == "backend/example"
     and .output == "grok raw answer for backend/example\n"' || {
    fail "$name" "output JSON shape was wrong: $(<"$output")"
    return
  }
  assert_file_lacks "$RUN_PROMPT_FILE" "IMPLEMENT mode" || {
    fail "$name" "prompt contains direction header"
    return
  }
  assert_file_lacks "$RUN_PROMPT_FILE" "Honor engineering-discipline" || {
    fail "$name" "prompt contains skill injection"
    return
  }
  assert_argv_has_pair "$RUN_ARGV_FILE" "--cwd" "$(<"$RUN_CWD_FILE")" || {
    fail "$name" "grok argv cwd did not match its process cwd"
    return
  }
  assert_argv_has_pair "$RUN_ARGV_FILE" "-m" "grok-4.5" || {
    fail "$name" "grok argv did not pin grok-4.5"
    return
  }
  assert_argv_lacks_line "$RUN_ARGV_FILE" "--deny" || {
    fail "$name" "bare grok unexpectedly used judge deny rules"
    return
  }
  grep -qx -- "--always-approve" "$RUN_ARGV_FILE" || {
    fail "$name" "grok argv omitted --always-approve"
    return
  }
  assert_argv_has_pair "$RUN_ARGV_FILE" "--max-turns" "80" || {
    fail "$name" "grok argv did not match the Track-A turn budget"
    return
  }

  pass "$name"
}

test_judge_codex() {
  local name="judge-codex normalizes judge JSON"
  local bundle="$TMP_DIR/bundle.md"
  local rubric="$TMP_DIR/rubric.md"
  local output="$TMP_DIR/judge-codex.json"

  printf 'A: good\nB: okay\nC: best\n' >"$bundle"
  printf 'Score correctness and quality from 0 to 5.\n' >"$rubric"

  run_helper "judge-codex" "$SCRIPTS_DIR/judge-codex.sh" "$output" \
    --task-id "backend/example" --track "B" \
    --bundle-file "$bundle" --rubric-file "$rubric" || return

  assert_jq "$output" \
    '.judge == "codex"
     and .taskId == "backend/example"
     and .track == "B"
     and .scores == {"A":4.1,"B":3,"C":5}
     and .rationale == "Codex judge rationale."' || {
    fail "$name" "output JSON shape was wrong: $(<"$output")"
    return
  }
  assert_file_lacks "$RUN_PROMPT_FILE" "IMPLEMENT mode" || {
    fail "$name" "judge prompt contains implementation header"
    return
  }
  assert_argv_lacks_line "$RUN_ARGV_FILE" "--model" || {
    fail "$name" "codex judge argv unexpectedly passed --model"
    return
  }
  assert_argv_lacks_line "$RUN_ARGV_FILE" "-m" || {
    fail "$name" "codex judge argv unexpectedly passed -m"
    return
  }
  assert_argv_has_pair "$RUN_ARGV_FILE" "-C" "$(<"$RUN_CWD_FILE")" || {
    fail "$name" "codex judge argv cwd did not match its process cwd"
    return
  }
  assert_argv_has_pair "$RUN_ARGV_FILE" "-s" "read-only" || {
    fail "$name" "codex judge omitted read-only sandboxing"
    return
  }
  if [[ "$(<"$RUN_CWD_FILE")" == "$(pwd -P)" ]]; then
    fail "$name" "codex judge ran in the caller repo"
    return
  fi

  pass "$name"
}

test_judge_grok() {
  local name="judge-grok normalizes judge JSON"
  local output="$TMP_DIR/judge-grok.json"

  run_helper "judge-grok" "$SCRIPTS_DIR/judge-grok.sh" "$output" \
    --task-id "backend/example" --track "A" \
    --bundle "A: weak"$'\n'"B: strong"$'\n'"C: fine" \
    --rubric "Score each candidate from 0 to 5." || return

  assert_jq "$output" \
    '.judge == "grok"
     and .taskId == "backend/example"
     and .track == "A"
     and .scores == {"A":2,"B":4.5,"C":3.25}
     and .rationale == "Grok judge rationale."' || {
    fail "$name" "output JSON shape was wrong: $(<"$output")"
    return
  }
  assert_file_lacks "$RUN_PROMPT_FILE" "Honor engineering-discipline" || {
    fail "$name" "judge prompt contains skill injection"
    return
  }
  assert_argv_lacks_line "$RUN_ARGV_FILE" "--model" || {
    fail "$name" "grok judge argv unexpectedly passed --model"
    return
  }
  assert_argv_lacks_line "$RUN_ARGV_FILE" "-m" || {
    fail "$name" "grok judge argv unexpectedly passed -m"
    return
  }
  assert_argv_has_pair "$RUN_ARGV_FILE" "--cwd" "$(<"$RUN_CWD_FILE")" || {
    fail "$name" "grok judge argv cwd did not match its process cwd"
    return
  }
  for denied in Write Edit Bash; do
    assert_argv_has_pair "$RUN_ARGV_FILE" "--deny" "$denied" || {
      fail "$name" "grok judge omitted --deny $denied"
      return
    }
  done
  if [[ "$(<"$RUN_CWD_FILE")" == "$(pwd -P)" ]]; then
    fail "$name" "grok judge ran in the caller repo"
    return
  fi

  pass "$name"
}

test_judges_do_not_disclose_caller_paths() {
  local name="judges isolate cwd and do not disclose caller paths"
  local caller_dir="$TMP_DIR/caller-repo"
  local bundle="$caller_dir/bundle.md"
  local rubric="$caller_dir/rubric.md"
  local deanon="$caller_dir/de-anon-map.json"
  local output="$TMP_DIR/canary.json"
  local kind script

  mkdir -p "$caller_dir"
  printf 'A: one\nB: two\nC: three\n' >"$bundle"
  printf 'Score from zero to five.\n' >"$rubric"
  printf '{"A":"codex"}\n' >"$deanon"

  for kind in judge-codex judge-grok; do
    script="$SCRIPTS_DIR/$kind.sh"
    HELPER_MOCK_REQUIRE_LOCAL_INPUTS=1 run_helper "$kind" "$script" "$output" \
      --task-id "backend/canary" --bundle-file "$bundle" --rubric-file "$rubric" || return
    if [[ ! -s "$RUN_INPUTS_FILE" ]]; then
      fail "$name" "$kind did not stage judge inputs in its sandbox"
      return
    fi
    if grep -Fq -- "$caller_dir" "$RUN_ARGV_FILE" || grep -Fq -- "$caller_dir" "$RUN_PROMPT_FILE"; then
      fail "$name" "$kind disclosed the caller repo path to the model"
      return
    fi
    if grep -Fq -- "$deanon" "$RUN_ARGV_FILE" || grep -Fq -- "$deanon" "$RUN_PROMPT_FILE"; then
      fail "$name" "$kind disclosed the de-anonymization canary path"
      return
    fi
  done

  pass "$name"
}

test_empty_files_fail_before_model_calls() {
  local empty="$TMP_DIR/empty-input"
  local bundle="$TMP_DIR/nonempty-bundle.md"
  local rubric="$TMP_DIR/nonempty-rubric.md"
  : >"$empty"
  printf 'A: one\nB: two\nC: three\n' >"$bundle"
  printf 'Score candidates.\n' >"$rubric"

  expect_invalid_file "bare-codex rejects empty spec file" "bare-codex" \
    "$SCRIPTS_DIR/bare-codex.sh" --task-id x --spec-file "$empty"
  expect_invalid_file "bare-grok rejects empty spec file" "bare-grok" \
    "$SCRIPTS_DIR/bare-grok.sh" --task-id x --spec-file "$empty"
  expect_invalid_file "judge-codex rejects empty bundle file" "judge-codex" \
    "$SCRIPTS_DIR/judge-codex.sh" --task-id x --bundle-file "$empty" --rubric-file "$rubric"
  expect_invalid_file "judge-codex rejects empty rubric file" "judge-codex" \
    "$SCRIPTS_DIR/judge-codex.sh" --task-id x --bundle-file "$bundle" --rubric-file "$empty"
  expect_invalid_file "judge-grok rejects empty bundle file" "judge-grok" \
    "$SCRIPTS_DIR/judge-grok.sh" --task-id x --bundle-file "$empty" --rubric-file "$rubric"
  expect_invalid_file "judge-grok rejects empty rubric file" "judge-grok" \
    "$SCRIPTS_DIR/judge-grok.sh" --task-id x --bundle-file "$bundle" --rubric-file "$empty"
}

test_judges_reject_out_of_range_scores() {
  expect_invalid_judge_output "judge-codex rejects out-of-range scores" \
    "judge-codex" "$SCRIPTS_DIR/judge-codex.sh"
  expect_invalid_judge_output "judge-grok rejects out-of-range scores" \
    "judge-grok" "$SCRIPTS_DIR/judge-grok.sh"
}

run_test "bare-codex emits bare envelope for spec file" test_bare_codex_file_spec
run_test "bare-grok emits bare envelope for inline spec" test_bare_grok_text_spec
run_test "judge-codex normalizes judge JSON" test_judge_codex
run_test "judge-grok normalizes judge JSON" test_judge_grok
run_test "judges isolate cwd and do not disclose caller paths" test_judges_do_not_disclose_caller_paths
run_test "empty files fail before model calls" test_empty_files_fail_before_model_calls
run_test "judges reject out-of-range scores" test_judges_reject_out_of_range_scores

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
