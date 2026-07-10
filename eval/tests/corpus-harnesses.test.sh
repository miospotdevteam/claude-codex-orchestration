#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
EVAL_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CONSOLIDATE_TASK="$EVAL_DIR/corpus/refactor/consolidate-responses"
VALIDATOR_TASK="$EVAL_DIR/corpus/refactor/extract-validator"

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

copy_reference() {
  local task_dir=$1
  local candidate_dir=$2

  mkdir -p "$candidate_dir"
  cp -R "$task_dir/reference/." "$candidate_dir"
}

replace_in_file() {
  local file=$1
  local pattern=$2
  local replacement=$3
  local rewritten="$file.rewritten"

  sed "s|$pattern|$replacement|g" "$file" >"$rewritten"
  mv "$rewritten" "$file"
}

expect_success() {
  local name=$1
  local task_dir=$2
  local candidate_dir=$3
  local output="$TMP_DIR/$name.output"

  if ! "$task_dir/tests/run.sh" "$candidate_dir" >"$output" 2>&1; then
    fail "$name" "expected success, got: $(<"$output")"
    return
  fi

  if ! grep -Fxq 'RESULT 9 9' "$output"; then
    fail "$name" "expected RESULT 9 9, got: $(<"$output")"
    return
  fi

  pass "$name"
}

expect_failure() {
  local name=$1
  local task_dir=$2
  local candidate_dir=$3
  local output="$TMP_DIR/$name.output"

  if "$task_dir/tests/run.sh" "$candidate_dir" >"$output" 2>&1; then
    fail "$name" "expected failure, got: $(<"$output")"
    return
  fi

  if ! grep -Eq '^RESULT [0-8] 9$' "$output"; then
    fail "$name" "expected a failing nine-test result, got: $(<"$output")"
    return
  fi

  pass "$name"
}

consolidate_reference="$TMP_DIR/consolidate-reference"
copy_reference "$CONSOLIDATE_TASK" "$consolidate_reference"
expect_success "consolidate reference passes" "$CONSOLIDATE_TASK" "$consolidate_reference"

consolidate_js_import="$TMP_DIR/consolidate-js-import"
copy_reference "$CONSOLIDATE_TASK" "$consolidate_js_import"
replace_in_file "$consolidate_js_import/handlers.js" 'require("./respond")' 'require("./respond.js")'
expect_success "consolidate accepts .js import" "$CONSOLIDATE_TASK" "$consolidate_js_import"

consolidate_extra_export="$TMP_DIR/consolidate-extra-export"
copy_reference "$CONSOLIDATE_TASK" "$consolidate_extra_export"
printf '\nmodule.exports.extra = () => true;\n' >>"$consolidate_extra_export/respond.js"
expect_failure "consolidate rejects extra export" "$CONSOLIDATE_TASK" "$consolidate_extra_export"

consolidate_missing_export="$TMP_DIR/consolidate-missing-export"
copy_reference "$CONSOLIDATE_TASK" "$consolidate_missing_export"
replace_in_file "$consolidate_missing_export/respond.js" \
  'module.exports = { ok, notFound };' \
  'module.exports = { ok };'
expect_failure "consolidate rejects missing export" "$CONSOLIDATE_TASK" "$consolidate_missing_export"

validator_reference="$TMP_DIR/validator-reference"
copy_reference "$VALIDATOR_TASK" "$validator_reference"
expect_success "validator reference passes" "$VALIDATOR_TASK" "$validator_reference"

validator_js_import="$TMP_DIR/validator-js-import"
copy_reference "$VALIDATOR_TASK" "$validator_js_import"
replace_in_file "$validator_js_import/users.js" 'require("./validators")' 'require("./validators.js")'
replace_in_file "$validator_js_import/products.js" 'require("./validators")' 'require("./validators.js")'
expect_success "validator accepts .js imports" "$VALIDATOR_TASK" "$validator_js_import"

validator_extra_export="$TMP_DIR/validator-extra-export"
copy_reference "$VALIDATOR_TASK" "$validator_extra_export"
printf '\nmodule.exports.extra = () => true;\n' >>"$validator_extra_export/validators.js"
expect_failure "validator rejects extra export" "$VALIDATOR_TASK" "$validator_extra_export"

validator_missing_export="$TMP_DIR/validator-missing-export"
copy_reference "$VALIDATOR_TASK" "$validator_missing_export"
replace_in_file "$validator_missing_export/validators.js" \
  'module.exports = { isNonEmptyString, isEmail };' \
  'module.exports = { isNonEmptyString };'
expect_failure "validator rejects missing export" "$VALIDATOR_TASK" "$validator_missing_export"

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
