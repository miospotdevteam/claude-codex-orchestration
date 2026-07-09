#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/../../scripts/run-grok-verify.sh"
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

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  grep -Fq -- "$pattern" "$file"
}

assert_argv_has_line() {
  local argv_file="$1"
  local expected="$2"
  grep -qx -- "$expected" "$argv_file"
}

assert_argv_lacks_line() {
  local argv_file="$1"
  local unexpected="$2"
  ! grep -qx -- "$unexpected" "$argv_file"
}

assert_argv_has_pair() {
  local argv_file="$1"
  local flag="$2"
  local value="$3"
  awk -v flag="$flag" -v value="$value" 'previous == flag && $0 == value { found = 1 } { previous = $0 } END { exit found ? 0 : 1 }' "$argv_file"
}

deny_values() {
  local argv_file="$1"
  awk 'previous == "--deny" { printf "%s%s", separator, $0; separator = " " } { previous = $0 }' "$argv_file"
}

write_mock_grok() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  cat >"$bin_dir/grok" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

: "${GROK_MOCK_ARGV:?}"
: "${GROK_MOCK_PROMPT:?}"

printf '%s\n' "$@" >"$GROK_MOCK_ARGV"

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
  cat "$prompt_file" >"$GROK_MOCK_PROMPT"
fi

case "${GROK_MOCK_MODE:-pass}" in
  pass)
    cat <<'EOF'
mock preface
=== ORCHESTRATION-CONTRACT ===
Summary: Verify wrapper parsed the final contract.
Verdict: PASS
Findings:
FilesTouched:
- orchestration/tests/scripts/run-grok-verify.test.sh
=== END-CONTRACT ===
EOF
    ;;
  nonzero)
    printf 'mock grok failed\n' >&2
    exit 17
    ;;
  no_contract)
    printf 'mock output without sentinels\n'
    ;;
  *)
    printf 'unknown GROK_MOCK_MODE: %s\n' "$GROK_MOCK_MODE" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "$bin_dir/grok"
}

invoke_verify() {
  local root_dir="$1"
  "$WRAPPER" \
    --plan-id "grok-wrapper-tests" \
    --step-id "step-06-wrapper-tests" \
    --root-dir "$root_dir" \
    --skill "test-driven-development" <<'EOF'
# Step
Exercise the Grok verify wrapper.
---DIFF---
diff --git a/example.txt b/example.txt
new file mode 100644
EOF
}

run_with_mock() {
  local name="$1"
  local mode="$2"
  local expected_status="$3"
  local expected_verdict="${4:-}"
  local case_dir="$TMP_DIR/$name"
  local root_dir="$case_dir/root"
  local bin_dir="$case_dir/bin"
  local argv_file="$case_dir/argv.txt"
  local prompt_file="$case_dir/prompt.txt"
  local stdout_file="$case_dir/stdout.txt"
  local stderr_file="$case_dir/stderr.txt"
  local status

  mkdir -p "$root_dir"
  write_mock_grok "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    GROK_MOCK_MODE="$mode" \
    GROK_MOCK_ARGV="$argv_file" \
    GROK_MOCK_PROMPT="$prompt_file" \
    invoke_verify "$root_dir" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e

  if [[ "$status" -ne "$expected_status" ]]; then
    fail "$name" "expected exit $expected_status, got $status; stderr=$(<"$stderr_file")"
    return
  fi

  if [[ ! -s "$argv_file" ]]; then
    fail "$name" "mock grok was not invoked"
    return
  fi

  if [[ "$expected_status" -eq 0 ]]; then
    if ! jq -e --arg verdict "$expected_verdict" '.verdict == $verdict' "$stdout_file" >/dev/null; then
      fail "$name" "stdout is not parsed JSON with verdict $expected_verdict: $(<"$stdout_file")"
      return
    fi
  fi

  pass "$name"
}

test_happy_path() {
  local name="happy path parses PASS and records argv"
  local case_dir="$TMP_DIR/happy"
  local root_dir="$case_dir/root"
  local bin_dir="$case_dir/bin"
  local argv_file="$case_dir/argv.txt"
  local prompt_file="$case_dir/prompt.txt"
  local stdout_file="$case_dir/stdout.txt"
  local stderr_file="$case_dir/stderr.txt"
  local status

  mkdir -p "$root_dir"
  write_mock_grok "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    GROK_MOCK_MODE="pass" \
    GROK_MOCK_ARGV="$argv_file" \
    GROK_MOCK_PROMPT="$prompt_file" \
    invoke_verify "$root_dir" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    fail "$name" "expected exit 0, got $status; stderr=$(<"$stderr_file")"
    return
  fi

  if [[ ! -s "$argv_file" ]]; then
    fail "$name" "mock grok was not invoked"
    return
  fi

  if ! jq -e '.verdict == "PASS"' "$stdout_file" >/dev/null; then
    fail "$name" "stdout is not parsed PASS JSON: $(<"$stdout_file")"
    return
  fi

  pass "$name"
}

test_nonzero_exits_2() {
  run_with_mock "mock nonzero exits 2" "nonzero" 2
}

test_argv_and_prompt_assertions() {
  local name="argv and prompt assertions"
  local case_dir="$TMP_DIR/argv-prompt"
  local root_dir="$case_dir/root"
  local bin_dir="$case_dir/bin"
  local argv_file="$case_dir/argv.txt"
  local prompt_file="$case_dir/prompt.txt"
  local stdout_file="$case_dir/stdout.txt"
  local stderr_file="$case_dir/stderr.txt"
  local status
  local deny_count
  local deny_sequence

  mkdir -p "$root_dir"
  write_mock_grok "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    GROK_MOCK_MODE="pass" \
    GROK_MOCK_ARGV="$argv_file" \
    GROK_MOCK_PROMPT="$prompt_file" \
    invoke_verify "$root_dir" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    fail "$name" "expected exit 0, got $status; stderr=$(<"$stderr_file")"
    return
  fi
  if [[ ! -s "$argv_file" ]]; then
    fail "$name" "mock grok was not invoked"
    return
  fi

  assert_argv_has_line "$argv_file" "--prompt-file" || {
    fail "$name" "argv missing --prompt-file"
    return
  }
  assert_argv_has_line "$argv_file" "--cwd" || {
    fail "$name" "argv missing --cwd"
    return
  }
  assert_argv_has_pair "$argv_file" "-m" "grok-build" || {
    fail "$name" "argv missing -m grok-build"
    return
  }
  assert_argv_has_pair "$argv_file" "--max-turns" "40" || {
    fail "$name" "argv missing --max-turns 40"
    return
  }
  assert_argv_lacks_line "$argv_file" "--model" || {
    fail "$name" "argv unexpectedly includes --model"
    return
  }
  assert_argv_lacks_line "$argv_file" "--always-approve" || {
    fail "$name" "verify argv unexpectedly includes --always-approve"
    return
  }
  assert_argv_lacks_line "$argv_file" "--no-auto-update" || {
    fail "$name" "argv unexpectedly includes --no-auto-update"
    return
  }

  deny_count="$(grep -cx -- "--deny" "$argv_file")"
  deny_sequence="$(deny_values "$argv_file")"
  if [[ "$deny_count" -ne 3 || "$deny_sequence" != "Write Edit Bash" ]]; then
    fail "$name" "expected exactly --deny Write/Edit/Bash, got count=$deny_count values='$deny_sequence'"
    return
  fi

  assert_file_contains "$prompt_file" "VERIFY mode" || {
    fail "$name" "prompt file missing VERIFY direction text"
    return
  }
  assert_file_contains "$prompt_file" "You may NOT edit files" || {
    fail "$name" "prompt file missing read-only edit constraint"
    return
  }
  assert_file_contains "$prompt_file" "Do not create, modify, delete, move, or format any file" || {
    fail "$name" "prompt file missing file mutation constraint"
    return
  }

  pass "$name"
}

test_missing_contract_exits_3() {
  run_with_mock "missing contract exits 3" "no_contract" 3
}

test_missing_binary_exits_4() {
  local name="missing grok exits 4 before invocation"
  local case_dir="$TMP_DIR/missing-binary"
  local root_dir="$case_dir/root"
  local empty_path="$case_dir/empty-path"
  local argv_file="$case_dir/argv.txt"
  local stdout_file="$case_dir/stdout.txt"
  local stderr_file="$case_dir/stderr.txt"
  local status

  mkdir -p "$root_dir" "$empty_path"

  set +e
  PATH="$empty_path:/usr/bin:/bin" \
    GROK_MOCK_ARGV="$argv_file" \
    invoke_verify "$root_dir" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e

  if [[ "$status" -ne 4 ]]; then
    fail "$name" "expected exit 4, got $status; stderr=$(<"$stderr_file")"
    return
  fi
  if [[ -e "$argv_file" ]]; then
    fail "$name" "argv file exists even though no mock should be invoked"
    return
  fi
  assert_file_contains "$stderr_file" "grok binary not found on PATH" || {
    fail "$name" "stderr missing missing-grok message"
    return
  }

  pass "$name"
}

test_happy_path
test_nonzero_exits_2
test_argv_and_prompt_assertions
test_missing_contract_exits_3
test_missing_binary_exits_4

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
