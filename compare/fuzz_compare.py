#!/usr/bin/env python3
"""Diffs fuzzed py/cr JSONL with generator-address normalization.

Python renders lazy generators/reverse-iterators as
'<... object at 0xADDR>' which no engine can byte-match, so cases whose
python output contains an address are counted as skipped, and any
remaining 0x... addresses are normalized before comparing.
"""
import json
import re
import sys

ADDR = re.compile(r"at 0x[0-9a-f]+")


def load(path):
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                r = json.loads(line)
                out[r["name"]] = r
    return out


def main():
    py = load(sys.argv[1])
    cr = load(sys.argv[2])
    seed = sys.argv[3] if len(sys.argv) > 3 else "?"
    divergences = []
    skipped = both_err = ok = 0
    for name in sorted(py):
        p = py[name]
        c = cr.get(name, {"output": None, "error": "MISSING"})
        if ADDR.search(p.get("output") or ""):
            skipped += 1
            continue
        pe, ce = p.get("error"), c.get("error")
        if pe and ce:
            both_err += 1
            continue
        if pe or ce:
            divergences.append((name, "error-mismatch",
                                pe, ce,
                                p.get("output"), c.get("output")))
            continue
        po = ADDR.sub("at ADDR", p.get("output") or "")
        co = ADDR.sub("at ADDR", c.get("output") or "")
        if po == co:
            ok += 1
        else:
            divergences.append((name, "output", None, None,
                                p.get("output"), c.get("output")))
    compared = ok + len(divergences)
    rate = 100.0 * len(divergences) / compared if compared else 0.0
    for name, kind, pe, ce, po, co in divergences[:12]:
        print(f"=== {name} ({kind})")
        if pe:
            print(f"  python error: {pe}")
        if ce:
            print(f"  crystal error: {ce}")
        if po is not None and not pe:
            print(f"  python: {po[:160]!r}")
        if co is not None and not ce:
            print(f"  crystal: {co[:160]!r}")
    print(f"seed={seed} total={len(py)} skipped-addr={skipped} both-error={both_err} "
          f"compared-ok={compared} divergent={len(divergences)} divergence={rate:.2f}%")
    sys.exit(1 if divergences else 0)


if __name__ == "__main__":
    main()
