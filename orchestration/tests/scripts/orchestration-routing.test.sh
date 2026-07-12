#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT="$SCRIPT_DIR/../.."
ROUTING="$PLUGIN_ROOT/scripts/orchestration-routing.sh"
PRESETS="$PLUGIN_ROOT/config/routing-presets.json"
SCHEMA="$PLUGIN_ROOT/schemas/routing.schema.json"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

[[ -x "$ROUTING" ]] || fail 'routing helper is missing or not executable'
[[ -f "$PRESETS" ]] || fail 'canonical routing presets are missing'
[[ -f "$SCHEMA" ]] || fail 'routing schema is missing'

jq -e '
  keys == ["codex_primary", "fable_primary"]
  and .codex_primary.profile == "codex-primary"
  and .codex_primary.policy == {"claude_workers":"deny"}
  and .codex_primary.routing.orchestrator.lanes[0]
    == {"id":"primary","model":"gpt-5.6-sol","reasoning":"xhigh"}
  and .fable_primary.profile == "fable-primary"
  and .fable_primary.policy == {"claude_workers":"allow"}
  and .fable_primary.routing.orchestrator.lanes[0]
    == {"id":"primary","model":"claude-fable","reasoning":"xhigh"}
  and ([.codex_primary.routing[], .fable_primary.routing[]
    | .lanes[] | select(.model == "grok-4.5")
    | .reasoning == "high"] | all)
  and ([.codex_primary.routing[].lanes[].model | startswith("claude-")] | any | not)
  and .codex_primary.routing.verification_review.gate
    == {"require":"all","cross_family_required":true}
  and .fable_primary.routing.verification_review.gate
    == {"require":"all","cross_family_required":true}
' "$PRESETS" >/dev/null || fail 'canonical presets do not match the approved profiles'

project="$SANDBOX/project"
mkdir -p "$project"

$ROUTING show "$project" | jq -e '
  .profile == "codex-primary"
  and .policy == {"claude_workers":"deny"}
  and .routing.orchestrator.lanes[0]
    == {"id":"primary","model":"gpt-5.6-sol","reasoning":"xhigh"}
' >/dev/null || fail 'missing project routing did not resolve to shipped Codex-primary default'
[[ ! -e "$project/.orchestration/routing.json" ]] \
  || fail 'reading the shipped default unexpectedly wrote project state'
$ROUTING validate "$project" | grep -Fqx 'valid=codex-primary' \
  || fail 'shipped Codex-primary default did not validate'

output="$($ROUTING activate codex-primary "$project")"
grep -Fq 'required_host=codex' <<<"$output" || fail 'Codex activation did not report its required host'
jq -e '.profile == "codex-primary" and .policy.claude_workers == "deny"' \
  "$project/.orchestration/routing.json" >/dev/null \
  || fail 'Codex activation wrote the wrong profile'
$ROUTING validate "$project" >/dev/null || fail 'activated Codex profile did not validate'

output="$($ROUTING activate fable-primary "$project")"
grep -Fq 'required_host=claude' <<<"$output" || fail 'Fable activation did not report its required host'
grep -Fq 'required_model=claude-fable' <<<"$output" || fail 'Fable activation did not report its required model'
grep -Fq 'required_reasoning=xhigh' <<<"$output" || fail 'Fable activation did not report its required reasoning'
jq -e '.profile == "fable-primary" and .policy.claude_workers == "allow"' \
  "$project/.orchestration/routing.json" >/dev/null \
  || fail 'Fable activation wrote the wrong profile'

$ROUTING show "$project" | jq -e '.profile == "fable-primary"' >/dev/null \
  || fail 'show did not return the active project profile'

printf '{bad-json\n' >"$project/.orchestration/routing.json"
if $ROUTING validate "$project" >"$SANDBOX/out" 2>"$SANDBOX/err"; then
  fail 'malformed routing unexpectedly validated'
fi

before="$(find "$project/.orchestration" -maxdepth 1 -type f -print | sort)"
if $ROUTING activate unavailable-profile "$project" >"$SANDBOX/out" 2>"$SANDBOX/err"; then
  fail 'unknown profile unexpectedly activated'
fi
after="$(find "$project/.orchestration" -maxdepth 1 -type f -print | sort)"
[[ "$before" == "$after" ]] || fail 'failed activation left a temporary file behind'

jq -e '
  .type == "object"
  and .additionalProperties == false
  and (.required | sort == ["format_version", "policy", "profile", "routing"])
  and .properties.profile.enum == ["codex-primary", "fable-primary"]
  and .properties.format_version.const == 2
' "$SCHEMA" >/dev/null || fail 'routing schema does not define the closed profile envelope'

printf 'PASS canonical routing profiles and activation contract\n'
