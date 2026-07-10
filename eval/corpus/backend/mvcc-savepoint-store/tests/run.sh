#!/usr/bin/env bash
# Scorer entry point. Usage: run.sh <candidate_dir>
# Prints one line per test, then exactly: RESULT <passed> <total>.
# Exits 0 iff passed == total.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CAND="${1:?usage: run.sh <candidate_dir>}"
python3 "$HERE/harness.py" "$CAND"
