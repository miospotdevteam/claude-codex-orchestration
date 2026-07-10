#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/../../skills/skill-review-standard/scripts/validate-structure.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
LAST_STATUS=0
LAST_OUTPUT=""
LAST_ERROR=""

pass() {
  printf 'PASS %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

run_validator() {
  local skill_dir="$1"
  local stderr_file="$TMP_DIR/validator.stderr"

  set +e
  LAST_OUTPUT="$(bash "$VALIDATOR" "$skill_dir" 2>"$stderr_file")"
  LAST_STATUS=$?
  set -e
  LAST_ERROR="$(<"$stderr_file")"
}

output_contains() {
  grep -Fq -- "$1" <<<"$LAST_OUTPUT"
}

output_lacks() {
  ! grep -Fq -- "$1" <<<"$LAST_OUTPUT"
}

write_valid_skill() {
  local skill_dir="$1"

  mkdir -p "$skill_dir/scripts"
  cat >"$skill_dir/SKILL.md" <<'EOF'
---
name: valid-skill
description: Validates a fixture skill. Do NOT use for unrelated work.
---

# Valid Skill

Run `scripts/helper.sh` when validation is requested.
EOF
  cat >"$skill_dir/scripts/helper.sh" <<'EOF'
#!/usr/bin/env bash
printf 'fixture helper\n'
EOF
}

test_strict_mode() {
  local name="validator keeps bash strict mode"

  if grep -Fqx 'set -euo pipefail' "$VALIDATOR"; then
    pass "$name"
  else
    fail "$name" "expected set -euo pipefail"
  fi
}

test_valid_skill() {
  local name="valid skill passes structural validation"
  local skill_dir="$TMP_DIR/valid"

  write_valid_skill "$skill_dir"
  run_validator "$skill_dir"

  if [[ "$LAST_STATUS" -ne 0 ]]; then
    fail "$name" "expected exit 0, got $LAST_STATUS; stderr=$LAST_ERROR"
  elif ! output_contains "PASS  Frontmatter: name and description present"; then
    fail "$name" "missing frontmatter PASS: $LAST_OUTPUT"
  elif ! output_contains "PASS  Reference: scripts/helper.sh exists (local)"; then
    fail "$name" "missing reference PASS: $LAST_OUTPUT"
  elif ! output_lacks "FAIL  "; then
    fail "$name" "unexpected failure output: $LAST_OUTPUT"
  elif ! output_lacks "WARN  "; then
    fail "$name" "unexpected warning output: $LAST_OUTPUT"
  else
    pass "$name"
  fi
}

test_missing_skill_file() {
  local name="missing SKILL.md fails"
  local skill_dir="$TMP_DIR/missing-skill-file"

  mkdir -p "$skill_dir"
  run_validator "$skill_dir"

  if [[ "$LAST_STATUS" -ne 1 ]]; then
    fail "$name" "expected exit 1, got $LAST_STATUS; output=$LAST_OUTPUT"
  elif ! output_contains "FAIL  SKILL.md does not exist in $skill_dir"; then
    fail "$name" "missing expected failure: $LAST_OUTPUT"
  else
    pass "$name"
  fi
}

test_missing_frontmatter() {
  local name="missing frontmatter fails"
  local skill_dir="$TMP_DIR/missing-frontmatter"

  mkdir -p "$skill_dir"
  cat >"$skill_dir/SKILL.md" <<'EOF'
# Missing Frontmatter

This skill has no YAML frontmatter.
EOF
  run_validator "$skill_dir"

  if [[ "$LAST_STATUS" -ne 1 ]]; then
    fail "$name" "expected exit 1, got $LAST_STATUS; output=$LAST_OUTPUT"
  elif ! output_contains "FAIL  Frontmatter: missing 'name' field"; then
    fail "$name" "missing name failure not reported: $LAST_OUTPUT"
  elif ! output_contains "FAIL  Frontmatter: missing 'description' field"; then
    fail "$name" "missing description failure not reported: $LAST_OUTPUT"
  else
    pass "$name"
  fi
}

test_unclosed_frontmatter() {
  local name="unclosed frontmatter fails"
  local skill_dir="$TMP_DIR/unclosed-frontmatter"

  mkdir -p "$skill_dir"
  cat >"$skill_dir/SKILL.md" <<'EOF'
---
name: unclosed-frontmatter
description: Looks complete but is not closed. Do NOT use for unrelated work.

# Invalid Skill
EOF
  run_validator "$skill_dir"

  if [[ "$LAST_STATUS" -ne 1 ]]; then
    fail "$name" "expected exit 1, got $LAST_STATUS; output=$LAST_OUTPUT"
  elif ! output_contains "FAIL  Frontmatter: missing opening or closing '---' delimiter"; then
    fail "$name" "missing delimiter failure not reported: $LAST_OUTPUT"
  else
    pass "$name"
  fi
}

test_missing_reference() {
  local name="missing referenced file fails"
  local skill_dir="$TMP_DIR/missing-reference"

  mkdir -p "$skill_dir"
  cat >"$skill_dir/SKILL.md" <<'EOF'
---
name: missing-reference
description: Exercises a broken file reference. Do NOT use for unrelated work.
---

# Missing Reference

Run `scripts/missing.sh` when invoked.
EOF
  run_validator "$skill_dir"

  if [[ "$LAST_STATUS" -ne 1 ]]; then
    fail "$name" "expected exit 1, got $LAST_STATUS; output=$LAST_OUTPUT"
  elif ! output_contains "FAIL  Reference: scripts/missing.sh does not exist"; then
    fail "$name" "missing reference failure not reported: $LAST_OUTPUT"
  else
    pass "$name"
  fi
}

test_orphan_warning_is_nonfatal() {
  local name="orphan warning preserves exit zero"
  local skill_dir="$TMP_DIR/orphan-warning"

  mkdir -p "$skill_dir/scripts"
  cat >"$skill_dir/SKILL.md" <<'EOF'
---
name: orphan-warning
description: Exercises warning semantics. Do NOT use for unrelated work.
---

# Orphan Warning

This skill is otherwise self-contained.
EOF
  cat >"$skill_dir/scripts/orphan.sh" <<'EOF'
#!/usr/bin/env bash
printf 'orphan fixture\n'
EOF
  run_validator "$skill_dir"

  if [[ "$LAST_STATUS" -ne 0 ]]; then
    fail "$name" "expected exit 0 for WARN-only result, got $LAST_STATUS; output=$LAST_OUTPUT"
  elif ! output_contains "WARN  Orphaned: scripts/orphan.sh not referenced in SKILL.md"; then
    fail "$name" "missing orphan warning: $LAST_OUTPUT"
  elif ! output_lacks "FAIL  "; then
    fail "$name" "warning-only fixture produced a failure: $LAST_OUTPUT"
  else
    pass "$name"
  fi
}

test_strict_mode
test_valid_skill
test_missing_skill_file
test_missing_frontmatter
test_unclosed_frontmatter
test_missing_reference
test_orphan_warning_is_nonfatal

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
