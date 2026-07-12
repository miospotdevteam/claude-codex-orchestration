#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: orchestration-policy.sh <get|source> [project-root]\n' >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROUTING_HELPER="$SCRIPT_DIR/orchestration-routing.sh"

policy_value() {
  local policy_file="$1"
  local value

  if ! command -v jq >/dev/null 2>&1; then
    printf 'deny\n'
    return
  fi

  if value="$(jq -er '
    if type == "object"
      and length == 1
      and has("claude_workers")
      and (.claude_workers == "allow" or .claude_workers == "deny")
    then .claude_workers
    else empty
    end
  ' "$policy_file" 2>/dev/null)"; then
    printf '%s\n' "$value"
  else
    printf 'deny\n'
  fi
}

policy_layer() {
  local project_root="$1"
  local project_routing="$project_root/.orchestration/routing.json"
  local project_policy="$project_root/.orchestration/policy.json"
  local user_policy=""

  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    user_policy="$XDG_CONFIG_HOME/orchestration/policy.json"
  elif [[ -n "${HOME:-}" ]]; then
    user_policy="$HOME/.config/orchestration/policy.json"
  fi

  if [[ -e "$project_routing" || -L "$project_routing" ]]; then
    printf 'routing:%s\n' "$project_routing"
  elif [[ -e "$project_policy" || -L "$project_policy" ]]; then
    printf 'project:%s\n' "$project_policy"
  elif [[ -n "$user_policy" && ( -e "$user_policy" || -L "$user_policy" ) ]]; then
    printf 'user:%s\n' "$user_policy"
  else
    printf 'default:\n'
  fi
}

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  usage
  exit 2
fi

project_root="${2:-$PWD}"
layer_and_path="$(policy_layer "$project_root")"
layer="${layer_and_path%%:*}"
policy_file="${layer_and_path#*:}"

case "$1" in
  get)
    if [[ "$layer" == "routing" ]]; then
      if [[ -x "$ROUTING_HELPER" ]] \
        && "$ROUTING_HELPER" validate "$project_root" >/dev/null 2>&1; then
        jq -r '.policy.claude_workers' "$policy_file" 2>/dev/null || printf 'deny\n'
      else
        printf 'deny\n'
      fi
    elif [[ "$layer" == "default" ]]; then
      printf 'deny\n'
    else
      policy_value "$policy_file"
    fi
    ;;
  source)
    printf '%s\n' "$layer"
    ;;
  *)
    usage
    exit 2
    ;;
esac
