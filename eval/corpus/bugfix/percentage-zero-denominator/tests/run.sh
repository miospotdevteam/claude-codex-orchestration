#!/usr/bin/env bash
# Scorer entry point. Usage: run.sh <candidate_dir>
# Prints, as its final stdout line, exactly: RESULT <passed> <total>
# Exits 0 iff passed == total.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CAND="${1:?usage: run.sh <candidate_dir>}"
node "$HERE/harness.js" "$CAND"
