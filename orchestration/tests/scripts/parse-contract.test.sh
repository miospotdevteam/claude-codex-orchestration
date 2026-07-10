#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/../../scripts/parse-contract.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

failures=0

pass_test() {
  printf 'PASS %s\n' "$1"
}

fail_test() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  failures=$((failures + 1))
}

expect_success() {
  local name="$1"
  local fixture="$2"
  local expected_verdict="$3"
  local output
  local err="$TMP_DIR/$name.err"

  if ! output="$("$PARSER" <"$fixture" 2>"$err")"; then
    fail_test "$name" "expected success, got failure: $(<"$err")"
    return
  fi

  if ! printf '%s\n' "$output" | jq -e .verdict >/dev/null; then
    fail_test "$name" "output is not valid JSON with a verdict"
    return
  fi

  local verdict
  verdict="$(printf '%s\n' "$output" | jq -r .verdict)"
  if [[ "$verdict" != "$expected_verdict" ]]; then
    fail_test "$name" "expected verdict $expected_verdict, got $verdict"
    return
  fi

  pass_test "$name"
}

expect_finding_text() {
  local name="$1"
  local fixture="$2"
  local expected_summary="$3"
  local expected_finding="$4"
  local output
  local err="$TMP_DIR/$name.err"

  if ! output="$("$PARSER" <"$fixture" 2>"$err")"; then
    fail_test "$name" "expected success, got failure: $(<"$err")"
    return
  fi

  if ! jq -e \
    --arg summary "$expected_summary" \
    --arg finding "$expected_finding" \
    '.summary == $summary and .verdict == "FINDINGS" and .findings == [$finding]' \
    <<<"$output" >/dev/null; then
    fail_test "$name" "unexpected parsed output: $output"
    return
  fi

  pass_test "$name"
}

expect_failure() {
  local name="$1"
  local fixture="$2"
  local output
  local err="$TMP_DIR/$name.err"

  if output="$("$PARSER" <"$fixture" 2>"$err")"; then
    fail_test "$name" "expected failure, got success: $output"
    return
  fi

  if [[ ! -s "$err" ]]; then
    fail_test "$name" "expected an error message on stderr"
    return
  fi

  pass_test "$name"
}

cat >"$TMP_DIR/pass.txt" <<'EOF'
Codex reasoning before the block.
=== ORCHESTRATION-CONTRACT ===
Summary: Implemented the parser and tests.
Verdict: PASS
Findings:
FilesTouched:
- scripts/parse-contract.sh
- tests/scripts/parse-contract.test.sh
=== END-CONTRACT ===
EOF

cat >"$TMP_DIR/findings.txt" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Verification found two concerns.
Verdict: FINDINGS
Findings:
- First non-blocking concern.
- Second non-blocking concern.
FilesTouched:
- scripts/parse-contract.sh
=== END-CONTRACT ===
EOF

cat >"$TMP_DIR/fail.txt" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Verification failed.
Verdict: FAIL
Findings:
- Required behavior is missing.
FilesTouched:
=== END-CONTRACT ===
EOF

cat >"$TMP_DIR/missing-open.txt" <<'EOF'
Summary: This is not inside a contract.
Verdict: PASS
=== END-CONTRACT ===
EOF

cat >"$TMP_DIR/missing-close.txt" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: The block never closes.
Verdict: PASS
Findings:
FilesTouched:
EOF

cat >"$TMP_DIR/malformed-verdict.txt" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Verdict token is invalid.
Verdict: PASSED
Findings:
FilesTouched:
=== END-CONTRACT ===
EOF

cat >"$TMP_DIR/trailing-text.txt" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: The contract is followed by text.
Verdict: PASS
Findings:
FilesTouched:
=== END-CONTRACT ===
extra text
EOF

cat >"$TMP_DIR/crlf-lf.txt" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: CRLF line endings should parse.
Verdict: PASS
Findings:
FilesTouched:
- scripts/parse-contract.sh
=== END-CONTRACT ===
EOF
sed 's/$/\r/' "$TMP_DIR/crlf-lf.txt" >"$TMP_DIR/crlf.txt"

cat >"$TMP_DIR/multiple-blocks.txt" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Earlier block should be ignored.
Verdict: FAIL
Findings:
- Earlier failure.
FilesTouched:
=== END-CONTRACT ===
Intervening model output.
=== ORCHESTRATION-CONTRACT ===
Summary: Final block should be parsed.
Verdict: PASS
Findings:
FilesTouched:
- scripts/parse-contract.sh
=== END-CONTRACT ===
EOF

cat >"$TMP_DIR/dash-verdict-finding.txt" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Reserved labels in finding text are allowed.
Verdict: FINDINGS
Findings:
- Verdict: this is finding text, not a field.
FilesTouched:
=== END-CONTRACT ===
EOF

cat >"$TMP_DIR/star-verdict-finding.txt" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Reserved labels in finding text are allowed.
Verdict: FINDINGS
Findings:
* Verdict: this is finding text, not a field.
FilesTouched:
=== END-CONTRACT ===
EOF

cat >"$TMP_DIR/dash-summary-finding.txt" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Reserved labels in finding text are allowed.
Verdict: FINDINGS
Findings:
- Summary: this is finding text, not a field.
FilesTouched:
=== END-CONTRACT ===
EOF

cat >"$TMP_DIR/star-summary-finding.txt" <<'EOF'
=== ORCHESTRATION-CONTRACT ===
Summary: Reserved labels in finding text are allowed.
Verdict: FINDINGS
Findings:
* Summary: this is finding text, not a field.
FilesTouched:
=== END-CONTRACT ===
EOF

expect_success "well-formed PASS with files" "$TMP_DIR/pass.txt" "PASS"
expect_success "well-formed FINDINGS" "$TMP_DIR/findings.txt" "FINDINGS"
expect_success "well-formed FAIL" "$TMP_DIR/fail.txt" "FAIL"
expect_failure "missing opening sentinel" "$TMP_DIR/missing-open.txt"
expect_failure "missing closing sentinel" "$TMP_DIR/missing-close.txt"
expect_failure "malformed verdict" "$TMP_DIR/malformed-verdict.txt"
expect_failure "trailing non-whitespace text" "$TMP_DIR/trailing-text.txt"
expect_success "CRLF well-formed PASS" "$TMP_DIR/crlf.txt" "PASS"
expect_success "multiple blocks use last" "$TMP_DIR/multiple-blocks.txt" "PASS"
expect_finding_text "dash Verdict prefix remains a finding" "$TMP_DIR/dash-verdict-finding.txt" \
  "Reserved labels in finding text are allowed." "Verdict: this is finding text, not a field."
expect_finding_text "star Verdict prefix remains a finding" "$TMP_DIR/star-verdict-finding.txt" \
  "Reserved labels in finding text are allowed." "Verdict: this is finding text, not a field."
expect_finding_text "dash Summary prefix remains a finding" "$TMP_DIR/dash-summary-finding.txt" \
  "Reserved labels in finding text are allowed." "Summary: this is finding text, not a field."
expect_finding_text "star Summary prefix remains a finding" "$TMP_DIR/star-summary-finding.txt" \
  "Reserved labels in finding text are allowed." "Summary: this is finding text, not a field."

if ((failures > 0)); then
  exit 1
fi
