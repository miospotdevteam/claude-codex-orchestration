#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WRAPPER="$SCRIPT_DIR/../../scripts/run-claude-verify.sh"
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

assert_argv_has_pair() {
  local argv_file="$1"
  local flag="$2"
  local value="$3"
  awk -v flag="$flag" -v value="$value" \
    'previous == flag && $0 == value { found = 1 } { previous = $0 } END { exit found ? 0 : 1 }' \
    "$argv_file"
}

assert_argv_lacks_line() {
  local argv_file="$1"
  local unexpected="$2"
  ! grep -qx -- "$unexpected" "$argv_file"
}

write_mock_claude() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  cat >"$bin_dir/claude" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

: "${CLAUDE_MOCK_DIR:?}"
counter_file="$CLAUDE_MOCK_DIR/count"
count=0
if [[ -f "$counter_file" ]]; then
  count=$(<"$counter_file")
fi
count=$((count + 1))
printf '%s\n' "$count" >"$counter_file"
printf '%s\n' "$@" >"$CLAUDE_MOCK_DIR/argv.$count"
pwd -P >"$CLAUDE_MOCK_DIR/pwd.$count"
if [[ ${CLAUDECODE+x} ]]; then
  printf 'set\n' >"$CLAUDE_MOCK_DIR/claudecode.$count"
else
  printf 'unset\n' >"$CLAUDE_MOCK_DIR/claudecode.$count"
fi
cat >"$CLAUDE_MOCK_DIR/prompt.$count"

write_contract() {
  cat <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Claude verifier returned a bounded read-only review.
Verdict: PASS
Findings:
FilesTouched:
- orchestration/tests/scripts/run-claude-verify.test.sh
=== END-CONTRACT ===
EOF
}

case "${CLAUDE_MOCK_MODE:-pass}" in
  pass)
    write_contract
    ;;
  malformed_then_pass)
    if [[ "$count" -eq 1 ]]; then
      cat <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: First response has a malformed verdict.
Verdict: MAYBE
Findings:
FilesTouched:
=== END-CONTRACT ===
EOF
    else
      write_contract
    fi
    ;;
  always_malformed)
    cat <<EOF
=== ORCHESTRATION-CONTRACT ===
Summary: Malformed response $count has an invalid verdict.
Verdict: MAYBE
Findings:
FilesTouched:
=== END-CONTRACT ===
EOF
    ;;
  nonzero)
    printf 'mock claude failed\n' >&2
    exit 17
    ;;
  *)
    printf 'unknown CLAUDE_MOCK_MODE: %s\n' "$CLAUDE_MOCK_MODE" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "$bin_dir/claude"
}

invoke_verify() {
  local root_dir="$1"
  "$WRAPPER" \
    --plan-id claude-wrapper-tests \
    --step-id step-verify \
    --root-dir "$root_dir" \
    --skill test-driven-development <<'EOF'
# Step
Exercise the Claude verify wrapper.
---DIFF---
diff --git a/example.txt b/example.txt
+claude-verify-marker
EOF
}

run_case() {
  local case_name="$1"
  local mode="$2"
  local expected_status="$3"
  local expected_count="$4"
  local case_dir="$TMP_DIR/$case_name"
  local root_dir="$case_dir/root"
  local bin_dir="$case_dir/bin"
  local status actual_count

  mkdir -p "$root_dir" "$case_dir/mock"
  write_mock_claude "$bin_dir"
  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    CLAUDECODE=parent-session \
    CLAUDE_MOCK_MODE="$mode" \
    CLAUDE_MOCK_DIR="$case_dir/mock" \
    invoke_verify "$root_dir" >"$case_dir/stdout.txt" 2>"$case_dir/stderr.txt"
  status=$?
  set -e
  if [[ -f "$case_dir/mock/count" ]]; then
    actual_count=$(<"$case_dir/mock/count")
  else
    actual_count=0
  fi

  [[ "$status" -eq "$expected_status" && "$actual_count" -eq "$expected_count" ]]
}

test_happy_path_is_headless_and_read_only() {
  local name="happy path is headless direction-locked and read-only"
  local case_dir="$TMP_DIR/happy"
  local root_dir="$case_dir/root"
  local bin_dir="$case_dir/bin"
  local argv_file="$case_dir/mock/argv.1"

  mkdir -p "$root_dir" "$case_dir/mock"
  write_mock_claude "$bin_dir"
  if ! PATH="$bin_dir:$ORIGINAL_PATH" CLAUDECODE=parent-session CLAUDE_MOCK_MODE=pass \
    CLAUDE_MOCK_DIR="$case_dir/mock" invoke_verify "$root_dir" \
    >"$case_dir/stdout.txt" 2>"$case_dir/stderr.txt"; then
    fail "$name" "wrapper failed: $(<"$case_dir/stderr.txt")"
    return
  fi

  jq -e '.verdict == "PASS" and (.findings | length == 0)' "$case_dir/stdout.txt" >/dev/null || {
    fail "$name" "stdout is not parsed PASS JSON"
    return
  }
  assert_argv_has_line "$argv_file" "-p" || {
    fail "$name" "argv missing headless -p"
    return
  }
  assert_argv_has_pair "$argv_file" "--permission-mode" "dontAsk" || {
    fail "$name" "argv missing --permission-mode dontAsk"
    return
  }
  assert_argv_has_pair "$argv_file" "--tools" "Read,Glob,Grep" || {
    fail "$name" "argv missing read-only tool allowlist"
    return
  }
  assert_argv_has_pair "$argv_file" "--disallowedTools" "Write,Edit,Bash,NotebookEdit" || {
    fail "$name" "argv missing explicit write/exec deny list"
    return
  }
  assert_argv_has_line "$argv_file" "--no-session-persistence" || {
    fail "$name" "argv missing --no-session-persistence"
    return
  }
  assert_argv_has_line "$argv_file" "--safe-mode" || {
    fail "$name" "argv missing --safe-mode customization isolation"
    return
  }
  assert_argv_has_line "$argv_file" "--strict-mcp-config" || {
    fail "$name" "argv missing --strict-mcp-config"
    return
  }
  for forbidden in --dangerously-skip-permissions --allow-dangerously-skip-permissions; do
    assert_argv_lacks_line "$argv_file" "$forbidden" || {
      fail "$name" "argv includes dangerous permission bypass"
      return
    }
  done
  [[ "$(<"$case_dir/mock/pwd.1")" == "$(cd "$root_dir" && pwd -P)" ]] || {
    fail "$name" "Claude did not run from the requested root"
    return
  }
  [[ "$(<"$case_dir/mock/claudecode.1")" == "unset" ]] || {
    fail "$name" "inherited CLAUDECODE was not removed"
    return
  }
  assert_file_contains "$case_dir/mock/prompt.1" "VERIFY mode" || {
    fail "$name" "prompt missing VERIFY direction lock"
    return
  }
  assert_file_contains "$case_dir/mock/prompt.1" "may NOT edit files or execute commands" || {
    fail "$name" "prompt missing read-only constraint"
    return
  }
  assert_file_contains "$case_dir/mock/prompt.1" "claude-verify-marker" || {
    fail "$name" "prompt missing supplied diff"
    return
  }
  pass "$name"
}

test_malformed_contract_retries_once_then_passes() {
  local name="malformed contract retries once then parses PASS"
  local case_dir="$TMP_DIR/retry-pass"
  if ! run_case retry-pass malformed_then_pass 0 2; then
    fail "$name" "expected exit 0 after exactly two invocations"
    return
  fi
  jq -e '.verdict == "PASS"' "$case_dir/stdout.txt" >/dev/null || {
    fail "$name" "retry result is not parsed PASS JSON"
    return
  }
  assert_file_contains "$case_dir/mock/prompt.2" "STRICT CONTRACT RETRY" || {
    fail "$name" "retry prompt lacks the stricter reminder"
    return
  }
  if assert_file_contains "$case_dir/mock/prompt.2" "First response has a malformed verdict"; then
    fail "$name" "retry prompt leaked raw first-attempt output"
    return
  fi
  pass "$name"
}

test_malformed_contract_twice_exits_3() {
  local name="two malformed contracts exit 3 after exactly one retry"
  if run_case retry-fail always_malformed 3 2; then
    pass "$name"
  else
    fail "$name" "expected exit 3 after exactly two invocations"
  fi
}

test_cli_failure_exits_2_without_retry() {
  local name="Claude CLI failure exits 2 without retry"
  if run_case cli-fail nonzero 2 1; then
    pass "$name"
  else
    fail "$name" "expected exit 2 after one invocation"
  fi
}

test_happy_path_is_headless_and_read_only
test_malformed_contract_retries_once_then_passes
test_malformed_contract_twice_exits_3
test_cli_failure_exits_2_without_retry

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
