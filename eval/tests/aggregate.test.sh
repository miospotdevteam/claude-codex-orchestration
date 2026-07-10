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

reset_fixture() {
  rm -rf "$RUN_DIR"
  mkdir -p "$RAW_DIR"
}

write_map() {
  printf '%s\n' "$1" >"$RAW_DIR/de-anonymization-map.json"
}

write_panels() {
  local task_id="$1"
  local track="$2"
  local score_a="$3"
  local score_b="$4"
  local score_c="$5"
  local judge
  local safe_task

  safe_task="${task_id//\//-}"
  for judge in codex grok opus; do
    jq -n \
      --arg judge "$judge" \
      --arg taskId "$task_id" \
      --arg track "$track" \
      --argjson scoreA "$score_a" \
      --argjson scoreB "$score_b" \
      --argjson scoreC "$score_c" \
      '{
        judge: $judge,
        taskId: $taskId,
        track: $track,
        scores: {A: $scoreA, B: $scoreB, C: $scoreC},
        rationale: "fixture rationale"
      }' >"$RAW_DIR/panel-$safe_task-$track-$judge.json"
  done
}

write_objective() {
  local task_id="$1"
  local model="$2"
  local track="$3"
  local passed="$4"
  local total="$5"
  local safe_task

  safe_task="${task_id//\//-}"
  jq -n \
    --arg taskId "$task_id" \
    --arg model "$model" \
    --arg track "$track" \
    --argjson passed "$passed" \
    --argjson total "$total" \
    '{
      taskId: $taskId,
      model: $model,
      track: $track,
      passed: $passed,
      total: $total,
      correctness: ($passed / $total)
    }' >"$RAW_DIR/objective-$safe_task-$track-$model.json"
}

expect_failure() {
  local name="$1"
  local expected="$2"
  local output

  if output="$(bash "$AGGREGATE" "$RUN_ID" 2>&1)"; then
    fail "$name" "aggregate.sh unexpectedly succeeded"
  elif [[ "$output" == *"$expected"* ]]; then
    pass "$name"
  else
    fail "$name" "expected error containing '$expected', got: $output"
  fi
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

# The established empty-input diagnostic must remain more specific than the
# required-map diagnostic.
reset_fixture
expect_failure "zero raw JSON files are rejected" "no raw JSON files found"

# A panel without the separately produced map must never be silently filtered.
reset_fixture
write_panels "frontend/pricing-table" "A" 5 4 0
expect_failure "missing de-anonymization map is rejected" "de-anonymization map not found"

# The map path contains exactly one JSON document. A valid first document must
# not cause trailing JSON documents to be ignored.
reset_fixture
write_map '{
  "mappings": [
    {"taskId":"frontend/pricing-table","track":"A","candidateModels":{"A":"codex","B":"grok","C":"opus"}},
    {"taskId":"frontend/pricing-table","track":"B","candidateModels":{"A":"opus","B":"codex","C":"grok"}}
  ]
}
{"unexpected":"second document"}'
write_panels "frontend/pricing-table" "A" 5 4 3
write_panels "frontend/pricing-table" "B" 3 5 4
expect_failure "multiple map documents are rejected" "invalid de-anonymization map schema"

# Runbook-verbatim judge records contain no inline candidateModels. The map is
# per task and per track: label A names codex for pricing-table but opus for
# empty-state, while label C names codex for empty-state.
reset_fixture
write_map '{
  "mappings": [
    {"taskId":"frontend/pricing-table","track":"A","candidateModels":{"A":"codex","B":"opus","C":"grok"}},
    {"taskId":"frontend/pricing-table","track":"B","candidateModels":{"A":"grok","B":"codex","C":"opus"}},
    {"taskId":"frontend/empty-state","track":"A","candidateModels":{"A":"opus","B":"grok","C":"codex"}},
    {"taskId":"frontend/empty-state","track":"B","candidateModels":{"A":"codex","B":"opus","C":"grok"}}
  ]
}'
write_panels "frontend/pricing-table" "A" 5 4 0
write_panels "frontend/pricing-table" "B" 0 4 3
write_panels "frontend/empty-state" "A" 1 0 4
write_panels "frontend/empty-state" "B" 3 1 0

if ! bash "$AGGREGATE" "$RUN_ID"; then
  fail "documented judge records emit a scorecard" "aggregate.sh exited non-zero"
else
  pass "documented judge records emit a scorecard"
fi

SCORECARD_JSON="$RUN_DIR/scorecard.json"
SCORECARD_MD="$RUN_DIR/scorecard.md"

if [[ -s "$SCORECARD_JSON" && -s "$SCORECARD_MD" ]]; then
  pass "scorecard outputs are non-empty"
else
  fail "scorecard outputs are non-empty" "expected scorecard.json and scorecard.md"
fi

assert_jq "documented shape yields nonzero task-specific ranking" "$SCORECARD_JSON" \
  '.domains.frontend.ranking[0].model == "codex" and .domains.frontend.ranking[0].combined == 4.5'
assert_jq "per-task label permutations drive Track B delta" "$SCORECARD_JSON" \
  '.domains.frontend.wrapperDelta.codex == 1'

# Corpus structure marks url-shortener as code. Complete panels without the
# corresponding objective records must fail rather than becoming taste scores.
reset_fixture
write_map '{
  "mappings": [
    {"taskId":"backend/url-shortener","track":"A","candidateModels":{"A":"codex","B":"grok","C":"opus"}},
    {"taskId":"backend/url-shortener","track":"B","candidateModels":{"A":"opus","B":"codex","C":"grok"}}
  ]
}'
write_panels "backend/url-shortener" "A" 5 4 3
write_panels "backend/url-shortener" "B" 3 5 4
expect_failure "code task missing objective records is rejected" "missing code objective record"

# The preflight requires both quality tracks before ranking anything.
reset_fixture
write_map '{
  "mappings": [
    {"taskId":"frontend/pricing-table","track":"A","candidateModels":{"A":"codex","B":"grok","C":"opus"}},
    {"taskId":"frontend/pricing-table","track":"B","candidateModels":{"A":"opus","B":"codex","C":"grok"}}
  ]
}'
write_panels "frontend/pricing-table" "A" 5 4 3
expect_failure "missing Track B quality is rejected" "incomplete judge panel"

# Duplicate panel identities and malformed score objects must be hard errors.
reset_fixture
write_map '{
  "mappings": [
    {"taskId":"frontend/pricing-table","track":"A","candidateModels":{"A":"codex","B":"grok","C":"opus"}},
    {"taskId":"frontend/pricing-table","track":"B","candidateModels":{"A":"opus","B":"codex","C":"grok"}}
  ]
}'
write_panels "frontend/pricing-table" "A" 5 4 3
write_panels "frontend/pricing-table" "B" 3 5 4
cp "$RAW_DIR/panel-frontend-pricing-table-A-codex.json" \
  "$RAW_DIR/panel-frontend-pricing-table-A-codex-duplicate.json"
expect_failure "duplicate judge identity is rejected" "duplicate judge panel identity"

reset_fixture
write_map '{
  "mappings": [
    {"taskId":"frontend/pricing-table","track":"A","candidateModels":{"A":"codex","B":"grok","C":"opus"}},
    {"taskId":"frontend/pricing-table","track":"B","candidateModels":{"A":"opus","B":"codex","C":"grok"}}
  ]
}'
write_panels "frontend/pricing-table" "A" 5 4 3
write_panels "frontend/pricing-table" "B" 3 5 4
jq '.scores.C = "high"' "$RAW_DIR/panel-frontend-pricing-table-B-opus.json" \
  >"$RAW_DIR/malformed.json"
rm "$RAW_DIR/panel-frontend-pricing-table-B-opus.json"
expect_failure "malformed judge panel is rejected" "malformed judge panel"

# Neither maps nor score records may introduce a task outside eval/corpus.
reset_fixture
write_map '{
  "mappings": [
    {"taskId":"frontend/not-in-corpus","track":"A","candidateModels":{"A":"codex","B":"grok","C":"opus"}},
    {"taskId":"frontend/not-in-corpus","track":"B","candidateModels":{"A":"opus","B":"codex","C":"grok"}}
  ]
}'
write_panels "frontend/not-in-corpus" "A" 5 4 3
write_panels "frontend/not-in-corpus" "B" 3 5 4
expect_failure "unknown task ID is rejected" "unknown taskId"

# A complete code dataset remains scoreable; a failed candidate is represented
# by a valid objective record and receives a gated combined score of zero.
reset_fixture
write_map '{
  "mappings": [
    {"taskId":"backend/url-shortener","track":"A","candidateModels":{"A":"codex","B":"grok","C":"opus"}},
    {"taskId":"backend/url-shortener","track":"B","candidateModels":{"A":"opus","B":"codex","C":"grok"}}
  ]
}'
write_panels "backend/url-shortener" "A" 5 4 3
write_panels "backend/url-shortener" "B" 3 5 4
for track in A B; do
  for model in codex grok opus; do
    if [[ "$track/$model" == "A/grok" ]]; then
      write_objective "backend/url-shortener" "$model" "$track" 7 8
    else
      write_objective "backend/url-shortener" "$model" "$track" 8 8
    fi
  done
done

if ! bash "$AGGREGATE" "$RUN_ID"; then
  fail "complete code dataset emits a scorecard" "aggregate.sh exited non-zero"
else
  pass "complete code dataset emits a scorecard"
fi
assert_jq "failed code candidate is correctness-gated" "$RUN_DIR/scorecard.json" \
  '.domains.backend.ranking[-1].model == "grok" and .domains.backend.ranking[-1].combined == 0'

if ((FAIL_COUNT > 0)); then
  exit 1
fi

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
