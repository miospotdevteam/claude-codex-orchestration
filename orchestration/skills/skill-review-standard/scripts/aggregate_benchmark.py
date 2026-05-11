#!/usr/bin/env python3
"""Aggregate grading results from skill evaluation runs.

Reads all *_grade.json files, computes mean/stddev/min/max for each
scoring dimension, determines pass/fail, and outputs a JSON summary.

Targets Python 3.8+ with no external dependencies beyond stdlib.
"""

import argparse
import glob
import json
import math
import os
import sys

PASS_THRESHOLD = 3.5
DIMENSIONS = ["structure", "completeness", "quality"]


def load_grade_files(results_dir):
    """Load all *_grade.json files from the results directory.

    Skips files that have parse errors or are missing score fields.
    Returns a list of parsed grade dicts.
    """
    pattern = os.path.join(results_dir, "*_grade.json")
    files = sorted(glob.glob(pattern))

    if not files:
        print(
            f"Warning: no *_grade.json files found in {results_dir}",
            file=sys.stderr,
        )
        return []

    grades = []
    for fpath in files:
        try:
            with open(fpath, encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError) as exc:
            print(
                f"Warning: skipping {fpath}: {exc}",
                file=sys.stderr,
            )
            continue

        # Validate that required dimensions exist with scores
        if "error" in data:
            print(
                f"Warning: skipping {fpath}: grading error — {data['error']}",
                file=sys.stderr,
            )
            continue

        valid = True
        for dim in DIMENSIONS:
            entry = data.get(dim)
            if not isinstance(entry, dict) or "score" not in entry:
                print(
                    f"Warning: skipping {fpath}: missing or invalid '{dim}' field",
                    file=sys.stderr,
                )
                valid = False
                break

        if valid:
            grades.append({"file": os.path.basename(fpath), "data": data})

    return grades


def compute_stats(values):
    """Compute mean, stddev, min, max for a list of numbers.

    Returns a dict. Handles edge cases (empty list, single value).
    """
    if not values:
        return {"mean": 0.0, "stddev": 0.0, "min": 0, "max": 0, "n": 0}

    n = len(values)
    mean = sum(values) / n

    if n > 1:
        variance = sum((x - mean) ** 2 for x in values) / (n - 1)
        stddev = math.sqrt(variance)
    else:
        stddev = 0.0

    return {
        "mean": round(mean, 2),
        "stddev": round(stddev, 2),
        "min": min(values),
        "max": max(values),
        "n": n,
    }


def aggregate(grades):
    """Compute aggregate statistics from a list of grade results.

    Returns a dict with per-dimension stats, overall score, and
    pass/fail verdict.
    """
    dim_scores = {dim: [] for dim in DIMENSIONS}

    for grade in grades:
        data = grade["data"]
        for dim in DIMENSIONS:
            score = data[dim]["score"]
            # Clamp to 1-5 range
            score = max(1, min(5, int(score)))
            dim_scores[dim].append(score)

    dim_stats = {}
    all_means = []
    for dim in DIMENSIONS:
        stats = compute_stats(dim_scores[dim])
        dim_stats[dim] = stats
        all_means.append(stats["mean"])

    overall_mean = round(sum(all_means) / len(all_means), 2) if all_means else 0.0
    passed = overall_mean >= PASS_THRESHOLD

    # Per-run breakdown
    per_run = []
    for grade in grades:
        data = grade["data"]
        run_scores = {}
        for dim in DIMENSIONS:
            run_scores[dim] = data[dim]["score"]
        run_total = sum(run_scores.values()) / len(DIMENSIONS)
        per_run.append({
            "file": grade["file"],
            "scores": run_scores,
            "mean": round(run_total, 2),
        })

    return {
        "dimensions": dim_stats,
        "overall_mean": overall_mean,
        "pass_threshold": PASS_THRESHOLD,
        "passed": passed,
        "verdict": "PASS" if passed else "FAIL",
        "total_runs": len(grades),
        "per_run": per_run,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Aggregate grading results from skill evaluation runs"
    )
    parser.add_argument(
        "--results-dir",
        required=True,
        help="Directory containing *_grade.json files",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Path to write aggregated results (default: stdout)",
    )
    args = parser.parse_args()

    if not os.path.isdir(args.results_dir):
        print(
            f"Error: results directory not found: {args.results_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    grades = load_grade_files(args.results_dir)

    if not grades:
        print("Error: no valid grade files found", file=sys.stderr)
        sys.exit(1)

    result = aggregate(grades)

    output_text = json.dumps(result, indent=2, ensure_ascii=False) + "\n"

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output_text)
        print(f"Aggregated results written to {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(output_text)


if __name__ == "__main__":
    main()
