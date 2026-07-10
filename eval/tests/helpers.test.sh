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

write_mock_clis() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"

  cat >"$bin_dir/codex" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

: "${HELPER_MOCK_ARGV:?}"
: "${HELPER_MOCK_PROMPT:?}"

printf '%s\n' "$@" >"$HELPER_MOCK_ARGV"
cat >"$HELPER_MOCK_PROMPT"

case "${HELPER_MOCK_KIND:?}" in
  bare-codex)
    printf 'codex raw answer for %s\n' "${HELPER_MOCK_TASK_ID:-unknown}"
    ;;
  judge-codex)
    cat <<'JSON'
{"scores":{"A":4.1,"B":3,"C":5},"rationale":"Codex judge rationale."}
JSON
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

printf '%s\n' "$@" >"$HELPER_MOCK_ARGV"

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

case "${HELPER_MOCK_KIND:?}" in
  bare-grok)
    printf 'grok raw answer for %s\n' "${HELPER_MOCK_TASK_ID:-unknown}"
    ;;
  judge-grok)
    cat <<'JSON'
{"scores":{"A":2,"B":4.5,"C":3.25},"rationale":"Grok judge rationale."}
JSON
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
  return 0
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
  assert_argv_lacks_line "$RUN_ARGV_FILE" "--model" || {
    fail "$name" "grok argv unexpectedly passed --model"
    return
  }
  assert_argv_lacks_line "$RUN_ARGV_FILE" "-m" || {
    fail "$name" "grok argv unexpectedly passed -m"
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

  pass "$name"
}

run_test "bare-codex emits bare envelope for spec file" test_bare_codex_file_spec
run_test "bare-grok emits bare envelope for inline spec" test_bare_grok_text_spec
run_test "judge-codex normalizes judge JSON" test_judge_codex
run_test "judge-grok normalizes judge JSON" test_judge_grok

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
