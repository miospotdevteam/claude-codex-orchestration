#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_SOURCE="$SCRIPT_DIR/../../../install.sh"
REAL_JQ="$(command -v jq)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
PORTABLE_SKILLS=(
  engineering-discipline
  test-driven-development
  refactoring
  systematic-debugging
  brainstorming
  doc-coauthoring
  frontend-design
  svg-art
  immersive-frontend
  mcp-builder
  react-native-mobile
  webapp-testing
  skill-review-standard
)
HOST_ONLY_SKILLS=(
  conductor
  writing-plans
  codex-dispatch
  persistent-plans
)

pass() { printf 'PASS %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

write_executable() {
  local path=$1
  shift
  printf '%s\n' "$@" >"$path"
  chmod +x "$path"
}

setup_case() {
  local name=$1
  CASE_DIR="$TMP_DIR/$name"
  HOME_DIR="$CASE_DIR/home"
  BIN_DIR="$CASE_DIR/bin"
  CODEX_LOG="$CASE_DIR/codex.log"
  CLAUDE_LOG="$CASE_DIR/claude.log"
  CODEX_LISTING="$CASE_DIR/codex-list.json"
  CODEX_INSTALL_MARKER="$CASE_DIR/codex-installed"
  CODEX_ARTIFACT="$CASE_DIR/codex-artifact"
  CODEX_PLUGIN_SOURCE="$CODEX_ARTIFACT/codex-plugin"
  STDOUT_FILE="$CASE_DIR/stdout"
  STDERR_FILE="$CASE_DIR/stderr"
  mkdir -p "$HOME_DIR" "$BIN_DIR" \
    "$CODEX_PLUGIN_SOURCE/.codex-plugin" \
    "$CODEX_ARTIFACT/scripts" \
    "$CODEX_ARTIFACT/skills" \
    "$CODEX_ARTIFACT/codex-skills" \
    "$CODEX_ARTIFACT/external-skills"
  printf '{"name":"orchestration"}\n' >"$CODEX_PLUGIN_SOURCE/.codex-plugin/plugin.json"
  local skill
  for skill in "${PORTABLE_SKILLS[@]}"; do
    mkdir -p "$CODEX_ARTIFACT/skills/$skill"
    printf 'skills:%s\n' "$skill" >"$CODEX_ARTIFACT/skills/$skill/SKILL.md"
  done
  mkdir -p "$CODEX_ARTIFACT/codex-skills/react-native-mobile" \
    "$CODEX_ARTIFACT/external-skills/frontend-design"
  for skill in "${HOST_ONLY_SKILLS[@]}"; do
    mkdir -p "$CODEX_ARTIFACT/codex-skills/$skill"
    printf 'host-only:%s\n' "$skill" \
      >"$CODEX_ARTIFACT/codex-skills/$skill/SKILL.md"
  done
  printf 'codex:react-native-mobile\n' \
    >"$CODEX_ARTIFACT/codex-skills/react-native-mobile/SKILL.md"
  printf 'external:frontend-design\n' \
    >"$CODEX_ARTIFACT/external-skills/frontend-design/SKILL.md"
  jq -n --arg path "$CODEX_PLUGIN_SOURCE" \
    '{installed:[{pluginId:"orchestration@claude-codex-orchestration",name:"orchestration",source:{path:$path}}]}' \
    >"$CODEX_LISTING"
  ln -s "$REAL_JQ" "$BIN_DIR/jq"

  write_executable "$BIN_DIR/gh" '#!/usr/bin/env bash' 'exit 0'
  write_executable "$BIN_DIR/grok" '#!/usr/bin/env bash' 'exit 0'
  # Variables expand in the generated mocks, not while this test writes them.
  # shellcheck disable=SC2016
  write_executable "$BIN_DIR/codex" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "%s\n" "$*" >>"$CODEX_LOG"' \
    'case "$*" in' \
    '  "plugin marketplace list --json") printf "{\"marketplaces\":[]}\n" ;;' \
    '  "plugin marketplace add miospotdevteam/claude-codex-orchestration --json") printf "{\"name\":\"claude-codex-orchestration\"}\n" ;;' \
    '  "plugin add orchestration@claude-codex-orchestration --json") : >"$CODEX_INSTALL_MARKER"; printf "{\"pluginId\":\"orchestration@claude-codex-orchestration\"}\n" ;;' \
    '  "plugin list --json") command cat "$CODEX_LISTING" ;;' \
    '  *) printf "unexpected codex command: %s\n" "$*" >&2; exit 64 ;;' \
    'esac'
  # Any Claude invocation is a test failure in the Codex-only cases.
  # shellcheck disable=SC2016
  write_executable "$BIN_DIR/claude" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"$CLAUDE_LOG"' \
    'exit 97'
}

run_installer() {
  set +e
  HOME="$HOME_DIR" \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    CODEX_LOG="$CODEX_LOG" \
    CLAUDE_LOG="$CLAUDE_LOG" \
    CODEX_LISTING="$CODEX_LISTING" \
    CODEX_INSTALL_MARKER="$CODEX_INSTALL_MARKER" \
    bash "$INSTALL_SOURCE" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  STATUS=$?
  set -e
}

assert_portable_skills_synced() {
  local lane skill expected
  for lane in .codex .grok; do
    for skill in "${PORTABLE_SKILLS[@]}"; do
      expected="skills:$skill"
      [[ "$skill" == react-native-mobile ]] && expected='codex:react-native-mobile'
      [[ "$skill" == frontend-design ]] && expected='external:frontend-design'
      [[ "$(<"$HOME_DIR/$lane/skills/$skill/SKILL.md")" == "$expected" ]] \
        || return 1
    done
    for skill in "${HOST_ONLY_SKILLS[@]}"; do
      [[ ! -e "$HOME_DIR/$lane/skills/$skill" ]] || return 1
    done
    [[ "$(<"$HOME_DIR/$lane/skills/user-owned/SKILL.md")" == USER ]] || return 1
  done
}

seed_lane_skills() {
  local lane skill
  for lane in .codex .grok; do
    for skill in "${HOST_ONLY_SKILLS[@]}"; do
      mkdir -p "$HOME_DIR/$lane/skills/$skill"
      printf 'STALE\n' >"$HOME_DIR/$lane/skills/$skill/SKILL.md"
    done
    mkdir -p "$HOME_DIR/$lane/skills/user-owned"
    printf 'USER\n' >"$HOME_DIR/$lane/skills/user-owned/SKILL.md"
  done
}

assert_codex_install_commands() {
  grep -Fqx 'plugin marketplace list --json' "$CODEX_LOG" \
    && grep -Fqx 'plugin marketplace add miospotdevteam/claude-codex-orchestration --json' "$CODEX_LOG" \
    && grep -Fqx 'plugin add orchestration@claude-codex-orchestration --json' "$CODEX_LOG"
}

test_codex_host_never_runs_claude() {
  local name='--host codex installs through Codex without running Claude'
  setup_case codex-host
  seed_lane_skills
  run_installer --host codex

  if [[ $STATUS -ne 0 ]]; then
    fail "$name" "expected exit 0, got $STATUS; stderr=$(<"$STDERR_FILE")"
  elif [[ -e $CLAUDE_LOG ]]; then
    fail "$name" "Claude was invoked: $(<"$CLAUDE_LOG")"
  elif ! assert_codex_install_commands; then
    fail "$name" "missing Codex install command; log=$(<"$CODEX_LOG")"
  elif ! assert_portable_skills_synced; then
    fail "$name" 'portable skills were not synced from the installed Codex artifact'
  else
    pass "$name"
  fi
}

test_default_host_is_codex() {
  local name='default install host is the no-Claude Codex lane'
  setup_case default-host
  seed_lane_skills
  run_installer

  if [[ $STATUS -ne 0 ]]; then
    fail "$name" "expected exit 0, got $STATUS; stderr=$(<"$STDERR_FILE")"
  elif [[ -e $CLAUDE_LOG ]]; then
    fail "$name" "default path invoked Claude: $(<"$CLAUDE_LOG")"
  elif ! assert_codex_install_commands; then
    fail "$name" 'default path did not install the Codex plugin'
  elif ! assert_portable_skills_synced; then
    fail "$name" 'default path did not sync both external lanes'
  else
    pass "$name"
  fi
}

test_missing_source_path_fails_before_cleanup() {
  local name='Codex source.path must resolve before external skill cleanup'
  setup_case missing-source-path
  seed_lane_skills
  printf '{"installed":[]}\n' >"$CODEX_LISTING"
  run_installer --host codex

  if [[ $STATUS -eq 0 ]]; then
    fail "$name" 'expected nonzero exit'
  elif [[ "$(<"$HOME_DIR/.codex/skills/conductor/SKILL.md")" != STALE \
    || "$(<"$HOME_DIR/.grok/skills/conductor/SKILL.md")" != STALE ]]; then
    fail "$name" 'cleanup ran before source.path validation failed'
  else
    pass "$name"
  fi
}

test_missing_portable_skill_fails_before_cleanup() {
  local name='all portable sources validate before external skill cleanup'
  setup_case missing-portable-skill
  seed_lane_skills
  rm -rf "$CODEX_ARTIFACT/skills/svg-art"
  run_installer --host codex

  if [[ $STATUS -eq 0 ]]; then
    fail "$name" 'expected nonzero exit'
  elif [[ "$(<"$HOME_DIR/.codex/skills/conductor/SKILL.md")" != STALE \
    || "$(<"$HOME_DIR/.grok/skills/conductor/SKILL.md")" != STALE ]]; then
    fail "$name" 'cleanup ran before portable-source validation failed'
  else
    pass "$name"
  fi
}

test_invalid_host_fails_before_provider_calls() {
  local name='invalid host fails before invoking any provider CLI'
  setup_case invalid-host
  run_installer --host nope

  if [[ $STATUS -eq 0 ]]; then
    fail "$name" 'expected nonzero exit'
  elif [[ -e $CODEX_LOG || -e $CLAUDE_LOG ]]; then
    fail "$name" 'provider CLI was invoked before host validation'
  else
    pass "$name"
  fi
}

test_codex_host_never_runs_claude
test_default_host_is_codex
test_missing_source_path_fails_before_cleanup
test_missing_portable_skill_fails_before_cleanup
test_invalid_host_fails_before_provider_calls

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
