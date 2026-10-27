#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACKAGE_ROOT="$SCRIPT_DIR/../.."
PLUGIN_ROOT="$PACKAGE_ROOT/codex-plugin"
MANIFEST="$PLUGIN_ROOT/.codex-plugin/plugin.json"
CODEX_SKILLS="$PLUGIN_ROOT/skills"
COMPATIBILITY_SKILLS="$PACKAGE_ROOT/codex-skills"
EXTERNAL_SKILLS="$PACKAGE_ROOT/external-skills"
EXPECTED_CODEX_SKILLS=(codex-dispatch conductor persistent-plans writing-plans)
VERSION_RE='^2\.0\.0(\+codex\.[a-z0-9]+(-[a-z0-9]+)*)?$'

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file=$1 text=$2
  grep -Fq -- "$text" "$file" || fail "$file is missing: $text"
}

[[ -f "$MANIFEST" ]] || fail 'Codex plugin manifest is missing'
jq -e --arg version_re "$VERSION_RE" '
  .name == "orchestration"
  and (.version | test($version_re))
  and .skills == "./skills/"
  and (.description | type == "string" and length > 0)
  and (.author.name == "Miospot Dev Team")
  and (.interface.displayName == "Orchestration")
  and (.interface.capabilities | index("Write") != null)
' "$MANIFEST" >/dev/null || fail 'Codex plugin manifest contract is invalid'
jq -en --arg version_re "$VERSION_RE" '
  (["2.0.0", "2.0.0+codex.20260712174544", "2.0.0+codex.local-20260712"]
    | all(.[]; test($version_re)))
  and (["2.0.0+codex.BAD", "2.0.0+codex.a.b", "2.0.0+codex.-", "2.0.0+codex.a-"]
    | all(.[]; (test($version_re) | not)))
' >/dev/null || fail 'Codex plugin version contract accepts an invalid cachebuster shape'

actual_codex_skills=()
for skill_dir in "$CODEX_SKILLS"/*/; do
  [[ -d "$skill_dir" ]] && actual_codex_skills+=("$(basename "$skill_dir")")
done

for skill in "${EXPECTED_CODEX_SKILLS[@]}"; do
  compatibility="$COMPATIBILITY_SKILLS/$skill/SKILL.md"
  [[ -f "$compatibility" ]] || fail "missing Codex source-compatibility entrypoint: $skill"
  assert_contains "$compatibility" "../../codex-plugin/skills/$skill/SKILL.md"
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
  assert_contains "$skill_file" 'codex plugin list --json'
  assert_contains "$skill_file" 'orchestration@claude-codex-orchestration'
  assert_contains "$skill_file" 'enabled'
  assert_contains "$skill_file" 'source.path'
  assert_contains "$skill_file" 'RUNTIME_PACKAGE_ROOT'
  assert_contains "$skill_file" 'scripts schemas templates config'
  assert_contains "$skill_file" 'Never infer the runtime package root from this SKILL.md'
  assert_contains "$skill_file" 'Never invoke `codex exec`, `grok`, or `claude` directly.'
  if grep -Fq '../../../codex-skills' "$skill_file"; then
    fail "$skill depends on the source compatibility tree"
  fi
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

test_runtime_root_resolution() {
  local tmp_dir bin_dir listing resolver nested_root plugin_source root_source resolved
  tmp_dir="$(mktemp -d)"
  bin_dir="$tmp_dir/bin"
  listing="$tmp_dir/listing.json"
  nested_root="$tmp_dir/package"
  plugin_source="$nested_root/codex-plugin"
  root_source="$tmp_dir/future-root"
  mkdir -p "$bin_dir" "$plugin_source/.codex-plugin" "$root_source/.codex-plugin"
  for directory in scripts schemas templates config; do
    mkdir -p "$nested_root/$directory" "$root_source/$directory"
  done
  nested_root="$(cd "$nested_root" && pwd -P)"
  plugin_source="$nested_root/codex-plugin"
  root_source="$(cd "$root_source" && pwd -P)"
  printf '{"name":"orchestration","skills":"./skills/"}\n' \
    >"$plugin_source/.codex-plugin/plugin.json"
  printf '{"name":"orchestration","skills":"./skills/"}\n' \
    >"$root_source/.codex-plugin/plugin.json"
  printf '%s\n' '#!/usr/bin/env bash' 'cat "$CODEX_LISTING"' >"$bin_dir/codex"
  chmod +x "$bin_dir/codex"
  resolver="$(awk '
    /^resolve_orchestration_runtime_root\(\) \{/ { copying = 1 }
    copying { print }
    copying && /^}$/ { exit }
  ' "$CONDUCTOR")"

  jq -n --arg path "$plugin_source" \
    '{installed:[{pluginId:"orchestration@claude-codex-orchestration",enabled:true,source:{path:$path}}]}' \
    >"$listing"
  resolved="$(PATH="$bin_dir:/usr/bin:/bin" CODEX_LISTING="$listing" \
    bash -c "$resolver; resolve_orchestration_runtime_root")" \
    || fail 'normal nested Codex source did not resolve'
  [[ "$resolved" == "$nested_root" ]] \
    || fail 'normal nested Codex source did not resolve its package parent'

  jq -n --arg path "$root_source" \
    '{plugins:[{id:"orchestration@claude-codex-orchestration",enabled:true,source:{path:$path}}]}' \
    >"$listing"
  resolved="$(PATH="$bin_dir:/usr/bin:/bin" CODEX_LISTING="$listing" \
    bash -c "$resolver; resolve_orchestration_runtime_root")" \
    || fail 'future root Codex source did not resolve'
  [[ "$resolved" == "$root_source" ]] \
    || fail 'future root Codex source did not remain the package root'

  jq -n --arg path "$plugin_source" \
    '{installed:[
      {pluginId:"orchestration@claude-codex-orchestration",enabled:true,source:{path:$path}},
      {pluginId:"orchestration@claude-codex-orchestration",enabled:true,source:{path:$path}}
    ]}' >"$listing"
  if PATH="$bin_dir:/usr/bin:/bin" CODEX_LISTING="$listing" \
    bash -c "$resolver; resolve_orchestration_runtime_root" >/dev/null 2>&1; then
    fail 'ambiguous enabled Codex sources did not fail closed'
  fi

  printf '{"installed":[{"pluginId":"orchestration@claude-codex-orchestration","enabled":true,"source":{"path":"relative"}}]}\n' \
    >"$listing"
  if PATH="$bin_dir:/usr/bin:/bin" CODEX_LISTING="$listing" \
    bash -c "$resolver; resolve_orchestration_runtime_root" >/dev/null 2>&1; then
    fail 'relative Codex source did not fail closed'
  fi

  printf '{"installed":"malformed"}\n' >"$listing"
  if PATH="$bin_dir:/usr/bin:/bin" CODEX_LISTING="$listing" \
    bash -c "$resolver; resolve_orchestration_runtime_root" >/dev/null 2>&1; then
    fail 'malformed Codex listing did not fail closed'
  fi

  rm -rf "$tmp_dir"
}

test_runtime_root_resolution

if rg -n 'Agent\(|model:[[:space:]]*"?(fable|opus|sonnet)|claude[[:space:]]+--yolo' \
  "$CODEX_SKILLS"; then
  fail 'Codex-native skills contain a Claude worker invocation or model fallback'
fi

printf 'PASS codex-native plugin manifest and skill contracts\n'
