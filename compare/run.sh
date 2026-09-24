#!/bin/bash
# Differential test harness: renders compare/cases.json with both real
# Jinja2 (python) and krikri-jinja (crystal), then diffs the results.
#
#   ./compare/run.sh            # run everything, print divergences
# Exits nonzero on any divergence.
set -e
cd "$(dirname "$0")/.."

python3 compare/gen_cases.py > /dev/null
python3 compare/render.py compare/cases.json > /tmp/krikri-jinja-py.jsonl
crystal run compare/render.cr -- compare/cases.json > /tmp/krikri-jinja-cr.jsonl 2>/dev/null
python3 compare/compare.py /tmp/krikri-jinja-py.jsonl /tmp/krikri-jinja-cr.jsonl
