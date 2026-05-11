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
    | jq -e --arg name "$PLUGIN_NAME" '
        (.. | objects | select(.name? == $name)) // empty
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
claude plugin install "${PLUGIN_NAME}@${MARKETPLACE_NAME}"
ok "installed"

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
