#!/usr/bin/env bash
# Install the orchestration plugin (latest) from the
# miospotdevteam/claude-codex-orchestration marketplace.
#
# Idempotent:
#   - Uninstalls the plugin if already installed.
#   - Adds the marketplace if not already registered; updates it if it is.
#   - Then installs (or reinstalls) the plugin.
#
# Usage:
#   bash install.sh
#
# Prerequisites:
#   - claude CLI on PATH (Claude Code)
#   - gh CLI on PATH, authenticated against an account with read access
#     to the public miospotdevteam/claude-codex-orchestration repo
#   - jq on PATH

set -euo pipefail

PLUGIN_NAME='orchestration'
MARKETPLACE_NAME='claude-codex-orchestration'
MARKETPLACE_SOURCE='miospotdevteam/claude-codex-orchestration'
PLUGIN_ID="${PLUGIN_NAME}@${MARKETPLACE_NAME}"

log()  { printf '\033[1;34m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ---- preflight --------------------------------------------------------------

command -v claude >/dev/null || die "claude CLI not on PATH. Install Claude Code first."
command -v gh     >/dev/null || die "gh CLI not on PATH. Install GitHub CLI first."
command -v jq     >/dev/null || die "jq not on PATH. Install jq first (brew install jq)."

if ! gh auth status >/dev/null 2>&1; then
  die "gh is not authenticated. Run 'gh auth login' first."
fi

ok "prereqs OK"

# ---- step 1: uninstall current plugin if present ----------------------------

is_plugin_installed() {
  claude plugin list --json 2>/dev/null \
    | jq -e --arg id "$PLUGIN_ID" --arg name "$PLUGIN_NAME" '
        def plugin_values:
          if type == "array" then .[]
          elif type == "object" then .
          else empty
          end;
        def matching_entries:
          if type == "array" then
            .[] | select(.id? == $id or .name? == $name)
          elif type == "object" then
            (.plugins? // .)
            | to_entries[]
            | select(.key == $id or .key == $name)
            | .value
            | plugin_values
          else empty
          end;
        [matching_entries] | length > 0
      ' >/dev/null 2>&1
}

if is_plugin_installed; then
  log "plugin '$PLUGIN_NAME' is currently installed — uninstalling"
  claude plugin uninstall "$PLUGIN_NAME" -y
  ok "uninstalled '$PLUGIN_NAME'"
else
  ok "plugin '$PLUGIN_NAME' is not installed yet (nothing to remove)"
fi

# ---- step 2: add or update the marketplace ---------------------------------

is_marketplace_added() {
  # `claude plugin marketplace list` prints text. Look for the marketplace
  # name as a token; the format is "  ❯ <name>" followed by "Source: ...".
  claude plugin marketplace list 2>/dev/null \
    | grep -qE "^[[:space:]]*[❯>*•-]?[[:space:]]*${MARKETPLACE_NAME}([[:space:]]|$)"
}

if is_marketplace_added; then
  log "marketplace '$MARKETPLACE_NAME' is already registered — updating to latest"
  claude plugin marketplace update "$MARKETPLACE_NAME"
  ok "marketplace updated"
else
  log "adding marketplace from $MARKETPLACE_SOURCE"
  claude plugin marketplace add "$MARKETPLACE_SOURCE"
  ok "marketplace added"
fi

# ---- step 3: install the plugin --------------------------------------------

log "installing $PLUGIN_NAME@$MARKETPLACE_NAME"
claude plugin install "$PLUGIN_ID"
ok "installed"

# ---- step 4: resolve and validate the installed plugin artifact ------------

resolve_plugin_install_path() {
  local listing paths path count=0

  if ! listing="$(claude plugin list --json 2>/dev/null)"; then
    die "could not read Claude's machine-readable plugin listing"
  fi
  if ! paths="$(
    jq -r --arg id "$PLUGIN_ID" --arg name "$PLUGIN_NAME" '
      def plugin_values:
        if type == "array" then .[]
        elif type == "object" then .
        else empty
        end;
      def matching_entries:
        if type == "array" then
          .[] | select(.id? == $id or .name? == $name)
        elif type == "object" then
          (.plugins? // .)
          | to_entries[]
          | select(.key == $id or .key == $name)
          | .value
          | plugin_values
        else empty
        end;
      [matching_entries | .installPath?]
      | map(select(type == "string" and length > 0))
      | unique[]
    ' <<<"$listing"
  )"; then
    die "Claude's machine-readable plugin listing is invalid"
  fi

  PLUGIN_INSTALL_PATH=''
  while IFS= read -r path; do
    if [[ -n "$path" ]]; then
      PLUGIN_INSTALL_PATH="$path"
      count=$((count + 1))
    fi
  done <<<"$paths"

  if [[ "$count" -ne 1 ]]; then
    die "expected exactly one installed $PLUGIN_ID installPath; found $count"
  fi
}

resolve_plugin_install_path

[[ "$PLUGIN_INSTALL_PATH" == /* ]] \
  || die "installed $PLUGIN_ID installPath is not absolute: $PLUGIN_INSTALL_PATH"
[[ -d "$PLUGIN_INSTALL_PATH" ]] \
  || die "installed $PLUGIN_ID installPath is not a directory: $PLUGIN_INSTALL_PATH"
[[ -f "$PLUGIN_INSTALL_PATH/.claude-plugin/plugin.json" ]] \
  || die "installed $PLUGIN_ID artifact has no plugin manifest: $PLUGIN_INSTALL_PATH"
jq -e --arg name "$PLUGIN_NAME" '.name == $name' \
  "$PLUGIN_INSTALL_PATH/.claude-plugin/plugin.json" >/dev/null \
  || die "installed artifact manifest is not for $PLUGIN_NAME: $PLUGIN_INSTALL_PATH"
[[ -d "$PLUGIN_INSTALL_PATH/skills" ]] \
  || die "installed $PLUGIN_ID artifact has no skills directory: $PLUGIN_INSTALL_PATH"

PLUGIN_INSTALL_PATH="$(cd "$PLUGIN_INSTALL_PATH" && pwd -P)"
ok "resolved installed plugin artifact: $PLUGIN_INSTALL_PATH"

# ---- step 5: de-duplicate skill dirs, then sync the external CLI lanes -----
#
# One canonical copy per lane, no doubles:
#
#   - Claude loads the plugin's skills from the plugin cache. Any same-named
#     copy in ~/.claude/skills would double-install → cleared, never copied.
#   - Codex and Grok load skills from their own skills dirs. The wrappers
#     inject "Honor the step-specific skill <name>", so the body must exist
#     CLI-side → cleared of every plugin-managed name, then EXACTLY the
#     injectable set from docs/09-routing-matrix.md ("Skill Injection Rules")
#     is installed: the engineering floor, the five injectable workflow
#     skills, and the dual-install react-native-mobile body (external-lane
#     copy from codex-skills/ preferred).
#
# Claude-only skills (frontend-design, svg-art, immersive-frontend,
# brainstorming, writing-plans, doc-coauthoring) are never installed
# CLI-side — panel-planning briefs and arbitration instructions arrive via
# the wrapper prompt, not as skills. v1 leftovers (lbyl-*,
# look-before-you-leap) are cleared everywhere. Skills the plugin does not
# own (user's own skills, a CLI's bundled skills) are never touched.

EXTERNAL_SKILLS=(
  engineering-discipline
  test-driven-development
  refactoring
  systematic-debugging
  webapp-testing
  mcp-builder
  react-native-mobile
)

# Validate every required source before cleanup so a malformed installed
# artifact cannot leave an external lane partially cleared or partially synced.
for s in "${EXTERNAL_SKILLS[@]}"; do
  if [[ ! -d "$PLUGIN_INSTALL_PATH/codex-skills/$s" \
    && ! -d "$PLUGIN_INSTALL_PATH/skills/$s" ]]; then
    die "installed artifact is missing external skill '$s': $PLUGIN_INSTALL_PATH"
  fi
done

# Every skill name the plugin owns, derived from the installed artifact so the
# list can never drift or be influenced by the checkout invoking this script.
MANAGED_SKILLS=()
for d in "$PLUGIN_INSTALL_PATH"/skills/*/ "$PLUGIN_INSTALL_PATH"/codex-skills/*/; do
  if [[ -d "$d" ]]; then
    MANAGED_SKILLS+=("$(basename "$d")")
  fi
done
MANAGED_SKILLS+=(look-before-you-leap)

clear_managed() {
  local lane="$1" target="$2"
  if [[ ! -d "$target" ]]; then
    return 0
  fi
  local removed=0 s d
  for s in "${MANAGED_SKILLS[@]}"; do
    if [[ -d "$target/$s" ]]; then
      rm -rf "${target:?}/${s:?}"
      removed=$((removed + 1))
    fi
  done
  for d in "$target"/lbyl-*; do
    if [[ -d "$d" ]]; then
      rm -rf "$d"
      removed=$((removed + 1))
    fi
  done
  if [[ "$removed" -gt 0 ]]; then
    log "$lane: cleared $removed duplicate/stale skill dir(s) from $target"
  else
    ok "$lane: no duplicate skill dirs in $target"
  fi
}

sync_external_lane() {
  local lane="$1" target="$2"
  mkdir -p "$target"
  clear_managed "$lane" "$target"

  local installed=0 s src
  for s in "${EXTERNAL_SKILLS[@]}"; do
    src="$PLUGIN_INSTALL_PATH/codex-skills/$s"
    if [[ ! -d "$src" ]]; then
      src="$PLUGIN_INSTALL_PATH/skills/$s"
    fi
    cp -R "$src" "$target/$s"
    installed=$((installed + 1))
  done
  ok "$lane: $installed skill(s) synced into $target"
}

# Claude: clear only — the plugin cache is the single source of these skills.
clear_managed claude "$HOME/.claude/skills"

if command -v codex >/dev/null; then
  sync_external_lane codex "$HOME/.codex/skills"
else
  warn "codex CLI not on PATH — skipping codex skill sync"
fi

if command -v grok >/dev/null; then
  sync_external_lane grok "$HOME/.grok/skills"
else
  warn "grok CLI not on PATH — skipping grok skill sync"
fi

# ---- final state report ----------------------------------------------------

echo ""
echo "============================================================"
echo "  Installed plugins"
echo "============================================================"
claude plugin list

echo ""
echo "============================================================"
echo "  Marketplaces"
echo "============================================================"
claude plugin marketplace list

echo ""
ok "done. Restart Claude Code (or run /reload-plugins in an open session) to pick up the install."
