#!/usr/bin/env bash
# One-shot: create miospotdevteam/claude-codex-orchestration on GitHub and push.
# Authored by Claude on the user's behalf; executed by the user.
# Safe to re-run — handles the stale-remote case from a prior partial run.

set -euo pipefail

REPO='miospotdevteam/claude-codex-orchestration'
DESC='Conductor-mode orchestrator for Claude Code: persistent plans, direction-locked Codex impl/verify, bounded prompt-contract I/O, read-only hooks. v2 rewrite of look-before-you-leap.'

# ---- preflight ----

cd "$(dirname "$0")"

if [[ ! -f plugin.json ]]; then
  echo "ERROR: plugin.json not found in $(pwd). Are you running from the repo root?" >&2
  exit 1
fi

if ! command -v gh >/dev/null; then
  echo "ERROR: gh CLI not on PATH." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

# Must be inside a git work tree with at least one commit
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not a git repository. Run 'git init -b main && git add . && git commit -m \"...\"' first." >&2
  exit 1
fi

if ! git rev-parse HEAD >/dev/null 2>&1; then
  echo "ERROR: no commits yet. Make the initial commit before running this script." >&2
  exit 1
fi

# ---- clean stale origin if a prior run left one ----

if git remote get-url origin >/dev/null 2>&1; then
  echo "→ removing stale 'origin' remote from a prior failed run"
  git remote remove origin
fi

# ---- check whether the repo already exists on GitHub ----

if gh repo view "$REPO" >/dev/null 2>&1; then
  echo "→ repo already exists on GitHub; wiring local 'origin' and pushing"
  git remote add origin "git@github.com:${REPO}.git"
  git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
else
  echo "→ creating $REPO (public) and pushing"
  gh repo create "$REPO" \
    --public \
    --source=. \
    --remote=origin \
    --description "$DESC" \
    --push
fi

# ---- verify final state ----

echo ""
echo "=== final state ==="
git remote -v
echo ""
git log --oneline -1
echo ""
gh repo view "$REPO" --json url,visibility,description -q '"URL:        " + .url + "\nVisibility: " + .visibility + "\nDescription: " + .description' 2>/dev/null || echo "(gh repo view failed; check https://github.com/${REPO})"
