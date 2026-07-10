#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$SCRIPT_DIR/../.."
AGGREGATE="$REPO_ROOT/eval/scripts/aggregate.sh"

RUN_ID="aggregate-test-$$"
RUN_DIR="$REPO_ROOT/eval/results/$RUN_ID"
RAW_DIR="$RUN_DIR/raw"

PASS_COUNT=0
FAIL_COUNT=0

trap 'rm -rf "$RUN_DIR"' EXIT

pass() {
  printf 'PASS %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_jq() {
  local name="$1"
  local file="$2"
  local filter="$3"

  if jq -e "$filter" "$file" >/dev/null; then
    pass "$name"
  else
    fail "$name" "jq assertion failed: $filter"
  fi
}

assert_file() {
  local name="$1"
  local file="$2"

  if [[ -s "$file" ]]; then
    pass "$name"
  else
    fail "$name" "expected non-empty file at $file"
  fi
}

write_fixture() {
  mkdir -p "$RAW_DIR"

  cat >"$RAW_DIR/backend-objective.json" <<'JSON'
[
  { "taskId": "backend/url-shortener", "model": "codex", "track": "A", "passed": 8, "total": 8, "correctness": 1 },
  { "taskId": "backend/url-shortener", "model": "opus",  "track": "A", "passed": 8, "total": 8, "correctness": 1 },
  { "taskId": "backend/url-shortener", "model": "grok",  "track": "A", "passed": 6, "total": 8, "correctness": 0.75 },
  { "taskId": "backend/url-shortener", "model": "codex", "track": "B", "passed": 8, "total": 8, "correctness": 1 },
  { "taskId": "backend/url-shortener", "model": "opus",  "track": "B", "passed": 8, "total": 8, "correctness": 1 },
  { "taskId": "backend/url-shortener", "model": "grok",  "track": "B", "passed": 8, "total": 8, "correctness": 1 },
  { "taskId": "backend/rate-limiter", "model": "codex", "track": "A", "passed": 5, "total": 5, "correctness": 1 },
  { "taskId": "backend/rate-limiter", "model": "opus",  "track": "A", "passed": 5, "total": 5, "correctness": 1 },
  { "taskId": "backend/rate-limiter", "model": "grok",  "track": "A", "passed": 5, "total": 5, "correctness": 1 },
  { "taskId": "backend/rate-limiter", "model": "codex", "track": "B", "passed": 5, "total": 5, "correctness": 1 },
  { "taskId": "backend/rate-limiter", "model": "opus",  "track": "B", "passed": 5, "total": 5, "correctness": 1 },
  { "taskId": "backend/rate-limiter", "model": "grok",  "track": "B", "passed": 5, "total": 5, "correctness": 1 }
]
JSON

  cat >"$RAW_DIR/backend-quality.json" <<'JSON'
[
  { "taskId": "backend/url-shortener", "model": "codex", "track": "A", "quality": 4.6 },
  { "taskId": "backend/url-shortener", "model": "opus",  "track": "A", "quality": 4.1 },
  { "taskId": "backend/url-shortener", "model": "grok",  "track": "A", "quality": 4.9 },
  { "taskId": "backend/url-shortener", "model": "codex", "track": "B", "quality": 4.0 },
  { "taskId": "backend/url-shortener", "model": "opus",  "track": "B", "quality": 4.3 },
  { "taskId": "backend/url-shortener", "model": "grok",  "track": "B", "quality": 3.0 },
  { "taskId": "backend/rate-limiter", "model": "codex", "track": "A", "quality": 4.4 },
  { "taskId": "backend/rate-limiter", "model": "opus",  "track": "A", "quality": 4.3 },
  { "taskId": "backend/rate-limiter", "model": "grok",  "track": "A", "quality": 5.0 },
  { "taskId": "backend/rate-limiter", "model": "codex", "track": "B", "quality": 3.8 },
  { "taskId": "backend/rate-limiter", "model": "opus",  "track": "B", "quality": 4.1 },
  { "taskId": "backend/rate-limiter", "model": "grok",  "track": "B", "quality": 4.5 }
]
JSON

  cat >"$RAW_DIR/frontend-quality.json" <<'JSON'
[
  { "taskId": "frontend/pricing-table", "model": "codex", "track": "A", "quality": 3.0 },
  { "taskId": "frontend/pricing-table", "model": "opus",  "track": "A", "quality": 4.7 },
  { "taskId": "frontend/pricing-table", "model": "grok",  "track": "A", "quality": 4.0 },
  { "taskId": "frontend/pricing-table", "model": "codex", "track": "B", "quality": 3.4 },
  { "taskId": "frontend/pricing-table", "model": "opus",  "track": "B", "quality": 4.2 },
  { "taskId": "frontend/pricing-table", "model": "grok",  "track": "B", "quality": 4.1 }
]
JSON
}

write_fixture

if ! bash "$AGGREGATE" "$RUN_ID"; then
  fail "aggregate emits scorecard" "aggregate.sh exited non-zero"
else
  pass "aggregate emits scorecard"
fi

SCORECARD_JSON="$RUN_DIR/scorecard.json"
SCORECARD_MD="$RUN_DIR/scorecard.md"

assert_file "scorecard.json exists" "$SCORECARD_JSON"
assert_file "scorecard.md exists" "$SCORECARD_MD"

assert_jq "backend Track A winner is codex" "$SCORECARD_JSON" \
  '.domains.backend.ranking[0].model == "codex" and .domains.backend.ranking[0].combined == 4.5'
assert_jq "backend margin is winner minus runner-up" "$SCORECARD_JSON" \
  '.domains.backend.margin == 0.3'
assert_jq "backend wrapper delta is Track A minus Track B" "$SCORECARD_JSON" \
  '.domains.backend.wrapperDelta.codex == 0.6 and .domains.backend.wrapperDelta.opus == 0 and .domains.backend.wrapperDelta.grok == -3.75'
assert_jq "failed code domain cannot outrank passing solutions" "$SCORECARD_JSON" \
  '.domains.backend.ranking[2].model == "grok" and .domains.backend.ranking[2].combined == 0'
assert_jq "frontend taste winner is opus" "$SCORECARD_JSON" \
  '.domains.frontend.ranking[0].model == "opus" and .domains.frontend.ranking[0].combined == 4.7'
assert_jq "frontend taste margin is reported" "$SCORECARD_JSON" \
  '.domains.frontend.margin == 0.7'
assert_jq "frontend taste delta uses rubric score directly" "$SCORECARD_JSON" \
  '.domains.frontend.wrapperDelta.opus == 0.5 and .domains.frontend.wrapperDelta.codex == -0.4'

if ((FAIL_COUNT > 0)); then
  exit 1
fi

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
