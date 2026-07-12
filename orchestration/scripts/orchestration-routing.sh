#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PRESETS="$SCRIPT_DIR/../config/routing-presets.json"

usage() {
  cat >&2 <<'USAGE'
Usage:
  orchestration-routing.sh activate <codex-primary|fable-primary> [project-root]
  orchestration-routing.sh show [project-root]
  orchestration-routing.sh validate [project-root]
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

routing_file_for() {
  local project_root="$1"
  printf '%s/.orchestration/routing.json\n' "${project_root%/}"
}

validate_file() {
  local routing_file="$1"

  [[ -f "$routing_file" ]] || return 1
  jq -e '
    def exact_keys($expected):
      type == "object" and ((keys | sort) == ($expected | sort));
    def valid_lane:
      exact_keys(["id", "model", "reasoning"])
      and (.id | type == "string" and length > 0)
      and (.model | IN(
        "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "grok-4.5",
        "claude-fable", "claude-opus", "claude-sonnet"
      ))
      and (.reasoning | IN("low", "medium", "high", "xhigh", "max"))
      and (if .model == "grok-4.5" then .reasoning == "high" else true end);
    def valid_lanes:
      (.lanes | type == "array" and length > 0 and all(.[]; valid_lane))
      and (([.lanes[].id] | length) == ([.lanes[].id] | unique | length));
    def valid_single:
      exact_keys(["strategy", "lanes"])
      and .strategy == "single"
      and valid_lanes
      and (.lanes | length == 1);
    def valid_parallel:
      exact_keys(["strategy", "lanes", "convergence"])
      and .strategy == "parallel_converge"
      and valid_lanes
      and (.lanes | length >= 2)
      and .convergence == {"owner":"orchestrator"};
    def valid_frontier:
      exact_keys(["strategy", "lanes"])
      and .strategy == "frontier"
      and valid_lanes;
    def valid_gate:
      exact_keys(["strategy", "lanes", "gate"])
      and .strategy == "parallel_gate"
      and valid_lanes
      and (.lanes | length >= 2)
      and .gate == {"require":"all","cross_family_required":true};
    def valid_routing:
      exact_keys([
        "orchestrator", "planning_convergence", "exploration", "implementation",
        "verification_review", "design_taste", "bulk_simple"
      ])
      and (.orchestrator | valid_single)
      and (.planning_convergence | valid_parallel)
      and (.exploration | valid_parallel)
      and (.implementation | valid_frontier)
      and (.verification_review | valid_gate)
      and (.design_taste | valid_single)
      and (.bulk_simple | valid_frontier);

    exact_keys(["format_version", "profile", "policy", "routing"])
    and .format_version == 2
    and (.policy | exact_keys(["claude_workers"]))
    and (.routing | valid_routing)
    and ([.routing[] | .lanes[] | select(.model == "grok-4.5")
      | .reasoning == "high"] | all)
    and if .profile == "codex-primary" then
      .policy == {"claude_workers":"deny"}
      and .routing.orchestrator.lanes[0]
        == {"id":"primary","model":"gpt-5.6-sol","reasoning":"xhigh"}
      and ([.routing[] | .lanes[] | .model | startswith("claude-")] | any | not)
    elif .profile == "fable-primary" then
      .policy == {"claude_workers":"allow"}
      and .routing.orchestrator.lanes[0]
        == {"id":"primary","model":"claude-fable","reasoning":"xhigh"}
    else
      false
    end
  ' "$routing_file" >/dev/null 2>&1
}

activate_profile() {
  local profile="$1" project_root="$2" preset_key required_host required_model
  local routing_file routing_dir tmp_file

  case "$profile" in
    codex-primary)
      preset_key=codex_primary
      required_host=codex
      required_model=gpt-5.6-sol
      ;;
    fable-primary)
      preset_key=fable_primary
      required_host=claude
      required_model=claude-fable
      ;;
    *) die "unknown routing profile: $profile" ;;
  esac

  [[ -d "$project_root" ]] || die "project root is not a directory: $project_root"
  [[ -f "$PRESETS" ]] || die "canonical routing presets are missing: $PRESETS"

  routing_file="$(routing_file_for "$project_root")"
  routing_dir="$(dirname "$routing_file")"
  mkdir -p "$routing_dir"
  tmp_file="$(mktemp "$routing_dir/.routing.json.tmp.XXXXXX")"
  trap 'rm -f "${tmp_file:-}"' EXIT

  jq -e ".${preset_key}" "$PRESETS" >"$tmp_file" \
    || die "canonical routing preset is invalid: $preset_key"
  validate_file "$tmp_file" \
    || die "canonical routing preset violates the routing contract: $preset_key"
  mv -f "$tmp_file" "$routing_file"
  trap - EXIT

  printf 'activated=%s\n' "$profile"
  printf 'routing_file=%s\n' "$routing_file"
  printf 'required_host=%s\n' "$required_host"
  printf 'required_model=%s\n' "$required_model"
  printf 'required_reasoning=xhigh\n'
}

emit_active_profile() {
  local project_root="$1" routing_file tmp_file

  routing_file="$(routing_file_for "$project_root")"
  if [[ -e "$routing_file" ]]; then
    validate_file "$routing_file" \
      || die "active routing profile is invalid: $routing_file"
    jq . "$routing_file"
    return
  fi

  [[ -f "$PRESETS" ]] || die "canonical routing presets are missing: $PRESETS"
  tmp_file="$(mktemp)"
  if ! jq -e '.codex_primary' "$PRESETS" >"$tmp_file" \
    || ! validate_file "$tmp_file"; then
    rm -f "$tmp_file"
    die "shipped Codex-primary routing preset is invalid: $PRESETS"
  fi
  jq . "$tmp_file"
  rm -f "$tmp_file"
}

[[ $# -ge 1 ]] || { usage; exit 2; }
command_name="$1"
shift

case "$command_name" in
  activate)
    [[ $# -ge 1 && $# -le 2 ]] || { usage; exit 2; }
    activate_profile "$1" "${2:-$PWD}"
    ;;
  show)
    [[ $# -le 1 ]] || { usage; exit 2; }
    emit_active_profile "${1:-$PWD}"
    ;;
  validate)
    [[ $# -le 1 ]] || { usage; exit 2; }
    active_profile="$(emit_active_profile "${1:-$PWD}")"
    printf 'valid=%s\n' "$(jq -r .profile <<<"$active_profile")"
    ;;
  *)
    usage
    exit 2
    ;;
esac
