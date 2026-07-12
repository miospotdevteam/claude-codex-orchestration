#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="$SCRIPT_DIR/../../scripts/orchestration-policy.sh"
SCHEMA="$SCRIPT_DIR/../../schemas/policy.schema.json"
PRESETS="$SCRIPT_DIR/../../config/routing-presets.json"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf 'PASS %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_query() {
  local name="$1"
  local expected="$2"
  local project_root="$3"
  local config_home="$4"
  local output

  if ! output="$(XDG_CONFIG_HOME="$config_home" "$POLICY" get "$project_root" 2>"$SANDBOX/error")"; then
    fail "$name" "query failed: $(<"$SANDBOX/error")"
  elif [[ "$output" != "$expected" ]]; then
    fail "$name" "expected $expected, got $output"
  else
    pass "$name"
  fi
}

write_policy() {
  local path="$1"
  local value="$2"

  mkdir -p "$(dirname "$path")"
  printf '{"claude_workers":"%s"}\n' "$value" >"$path"
}

write_routing_profile() {
  local path="$1"
  local key="$2"

  mkdir -p "$(dirname "$path")"
  jq ".${key}" "$PRESETS" >"$path"
}

test_valid_routing_profile_is_canonical_policy_source() {
  local project="$SANDBOX/routing-profile/project"
  local config="$SANDBOX/routing-profile/config"

  write_policy "$project/.orchestration/policy.json" allow
  write_routing_profile "$project/.orchestration/routing.json" codex_primary
  assert_query "Codex routing profile overrides legacy allow" deny "$project" "$config"

  write_policy "$project/.orchestration/policy.json" deny
  write_routing_profile "$project/.orchestration/routing.json" fable_primary
  assert_query "Fable routing profile overrides legacy deny" allow "$project" "$config"
}

test_malformed_routing_fails_closed_without_legacy_fallback() {
  local project="$SANDBOX/invalid-routing/project"
  local config="$SANDBOX/invalid-routing/config"
  local routing="$project/.orchestration/routing.json"

  write_policy "$project/.orchestration/policy.json" allow
  mkdir -p "$(dirname "$routing")"
  printf '{bad-json\n' >"$routing"
  assert_query "malformed routing fails closed over legacy allow" deny "$project" "$config"

  jq '.fable_primary | .profile = "codex-primary"' "$PRESETS" >"$routing"
  assert_query "inconsistent routing profile fails closed" deny "$project" "$config"
}

test_missing_policy_defaults_to_deny() {
  local project="$SANDBOX/missing/project"
  local config="$SANDBOX/missing/config"

  mkdir -p "$project" "$config"
  assert_query "missing policy defaults to deny" deny "$project" "$config"
}

test_user_policy_is_used_when_project_policy_is_missing() {
  local project="$SANDBOX/user/project"
  local config="$SANDBOX/user/config"

  mkdir -p "$project"
  write_policy "$config/orchestration/policy.json" allow
  assert_query "user allow is used when project policy is missing" allow "$project" "$config"
}

test_project_policy_overrides_user_policy() {
  local project="$SANDBOX/project-wins/project"
  local config="$SANDBOX/project-wins/config"

  write_policy "$config/orchestration/policy.json" allow
  write_policy "$project/.orchestration/policy.json" deny
  assert_query "project deny overrides user allow" deny "$project" "$config"

  write_policy "$config/orchestration/policy.json" deny
  write_policy "$project/.orchestration/policy.json" allow
  assert_query "project allow overrides user deny" allow "$project" "$config"
}

test_invalid_project_policy_fails_closed_without_user_fallback() {
  local project="$SANDBOX/invalid-project/project"
  local config="$SANDBOX/invalid-project/config"
  local policy="$project/.orchestration/policy.json"

  write_policy "$config/orchestration/policy.json" allow
  mkdir -p "$(dirname "$policy")"

  printf '{not-json\n' >"$policy"
  assert_query "malformed project policy fails closed" deny "$project" "$config"

  write_policy "$policy" sometimes
  assert_query "invalid project value fails closed" deny "$project" "$config"

  printf '{"claude_workers":"allow","other":true}\n' >"$policy"
  assert_query "extra project fields fail closed" deny "$project" "$config"
}

test_invalid_user_policy_fails_closed() {
  local project="$SANDBOX/invalid-user/project"
  local config="$SANDBOX/invalid-user/config"
  local policy="$config/orchestration/policy.json"

  mkdir -p "$project" "$(dirname "$policy")"
  printf '{}\n' >"$policy"
  assert_query "missing claude_workers fails closed" deny "$project" "$config"

  printf '[]\n' >"$policy"
  assert_query "non-object user policy fails closed" deny "$project" "$config"
}

test_home_config_is_used_when_xdg_config_home_is_unset() {
  local project="$SANDBOX/home-fallback/project"
  local home="$SANDBOX/home-fallback/home"
  local output

  mkdir -p "$project"
  write_policy "$home/.config/orchestration/policy.json" allow

  if ! output="$(env -u XDG_CONFIG_HOME HOME="$home" "$POLICY" get "$project" 2>"$SANDBOX/error")"; then
    fail "HOME config fallback is supported" "query failed: $(<"$SANDBOX/error")"
  elif [[ "$output" != "allow" ]]; then
    fail "HOME config fallback is supported" "expected allow, got $output"
  else
    pass "HOME config fallback is supported"
  fi
}

test_source_reports_winning_layer() {
  local project="$SANDBOX/source/project"
  local config="$SANDBOX/source/config"
  local output

  mkdir -p "$project" "$config"
  output="$(XDG_CONFIG_HOME="$config" "$POLICY" source "$project")"
  [[ "$output" == "default" ]] || {
    fail "source reports shipped default" "expected default, got $output"
    return
  }
  pass "source reports shipped default"

  write_routing_profile "$project/.orchestration/routing.json" codex_primary
  output="$(XDG_CONFIG_HOME="$config" "$POLICY" source "$project")"
  [[ "$output" == "routing" ]] || {
    fail "source reports project routing" "expected routing, got $output"
    return
  }
  pass "source reports project routing"
  rm "$project/.orchestration/routing.json"

  write_policy "$config/orchestration/policy.json" allow
  output="$(XDG_CONFIG_HOME="$config" "$POLICY" source "$project")"
  [[ "$output" == "user" ]] || {
    fail "source reports user policy" "expected user, got $output"
    return
  }
  pass "source reports user policy"

  write_policy "$project/.orchestration/policy.json" deny
  output="$(XDG_CONFIG_HOME="$config" "$POLICY" source "$project")"
  [[ "$output" == "project" ]] || {
    fail "source reports project policy" "expected project, got $output"
    return
  }
  pass "source reports project policy"
}

test_schema_describes_the_exact_policy_shape_and_default() {
  local name="schema permits exactly allow or deny and defaults deny"

  if ! jq -e '
    .type == "object"
    and .additionalProperties == false
    and .required == ["claude_workers"]
    and .properties.claude_workers.enum == ["allow", "deny"]
    and .properties.claude_workers.default == "deny"
  ' "$SCHEMA" >/dev/null; then
    fail "$name" "schema does not define the required closed policy shape"
  else
    pass "$name"
  fi
}

test_unknown_command_is_rejected() {
  local name="unknown command is rejected"

  if "$POLICY" unknown >"$SANDBOX/output" 2>"$SANDBOX/error"; then
    fail "$name" "expected a non-zero exit status"
  elif ! grep -Fq "Usage:" "$SANDBOX/error"; then
    fail "$name" "expected usage on stderr"
  else
    pass "$name"
  fi
}

test_missing_policy_defaults_to_deny
test_valid_routing_profile_is_canonical_policy_source
test_malformed_routing_fails_closed_without_legacy_fallback
test_user_policy_is_used_when_project_policy_is_missing
test_project_policy_overrides_user_policy
test_invalid_project_policy_fails_closed_without_user_fallback
test_invalid_user_policy_fails_closed
test_home_config_is_used_when_xdg_config_home_is_unset
test_source_reports_winning_layer
test_schema_describes_the_exact_policy_shape_and_default
test_unknown_command_is_rejected

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
