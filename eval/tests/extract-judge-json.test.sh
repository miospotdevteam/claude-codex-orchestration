#!/usr/bin/env bash
# Unit tests for extract-judge-json.py — the robust judge-output extractor that
# recovers a {"scores":{A,B,C},"rationale"} object from a model's raw stdout even
# when wrapped in prose or markdown fences.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT="$SCRIPT_DIR/../scripts/extract-judge-json.py"

pass=0
fail=0
ok() { printf 'PASS %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL %s: %s\n' "$1" "$2"; fail=$((fail + 1)); }

# expect success + scores equal to a jq-comparable object
expect_scores() {
  local name="$1" input="$2" want="$3"
  local out
  out="$(printf '%s' "$input" | python3 "$EXTRACT" 2>/dev/null)" || { no "$name" "extractor exited non-zero"; return; }
  if jq -e --argjson want "$want" '.scores == $want' >/dev/null <<<"$out"; then
    ok "$name"
  else
    no "$name" "scores mismatch: got $out"
  fi
}

expect_fail() {
  local name="$1" input="$2"
  if printf '%s' "$input" | python3 "$EXTRACT" >/dev/null 2>&1; then
    no "$name" "expected non-zero exit but succeeded"
  else
    ok "$name"
  fi
}

expect_scores "bare json" \
  '{"scores":{"A":4.1,"B":3,"C":5},"rationale":"ok"}' \
  '{"A":4.1,"B":3,"C":5}'

expect_scores "fenced json" \
  'Here you go:
```json
{"scores":{"A":4,"B":2,"C":5},"rationale":"x"}
```
Thanks!' \
  '{"A":4,"B":2,"C":5}'

expect_scores "prose-wrapped with leading non-scores object" \
  'My reasoning: {"note":"thinking"} then the result
{"scores":{"A":2,"B":4.5,"C":3.25},"rationale":"done"}' \
  '{"A":2,"B":4.5,"C":3.25}'

expect_fail "no json at all" "I could not evaluate these candidates."
expect_fail "json without scores" '{"foo":1,"bar":2}'
expect_fail "non-numeric score" '{"scores":{"A":"high","B":3,"C":5},"rationale":"bad"}'
expect_scores "boundary scores are accepted" \
  '{"scores":{"A":0,"B":5,"C":2.5},"rationale":"bounds"}' \
  '{"A":0,"B":5,"C":2.5}'
expect_fail "negative score" '{"scores":{"A":-0.1,"B":3,"C":5},"rationale":"bad"}'
expect_fail "score above five" '{"scores":{"A":5.1,"B":3,"C":5},"rationale":"bad"}'
expect_fail "NaN score" '{"scores":{"A":NaN,"B":3,"C":5},"rationale":"bad"}'
expect_fail "positive infinity score" '{"scores":{"A":Infinity,"B":3,"C":5},"rationale":"bad"}'
expect_fail "negative infinity score" '{"scores":{"A":-Infinity,"B":3,"C":5},"rationale":"bad"}'
expect_fail "partial score object" '{"scores":{"A":1,"B":3},"rationale":"bad"}'

printf 'TOTAL pass=%d fail=%d\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
