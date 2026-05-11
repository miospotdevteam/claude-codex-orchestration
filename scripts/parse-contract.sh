#!/usr/bin/env bash
set -euo pipefail

raw_input="$(mktemp)"
trap 'rm -f "$raw_input"' EXIT

cat >"$raw_input"

python3 - "$raw_input" <<'PY'
import json
import re
import sys

OPEN = "=== ORCHESTRATION-CONTRACT ==="
CLOSE = "=== END-CONTRACT ==="


def die(message: str) -> None:
    print(f"parse-contract: {message}", file=sys.stderr)
    sys.exit(1)


def strip_optional_marker(line: str) -> str:
    stripped = line.strip()
    if len(stripped) >= 2 and stripped[0] in "-*" and stripped[1].isspace():
        return stripped[2:].strip()
    return stripped


try:
    with open(sys.argv[1], "rb") as handle:
        text = handle.read().decode("utf-8", errors="replace")
except OSError as exc:
    die(f"unable to read stdin fixture: {exc}")

text = text.replace("\r\n", "\n").replace("\r", "\n")

open_matches = list(re.finditer(rf"(?m)^{re.escape(OPEN)}$", text))
close_matches = list(re.finditer(rf"(?m)^{re.escape(CLOSE)}$", text))

if not open_matches:
    if close_matches:
        die("closing sentinel found without opening sentinel")
    die("no contract block found")

open_match = open_matches[-1]
close_match = next((match for match in close_matches if match.start() > open_match.end()), None)
if close_match is None:
    die("opening sentinel found without closing sentinel")

if not re.fullmatch(r"\s*", text[close_match.end():]):
    die("trailing non-whitespace content after closing sentinel")

block = text[open_match.end():close_match.start()]

summary_parts = []
verdict = None
findings = []
files_touched = []
seen_summary = False
seen_verdict = False
seen_findings = False
seen_files_touched = False
section = None

for raw_line in block.split("\n"):
    candidate = strip_optional_marker(raw_line)

    if candidate.startswith("Summary:"):
        seen_summary = True
        section = "summary"
        value = candidate[len("Summary:"):].strip()
        if value:
            summary_parts.append(value)
        continue

    if candidate.startswith("Verdict:"):
        seen_verdict = True
        section = "verdict"
        value = candidate[len("Verdict:"):].strip()
        if value not in {"PASS", "FINDINGS", "FAIL"}:
            die(f"malformed verdict: {value or '<empty>'}")
        verdict = value
        continue

    if candidate == "Findings:":
        seen_findings = True
        section = "findings"
        continue

    if candidate == "FilesTouched:":
        seen_files_touched = True
        section = "files_touched"
        continue

    if not raw_line.strip():
        continue

    if section == "summary":
        summary_parts.append(raw_line.strip())
    elif section == "findings":
        findings.append(strip_optional_marker(raw_line))
    elif section == "files_touched":
        files_touched.append(strip_optional_marker(raw_line))

if not seen_summary or not " ".join(summary_parts).strip():
    die("missing Summary field")
if not seen_verdict or verdict is None:
    die("missing Verdict field")
if not seen_findings and verdict != "PASS":
    die("missing Findings field")
if not seen_files_touched:
    die("missing FilesTouched field")

json.dump(
    {
        "summary": " ".join(summary_parts).strip(),
        "verdict": verdict,
        "findings": findings,
        "filesTouched": files_touched,
    },
    sys.stdout,
    separators=(",", ":"),
)
sys.stdout.write("\n")
PY
