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
EXTERNAL_SKILLS_DIR="$SCRIPT_DIR/../../external-skills"
REMOTE_AGENT_HOST_SKILL="$SKILLS_DIR/remote-agent-host/SKILL.md"
CONDUCTOR_SKILL="$SKILLS_DIR/conductor/SKILL.md"

# Shipped skill bodies we audit (one SKILL.md per skill directory,
# the Claude-side skills/, Codex host skills, and provider-portable lane).
SKILL_FILES=()
for f in "$SKILLS_DIR"/*/SKILL.md "$CODEX_SKILLS_DIR"/*/SKILL.md \
  "$EXTERNAL_SKILLS_DIR"/*/SKILL.md; do
  [[ -f "$f" ]] && SKILL_FILES+=("$f")
done

# Valid skill-route targets: every shipped skill (skills/ + codex-skills/)
# plus the harness built-in sub-agents the orchestrator dispatches.
VALID_SKILLS=(Explore general-purpose Plan)
for d in "$SKILLS_DIR"/*/; do VALID_SKILLS+=("$(basename "$d")"); done
if [[ -d "$CODEX_SKILLS_DIR" ]]; then
  for d in "$CODEX_SKILLS_DIR"/*/; do VALID_SKILLS+=("$(basename "$d")"); done
fi
if [[ -d "$EXTERNAL_SKILLS_DIR" ]]; then
  for d in "$EXTERNAL_SKILLS_DIR"/*/; do VALID_SKILLS+=("$(basename "$d")"); done
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
  local name="scripts/*.sh calls resolve from a plugin or selected-skill root"
  local hits
  hits="$(grep_files 'scripts/[A-Za-z0-9._-]+\.sh' \
    | grep -vE 'CLAUDE_PLUGIN_ROOT|PLUGIN_ROOT|SKILL_ROOT' || true)"
  if [[ -n "$hits" ]]; then
    fail "$name" "$hits"
  else
    pass "$name"
  fi
}

# (g) Provider packaging is intentionally asymmetric: four orchestration
#     skills belong only to the Codex host, while thirteen task skills can be
#     copied into either Codex or Grok's user skill directory. remote-agent-host
#     remains Claude-only and must never leak into either external surface.
test_host_and_external_skill_inventories() {
  local name="host and external skill inventories are exact"
  local expected_host expected_external actual_host actual_external
  expected_host="$(printf '%s\n' codex-dispatch conductor persistent-plans writing-plans | sort)"
  expected_external="$(printf '%s\n' \
    brainstorming doc-coauthoring engineering-discipline frontend-design \
    immersive-frontend mcp-builder react-native-mobile refactoring \
    skill-review-standard svg-art systematic-debugging \
    test-driven-development webapp-testing | sort)"
  actual_host="$(find "$CODEX_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d \
    -exec basename {} \; | sort)"
  if [[ -d "$EXTERNAL_SKILLS_DIR" ]]; then
    actual_external="$(find "$EXTERNAL_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d \
      -exec basename {} \; | sort)"
  else
    actual_external=""
  fi

  if [[ "$actual_host" != "$expected_host" ]]; then
    fail "$name" "Codex host inventory mismatch:\n$actual_host"
  elif [[ "$actual_external" != "$expected_external" ]]; then
    fail "$name" "external inventory mismatch:\n$actual_external"
  elif find "$EXTERNAL_SKILLS_DIR" -mindepth 2 -maxdepth 2 -type d \
    \( -name conductor -o -name persistent-plans -o -name writing-plans \
       -o -name codex-dispatch -o -name remote-agent-host \) 2>/dev/null | grep -q .; then
    fail "$name" "host-only skill leaked into external packaging"
  else
    pass "$name"
  fi
}

test_external_skills_are_self_contained() {
  local name="external skills include their complete portable packages"
  local viol="" skill

  for skill in brainstorming doc-coauthoring engineering-discipline \
    frontend-design immersive-frontend mcp-builder refactoring \
    skill-review-standard svg-art systematic-debugging \
    test-driven-development webapp-testing; do
    [[ -f "$EXTERNAL_SKILLS_DIR/$skill/SKILL.md" ]] \
      || { viol+="missing $skill/SKILL.md"$'\n'; continue; }
    bash "$SKILLS_DIR/skill-review-standard/scripts/validate-structure.sh" \
      "$EXTERNAL_SKILLS_DIR/$skill" >/dev/null 2>&1 \
      || viol+="$skill external package fails structural validation"$'\n'
    case "$skill" in
      immersive-frontend|mcp-builder|refactoring|skill-review-standard|svg-art|systematic-debugging|webapp-testing)
        # External copies remove plugin-only cross-skill references while
        # retaining their provider-neutral implementation guidance.
        ;;
      *)
        diff -q "$SKILLS_DIR/$skill/SKILL.md" \
          "$EXTERNAL_SKILLS_DIR/$skill/SKILL.md" >/dev/null \
          || viol+="$skill external body drifted from shared body"$'\n'
        ;;
    esac
  done

  [[ -f "$EXTERNAL_SKILLS_DIR/react-native-mobile/SKILL.md" ]] \
    || viol+="missing react-native-mobile external override"$'\n'

  if [[ -n "$viol" ]]; then
    fail "$name" "$viol"
  else
    pass "$name"
  fi
}

test_external_bodies_are_host_neutral() {
  local name="portable bodies avoid unconditional Claude APIs and routing"
  local files hits=""
  files=(
    "$EXTERNAL_SKILLS_DIR/brainstorming/SKILL.md"
    "$EXTERNAL_SKILLS_DIR/doc-coauthoring/SKILL.md"
    "$EXTERNAL_SKILLS_DIR/frontend-design/SKILL.md"
    "$EXTERNAL_SKILLS_DIR/skill-review-standard/SKILL.md"
  )

  hits="$(grep -HnE 'AskUserQuestion|Agent\(|Claude Code sub-agent|baseline Claude|\$\{CLAUDE_PLUGIN_ROOT\}' \
    "${files[@]}" 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    fail "$name" "$hits"
  elif grep -RInF '${CLAUDE_PLUGIN_ROOT}' "$EXTERNAL_SKILLS_DIR" >/dev/null 2>&1; then
    fail "$name" "external package contains a Claude-plugin-root dependency"
  elif grep -RInE '^allowed-tools:.*(Agent|AskUserQuestion)' \
    "$EXTERNAL_SKILLS_DIR" >/dev/null 2>&1; then
    fail "$name" "external package declares a Claude-only tool"
  elif grep -nEi 'route .* to Claude|to Claude instead|owner:[[:space:]]*"?claude-impl' \
    "$EXTERNAL_SKILLS_DIR/react-native-mobile/SKILL.md" >/dev/null 2>&1; then
    fail "$name" "react-native-mobile contains an unconditional Claude route"
  elif grep -RInE '\["claude"|claude[[:space:]]+-p' \
    "$EXTERNAL_SKILLS_DIR/skill-review-standard" >/dev/null 2>&1; then
    fail "$name" "skill-review-standard contains a provider-locked helper"
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

  # Markdown backticks are intentional literal regex characters.
  # shellcheck disable=SC2016
  tokens="$(grep -rhoE '`[A-Za-z][A-Za-z0-9-]*` (skill|sub-agent)' "${SKILL_FILES[@]}" 2>/dev/null \
    | grep -oE '`[A-Za-z][A-Za-z0-9-]*`' | tr -d '`' | sort -u || true)"
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    is_valid_skill "$tok" || viol+="unknown skill route: \`$tok\` (\`$tok\` skill/sub-agent)"$'\n'
  done <<< "$tokens"

  # shellcheck disable=SC2016
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

# (f) The remote agent host publishes the complete natural-language Mini
#     intent surface and the safety rules that keep the local checkout from
#     racing a remote writer. Keep these as prose contracts: the conductor
#     routes user intent to this skill, while the skill owns the mechanics.
test_remote_agent_host_contract() {
  local name="remote-agent-host declares Mini intents and safety invariants"
  local viol="" requirement label pattern
  local requirements=(
    'start Mini intent|(start|launch).*Mini|Mini.*(start|launch)'
    'continue Mini intent|(continue|resume).*Mini|Mini.*(continue|resume)'
    'inspect-for-input Mini intent|(inspect|check).*(input|waiting|needs)|((input|waiting|needs).*(inspect|check))'
    'control Mini intent|(control|steer|send|tell).*Mini|Mini.*(control|steer|send|tell)'
    'reclaim Mini intent|(reclaim|take over).*Mini|Mini.*(reclaim|take over)'
    'capture before prompting|(capture|snapshot).*(before|prior to).*(prompt|message)|(before|prior to).*(prompt|message).*(capture|snapshot)'
    'no sync under an active writer|(do not|never|must not).*(sync|synchroniz).*(active writer|writer.*active)|(active writer|writer.*active).*(do not|never|must not).*(sync|synchroniz)'
    'approval for ignored paths|(ignored (path|file)|gitignored).*(approval|approve|consent)|(approval|approve|consent).*(ignored (path|file)|gitignored)'
    'safe reclaim protocol|(reclaim|take over).*(stop|terminate|writer|ownership|safe)|(stop|terminate|writer|ownership|safe).*(reclaim|take over)'
    'blocking lifecycle wait|(blocking|block).*(wait|event)|(wait|event).*(blocking|block)'
    'monotonic wait cursor|(monotonic|increasing).*(cursor)|(cursor).*(monotonic|increasing)'
    'returned cursor for first wait|(list|inspect|start-conductor).*(return|returned).*(cursor)|(cursor).*(list|inspect|start-conductor)'
    'writer records remain active until protocol transition|writer record.*(live|active).*(explicit|safe).*(transition|clears)|explicit.*(transition|clears).*writer record'
    'no PID or heartbeat stale inference|heartbeat signals to infer a stale writer|(do not|never).*(PID|heartbeat).*(stale|infer)'
    'main and subagent completion are distinct|(main|main-turn).*(subagent).*(distinct|separate|different)|(subagent).*(main|main-turn).*(distinct|separate|different)'
    'input-needed allowlist|permission_prompt.*idle_prompt.*elicitation_dialog'
    'bounded capture after event wake|(wake|event).*(bounded).*(capture|inspect)|(capture|inspect).*(after|following).*(wake|event)'
    'visible Terminal reveal|(reveal|show|open).*(Mini )?Terminal|(Mini )?Terminal.*(reveal|show|open)'
    'workflow-id reveal command|reveal WORKFLOW_ID'
    'reveal keeps prompt out of argv|(reveal|Terminal).*(prompt).*(not|never|without).*(argv)|(prompt).*(not|never|without).*(argv).*(reveal|Terminal)'
    'reveal does not replace the pane|(reveal|Terminal).*(not|never|without).*(replace|replacing).*(pane)|(not|never|without).*(replace|replacing).*(pane).*(reveal|Terminal)'
    'Mini Claude defaults to Fable xhigh|model=fable.*effortLevel=xhigh|Fable.*xhigh'
    'Claude model preference is not a launch flag|not as launch flags|not.*launch arguments'
    'workflow list is the discovery source|remote-agent\.sh(\s|`)* list|workflow.*list'
    'workflow start conductor command|start-conductor PROJECT PLAN_ID'
    'workflow-id inspect command|inspect WORKFLOW_ID'
    'workflow-id send command|send WORKFLOW_ID'
    'workflow-id wait command|wait WORKFLOW_ID.*--cursor.*--timeout'
    'workflow-id release command|release WORKFLOW_ID'
    'separate mirror sync command|sync WORKFLOW_ID|request-mirror-sync'
    'diagnostic harness family|diagnostic (ACTION|start).*PROJECT HARNESS'
  )

  if [[ ! -f "$REMOTE_AGENT_HOST_SKILL" ]]; then
    fail "$name" "missing skill body: $REMOTE_AGENT_HOST_SKILL"
    return
  fi

  for requirement in "${requirements[@]}"; do
    label="${requirement%%|*}"
    pattern="${requirement#*|}"
    grep -qiE "$pattern" "$REMOTE_AGENT_HOST_SKILL" \
      || viol+="missing contract: $label"$'\n'
  done

  grep -Fq "\${CLAUDE_PLUGIN_ROOT}/scripts/remote-agent.sh" "$REMOTE_AGENT_HOST_SKILL" \
    || viol+="missing contract: helper invocation through CLAUDE_PLUGIN_ROOT"$'\n'

  # shellcheck disable=SC2016
  if grep -qiE 'first JSON line|second and final line|appended by a running `status`|stale-writer|stale ownership|break a stale writer|remote-agent\.sh status PROJECT|remote-agent\.sh start PROJECT|remote-agent\.sh continue PROJECT|remote-agent\.sh reclaim PROJECT' "$REMOTE_AGENT_HOST_SKILL"; then
    viol+="obsolete remote status or stale-writer doctrine remains"$'\n'
  fi

  if [[ -n "$viol" ]]; then
    fail "$name" "$viol"
  else
    pass "$name"
  fi
}

# (g) The conductor recognizes the same user-facing Mini intent families and
#     sends them to remote-agent-host. This is deliberately checked apart
#     from skill discovery so a missing route cannot hide behind a missing
#     implementation.
test_conductor_routes_remote_agent_host() {
  local name="conductor routes natural-language Mini intents to remote-agent-host"
  local viol="" requirement label pattern
  local requirements=(
    "remote-agent-host route|\`remote-agent-host\`"
    'start Mini intent|(start|launch).*Mini|Mini.*(start|launch)'
    'continue Mini intent|(continue|resume).*Mini|Mini.*(continue|resume)'
    'inspect-for-input Mini intent|(inspect|check).*(input|waiting|needs)|((input|waiting|needs).*(inspect|check))'
    'control Mini intent|(control|steer|send|tell).*Mini|Mini.*(control|steer|send|tell)'
    'reclaim Mini intent|(reclaim|take over).*Mini|Mini.*(reclaim|take over)'
    'wait Mini lifecycle intent|(wait|watch|monitor).*(Mini|agent)|(Mini|agent).*(wait|watch|monitor)'
    'reveal Mini Terminal intent|(reveal|show|open).*(Mini )?Terminal|(Mini )?Terminal.*(reveal|show|open)'
  )

  if [[ ! -f "$CONDUCTOR_SKILL" ]]; then
    fail "$name" "missing conductor skill body: $CONDUCTOR_SKILL"
    return
  fi

  for requirement in "${requirements[@]}"; do
    label="${requirement%%|*}"
    pattern="${requirement#*|}"
    grep -qiE "$pattern" "$CONDUCTOR_SKILL" \
      || viol+="missing route contract: $label"$'\n'
  done

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
test_remote_agent_host_contract
test_conductor_routes_remote_agent_host
test_host_and_external_skill_inventories
test_external_skills_are_self_contained
test_external_bodies_are_host_neutral

printf 'TOTAL pass=%d fail=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
