#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$SCRIPT_DIR/../../.."
HTML="$ROOT_DIR/docs/model-routing-configurator.html"
PRESETS="$ROOT_DIR/orchestration/config/routing-presets.json"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

[[ -f $HTML ]] || fail 'configurator HTML is missing'

for token in \
  'claude_workers' 'deny' 'allow' \
  'orchestrator' 'planning_convergence' 'exploration' 'implementation' \
  'verification_review' 'design_taste' 'bulk_simple' \
  'gpt-5.6-sol' 'gpt-5.6-terra' 'gpt-5.6-luna' 'grok-4.5' \
  'claude-fable' 'claude-opus' 'claude-sonnet' \
  'format_version' 'strategy' 'lanes' 'parallel_converge' 'parallel_gate' \
  'codex-primary' 'fable-primary' \
  'xhigh' 'Add lane' 'Copy JSON' 'Download JSON' 'dirty worktree'; do
  grep -Fiq "$token" "$HTML" || fail "missing contract token: $token"
done

if grep -Eiq "<(script|link)[^>]+(src|href)=['\"]https?://" "$HTML"; then
  fail 'configurator has an external dependency'
fi

grep -Fq '"grok-4.5": ["high"]' "$HTML" \
  || fail 'Grok 4.5 reasoning selector is not pinned to high'

sed -n '/<script id="routing-presets" type="application\/json">/,/<\/script>/p' "$HTML" \
  | sed '1d;$d' >"$TMP_DIR/presets.json"
jq -S . "$TMP_DIR/presets.json" >"$TMP_DIR/html-presets.sorted.json"
jq -S . "$PRESETS" >"$TMP_DIR/canonical-presets.sorted.json"
cmp -s "$TMP_DIR/html-presets.sorted.json" "$TMP_DIR/canonical-presets.sorted.json" \
  || fail 'HTML embedded presets drifted from canonical routing-presets.json'
jq -e '
  def has_sol_and_grok:
    [.lanes[].model] as $models
    | (($models | index("gpt-5.6-sol")) != null)
      and (($models | index("grok-4.5")) != null);

  .codex_primary.format_version == 2
  and .fable_primary.format_version == 2
  and .codex_primary.profile == "codex-primary"
  and .fable_primary.profile == "fable-primary"
  and .codex_primary.policy == {"claude_workers":"deny"}
  and ([.codex_primary.routing[].lanes | type == "array" and length > 0] | all)
  and ([.fable_primary.routing[].lanes | type == "array" and length > 0] | all)
  and .codex_primary.routing.orchestrator.strategy == "single"
  and .codex_primary.routing.orchestrator.lanes[0]
    == {"id":"primary","model":"gpt-5.6-sol","reasoning":"xhigh"}
  and .fable_primary.routing.orchestrator.lanes[0]
    == {"id":"primary","model":"claude-fable","reasoning":"xhigh"}
  and .codex_primary.routing.planning_convergence.strategy == "parallel_converge"
  and (.codex_primary.routing.planning_convergence | has_sol_and_grok)
  and .codex_primary.routing.exploration.strategy == "parallel_converge"
  and (.codex_primary.routing.exploration | has_sol_and_grok)
  and .codex_primary.routing.verification_review.strategy == "parallel_gate"
  and (.codex_primary.routing.verification_review | has_sol_and_grok)
  and .codex_primary.routing.verification_review.gate
    == {"require":"all","cross_family_required":true}
  and ([.codex_primary.routing[], .fable_primary.routing[]
    | .lanes[]
    | select(.model == "grok-4.5")
    | .reasoning == "high"] | all)
  and ([.codex_primary.routing[].lanes[].model | startswith("claude-")] | any | not)
  and .fable_primary.policy == {"claude_workers":"allow"}
  and .fable_primary.routing.exploration.lanes[2]
    == {"id":"claude-explore","model":"claude-fable","reasoning":"high"}
  and .fable_primary.routing.implementation.lanes[1]
    == {"id":"claude-implement","model":"claude-fable","reasoning":"high"}
  and .fable_primary.routing.verification_review.lanes[2]
    == {"id":"claude-review","model":"claude-fable","reasoning":"high"}
' "$TMP_DIR/presets.json" >/dev/null || fail 'preset JSON violates safe routing defaults'

printf 'PASS standalone model-routing configurator contract\n'
