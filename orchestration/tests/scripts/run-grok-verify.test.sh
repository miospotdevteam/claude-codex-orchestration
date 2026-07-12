#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/../../scripts/run-grok-verify.sh"
ORIGINAL_PATH="$PATH"

# Single place to change the expected turn cap (see AC5: 40 exhausted 2026-07-10).
EXPECTED_MAX_TURNS=80

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

argv_value_after() {
  local argv_file="$1"
  local flag="$2"
  awk -v flag="$flag" 'previous == flag { print; exit } { previous = $0 }' "$argv_file"
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
  preamble_footer)
    cat <<'EOF'
mock preamble before contract
=== ORCHESTRATION-CONTRACT ===
Summary: Verify wrapper extracted a surrounded contract.
Verdict: PASS
Findings:
FilesTouched:
- orchestration/tests/scripts/run-grok-verify.test.sh
=== END-CONTRACT ===
mock footer after contract
EOF
    ;;
  two_blocks)
    cat <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Earlier verify contract must be ignored.
Verdict: FAIL
Findings:
- stale finding
FilesTouched:
=== END-CONTRACT ===
interstitial output
=== ORCHESTRATION-CONTRACT ===
Summary: Last verify contract wins.
Verdict: PASS
Findings:
FilesTouched:
- orchestration/tests/scripts/run-grok-verify.test.sh
=== END-CONTRACT ===
mock footer after both contracts
EOF
    ;;
  missing_open)
    cat <<'EOF'
Summary: Verify output is missing its opening sentinel.
Verdict: PASS
Findings:
FilesTouched:
=== END-CONTRACT ===
EOF
    ;;
  missing_close)
    cat <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Verify output is missing its closing sentinel.
Verdict: PASS
Findings:
FilesTouched:
EOF
    ;;
  stderr_noise)
    cat <<'EOF'
mock preface
=== ORCHESTRATION-CONTRACT ===
Summary: Verify wrapper parsed stdout despite late stderr noise.
Verdict: PASS
Findings:
FilesTouched:
- orchestration/tests/scripts/run-grok-verify.test.sh
=== END-CONTRACT ===
EOF
    printf 'grok: late diagnostic footer emitted on stderr\n' >&2
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
  local expected_summary="${5:-}"
  local expected_log_text="${6:-}"
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
    if [[ -n "$expected_summary" ]] && ! jq -e --arg summary "$expected_summary" '.summary == $summary' "$stdout_file" >/dev/null; then
      fail "$name" "stdout does not contain expected summary '$expected_summary': $(<"$stdout_file")"
      return
    fi
  fi

  if [[ -n "$expected_log_text" ]]; then
    # Synthetic plan ids land under plan-mode/logs/ (not active/) so they leave no debris.
    local log_file="$root_dir/.temp/plan-mode/logs/grok-wrapper-tests/grok-verify-step-06-wrapper-tests.log"
    if ! assert_file_contains "$log_file" "$expected_log_text"; then
      fail "$name" "raw stdout was not preserved in log: $log_file"
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
  local leader_socket

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
  assert_argv_has_pair "$argv_file" "-m" "grok-4.5" || {
    fail "$name" "argv missing -m grok-4.5"
    return
  }
  assert_argv_has_pair "$argv_file" "--reasoning-effort" "high" || {
    fail "$name" "argv missing --reasoning-effort high"
    return
  }
  assert_argv_has_pair "$argv_file" "--max-turns" "$EXPECTED_MAX_TURNS" || {
    fail "$name" "argv missing --max-turns $EXPECTED_MAX_TURNS"
    return
  }
  leader_socket=$(argv_value_after "$argv_file" "--leader-socket")
  if [[ -z "$leader_socket" || "$(grep -cx -- '--leader-socket' "$argv_file")" -ne 1 ]]; then
    fail "$name" "argv must contain exactly one nonempty --leader-socket"
    return
  fi
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
  assert_file_contains "$prompt_file" "The block must be plain text: no markdown bold, exact field labels, both sentinel lines mandatory, nothing after the closing sentinel." || {
    fail "$name" "prompt file missing plain-text hardening language"
    return
  }

  pass "$name"
}

test_leader_socket_is_distinct_per_invocation() {
  local name="leader socket is distinct per invocation"
  local case_dir="$TMP_DIR/distinct-leader-sockets"
  local root_dir="$case_dir/root"
  local bin_dir="$case_dir/bin"
  local first_socket second_socket

  mkdir -p "$root_dir"
  write_mock_grok "$bin_dir"
  PATH="$bin_dir:$ORIGINAL_PATH" GROK_MOCK_MODE=pass \
    GROK_MOCK_ARGV="$case_dir/first-argv.txt" GROK_MOCK_PROMPT="$case_dir/first-prompt.txt" \
    invoke_verify "$root_dir" >"$case_dir/first-stdout.txt" 2>"$case_dir/first-stderr.txt" || return 1
  PATH="$bin_dir:$ORIGINAL_PATH" GROK_MOCK_MODE=pass \
    GROK_MOCK_ARGV="$case_dir/second-argv.txt" GROK_MOCK_PROMPT="$case_dir/second-prompt.txt" \
    invoke_verify "$root_dir" >"$case_dir/second-stdout.txt" 2>"$case_dir/second-stderr.txt" || return 1

  first_socket=$(argv_value_after "$case_dir/first-argv.txt" "--leader-socket")
  second_socket=$(argv_value_after "$case_dir/second-argv.txt" "--leader-socket")
  if [[ -z "$first_socket" || -z "$second_socket" || "$first_socket" == "$second_socket" ]]; then
    fail "$name" "expected two nonempty distinct socket paths"
    return
  fi
  pass "$name"
}

test_missing_contract_exits_3() {
  run_with_mock "missing contract exits 3" "no_contract" 3 "" "" "mock output without sentinels"
}

test_preamble_footer_exits_0() {
  run_with_mock "preamble and footer around contract exits 0" "preamble_footer" 0 "PASS" "Verify wrapper extracted a surrounded contract."
}

test_two_blocks_last_wins() {
  run_with_mock "two complete contracts use the last block" "two_blocks" 0 "PASS" "Last verify contract wins."
}

test_missing_open_exits_3_and_preserves_log() {
  run_with_mock "missing opening sentinel exits 3 and preserves raw log" "missing_open" 3 "" "" "Summary: Verify output is missing its opening sentinel."
}

test_missing_close_exits_3() {
  run_with_mock "missing closing sentinel exits 3" "missing_close" 3 "" "" "Summary: Verify output is missing its closing sentinel."
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

test_stderr_noise_exits_0() {
  run_with_mock "stderr noise after block still exits 0" "stderr_noise" 0 "PASS"
}

test_max_turns_cap() {
  local name="max-turns cap is $EXPECTED_MAX_TURNS"
  local case_dir="$TMP_DIR/max-turns"
  local root_dir="$case_dir/root"
  local bin_dir="$case_dir/bin"
  local argv_file="$case_dir/argv.txt"
  local status

  mkdir -p "$root_dir"
  write_mock_grok "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    GROK_MOCK_MODE="pass" \
    GROK_MOCK_ARGV="$argv_file" \
    GROK_MOCK_PROMPT="$case_dir/prompt.txt" \
    invoke_verify "$root_dir" >"$case_dir/stdout.txt" 2>"$case_dir/stderr.txt"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    fail "$name" "expected exit 0, got $status"
    return
  fi
  assert_argv_has_pair "$argv_file" "--max-turns" "$EXPECTED_MAX_TURNS" || {
    fail "$name" "argv missing --max-turns $EXPECTED_MAX_TURNS"
    return
  }
  pass "$name"
}

test_diff_file_input_mode() {
  local name="--diff-file input mode parses PASS"
  local case_dir="$TMP_DIR/diff-file"
  local root_dir="$case_dir/root"
  local bin_dir="$case_dir/bin"
  local argv_file="$case_dir/argv.txt"
  local prompt_file="$case_dir/prompt.txt"
  local stdout_file="$case_dir/stdout.txt"
  local stderr_file="$case_dir/stderr.txt"
  local diff_file="$case_dir/change.diff"
  local status

  mkdir -p "$root_dir"
  write_mock_grok "$bin_dir"
  printf 'diff --git a/x b/x\n+unique-diff-marker\n' >"$diff_file"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    GROK_MOCK_MODE="pass" \
    GROK_MOCK_ARGV="$argv_file" \
    GROK_MOCK_PROMPT="$prompt_file" \
    "$WRAPPER" \
    --plan-id "grok-wrapper-tests" \
    --step-id "step-06-wrapper-tests" \
    --root-dir "$root_dir" \
    --diff-file "$diff_file" <<'EOF' >"$stdout_file" 2>"$stderr_file"
# Step
Exercise diff-file input mode.
EOF
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    fail "$name" "expected exit 0, got $status; stderr=$(<"$stderr_file")"
    return
  fi
  if ! jq -e '.verdict == "PASS"' "$stdout_file" >/dev/null; then
    fail "$name" "stdout is not parsed PASS JSON: $(<"$stdout_file")"
    return
  fi
  assert_file_contains "$prompt_file" "unique-diff-marker" || {
    fail "$name" "prompt file did not include the diff read from --diff-file"
    return
  }

  pass "$name"
}

test_missing_sentinel_exits_1() {
  local name="stdin without ---DIFF--- sentinel exits 1"
  local case_dir="$TMP_DIR/missing-sentinel"
  local root_dir="$case_dir/root"
  local bin_dir="$case_dir/bin"
  local argv_file="$case_dir/argv.txt"
  local stderr_file="$case_dir/stderr.txt"
  local status

  mkdir -p "$root_dir"
  write_mock_grok "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    GROK_MOCK_MODE="pass" \
    GROK_MOCK_ARGV="$argv_file" \
    GROK_MOCK_PROMPT="$case_dir/prompt.txt" \
    "$WRAPPER" \
    --plan-id "grok-wrapper-tests" \
    --step-id "step-06-wrapper-tests" \
    --root-dir "$root_dir" <<'EOF' >/dev/null 2>"$stderr_file"
# Step
No diff sentinel here.
EOF
  status=$?
  set -e

  if [[ "$status" -ne 1 ]]; then
    fail "$name" "expected exit 1, got $status; stderr=$(<"$stderr_file")"
    return
  fi
  assert_file_contains "$stderr_file" "---DIFF---" || {
    fail "$name" "stderr missing ---DIFF--- sentinel message"
    return
  }
  pass "$name"
}

test_relative_root_dir_exits_1() {
  local name="relative --root-dir rejected with exit 1"
  local case_dir="$TMP_DIR/rel-root"
  local bin_dir="$case_dir/bin"
  local argv_file="$case_dir/argv.txt"
  local stderr_file="$case_dir/stderr.txt"
  local status

  mkdir -p "$case_dir"
  write_mock_grok "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    GROK_MOCK_ARGV="$argv_file" \
    "$WRAPPER" \
    --plan-id "p" --step-id "s" --root-dir "relative/root" <<'EOF' >/dev/null 2>"$stderr_file"
# Step
Exercise the Grok verify wrapper.
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
  pass "$name"
}

test_validation_precedence_exits_1() {
  local name="bad --diff-file + no grok exits 1, not 4"
  local case_dir="$TMP_DIR/precedence"
  local root_dir="$case_dir/root"
  local empty_path="$case_dir/empty-path"
  local argv_file="$case_dir/argv.txt"
  local stderr_file="$case_dir/stderr.txt"
  local status

  mkdir -p "$root_dir" "$empty_path"

  set +e
  PATH="$empty_path:/usr/bin:/bin" \
    GROK_MOCK_ARGV="$argv_file" \
    "$WRAPPER" \
    --plan-id "p" --step-id "s" --root-dir "$root_dir" \
    --diff-file "$case_dir/does-not-exist.diff" <<'EOF' >/dev/null 2>"$stderr_file"
# Step
EOF
  status=$?
  set -e

  if [[ "$status" -ne 1 ]]; then
    fail "$name" "expected exit 1, got $status; stderr=$(<"$stderr_file")"
    return
  fi
  if [[ -e "$argv_file" ]]; then
    fail "$name" "argv file exists even though invocation was invalid"
    return
  fi
  assert_file_contains "$stderr_file" "--diff-file does not exist" || {
    fail "$name" "stderr missing bad --diff-file message"
    return
  }
  pass "$name"
}

test_logs_real_plan_vs_synthetic() {
  local name="logs: real plan uses active/<id>/logs; synthetic uses plan-mode/logs/<id>"
  local case_dir="$TMP_DIR/log-destinations"
  local root_real="$case_dir/real-root"
  local root_synth="$case_dir/synth-root"
  local bin_dir="$case_dir/bin"
  local plan_id="grok-wrapper-tests"
  local step_id="step-06-wrapper-tests"
  local real_log="$root_real/.temp/plan-mode/active/$plan_id/logs/grok-verify-$step_id.log"
  local synth_log="$root_synth/.temp/plan-mode/logs/$plan_id/grok-verify-$step_id.log"
  local status

  mkdir -p "$root_real/.temp/plan-mode/active/$plan_id" "$root_synth" "$bin_dir"
  printf '{"planId":"%s"}\n' "$plan_id" >"$root_real/.temp/plan-mode/active/$plan_id/plan.json"
  write_mock_grok "$bin_dir"

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    GROK_MOCK_MODE="pass" \
    GROK_MOCK_ARGV="$case_dir/real-argv.txt" \
    GROK_MOCK_PROMPT="$case_dir/real-prompt.txt" \
    invoke_verify "$root_real" >"$case_dir/real-stdout.txt" 2>"$case_dir/real-stderr.txt"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    fail "$name" "real-plan invoke exit $status; stderr=$(<"$case_dir/real-stderr.txt")"
    return
  fi
  if [[ ! -f "$real_log" ]]; then
    fail "$name" "expected real-plan log at $real_log"
    return
  fi
  if [[ -e "$root_real/.temp/plan-mode/logs" ]]; then
    fail "$name" "real plan should not write under plan-mode/logs/"
    return
  fi

  set +e
  PATH="$bin_dir:$ORIGINAL_PATH" \
    GROK_MOCK_MODE="pass" \
    GROK_MOCK_ARGV="$case_dir/synth-argv.txt" \
    GROK_MOCK_PROMPT="$case_dir/synth-prompt.txt" \
    invoke_verify "$root_synth" >"$case_dir/synth-stdout.txt" 2>"$case_dir/synth-stderr.txt"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    fail "$name" "synthetic invoke exit $status; stderr=$(<"$case_dir/synth-stderr.txt")"
    return
  fi
  if [[ ! -f "$synth_log" ]]; then
    fail "$name" "expected synthetic log at $synth_log"
    return
  fi
  if [[ -e "$root_synth/.temp/plan-mode/active" ]]; then
    fail "$name" "synthetic id must not create active/ debris"
    return
  fi

  pass "$name"
}

test_happy_path
test_nonzero_exits_2
test_argv_and_prompt_assertions
test_leader_socket_is_distinct_per_invocation
test_missing_contract_exits_3
test_preamble_footer_exits_0
test_two_blocks_last_wins
test_missing_open_exits_3_and_preserves_log
test_missing_close_exits_3
test_missing_binary_exits_4
test_stderr_noise_exits_0
test_max_turns_cap
test_diff_file_input_mode
test_missing_sentinel_exits_1
test_relative_root_dir_exits_1
test_validation_precedence_exits_1
test_logs_real_plan_vs_synthetic

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
