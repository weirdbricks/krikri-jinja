#!/usr/bin/env python3
"""Compares the two renderer outputs line by line.

Compatibility rules:
- both ok: outputs must be byte-identical
- both error: compatible (error text intentionally differs; engines have
  different exception vocabularies)
- one ok, one error: DIVERGENCE
"""
import json
import sys


def load(path):
    results = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            results[r["name"]] = r
    return results


py = load(sys.argv[1] if len(sys.argv) > 1 else "py.jsonl")
cr = load(sys.argv[2] if len(sys.argv) > 2 else "cr.jsonl")

mismatches = []
both_error = 0
ok = 0
for name in sorted(set(py) | set(cr)):
    p = py.get(name, {"output": None, "error": "MISSING"})
    c = cr.get(name, {"output": None, "error": "MISSING"})
    if p["error"] and c["error"]:
        both_error += 1
        continue
    if p["error"] or c["error"]:
        mismatches.append((name, "error-mismatch", p["error"], c["error"], p["output"], c["output"]))
        continue
    if p["output"] == c["output"]:
        ok += 1
    else:
        mismatches.append((name, "output", None, None, p["output"], c["output"]))

print(f"total: {len(set(py) | set(cr))}  identical: {ok}  both-error: {both_error}  divergent: {len(mismatches)}")
for name, kind, perr, cerr, pout, cout in mismatches:
    print(f"\n=== {name} ({kind})")
    if perr:
        print(f"  python error: {perr}")
    if cerr:
        print(f"  crystal error: {cerr}")
    if pout is not None:
        print(f"  python: {pout!r}")
    if cout is not None:
        print(f"  crystal: {cout!r}")
sys.exit(1 if mismatches else 0)
