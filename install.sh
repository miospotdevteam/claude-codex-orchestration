#!/usr/bin/env bash
# Install the orchestration plugin (latest) from the
# miospotdevteam/claude-codex-orchestration marketplace.
#
# Idempotent:
#   - Removes the legacy v1 plugin and marketplace when present.
#   - Uninstalls the plugin if already installed.
#   - Adds the marketplace if not already registered; updates it if it is.
#   - Then installs (or reinstalls) the plugin.
#
# Usage:
#   bash install.sh [--host codex|claude|both]
#
# Prerequisites:
#   - the selected host CLI on PATH (Codex is the default)
#   - gh CLI on PATH, authenticated against an account with read access
#     to the public miospotdevteam/claude-codex-orchestration repo
#   - jq on PATH

set -euo pipefail

PLUGIN_NAME='orchestration'
MARKETPLACE_NAME='claude-codex-orchestration'
MARKETPLACE_SOURCE='miospotdevteam/claude-codex-orchestration'
PLUGIN_ID="${PLUGIN_NAME}@${MARKETPLACE_NAME}"
LEGACY_MARKETPLACE_NAME='claude-code-setup'
LEGACY_PLUGIN_NAME='look-before-you-leap'
LEGACY_PLUGIN_ID="${LEGACY_PLUGIN_NAME}@${LEGACY_MARKETPLACE_NAME}"

log()  { printf '\033[1;34m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'USAGE'
Usage: bash install.sh [--host codex|claude|both]

Hosts:
  codex   Install the Codex plugin only (default; never invokes Claude).
  claude  Install the Claude Code plugin plus required Codex/Grok dependencies.
  both    Install both hosts so switching is explicit and immediate.
USAGE
}

host=codex
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      host=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case "$host" in
  codex|claude|both) ;;
  *) die "unsupported host: $host (expected codex, claude, or both)" ;;
esac

# ---- preflight --------------------------------------------------------------

command -v gh     >/dev/null || die "gh CLI not on PATH. Install GitHub CLI first."
command -v jq     >/dev/null || die "jq not on PATH. Install jq first (brew install jq)."

command -v codex >/dev/null || die "codex CLI not on PATH. Every host requires Codex as an implementation and verification lane."
command -v grok  >/dev/null || die "grok CLI not on PATH. Every host requires Grok 4.5 as its independent counterweight."
if [[ "$host" == claude || "$host" == both ]]; then
  command -v claude >/dev/null || die "claude CLI not on PATH. Install Claude Code first."
fi

if ! gh auth status >/dev/null 2>&1; then
  die "gh is not authenticated. Run 'gh auth login' first."
fi

ok "prereqs OK"

install_codex_host() {
  local marketplaces

  log "installing Codex host from $MARKETPLACE_SOURCE"
  marketplaces=$(codex plugin marketplace list --json) \
    || die "could not read Codex marketplace listing"
  if jq -e --arg name "$MARKETPLACE_NAME" \
    '.marketplaces | any(.name == $name)' <<<"$marketplaces" >/dev/null; then
    codex plugin marketplace upgrade "$MARKETPLACE_NAME" --json >/dev/null
    ok "Codex marketplace updated"
  else
    codex plugin marketplace add "$MARKETPLACE_SOURCE" --json >/dev/null
    ok "Codex marketplace added"
  fi

  codex plugin add "$PLUGIN_ID" --json >/dev/null
  ok "Codex plugin installed"
}

resolve_codex_plugin_install_path() {
  local listing paths path count=0

  listing=$(codex plugin list --json) \
    || die "could not read Codex's machine-readable plugin listing"
  paths=$(
    jq -r --arg id "$PLUGIN_ID" --arg name "$PLUGIN_NAME" '
      def installed_entries:
        if type == "array" then .[]
        elif (.installed? | type) == "array" then .installed[]
        else empty
        end;
      [installed_entries
        | select(.pluginId? == $id or .id? == $id or .name? == $name)
        | .source.path?]
      | map(select(type == "string" and length > 0))
      | unique[]
    ' <<<"$listing"
  ) || die "Codex's machine-readable plugin listing is invalid"

  CODEX_PLUGIN_INSTALL_PATH=''
  while IFS= read -r path; do
    if [[ -n "$path" ]]; then
      CODEX_PLUGIN_INSTALL_PATH="$path"
      count=$((count + 1))
    fi
  done <<<"$paths"

  if [[ "$count" -ne 1 ]]; then
    die "expected exactly one installed $PLUGIN_ID source.path; found $count"
  fi

  [[ "$CODEX_PLUGIN_INSTALL_PATH" == /* ]] \
    || die "installed $PLUGIN_ID source.path is not absolute: $CODEX_PLUGIN_INSTALL_PATH"
  [[ -d "$CODEX_PLUGIN_INSTALL_PATH" ]] \
    || die "installed $PLUGIN_ID source.path is not a directory: $CODEX_PLUGIN_INSTALL_PATH"
  [[ -f "$CODEX_PLUGIN_INSTALL_PATH/.codex-plugin/plugin.json" ]] \
    || die "installed $PLUGIN_ID Codex artifact has no plugin manifest: $CODEX_PLUGIN_INSTALL_PATH"
  jq -e --arg name "$PLUGIN_NAME" '.name == $name' \
    "$CODEX_PLUGIN_INSTALL_PATH/.codex-plugin/plugin.json" >/dev/null \
    || die "installed Codex artifact manifest is not for $PLUGIN_NAME: $CODEX_PLUGIN_INSTALL_PATH"

  CODEX_PLUGIN_INSTALL_PATH="$(cd "$CODEX_PLUGIN_INSTALL_PATH" && pwd -P)"
  CODEX_PACKAGE_ROOT="$(cd "$CODEX_PLUGIN_INSTALL_PATH/.." && pwd -P)"
  [[ -d "$CODEX_PACKAGE_ROOT/external-skills" ]] \
    || die "installed Codex package has no portable skill source: $CODEX_PACKAGE_ROOT"
  [[ -d "$CODEX_PACKAGE_ROOT/scripts" ]] \
    || die "installed Codex package has no wrapper scripts: $CODEX_PACKAGE_ROOT"
  ok "resolved installed Codex plugin artifact: $CODEX_PLUGIN_INSTALL_PATH"
  ok "resolved installed orchestration package: $CODEX_PACKAGE_ROOT"
}

install_codex_host
resolve_codex_plugin_install_path

if [[ "$host" != codex ]]; then

# ---- step 1: uninstall current plugin if present ----------------------------

is_plugin_installed() {
  local plugin_name="${1:-$PLUGIN_NAME}"
  local plugin_id="${2:-$PLUGIN_ID}"
  claude plugin list --json 2>/dev/null \
    | jq -e --arg id "$plugin_id" --arg name "$plugin_name" '
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

if is_plugin_installed "$LEGACY_PLUGIN_NAME" "$LEGACY_PLUGIN_ID"; then
  log "legacy plugin '$LEGACY_PLUGIN_NAME' is installed — uninstalling"
  claude plugin uninstall "$LEGACY_PLUGIN_NAME" -y
  ok "uninstalled legacy plugin '$LEGACY_PLUGIN_NAME'"
fi

if is_plugin_installed "$PLUGIN_NAME" "$PLUGIN_ID"; then
  log "plugin '$PLUGIN_NAME' is currently installed — uninstalling"
  claude plugin uninstall "$PLUGIN_NAME" -y
  ok "uninstalled '$PLUGIN_NAME'"
else
  ok "plugin '$PLUGIN_NAME' is not installed yet (nothing to remove)"
fi

# ---- step 2: add or update the marketplace ---------------------------------

is_marketplace_added() {
  local marketplace_name="${1:-$MARKETPLACE_NAME}"
  # `claude plugin marketplace list` prints text. Look for the marketplace
  # name as a token; the format is "  ❯ <name>" followed by "Source: ...".
  claude plugin marketplace list 2>/dev/null \
    | grep -qE "^[[:space:]]*[❯>*•-]?[[:space:]]*${marketplace_name}([[:space:]]|$)"
}

if is_marketplace_added "$LEGACY_MARKETPLACE_NAME"; then
  log "removing legacy marketplace '$LEGACY_MARKETPLACE_NAME'"
  claude plugin marketplace remove "$LEGACY_MARKETPLACE_NAME"
  ok "legacy marketplace removed"
fi

if is_marketplace_added "$MARKETPLACE_NAME"; then
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

else
  PLUGIN_INSTALL_PATH="$CODEX_PACKAGE_ROOT"
fi

# ---- step 5: de-duplicate skill dirs, then sync the external CLI lanes -----
#
#   - Claude loads the plugin's skills from the plugin cache. Any same-named
#     copy in ~/.claude/skills would double-install → cleared, never copied.
#   - Codex and Grok require the exact portable set in their own skill dirs. The wrappers
#     inject "Honor the step-specific skill <name>", so the body must exist
#     CLI-side → cleared of every plugin-managed name, then EXACTLY the
#     portable set is installed. An external-skills/ body wins when supplied,
#     followed by a Codex-specific body and then the shared skill body.
#
# Host-only skills such as conductor, writing-plans, and codex-dispatch remain
# plugin-provided and are never copied into a user skill directory. v1
# leftovers (lbyl-*, look-before-you-leap) are cleared everywhere. Skills the
# plugin does not own (user's own skills, a CLI's bundled skills) are never
# touched.

PORTABLE_SKILLS=(
  engineering-discipline
  test-driven-development
  refactoring
  systematic-debugging
  brainstorming
  doc-coauthoring
  frontend-design
  svg-art
  immersive-frontend
  mcp-builder
  react-native-mobile
  webapp-testing
  skill-review-standard
)

# Resolve and validate every required source before cleanup so a malformed
# installed artifact cannot leave an external lane partially cleared or synced.
PORTABLE_SKILL_SOURCES=()
for s in "${PORTABLE_SKILLS[@]}"; do
  src=''
  for candidate in \
    "$PLUGIN_INSTALL_PATH/external-skills/$s" \
    "$PLUGIN_INSTALL_PATH/codex-skills/$s" \
    "$PLUGIN_INSTALL_PATH/skills/$s"; do
    if [[ -d "$candidate" && -f "$candidate/SKILL.md" ]]; then
      src="$candidate"
      break
    fi
  done
  [[ -n "$src" ]] \
    || die "installed artifact is missing portable skill '$s': $PLUGIN_INSTALL_PATH"
  PORTABLE_SKILL_SOURCES+=("$src")
done

# Every skill name the plugin owns, derived from the installed artifact so the
# list can never drift or be influenced by the checkout invoking this script.
MANAGED_SKILLS=()
for skill_root in skills codex-skills external-skills; do
  for d in "$PLUGIN_INSTALL_PATH/$skill_root"/*/; do
    if [[ -d "$d" ]]; then
      MANAGED_SKILLS+=("$(basename "$d")")
    fi
  done
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

  local installed=0 index s src
  for ((index = 0; index < ${#PORTABLE_SKILLS[@]}; index++)); do
    s="${PORTABLE_SKILLS[$index]}"
    src="${PORTABLE_SKILL_SOURCES[$index]}"
    cp -R "$src" "$target/$s"
    installed=$((installed + 1))
  done
  ok "$lane: $installed skill(s) synced into $target"
}

# Claude: clear only — the plugin cache is the single source of these skills.
if [[ "$host" == claude || "$host" == both ]]; then
  clear_managed claude "$HOME/.claude/skills"
fi

sync_external_lane codex "$HOME/.codex/skills"
sync_external_lane grok "$HOME/.grok/skills"

# ---- final state report ----------------------------------------------------

if [[ "$host" == claude || "$host" == both ]]; then
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
fi

echo ""
if [[ "$host" == codex ]]; then
  ok "done. Start a new Codex session to pick up the plugin and synced skills."
else
  ok "done. Restart Claude Code (or run /reload-plugins in an open session) to pick up the install."
fi
