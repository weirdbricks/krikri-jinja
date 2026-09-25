#!/bin/bash
# Fuzz rounds vs real Jinja2: ./compare/fuzz_run.sh [rounds] [cases-per-round] [start-seed]
# Prints one progress line per round with a divergence rate. Exits nonzero
# if any round finds a divergence.
set -e
cd "$(dirname "$0")/.."
ROUNDS=${1:-5}
N=${2:-3000}
SEED0=${3:-1000}

mkdir -p /tmp/krikri-fuzz
found=0
echo "round seed    total  skipped  both-err     ok  divergent  rate"
for i in $(seq 1 "$ROUNDS"); do
  seed=$((SEED0 + i))
  cases=/tmp/krikri-fuzz/cases-$seed.json
  python3 compare/fuzz_gen.py "$seed" "$N" "$cases" > /dev/null
  timeout 280 python3 compare/render.py "$cases" > /tmp/krikri-fuzz/py-$seed.jsonl || { echo "seed $seed: python render timeout/failure"; found=1; continue; }
  timeout 280 crystal run compare/render.cr -- "$cases" > /tmp/krikri-fuzz/cr-$seed.jsonl 2>/dev/null || { echo "seed $seed: crystal render timeout/failure"; found=1; continue; }
  if python3 compare/fuzz_compare.py /tmp/krikri-fuzz/py-$seed.jsonl /tmp/krikri-fuzz/cr-$seed.jsonl "$seed"; then
    :
  else
    found=1
  fi
done
if [ "$found" -ne 0 ]; then
  echo "FUZZ: divergences found"
  exit 1
fi
echo "FUZZ: all rounds clean"
