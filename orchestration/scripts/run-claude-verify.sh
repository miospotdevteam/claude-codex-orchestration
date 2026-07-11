#!/usr/bin/env bash
set -euo pipefail

# Diff input convention:
# - With --diff-file <path>, stdin is the rendered step block and the diff is read
#   from the provided file.
# - Without --diff-file, stdin contains the step block, an exact ---DIFF--- line,
#   and the diff content.

usage() {
  cat >&2 <<'EOF'
usage: run-claude-verify.sh --plan-id <id> --step-id <id> --root-dir <path> [--skill <name>] [--diff-file <path>]
EOF
}

die_invocation() {
  printf 'run-claude-verify: %s\n' "$1" >&2
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
      PLAN_ID=$2
      shift 2
      ;;
    --step-id)
      (($# >= 2)) || die_invocation "--step-id requires a value"
      STEP_ID=$2
      shift 2
      ;;
    --root-dir)
      (($# >= 2)) || die_invocation "--root-dir requires a value"
      ROOT_DIR=$2
      shift 2
      ;;
    --skill)
      (($# >= 2)) || die_invocation "--skill requires a value"
      SKILL=$2
      shift 2
      ;;
    --diff-file)
      (($# >= 2)) || die_invocation "--diff-file requires a value"
      DIFF_FILE=$2
      shift 2
      ;;
    --help | -h)
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
[[ -n "$STEP_ID" ]] || die_invocation "--step-id is required"
case "$STEP_ID" in */* | *..*) die_invocation "--step-id must be a plain identifier (no / or ..)" ;; esac
[[ -n "$ROOT_DIR" ]] || die_invocation "--root-dir is required"
[[ "$ROOT_DIR" = /* ]] || die_invocation "--root-dir must be an absolute path"
[[ -d "$ROOT_DIR" ]] || die_invocation "--root-dir does not exist or is not a directory: $ROOT_DIR"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PARSER="$SCRIPT_DIR/parse-contract.sh"
[[ -x "$PARSER" ]] || die_invocation "parser is not executable: $PARSER"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

STEP_BLOCK_FILE="$TMP_DIR/step-block.txt"
DIFF_CONTENT_FILE="$TMP_DIR/diff.txt"
BASE_PROMPT_FILE="$TMP_DIR/prompt-base.txt"
RETRY_PROMPT_FILE="$TMP_DIR/prompt-retry.txt"
PARSED_FILE="$TMP_DIR/parsed.json"
PARSE_ERROR_FILE="$TMP_DIR/parse-error.txt"

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
  [[ "$found_diff_sentinel" -eq 1 ]] ||
    die_invocation "stdin must contain a ---DIFF--- sentinel when --diff-file is absent"
fi

# Real plans keep logs beside plan.json. Synthetic/out-of-band ids stay out of
# active/ so a verifier cannot recreate archived-plan debris.
if [[ -f "$ROOT_DIR/.temp/plan-mode/active/$PLAN_ID/plan.json" ]]; then
  LOG_DIR="$ROOT_DIR/.temp/plan-mode/active/$PLAN_ID/logs"
else
  LOG_DIR="$ROOT_DIR/.temp/plan-mode/logs/$PLAN_ID"
fi
LOG_FILE="$LOG_DIR/claude-verify-$STEP_ID.log"
mkdir -p "$LOG_DIR"
if [[ "$LOG_DIR" == "$ROOT_DIR/.temp/plan-mode/active/"* && ! -f "$ROOT_DIR/.temp/plan-mode/active/$PLAN_ID/plan.json" ]]; then
  rmdir "$LOG_DIR" 2>/dev/null || true
  rmdir "$ROOT_DIR/.temp/plan-mode/active/$PLAN_ID" 2>/dev/null || true
  LOG_DIR="$ROOT_DIR/.temp/plan-mode/logs/$PLAN_ID"
  LOG_FILE="$LOG_DIR/claude-verify-$STEP_ID.log"
  mkdir -p "$LOG_DIR"
fi

{
  cat <<'EOF'
You are Claude running in VERIFY mode for the orchestration plugin. You may read files and the provided diff. You may NOT edit files or execute commands. Do not create, modify, delete, move, or format any file. You must finish with the contract block. Your verdict is PASS only if every acceptance criterion is met by the diff.

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

The block must be plain text: no markdown bold, exact field labels, both sentinel lines mandatory, nothing after the closing sentinel.

=== ORCHESTRATION-CONTRACT ===
Summary: <one paragraph, at most 6 sentences, plain prose>
Verdict: PASS | FINDINGS | FAIL
Findings:
- <one-line finding, or omit on PASS>
FilesTouched:
=== END-CONTRACT ===
EOF
} >"$BASE_PROMPT_FILE"

cp "$BASE_PROMPT_FILE" "$RETRY_PROMPT_FILE"
cat >>"$RETRY_PROMPT_FILE" <<'EOF'

STRICT CONTRACT RETRY: Your previous response was not parseable. Return the required plain-text contract block with both exact sentinel lines and field labels. Emit nothing after the closing sentinel.
EOF

run_claude_attempt() {
  local prompt_file=$1
  local stdout_file=$2
  local stderr_file=$3
  local status

  set +e
  (
    cd "$ROOT_DIR"
    env -u CLAUDECODE claude -p \
      --safe-mode \
      --strict-mcp-config \
      --permission-mode dontAsk \
      --no-session-persistence \
      --tools Read,Glob,Grep \
      --disallowedTools Write,Edit,Bash,NotebookEdit \
      <"$prompt_file"
  ) >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  return "$status"
}

append_attempt_log() {
  local attempt=$1
  local stdout_file=$2
  local stderr_file=$3
  {
    printf '%s\n' "--- claude attempt $attempt stdout ---"
    cat "$stdout_file"
    printf '%s\n' "--- claude attempt $attempt stderr ---"
    cat "$stderr_file"
  } >>"$LOG_FILE"
}

: >"$LOG_FILE"
for attempt in 1 2; do
  ATTEMPT_STDOUT_FILE="$TMP_DIR/claude-stdout-$attempt.txt"
  ATTEMPT_STDERR_FILE="$TMP_DIR/claude-stderr-$attempt.txt"
  if [[ "$attempt" -eq 1 ]]; then
    ATTEMPT_PROMPT_FILE="$BASE_PROMPT_FILE"
  else
    ATTEMPT_PROMPT_FILE="$RETRY_PROMPT_FILE"
  fi

  if ! run_claude_attempt "$ATTEMPT_PROMPT_FILE" "$ATTEMPT_STDOUT_FILE" "$ATTEMPT_STDERR_FILE"; then
    append_attempt_log "$attempt" "$ATTEMPT_STDOUT_FILE" "$ATTEMPT_STDERR_FILE"
    exit 2
  fi
  append_attempt_log "$attempt" "$ATTEMPT_STDOUT_FILE" "$ATTEMPT_STDERR_FILE"

  if "$PARSER" <"$ATTEMPT_STDOUT_FILE" >"$PARSED_FILE" 2>"$PARSE_ERROR_FILE"; then
    cat "$PARSED_FILE"
    exit 0
  fi
done

cat "$PARSE_ERROR_FILE" >&2
exit 3
