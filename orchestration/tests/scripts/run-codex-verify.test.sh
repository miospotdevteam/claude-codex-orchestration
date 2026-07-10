#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/../../scripts/run-codex-verify.sh"
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

assert_argv_has_pair() {
  local argv_file="$1"
  local flag="$2"
  local value="$3"
  awk -v flag="$flag" -v value="$value" 'previous == flag && $0 == value { found = 1 } { previous = $0 } END { exit found ? 0 : 1 }' "$argv_file"
}

assert_argv_lacks_line() {
  local argv_file="$1"
  local unexpected="$2"
  ! grep -qx -- "$unexpected" "$argv_file"
}

write_mock_codex() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  cat >"$bin_dir/codex" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

: "${CODEX_MOCK_ARGV:?}"
: "${CODEX_MOCK_PROMPT:?}"

printf '%s\n' "$@" >"$CODEX_MOCK_ARGV"

last_message_file=""
while (($# > 0)); do
  case "$1" in
    -o)
      last_message_file="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

cat >"$CODEX_MOCK_PROMPT"

write_contract() {
  cat >"$last_message_file" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Verify wrapper parsed the output-last-message file.
Verdict: PASS
Findings:
FilesTouched:
- orchestration/tests/scripts/run-codex-verify.test.sh
=== END-CONTRACT ===
EOF
}

case "${CODEX_MOCK_MODE:-pass}" in
  pass)
    write_contract
    printf 'mock progress stream without a contract\n'
    printf 'mock diagnostic stream without a contract\n' >&2
    ;;
  footer_noise)
    write_contract
    cat "$last_message_file"
    printf 'tool footer after the contract block\n'
    printf 'late diagnostic footer\n' >&2
    ;;
  stdout_fallback)
    : >"$last_message_file"
    cat <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Verify wrapper used isolated stdout as the empty-last-message fallback.
Verdict: PASS
Findings:
FilesTouched:
- orchestration/tests/scripts/run-codex-verify.test.sh
=== END-CONTRACT ===
EOF
    printf 'late diagnostic footer\n' >&2
    ;;
  nonzero)
    printf 'mock codex failed\n' >&2
    exit 17
    ;;
  missing)
    printf 'last message without sentinels\n' >"$last_message_file"
    ;;
  malformed)
    cat >"$last_message_file" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Missing required closing content.
Verdict: MAYBE
EOF
    ;;
  *)
    printf 'unknown CODEX_MOCK_MODE: %s\n' "$CODEX_MOCK_MODE" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "$bin_dir/codex"
}

invoke_verify() {
  local root_dir="$1"
  "$WRAPPER" \
    --plan-id "codex-wrapper-tests" \
    --step-id "step-01-wrapper-tests" \
    --root-dir "$root_dir" \
    --skill "test-driven-development" <<'EOF'
# Step
Exercise the Codex verify wrapper.
---DIFF---
diff --git a/example.txt b/example.txt
new file mode 100644
EOF
}

run_with_mock() {
  local name="$1"
  local mode="$2"
  local expected_status="$3"
  local case_dir="$TMP_DIR/$name"
  local root_dir="$case_dir/root"
  local bin_dir="$case_dir/bin"
  local stdout_file="$case_dir/stdout.txt"
  local stderr_file="$case_dir/stderr.txt"
  local status

  mkdir -p "$root_dir"
  write_mock_codex "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    CODEX_MOCK_MODE="$mode" \
    CODEX_MOCK_ARGV="$case_dir/argv.txt" \
    CODEX_MOCK_PROMPT="$case_dir/prompt.txt" \
    invoke_verify "$root_dir" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e

  if [[ "$status" -ne "$expected_status" ]]; then
    fail "$name" "expected exit $expected_status, got $status; stderr=$(<"$stderr_file")"
    return
  fi

  if [[ ! -s "$case_dir/argv.txt" ]]; then
    fail "$name" "mock codex was not invoked"
    return
  fi

  if [[ "$expected_status" -eq 0 ]] && ! jq -e '.verdict == "PASS" and (.findings | length == 0)' "$stdout_file" >/dev/null; then
    fail "$name" "stdout is not parsed PASS JSON: $(<"$stdout_file")"
    return
  fi

  pass "$name"
}

test_happy_path_and_prompt() {
  local name="happy path parses last message and keeps verify read-only"
  local case_dir="$TMP_DIR/happy"
  local root_dir="$case_dir/root"
  local bin_dir="$case_dir/bin"
  local argv_file="$case_dir/argv.txt"
  local prompt_file="$case_dir/prompt.txt"
  local stdout_file="$case_dir/stdout.txt"
  local stderr_file="$case_dir/stderr.txt"
  local status

  mkdir -p "$root_dir"
  write_mock_codex "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    CODEX_MOCK_MODE="pass" \
    CODEX_MOCK_ARGV="$argv_file" \
    CODEX_MOCK_PROMPT="$prompt_file" \
    invoke_verify "$root_dir" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    fail "$name" "expected exit 0, got $status; stderr=$(<"$stderr_file")"
    return
  fi
  if ! jq -e '.summary == "Verify wrapper parsed the output-last-message file." and .verdict == "PASS"' "$stdout_file" >/dev/null; then
    fail "$name" "stdout is not the expected parse-contract JSON: $(<"$stdout_file")"
    return
  fi
  assert_argv_has_pair "$argv_file" "-C" "$root_dir" || {
    fail "$name" "argv missing -C root"
    return
  }
  assert_argv_has_pair "$argv_file" "-s" "read-only" || {
    fail "$name" "argv missing read-only sandbox"
    return
  }
  for forbidden in -m --model --reasoning-effort; do
    assert_argv_lacks_line "$argv_file" "$forbidden" || {
      fail "$name" "argv unexpectedly includes $forbidden"
      return
    }
  done
  assert_file_contains "$prompt_file" "=== ORCHESTRATION-CONTRACT ===" || {
    fail "$name" "prompt missing contract opening sentinel"
    return
  }
  assert_file_contains "$prompt_file" "=== END-CONTRACT ===" || {
    fail "$name" "prompt missing contract closing sentinel"
    return
  }

  pass "$name"
}

test_relative_root_dir_exits_1() {
  local name="relative --root-dir rejected with exit 1 before side effects"
  local case_dir="$TMP_DIR/relative-root"
  local bin_dir="$case_dir/bin"
  local stderr_file="$case_dir/stderr.txt"
  local status

  mkdir -p "$case_dir/relative/root"
  write_mock_codex "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    CODEX_MOCK_ARGV="$case_dir/argv.txt" \
    CODEX_MOCK_PROMPT="$case_dir/prompt.txt" \
    bash -c 'cd "$1" && "$2" --plan-id p --step-id s --root-dir relative/root' _ "$case_dir" "$WRAPPER" <<'EOF' >/dev/null 2>"$stderr_file"
# Step
Exercise the Codex verify wrapper.
---DIFF---
diff --git a/x b/x
EOF
  status=$?
  set -e

  if [[ "$status" -ne 1 ]]; then
    fail "$name" "expected exit 1, got $status; stderr=$(<"$stderr_file")"
    return
  fi
  assert_file_contains "$stderr_file" "absolute path" || {
    fail "$name" "stderr missing absolute-path message"
    return
  }
  if [[ -e "$case_dir/argv.txt" ]]; then
    fail "$name" "mock codex was invoked for invalid input"
    return
  fi
  if [[ -e "$case_dir/relative/root/.temp" ]]; then
    fail "$name" "wrapper created log side effects for invalid input"
    return
  fi

  pass "$name"
}

test_happy_path_and_prompt
run_with_mock "trailing footer after block still exits 0" "footer_noise" 0
run_with_mock "empty last message falls back to isolated stdout" "stdout_fallback" 0
run_with_mock "codex non-zero exits 2" "nonzero" 2
run_with_mock "missing contract exits 3" "missing" 3
run_with_mock "malformed contract exits 3" "malformed" 3
test_relative_root_dir_exits_1

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
