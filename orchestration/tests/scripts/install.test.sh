#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SOURCE="$SCRIPT_DIR/../../../install.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
EXTERNAL_SKILLS=(
  engineering-discipline
  test-driven-development
  refactoring
  systematic-debugging
  webapp-testing
  mcp-builder
  react-native-mobile
)

pass() {
  printf 'PASS %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

write_executable() {
  local path="$1"
  shift
  printf '%s\n' "$@" >"$path"
  chmod +x "$path"
}

write_skill() {
  local root="$1" skill="$2" marker="$3"
  mkdir -p "$root/$skill"
  printf '%s\n' "$marker" >"$root/$skill/SKILL.md"
}

setup_case() {
  local case_name="$1"
  CASE_DIR="$TMP_DIR/$case_name"
  TEST_HOME="$CASE_DIR/home"
  STALE_CHECKOUT="$CASE_DIR/stale-checkout"
  CACHE_ONE="$CASE_DIR/cache-one"
  CACHE_TWO="$CASE_DIR/cache-two"
  FAKE_BIN="$CASE_DIR/bin"
  LISTING_FILE="$CASE_DIR/plugin-list.json"
  INSTALL_MARKER="$CASE_DIR/plugin-installed"
  COMMAND_LOG="$CASE_DIR/claude.log"
  GIT_LOG="$CASE_DIR/git.log"
  STDOUT_FILE="$CASE_DIR/stdout"
  STDERR_FILE="$CASE_DIR/stderr"

  mkdir -p "$TEST_HOME" "$STALE_CHECKOUT" "$FAKE_BIN"
  cp "$INSTALL_SOURCE" "$STALE_CHECKOUT/install.sh"
  chmod +x "$STALE_CHECKOUT/install.sh"

  write_executable "$FAKE_BIN/gh" \
    '#!/usr/bin/env bash' \
    'exit 0'
  write_executable "$FAKE_BIN/codex" \
    '#!/usr/bin/env bash' \
    'exit 0'
  write_executable "$FAKE_BIN/grok" \
    '#!/usr/bin/env bash' \
    'exit 0'
  # These variables intentionally expand when the generated mock runs.
  # shellcheck disable=SC2016
  write_executable "$FAKE_BIN/git" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"$GIT_LOG"' \
    'exit 99'
  # These variables intentionally expand when the generated mock runs.
  # shellcheck disable=SC2016
  write_executable "$FAKE_BIN/claude" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "%s\n" "$*" >>"$COMMAND_LOG"' \
    'case "$*" in' \
    '  "plugin list --json")' \
    '    if [[ -f "$INSTALL_MARKER" ]]; then' \
    '      command cat "$LISTING_FILE"' \
    '    else' \
    '      printf "[]\n"' \
    '    fi' \
    '    ;;' \
    '  "plugin marketplace list") printf "  * claude-code-setup\n  * claude-codex-orchestration\n" ;;' \
    '  "plugin marketplace remove claude-code-setup") ;;' \
    '  "plugin marketplace update claude-codex-orchestration") ;;' \
    '  "plugin install orchestration@claude-codex-orchestration") : >"$INSTALL_MARKER" ;;' \
    '  "plugin uninstall orchestration -y") ;;' \
    '  "plugin uninstall look-before-you-leap -y") ;;' \
    '  "plugin list") printf "orchestration enabled\n" ;;' \
    '  *) printf "unexpected claude command: %s\n" "$*" >&2; exit 64 ;;' \
    'esac'
}

populate_artifact() {
  local artifact="$1" marker="$2" skill
  mkdir -p "$artifact/.claude-plugin" "$artifact/skills" "$artifact/codex-skills"
  printf '{"name":"orchestration"}\n' >"$artifact/.claude-plugin/plugin.json"
  for skill in "${EXTERNAL_SKILLS[@]}"; do
    write_skill "$artifact/skills" "$skill" "$marker:$skill:skills"
  done
  write_skill "$artifact/codex-skills" react-native-mobile "$marker:react-native-mobile:codex-skills"
}

populate_stale_checkout() {
  local skill
  mkdir -p "$STALE_CHECKOUT/orchestration/skills" "$STALE_CHECKOUT/orchestration/codex-skills"
  for skill in "${EXTERNAL_SKILLS[@]}"; do
    write_skill "$STALE_CHECKOUT/orchestration/skills" "$skill" "CHECKOUT:$skill:skills"
  done
  write_skill "$STALE_CHECKOUT/orchestration/codex-skills" react-native-mobile \
    'CHECKOUT:react-native-mobile:codex-skills'
  write_skill "$STALE_CHECKOUT/orchestration/skills" checkout-only-managed CHECKOUT
}

run_installer() {
  set +e
  HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:$PATH" \
    LISTING_FILE="$LISTING_FILE" \
    INSTALL_MARKER="$INSTALL_MARKER" \
    COMMAND_LOG="$COMMAND_LOG" \
    GIT_LOG="$GIT_LOG" \
    bash "$STALE_CHECKOUT/install.sh" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  INSTALL_STATUS=$?
  set -e
}

assert_cache_sync() {
  local lane skill expected
  for lane in .codex .grok; do
    for skill in "${EXTERNAL_SKILLS[@]}"; do
      expected="CACHE:$skill:skills"
      if [[ "$skill" == react-native-mobile ]]; then
        expected='CACHE:react-native-mobile:codex-skills'
      fi
      [[ "$(<"$TEST_HOME/$lane/skills/$skill/SKILL.md")" == "$expected" ]] || return 1
    done
  done
  [[ ! -e "$TEST_HOME/.claude/skills/cache-only-managed" ]] || return 1
  [[ ! -e "$TEST_HOME/.codex/skills/cache-only-managed" ]] || return 1
  [[ ! -e "$TEST_HOME/.grok/skills/cache-only-managed" ]] || return 1
  [[ -f "$TEST_HOME/.claude/skills/checkout-only-managed/SKILL.md" ]] || return 1
  [[ -f "$TEST_HOME/.codex/skills/checkout-only-managed/SKILL.md" ]] || return 1
  [[ -f "$TEST_HOME/.grok/skills/checkout-only-managed/SKILL.md" ]] || return 1
  [[ ! -e "$GIT_LOG" ]]
}

seed_discovery_sentinels() {
  local lane
  for lane in .claude .codex .grok; do
    write_skill "$TEST_HOME/$lane/skills" cache-only-managed SENTINEL
    write_skill "$TEST_HOME/$lane/skills" checkout-only-managed PRESERVE
  done
}

test_plugin_id_keyed_cache_is_the_only_source() {
  local name='plugin-id keyed listing syncs only installed cache content'
  setup_case plugin-id-keyed
  populate_artifact "$CACHE_ONE" CACHE
  populate_stale_checkout
  write_skill "$CACHE_ONE/skills" cache-only-managed CACHE
  seed_discovery_sentinels
  jq -n --arg path "$CACHE_ONE" \
    '{version:2, plugins:{"orchestration@claude-codex-orchestration":[{installPath:$path}]}}' \
    >"$LISTING_FILE"

  run_installer
  if [[ "$INSTALL_STATUS" -ne 0 ]]; then
    fail "$name" "expected exit 0, got $INSTALL_STATUS; stderr=$(<"$STDERR_FILE")"
  elif ! assert_cache_sync; then
    fail "$name" 'installed skills did not come exclusively from the cache artifact'
  else
    pass "$name"
  fi
}

test_bare_name_keyed_cache_is_supported() {
  local name='bare-name keyed listing resolves the installed cache'
  setup_case bare-name-keyed
  populate_artifact "$CACHE_ONE" CACHE
  populate_stale_checkout
  jq -n --arg path "$CACHE_ONE" \
    '{plugins:{orchestration:{installPath:$path}}}' >"$LISTING_FILE"

  run_installer
  if [[ "$INSTALL_STATUS" -ne 0 ]]; then
    fail "$name" "expected exit 0, got $INSTALL_STATUS; stderr=$(<"$STDERR_FILE")"
  elif [[ "$(<"$TEST_HOME/.codex/skills/engineering-discipline/SKILL.md")" != \
    'CACHE:engineering-discipline:skills' ]]; then
    fail "$name" 'bare-name map did not select cache content'
  else
    pass "$name"
  fi
}

test_array_id_listing_is_supported() {
  local name='array listing with full plugin id resolves the installed cache'
  setup_case array-id
  populate_artifact "$CACHE_ONE" CACHE
  populate_stale_checkout
  jq -n --arg path "$CACHE_ONE" \
    '[{id:"orchestration@claude-codex-orchestration", installPath:$path}]' \
    >"$LISTING_FILE"
  : >"$INSTALL_MARKER"

  run_installer
  if [[ "$INSTALL_STATUS" -ne 0 ]]; then
    fail "$name" "expected exit 0, got $INSTALL_STATUS; stderr=$(<"$STDERR_FILE")"
  elif [[ "$(<"$TEST_HOME/.codex/skills/engineering-discipline/SKILL.md")" != \
    'CACHE:engineering-discipline:skills' ]]; then
    fail "$name" 'full-id array entry did not select cache content'
  elif ! grep -Fqx 'plugin uninstall orchestration -y' "$COMMAND_LOG"; then
    fail "$name" 'full-id array entry was not detected by the installed-plugin check'
  else
    pass "$name"
  fi
}

assert_sentinels_unchanged() {
  local lane
  for lane in .claude .codex .grok; do
    [[ "$(<"$TEST_HOME/$lane/skills/engineering-discipline/SKILL.md")" == SENTINEL ]] || return 1
  done
  [[ ! -e "$GIT_LOG" ]]
}

seed_cleanup_sentinels() {
  local lane
  for lane in .claude .codex .grok; do
    write_skill "$TEST_HOME/$lane/skills" engineering-discipline SENTINEL
  done
}

test_missing_install_path_fails_before_cleanup() {
  local name='missing installPath fails before destructive cleanup'
  setup_case missing-install-path
  populate_stale_checkout
  seed_cleanup_sentinels
  printf '%s\n' \
    '{"plugins":{"orchestration@claude-codex-orchestration":[{"installPath":""}]}}' \
    >"$LISTING_FILE"

  run_installer
  if [[ "$INSTALL_STATUS" -eq 0 ]]; then
    fail "$name" 'expected a nonzero exit'
  elif ! assert_sentinels_unchanged; then
    fail "$name" 'managed skill content changed before installPath validation failed'
  else
    pass "$name"
  fi
}

test_ambiguous_install_paths_fail_before_cleanup() {
  local name='ambiguous installPaths fail before destructive cleanup'
  setup_case ambiguous-install-paths
  populate_artifact "$CACHE_ONE" CACHE
  populate_artifact "$CACHE_TWO" CACHE_TWO
  populate_stale_checkout
  seed_cleanup_sentinels
  jq -n --arg one "$CACHE_ONE" --arg two "$CACHE_TWO" \
    '{plugins:{"orchestration@claude-codex-orchestration":[{installPath:$one},{installPath:$two}]}}' \
    >"$LISTING_FILE"

  run_installer
  if [[ "$INSTALL_STATUS" -eq 0 ]]; then
    fail "$name" 'expected a nonzero exit'
  elif ! assert_sentinels_unchanged; then
    fail "$name" 'managed skill content changed before ambiguity validation failed'
  else
    pass "$name"
  fi
}

test_legacy_claude_marketplace_is_removed() {
  local name='legacy Claude marketplace is removed before orchestration install'
  setup_case legacy-marketplace
  populate_artifact "$CACHE_ONE" CACHE
  populate_stale_checkout
  jq -n --arg path "$CACHE_ONE" \
    '{plugins:{orchestration:{installPath:$path}}}' >"$LISTING_FILE"

  run_installer
  if [[ "$INSTALL_STATUS" -ne 0 ]]; then
    fail "$name" "expected exit 0, got $INSTALL_STATUS; stderr=$(<"$STDERR_FILE")"
  elif ! grep -Fqx 'plugin marketplace remove claude-code-setup' "$COMMAND_LOG"; then
    fail "$name" 'installer did not remove the legacy Claude marketplace'
  else
    pass "$name"
  fi
}

test_legacy_claude_plugin_is_uninstalled() {
  local name='legacy Claude plugin is uninstalled before marketplace removal'
  setup_case legacy-plugin
  populate_artifact "$CACHE_ONE" CACHE
  populate_stale_checkout
  jq -n --arg path "$CACHE_ONE" \
    '{plugins:{
      orchestration:{installPath:$path},
      "look-before-you-leap":{installPath:"/tmp/legacy-plugin"}
    }}' >"$LISTING_FILE"
  : >"$INSTALL_MARKER"

  run_installer
  if [[ "$INSTALL_STATUS" -ne 0 ]]; then
    fail "$name" "expected exit 0, got $INSTALL_STATUS; stderr=$(<"$STDERR_FILE")"
  elif ! grep -Fqx 'plugin uninstall look-before-you-leap -y' "$COMMAND_LOG"; then
    fail "$name" 'installer did not uninstall the legacy Claude plugin'
  else
    pass "$name"
  fi
}

test_plugin_id_keyed_cache_is_the_only_source
test_bare_name_keyed_cache_is_supported
test_array_id_listing_is_supported
test_missing_install_path_fails_before_cleanup
test_ambiguous_install_paths_fail_before_cleanup
test_legacy_claude_marketplace_is_removed
test_legacy_claude_plugin_is_uninstalled

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
