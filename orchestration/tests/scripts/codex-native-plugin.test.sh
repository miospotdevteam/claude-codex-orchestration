#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACKAGE_ROOT="$SCRIPT_DIR/../.."
PLUGIN_ROOT="$PACKAGE_ROOT/codex-plugin"
MANIFEST="$PLUGIN_ROOT/.codex-plugin/plugin.json"
ENTRYPOINT_SKILLS="$PLUGIN_ROOT/skills"
CODEX_SKILLS="$PACKAGE_ROOT/codex-skills"
EXTERNAL_SKILLS="$PACKAGE_ROOT/external-skills"
EXPECTED_CODEX_SKILLS=(codex-dispatch conductor persistent-plans writing-plans)

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file=$1 text=$2
  grep -Fq -- "$text" "$file" || fail "$file is missing: $text"
}

[[ -f "$MANIFEST" ]] || fail 'Codex plugin manifest is missing'
jq -e '
  .name == "orchestration"
  and .version == "2.0.0"
  and .skills == "./skills/"
  and (.description | type == "string" and length > 0)
  and (.author.name == "Miospot Dev Team")
  and (.interface.displayName == "Orchestration")
  and (.interface.capabilities | index("Write") != null)
' "$MANIFEST" >/dev/null || fail 'Codex plugin manifest contract is invalid'

actual_codex_skills=()
for skill_dir in "$CODEX_SKILLS"/*/; do
  [[ -d "$skill_dir" ]] && actual_codex_skills+=("$(basename "$skill_dir")")
done

actual_entrypoints=()
for skill_dir in "$ENTRYPOINT_SKILLS"/*/; do
  [[ -d "$skill_dir" ]] && actual_entrypoints+=("$(basename "$skill_dir")")
done

if [[ "$(printf '%s\n' "${actual_entrypoints[@]}" | sort)" != \
  "$(printf '%s\n' "${EXPECTED_CODEX_SKILLS[@]}" | sort)" ]]; then
  fail "Codex plugin entrypoints are not exactly: ${EXPECTED_CODEX_SKILLS[*]}"
fi

for skill in "${EXPECTED_CODEX_SKILLS[@]}"; do
  entrypoint="$ENTRYPOINT_SKILLS/$skill/SKILL.md"
  [[ -f "$entrypoint" ]] || fail "missing Codex plugin entrypoint: $skill"
  assert_contains "$entrypoint" "../../../codex-skills/$skill/SKILL.md"
done

# Codex rejects skill metadata descriptions longer than 1024 characters.
# The portable catalog uses single-line quoted descriptions for the visual
# skills, so enforce that install-time boundary without requiring PyYAML.
for skill in frontend-design immersive-frontend svg-art; do
  skill_file="$EXTERNAL_SKILLS/$skill/SKILL.md"
  description=$(sed -n 's/^description: //p' "$skill_file" | head -n 1)
  [[ -n "$description" ]] || fail "$skill is missing its description"
  [[ ${#description} -le 1024 ]] \
    || fail "$skill description exceeds Codex's 1024-character limit"
done

if [[ "$(printf '%s\n' "${actual_codex_skills[@]}" | sort)" != \
  "$(printf '%s\n' "${EXPECTED_CODEX_SKILLS[@]}" | sort)" ]]; then
  fail "Codex host skill inventory is not exactly: ${EXPECTED_CODEX_SKILLS[*]}"
fi

for skill in "${EXPECTED_CODEX_SKILLS[@]}"; do
  skill_file="$CODEX_SKILLS/$skill/SKILL.md"
  [[ -f "$skill_file" ]] || fail "missing Codex-native skill: $skill"
  [[ "$(sed -n '1p' "$skill_file")" == '---' ]] \
    || fail "$skill does not start with frontmatter"
  assert_contains "$skill_file" "name: $skill"
done

PERSISTENT_PLANS="$CODEX_SKILLS/persistent-plans/SKILL.md"
assert_contains "$PERSISTENT_PLANS" 'plan.json'
assert_contains "$PERSISTENT_PLANS" 'progress.json'
assert_contains "$PERSISTENT_PLANS" 'scripts/plan-utils.sh'
assert_contains "$PERSISTENT_PLANS" 'compute-frontier'
assert_contains "$PERSISTENT_PLANS" 'archive-plan'
assert_contains "$PERSISTENT_PLANS" 'claude_workers=deny'

CONDUCTOR="$CODEX_SKILLS/conductor/SKILL.md"
assert_contains "$CONDUCTOR" 'gpt-5.6-sol'
assert_contains "$CONDUCTOR" 'xhigh'
assert_contains "$CONDUCTOR" 'claude_workers=deny'
assert_contains "$CONDUCTOR" 'orchestration-policy.sh get'
assert_contains "$CONDUCTOR" 'fail closed'
assert_contains "$CONDUCTOR" 'no Claude fallback'
assert_contains "$CONDUCTOR" 'grok-4.5'
assert_contains "$CONDUCTOR" 'independent planner, reviewer, and verifier'
assert_contains "$CONDUCTOR" 'plan.json'
assert_contains "$CONDUCTOR" 'progress.json'

WRITING_PLANS="$CODEX_SKILLS/writing-plans/SKILL.md"
assert_contains "$WRITING_PLANS" 'schemas/plan.schema.json'
assert_contains "$WRITING_PLANS" 'templates/masterPlan.template.md'
assert_contains "$WRITING_PLANS" 'scripts/plan-utils.sh init-progress'
assert_contains "$WRITING_PLANS" 'claude-impl'
assert_contains "$WRITING_PLANS" 'must not be approved'

DISPATCH="$CODEX_SKILLS/codex-dispatch/SKILL.md"
assert_contains "$DISPATCH" 'scripts/run-codex-impl.sh'
assert_contains "$DISPATCH" 'scripts/run-codex-verify.sh'
assert_contains "$DISPATCH" 'scripts/run-grok-impl.sh'
assert_contains "$DISPATCH" 'scripts/run-grok-verify.sh'
assert_contains "$DISPATCH" 'scripts/parse-contract.sh'
assert_contains "$DISPATCH" 'scripts/plan-utils.sh'
assert_contains "$DISPATCH" 'Never invoke `codex exec`, `grok`, or `claude` directly.'
assert_contains "$DISPATCH" 'Grok 4.5 is unavailable'
assert_contains "$DISPATCH" 'blocked'

if rg -n 'Agent\(|model:[[:space:]]*"?(fable|opus|sonnet)|claude[[:space:]]+--yolo' \
  "$CODEX_SKILLS"; then
  fail 'Codex-native skills contain a Claude worker invocation or model fallback'
fi

printf 'PASS codex-native plugin manifest and skill contracts\n'
