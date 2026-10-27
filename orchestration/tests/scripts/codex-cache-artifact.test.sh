#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACKAGE_ROOT="$SCRIPT_DIR/../.."
REPO_ROOT="$PACKAGE_ROOT/.."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_ROOT="$TMP_DIR/plugins/cache/claude-codex-orchestration/orchestration/2.0.0"
EXPECTED_SKILLS=(codex-dispatch conductor persistent-plans writing-plans)
VERSION_RE='^2\.0\.0(\+codex\.[a-z0-9]+(-[a-z0-9]+)*)?$'

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

mkdir -p "$(dirname "$CACHE_ROOT")"
jq -e '
  [.plugins[] | select(.name == "orchestration")]
  | length == 1
  and .[0].source == {source:"local", path:"./orchestration/codex-plugin"}
  and .[0].policy == {installation:"AVAILABLE", authentication:"ON_USE"}
' "$REPO_ROOT/.agents/plugins/marketplace.json" >/dev/null \
  || fail 'Codex marketplace source or preserved policy metadata is invalid'
cp -R "$PACKAGE_ROOT/codex-plugin" "$CACHE_ROOT"
CACHE_ROOT=$(cd "$CACHE_ROOT" && pwd -P)

MANIFEST="$CACHE_ROOT/.codex-plugin/plugin.json"
[[ -r "$MANIFEST" ]] || fail 'versioned Codex plugin artifact has no readable manifest'
jq -e --arg version_re "$VERSION_RE" '
  .name == "orchestration"
  and (.version | test($version_re))
  and .skills == "./skills/"
' "$MANIFEST" >/dev/null || fail 'Codex manifest does not use its conventional skills directory'
jq -en --arg version_re "$VERSION_RE" '
  (["2.0.0", "2.0.0+codex.20260712174544", "2.0.0+codex.local-20260712"]
    | all(.[]; test($version_re)))
  and (["2.0.0+codex.BAD", "2.0.0+codex.a.b", "2.0.0+codex.-", "2.0.0+codex.a-"]
    | all(.[]; (test($version_re) | not)))
' >/dev/null || fail 'Codex manifest version contract accepts an invalid cachebuster shape'

ENTRYPOINT_ROOT="$CACHE_ROOT/skills"
actual_skills=()
for skill_dir in "$ENTRYPOINT_ROOT"/*/; do
  [[ -d "$skill_dir" ]] && actual_skills+=("$(basename "$skill_dir")")
done
if [[ "$(printf '%s\n' "${actual_skills[@]}" | sort)" != \
  "$(printf '%s\n' "${EXPECTED_SKILLS[@]}" | sort)" ]]; then
  fail 'versioned cache artifact does not expose exactly four Codex host skills'
fi

for skill in "${EXPECTED_SKILLS[@]}"; do
  entrypoint="$ENTRYPOINT_ROOT/$skill/SKILL.md"
  [[ -r "$entrypoint" ]] || fail "canonical installed body is unreadable: $skill"
  [[ "$(wc -l <"$entrypoint")" -ge 45 ]] \
    || fail "canonical installed body is only a forwarding stub: $skill"
  grep -Fq 'codex plugin list --json' "$entrypoint" \
    || fail "installed body does not resolve the plugin listing: $skill"
  grep -Fq 'source.path' "$entrypoint" \
    || fail "installed body does not select source.path: $skill"
  grep -Fq 'RUNTIME_PACKAGE_ROOT' "$entrypoint" \
    || fail "installed body has no runtime package contract: $skill"
  grep -Fq 'Never infer the runtime package root from this SKILL.md' "$entrypoint" \
    || fail "installed body can infer helpers from the version cache: $skill"
  if grep -Fq '../../../codex-skills' "$entrypoint"; then
    fail "installed body has a dangling codex-skills dependency: $skill"
  fi
done

[[ ! -e "$CACHE_ROOT/codex-skills" ]] \
  || fail 'real Codex cache artifact unexpectedly contains source compatibility entrypoints'

printf 'PASS Codex versioned plugin artifact is self-contained\n'
