#!/usr/bin/env bash
set -euo pipefail

# Diff input convention:
# - With --diff-file <path>, stdin is the rendered step block and the diff is read
#   from the provided file.
# - Without --diff-file, stdin must contain the rendered step block, followed by a
#   line containing exactly ---DIFF---, followed by the diff content.

usage() {
  cat >&2 <<'EOF'
usage: run-codex-verify.sh --plan-id <id> --step-id <id> --root-dir <path> [--skill <name>] [--diff-file <path>]
EOF
}

die_invocation() {
  printf 'run-codex-verify: %s\n' "$1" >&2
  usage
  exit 1
}

PLAN_ID=""
STEP_ID=""
ROOT_DIR=""
SKILL=""
DIFF_FILE=""

while (($# > 0)); do
  case "$1" in
    --plan-id)
      (($# >= 2)) || die_invocation "--plan-id requires a value"
      PLAN_ID="$2"
      shift 2
      ;;
    --step-id)
      (($# >= 2)) || die_invocation "--step-id requires a value"
      STEP_ID="$2"
      shift 2
      ;;
    --root-dir)
      (($# >= 2)) || die_invocation "--root-dir requires a value"
      ROOT_DIR="$2"
      shift 2
      ;;
    --skill)
      (($# >= 2)) || die_invocation "--skill requires a value"
      SKILL="$2"
      shift 2
      ;;
    --diff-file)
      (($# >= 2)) || die_invocation "--diff-file requires a value"
      DIFF_FILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die_invocation "unknown argument: $1"
      ;;
  esac
done

[[ -n "$PLAN_ID" ]] || die_invocation "--plan-id is required"
case "$PLAN_ID" in */* | *..*) die_invocation "--plan-id must be a plain identifier (no / or ..)" ;; esac
case "$STEP_ID" in */* | *..*) die_invocation "--step-id must be a plain identifier (no / or ..)" ;; esac
[[ -n "$STEP_ID" ]] || die_invocation "--step-id is required"
[[ -n "$ROOT_DIR" ]] || die_invocation "--root-dir is required"
[[ "$ROOT_DIR" = /* ]] || die_invocation "--root-dir must be an absolute path"
[[ -d "$ROOT_DIR" ]] || die_invocation "--root-dir does not exist or is not a directory: $ROOT_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PARSER="$SCRIPT_DIR/parse-contract.sh"
[[ -x "$PARSER" ]] || die_invocation "parser is not executable: $PARSER"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STEP_BLOCK_FILE="$TMP_DIR/step-block.txt"
DIFF_CONTENT_FILE="$TMP_DIR/diff.txt"
PROMPT_FILE="$TMP_DIR/prompt.txt"
CODEX_STDOUT_FILE="$TMP_DIR/codex-stdout.txt"
CODEX_STDERR_FILE="$TMP_DIR/codex-stderr.txt"
CODEX_LAST_MESSAGE_FILE="$TMP_DIR/codex-last-message.txt"

if [[ -n "$DIFF_FILE" ]]; then
  [[ -f "$DIFF_FILE" ]] || die_invocation "--diff-file does not exist or is not a file: $DIFF_FILE"
  cat >"$STEP_BLOCK_FILE"
  cat "$DIFF_FILE" >"$DIFF_CONTENT_FILE"
else
  found_diff_sentinel=0
  : >"$STEP_BLOCK_FILE"
  : >"$DIFF_CONTENT_FILE"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$found_diff_sentinel" -eq 0 && "$line" == "---DIFF---" ]]; then
      found_diff_sentinel=1
      continue
    fi

    if [[ "$found_diff_sentinel" -eq 1 ]]; then
      printf '%s\n' "$line" >>"$DIFF_CONTENT_FILE"
    else
      printf '%s\n' "$line" >>"$STEP_BLOCK_FILE"
    fi
  done

  [[ "$found_diff_sentinel" -eq 1 ]] || die_invocation "stdin must contain a ---DIFF--- sentinel when --diff-file is absent"
fi

# Real plans keep logs beside plan.json; synthetic/out-of-band ids must not
# mkdir plan-less debris under active/.
if [[ -f "$ROOT_DIR/.temp/plan-mode/active/$PLAN_ID/plan.json" ]]; then
  LOG_DIR="$ROOT_DIR/.temp/plan-mode/active/$PLAN_ID/logs"
else
  LOG_DIR="$ROOT_DIR/.temp/plan-mode/logs/$PLAN_ID"
fi
LOG_FILE="$LOG_DIR/codex-verify-$STEP_ID.log"
mkdir -p "$LOG_DIR"
# Recheck after mkdir: if archive-plan moved the plan between the
# plan.json check and mkdir, drop the recreated debris dir and fall
# back to the out-of-band location.
if [[ "$LOG_DIR" == "$ROOT_DIR/.temp/plan-mode/active/"* && ! -f "$ROOT_DIR/.temp/plan-mode/active/$PLAN_ID/plan.json" ]]; then
  rmdir "$LOG_DIR" 2>/dev/null || true
  rmdir "$ROOT_DIR/.temp/plan-mode/active/$PLAN_ID" 2>/dev/null || true
  LOG_DIR="$ROOT_DIR/.temp/plan-mode/logs/$PLAN_ID"
  LOG_FILE="$LOG_DIR/codex-verify-$STEP_ID.log"
  mkdir -p "$LOG_DIR"
fi

{
  cat <<'EOF'
You are Codex running in VERIFY mode for the orchestration plugin. You may read files and the provided diff. You may NOT edit files. You must finish with the contract block. Your verdict is PASS only if every acceptance criterion is met by the diff.

# Step Block
EOF
  cat "$STEP_BLOCK_FILE"
  printf '\n'
  if [[ -n "$SKILL" ]]; then
    printf '# Skill\n%s\n\n' "$SKILL"
  fi
  cat <<'EOF'
# Diff
EOF
  cat "$DIFF_CONTENT_FILE"
  cat <<'EOF'

# Output Contract
Your final output must end with the contract block in the exact shape specified. Do not omit any field. Do not emit anything after `=== END-CONTRACT ===`.

=== ORCHESTRATION-CONTRACT ===
Summary: <one paragraph, at most 6 sentences, plain prose>
Verdict: PASS | FINDINGS | FAIL
Findings:
- <one-line finding, or omit on PASS>
FilesTouched:
=== END-CONTRACT ===
EOF
} >"$PROMPT_FILE"

if ! codex exec \
  -C "$ROOT_DIR" \
  -s read-only \
  --skip-git-repo-check \
  -o "$CODEX_LAST_MESSAGE_FILE" \
  - <"$PROMPT_FILE" >"$CODEX_STDOUT_FILE" 2>"$CODEX_STDERR_FILE"; then
  {
    printf '%s\n' '--- codex stdout ---'
    cat "$CODEX_STDOUT_FILE"
    printf '%s\n' '--- codex stderr ---'
    cat "$CODEX_STDERR_FILE"
  } >"$LOG_FILE"
  exit 2
fi

{
  printf '%s\n' '--- codex stdout ---'
  cat "$CODEX_STDOUT_FILE"
  printf '%s\n' '--- codex stderr ---'
  cat "$CODEX_STDERR_FILE"
} >"$LOG_FILE"

PARSE_SOURCE="$CODEX_LAST_MESSAGE_FILE"
if [[ ! -s "$PARSE_SOURCE" ]]; then
  PARSE_SOURCE="$CODEX_STDOUT_FILE"
fi

if ! "$PARSER" <"$PARSE_SOURCE"; then
  exit 3
fi
