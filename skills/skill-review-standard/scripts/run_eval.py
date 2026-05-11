#!/usr/bin/env python3
"""Run a skill evaluation by invoking claude -p.

For each run:
  1. Invokes claude -p with the skill loaded and the test prompt
  2. Saves output to {output-dir}/run_{i}.md
  3. Invokes claude -p again as a grader to score the output
  4. Saves grading results to {output-dir}/run_{i}_grade.json

Targets Python 3.8+ with no external dependencies beyond stdlib.
"""

import argparse
import json
import os
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
from utils import parse_skill_md


GRADER_PROMPT_TEMPLATE = """\
You are a strict grader evaluating the output of a Claude Code skill.

The skill was asked to respond to this prompt:
---
{prompt}
---

Here is the skill's output:
---
{output}
---

Score the output on three dimensions, each from 1 to 5:

1. **structure** (1-5): Does the output follow a consistent, well-organized format? \
Is it easy to navigate? Are sections logical?
2. **completeness** (1-5): Does the output address all aspects of the prompt? \
Are there gaps or missing pieces?
3. **quality** (1-5): Is the output genuinely useful? Would it help a real user? \
Is the advice accurate and actionable?

Respond with ONLY valid JSON (no markdown fences, no extra text) in this exact format:
{{
  "structure": {{"score": <int>, "justification": "<brief>"}},
  "completeness": {{"score": <int>, "justification": "<brief>"}},
  "quality": {{"score": <int>, "justification": "<brief>"}}
}}
"""


def run_claude(prompt, timeout=300):
    """Invoke claude -p and return stdout. Returns None on failure."""
    try:
        result = subprocess.run(
            ["claude", "-p", prompt],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if result.returncode != 0:
            print(
                f"Warning: claude exited with code {result.returncode}",
                file=sys.stderr,
            )
            if result.stderr:
                print(f"  stderr: {result.stderr[:500]}", file=sys.stderr)
        return result.stdout
    except FileNotFoundError:
        print(
            "Error: 'claude' CLI not found on PATH. Install it first.",
            file=sys.stderr,
        )
        return None
    except subprocess.TimeoutExpired:
        print("Error: claude timed out", file=sys.stderr)
        return None


def parse_grade_json(text):
    """Try to extract valid JSON from grader output.

    The grader is asked for raw JSON, but sometimes wraps it in
    markdown fences. Handle both cases.
    """
    if not text:
        return None

    # Strip markdown code fences if present
    stripped = text.strip()
    if stripped.startswith("```"):
        lines = stripped.split("\n")
        # Remove first and last fence lines
        lines = [l for l in lines if not l.strip().startswith("```")]
        stripped = "\n".join(lines).strip()

    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        # Try to find JSON object in the text
        start = stripped.find("{")
        end = stripped.rfind("}")
        if start >= 0 and end > start:
            try:
                return json.loads(stripped[start : end + 1])
            except json.JSONDecodeError:
                pass
    return None


def run_single_eval(skill_dir, prompt, output_dir, run_index):
    """Execute one evaluation run: generate output then grade it."""
    skill_md_path = os.path.join(skill_dir, "SKILL.md")
    parsed = parse_skill_md(skill_md_path)

    if parsed is None:
        print(f"Error: could not parse {skill_md_path}", file=sys.stderr)
        return False

    # Build the generation prompt
    gen_prompt = (
        f"Read and follow the skill instructions below, then complete the task.\n\n"
        f"=== SKILL ===\n{parsed['raw']}\n=== END SKILL ===\n\n"
        f"Task: {prompt}"
    )

    print(f"  Run {run_index}: generating output...", file=sys.stderr)
    output = run_claude(gen_prompt)
    if output is None:
        return False

    # Save output
    output_path = os.path.join(output_dir, f"run_{run_index}.md")
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(output)
    print(f"  Run {run_index}: saved output to {output_path}", file=sys.stderr)

    # Grade the output
    print(f"  Run {run_index}: grading...", file=sys.stderr)
    grader_prompt = GRADER_PROMPT_TEMPLATE.format(
        prompt=prompt, output=output[:10000]  # Cap at 10k chars for grading
    )
    grade_text = run_claude(grader_prompt)
    if grade_text is None:
        return False

    grade = parse_grade_json(grade_text)
    if grade is None:
        print(
            f"  Run {run_index}: WARNING — could not parse grading JSON. "
            f"Raw output saved for inspection.",
            file=sys.stderr,
        )
        grade = {
            "error": "Failed to parse grader output",
            "raw": grade_text[:2000],
        }

    # Add metadata
    grade["_meta"] = {
        "run_index": run_index,
        "model": "machine-default",
        "skill_dir": skill_dir,
        "prompt": prompt,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }

    grade_path = os.path.join(output_dir, f"run_{run_index}_grade.json")
    with open(grade_path, "w", encoding="utf-8") as f:
        json.dump(grade, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"  Run {run_index}: saved grade to {grade_path}", file=sys.stderr)

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Run a skill evaluation with claude -p"
    )
    parser.add_argument(
        "--skill-dir",
        required=True,
        help="Path to the skill directory containing SKILL.md",
    )
    parser.add_argument(
        "--prompt",
        required=True,
        help="The test prompt to evaluate",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Where to write results",
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=3,
        help="Number of evaluation runs (default: 3)",
    )
    args = parser.parse_args()

    # Validate inputs
    skill_md = os.path.join(args.skill_dir, "SKILL.md")
    if not os.path.isfile(skill_md):
        print(f"Error: SKILL.md not found at {skill_md}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(args.output_dir, exist_ok=True)

    print(
        f"Eval: {args.runs} run(s) for {args.skill_dir}",
        file=sys.stderr,
    )

    failures = 0
    for i in range(1, args.runs + 1):
        ok = run_single_eval(
            args.skill_dir, args.prompt, args.output_dir, i
        )
        if not ok:
            failures += 1

    # Summary
    print(file=sys.stderr)
    print(
        f"Done: {args.runs - failures}/{args.runs} runs succeeded. "
        f"Results in {args.output_dir}",
        file=sys.stderr,
    )
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
