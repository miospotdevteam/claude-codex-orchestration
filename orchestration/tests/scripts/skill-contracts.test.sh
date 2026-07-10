#!/usr/bin/env bash
set -euo pipefail

# Guards the self-containment and vocabulary contracts of the shipped
# skills. Every check greps the real SKILL.md bodies under skills/ and
# fails if a runtime-dangling or stale construct reappears. Companion to
# validate-structure.test.sh (which checks one skill's structure); this
# suite checks cross-cutting invariants over ALL shipped skills.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS_DIR="$SCRIPT_DIR/../../skills"
CODEX_SKILLS_DIR="$SCRIPT_DIR/../../codex-skills"

# Shipped skill bodies we audit (one SKILL.md per skill directory,
# both the Claude-side skills/ and the external codex-skills/ lane).
SKILL_FILES=()
for f in "$SKILLS_DIR"/*/SKILL.md "$CODEX_SKILLS_DIR"/*/SKILL.md; do
  [[ -f "$f" ]] && SKILL_FILES+=("$f")
done

# Valid skill-route targets: every shipped skill (skills/ + codex-skills/)
# plus the harness built-in sub-agents the orchestrator dispatches.
VALID_SKILLS=(Explore general-purpose Plan)
for d in "$SKILLS_DIR"/*/; do VALID_SKILLS+=("$(basename "$d")"); done
if [[ -d "$CODEX_SKILLS_DIR" ]]; then
  for d in "$CODEX_SKILLS_DIR"/*/; do VALID_SKILLS+=("$(basename "$d")"); done
fi

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf 'PASS %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL %s:\n%s\n' "$1" "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

is_valid_skill() {
  local needle="$1" v
  for v in "${VALID_SKILLS[@]}"; do
    [[ "$v" == "$needle" ]] && return 0
  done
  return 1
}

# grep_files PATTERN [extra grep flags...] — run egrep over the skill
# bodies without tripping `set -e` when there are no matches.
grep_files() {
  local pattern="$1"; shift
  grep -HnE "$@" "$pattern" "${SKILL_FILES[@]}" 2>/dev/null || true
}

# (a) No runtime-dangling docs/NN-*.md citations. The spec docs are not
#     shipped inside the plugin, so any `docs/04-execution-loop.md`-style
#     path in skill prose dangles at runtime.
test_no_dangling_doc_citations() {
  local name="no dangling docs/NN-*.md citations in skill prose"
  local hits
  hits="$(grep_files 'docs/[0-9]{2}-[A-Za-z0-9-]+\.md')"
  if [[ -n "$hits" ]]; then
    fail "$name" "$hits"
  else
    pass "$name"
  fi
}

# (b) Every executable plugin script call (scripts/<name>.sh) is
#     ${CLAUDE_PLUGIN_ROOT}-prefixed so it resolves at the installed
#     location. Bare `scripts/plan-utils.sh` would break the dispatch
#     lane. (Skill-local helpers under skills/<skill>/scripts/ carry
#     their own ${CLAUDE_PLUGIN_ROOT}/skills/... base and are not this
#     check's concern — it targets the top-level executable wrappers.)
test_scripts_are_plugin_root_prefixed() {
  local name="scripts/*.sh calls are \${CLAUDE_PLUGIN_ROOT}-prefixed"
  local hits
  hits="$(grep_files 'scripts/[A-Za-z0-9._-]+\.sh' | grep -v 'CLAUDE_PLUGIN_ROOT' || true)"
  if [[ -n "$hits" ]]; then
    fail "$name" "$hits"
  else
    pass "$name"
  fi
}

# (c) Plan-step routing vocab stays on the owner enum. No owner value
#     outside {codex-impl, claude-impl, grok-impl, manual}, and no
#     `mode:` plan field (the pre-enum vocabulary).
test_owner_vocab_is_enum() {
  local name="plan-step owner/mode vocab stays on the enum"
  local viol="" bad_owner bad_mode
  bad_owner="$(grep -HnoE 'owner:[[:space:]]*"?[a-z][a-z-]*"?' "${SKILL_FILES[@]}" 2>/dev/null \
    | grep -vE 'owner:[[:space:]]*"?(codex-impl|claude-impl|grok-impl|manual)"?' || true)"
  [[ -n "$bad_owner" ]] && viol+="$bad_owner"$'\n'
  # `mode:` used as a plan field: a JSON "mode" key, or `mode:` valued
  # with an executor name. Prose like "dark mode" / "Integration mode:"
  # is deliberately not matched.
  bad_mode="$(grep_files '"mode"[[:space:]]*:|(^|[^A-Za-z-])mode:[[:space:]]*(codex|claude|grok|manual)')"
  [[ -n "$bad_mode" ]] && viol+="$bad_mode"$'\n'
  if [[ -n "$viol" ]]; then
    fail "$name" "$viol"
  else
    pass "$name"
  fi
}

# (d) Skill routes resolve to a skill that exists on disk. Detects the
#     `X` skill / `X` sub-agent route form and plugin-namespaced
#     `ns:name` tokens, plus an explicit denylist of skills this plugin
#     removed (skill-creator, plugin-dev:skill-development).
test_skill_routes_resolve() {
  local name="skill routes resolve to shipped skills"
  local viol="" tok base tokens nstokens deny

  tokens="$(grep -rhoE '`[A-Za-z][A-Za-z0-9-]*` (skill|sub-agent)' "${SKILL_FILES[@]}" 2>/dev/null \
    | grep -oE '`[A-Za-z][A-Za-z0-9-]*`' | tr -d '`' | sort -u || true)"
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    is_valid_skill "$tok" || viol+="unknown skill route: \`$tok\` (\`$tok\` skill/sub-agent)"$'\n'
  done <<< "$tokens"

  nstokens="$(grep -rhoE '`[a-z][a-z0-9-]*:[a-z0-9-]+`' "${SKILL_FILES[@]}" 2>/dev/null \
    | tr -d '`' | sort -u || true)"
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    base="${tok##*:}"
    is_valid_skill "$base" || viol+="unknown namespaced skill route: \`$tok\`"$'\n'
  done <<< "$nstokens"

  deny="$(grep_files 'skill-creator|plugin-dev:skill-development|\bskill-development\b')"
  [[ -n "$deny" ]] && viol+="$deny"$'\n'

  if [[ -n "$viol" ]]; then
    fail "$name" "$viol"
  else
    pass "$name"
  fi
}

# (e) No stale verdict-policy phrases. The current policy is "always fix
#     findings and re-verify"; the old vocabulary ("mark done with
#     findings", "surface and ask" on FAIL, "Do not auto-retry") must
#     not reappear as policy. A line that *prohibits* the phrase (do not
#     / never / don't) is allowlisted.
test_no_stale_verdict_phrases() {
  local name="no stale verdict-policy phrases"
  local viol="" mdf saa ret
  # "mark done with findings" is legal only inside a prohibition.
  mdf="$(grep_files 'mark(s)? (the step |it )?done with findings|mark done with findings' -i \
    | grep -viE "do not|don't|never|not " || true)"
  [[ -n "$mdf" ]] && viol+="$mdf"$'\n'
  saa="$(grep_files 'surface and ask' -i)"
  [[ -n "$saa" ]] && viol+="$saa"$'\n'
  ret="$(grep_files 'auto-retry' -i)"
  [[ -n "$ret" ]] && viol+="$ret"$'\n'
  if [[ -n "$viol" ]]; then
    fail "$name" "$viol"
  else
    pass "$name"
  fi
}

test_no_dangling_doc_citations
test_scripts_are_plugin_root_prefixed
test_owner_vocab_is_enum
test_skill_routes_resolve
test_no_stale_verdict_phrases

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
