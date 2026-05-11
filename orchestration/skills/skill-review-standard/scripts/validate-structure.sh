#!/usr/bin/env bash
# Structural validation for a Claude Code skill directory.
# Usage: validate-structure.sh <path-to-skill-directory>
# Exit code: 0 if all PASS/WARN, 1 if any FAIL.

set -euo pipefail

SKILL_DIR="${1:?Usage: validate-structure.sh <skill-directory>}"
SKILL_FILE="$SKILL_DIR/SKILL.md"
HAS_FAIL=0

pass() { printf "PASS  %s\n" "$1"; }
fail() { printf "FAIL  %s\n" "$1"; HAS_FAIL=1; }
warn() { printf "WARN  %s\n" "$1"; }

# --- Check 1: SKILL.md exists ---
if [ ! -f "$SKILL_FILE" ]; then
  fail "SKILL.md does not exist in $SKILL_DIR"
  exit 1
fi

# --- Check 2: Frontmatter has name and description ---
# Extract YAML frontmatter (between first pair of ---)
FRONTMATTER=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$SKILL_FILE")

HAS_NAME=$(echo "$FRONTMATTER" | grep -c '^name:' || true)
HAS_DESC=$(echo "$FRONTMATTER" | grep -c '^description:' || true)

if [ "$HAS_NAME" -ge 1 ] && [ "$HAS_DESC" -ge 1 ]; then
  pass "Frontmatter: name and description present"
else
  [ "$HAS_NAME" -lt 1 ] && fail "Frontmatter: missing 'name' field"
  [ "$HAS_DESC" -lt 1 ] && fail "Frontmatter: missing 'description' field"
fi

# --- Check 3: Description has negative trigger guidance ---
DESC_TEXT=$(echo "$FRONTMATTER" | sed -n '/^description:/,/^[a-z]*:/{ /^description:/p; /^[^a-z]/p; }')
if echo "$DESC_TEXT" | grep -qi 'do not use\|don.t use\|not use when\|not use for'; then
  pass "Description: has negative trigger guidance"
else
  fail "Description: no negative trigger guidance (missing 'do not use' or equivalent)"
fi

# --- Check 4: SKILL.md line count ---
LINE_COUNT=$(wc -l < "$SKILL_FILE" | tr -d ' ')
if [ "$LINE_COUNT" -le 500 ]; then
  pass "Size: $LINE_COUNT lines (under 500)"
else
  fail "Size: $LINE_COUNT lines (over 500 limit)"
fi

# --- Check 5: Referenced files exist ---
# Strip code fences before scanning for references (avoids false positives from
# template examples like `scripts/task.sh` inside ```md blocks).
SKILL_NO_FENCES=$(awk '/^```/{skip=!skip; next} !skip{print}' "$SKILL_FILE")
REFERENCED_FILES=$(echo "$SKILL_NO_FENCES" | grep -oE '(references|scripts)/[a-zA-Z0-9._-]+\.[a-z]+' | sort -u || true)

# Skills often reference shared files from sibling skill directories.
# Walk up to find the plugin root (directory containing skills/) so we can
# resolve references across all skills in the plugin.
PLUGIN_ROOT=""
_dir="$SKILL_DIR"
while [ "$_dir" != "/" ]; do
  _dir=$(dirname "$_dir")
  if [ -d "$_dir/skills" ]; then
    PLUGIN_ROOT="$_dir"
    break
  fi
done

if [ -n "$REFERENCED_FILES" ]; then
  while IFS= read -r ref; do
    if [ -f "$SKILL_DIR/$ref" ]; then
      pass "Reference: $ref exists (local)"
    elif [ -n "$PLUGIN_ROOT" ]; then
      # Search all skill directories under the plugin root
      FOUND=0
      for skill_dir in "$PLUGIN_ROOT"/skills/*/; do
        if [ -f "$skill_dir$ref" ]; then
          FOUND=1
          break
        fi
      done
      if [ "$FOUND" -eq 1 ]; then
        pass "Reference: $ref exists (shared)"
      else
        fail "Reference: $ref does not exist"
      fi
    else
      fail "Reference: $ref does not exist"
    fi
  done <<< "$REFERENCED_FILES"
else
  pass "References: no external files referenced (self-contained skill)"
fi

# --- Check 6: Orphaned files ---
for subdir in references scripts; do
  if [ -d "$SKILL_DIR/$subdir" ]; then
    for file in "$SKILL_DIR/$subdir"/*; do
      [ -f "$file" ] || continue
      BASENAME=$(basename "$file")
      RELATIVE="$subdir/$BASENAME"
      if ! grep -q "$RELATIVE" "$SKILL_FILE" 2>/dev/null; then
        warn "Orphaned: $RELATIVE not referenced in SKILL.md"
      fi
    done
  fi
done

exit $HAS_FAIL
