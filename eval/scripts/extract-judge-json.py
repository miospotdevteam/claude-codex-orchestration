#!/usr/bin/env python3
"""Extract a judge's score object from a model's raw stdout.

Judge CLIs (codex/grok) often wrap their answer in prose or ```json fences
instead of emitting a bare JSON object, which makes a naive `jq` parse fail.
This scans the text for the first balanced JSON object that carries a
"scores" key with numeric A/B/C, and re-emits it in the canonical shape:

    {"scores": {"A": n, "B": n, "C": n}, "rationale": "..."}

Exit 0 and print the object on success; exit 1 if no usable object is found.
Scores are passed through unchanged (scale normalization happens downstream);
only their presence and numeric type are enforced here.
"""
import sys
import json


def find_score_objects(text):
    dec = json.JSONDecoder()
    i = 0
    n = len(text)
    while i < n:
        j = text.find("{", i)
        if j < 0:
            return
        try:
            obj, end = dec.raw_decode(text, j)
        except json.JSONDecodeError:
            i = j + 1
            continue
        yield obj
        i = end


def usable(obj):
    if not isinstance(obj, dict):
        return None
    scores = obj.get("scores")
    if not isinstance(scores, dict):
        return None
    out = {}
    for k in ("A", "B", "C"):
        v = scores.get(k)
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            return None
        out[k] = v
    return {"scores": out, "rationale": str(obj.get("rationale", ""))}


def main():
    text = sys.stdin.read()
    for obj in find_score_objects(text):
        result = usable(obj)
        if result is not None:
            print(json.dumps(result))
            return 0
    sys.stderr.write("extract-judge-json: no valid score object found in model output\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
