#!/usr/bin/env bash
#
# Locate the shaped-blunder sampler (shapedBotMove) on our calibrated WASM ELO
# scale. shaped:N runs a STRONG depth-12 MultiPV search and picks its move with
# the human-error model (shapedParams(N)); the weakening is all in the params,
# not the search. This run measures (a) shaped's own internal spread and
# monotonicity, and (b) where each shaped band lands against our anchored numeric
# bands — so we can then tune shapedParams to hit the target ELOs.
#
# EXPECT the first pass to show shaped playing STRONGER than its label (coherent
# + bounded beats the swingy sampler — the anchoring run showed our sampler is
# "wrong-kind-of-weak"). That's the point: the delta tells us how much to raise
# blunderProb/windowPct. Run in your own terminal (resume-safe, checkpointed):
#
#     bash scripts/run-shaped-calibration.sh
#
# Slower than the sampler runs (depth-12 searches, not depth-1): ballpark
# 15-25 games/min on WASM, so ~1 hour for the full set. Ctrl-C and re-run to
# resume. When done, tell Claude "shaped calibration done".
#
set -euo pipefail
cd "$(dirname "$0")/.."

# rebuild the WASM engine wrapper (gitignored) if missing
if [ ! -f scripts/wasm-engine/stockfish.js ]; then
	echo ">> setting up scripts/wasm-engine"
	mkdir -p scripts/wasm-engine
	cp static/wasm/stockfish.js scripts/wasm-engine/stockfish.js
	cp static/wasm/stockfish.wasm scripts/wasm-engine/stockfish.wasm
	printf '{"type":"commonjs"}\n' >scripts/wasm-engine/package.json
	printf '#!/bin/sh\nDIR=$(cd "$(dirname "$0")" && pwd)\nexec node "$DIR/stockfish.js"\n' >scripts/wasm-engine/run.sh
	chmod +x scripts/wasm-engine/run.sh
fi

# shaped internal ladder (does the params ramp give a monotonic spread?) +
# each shaped band bracketed against our anchored numeric bands (absolute
# placement) + a numeric anchor ladder (ids >=1320 anchor the whole fit).
PAIRS="shaped:600~shaped:900,shaped:900~shaped:1200,shaped:1200~shaped:1500,shaped:600~shaped:1500,\
shaped:600~900,shaped:600~1200,shaped:900~1200,shaped:900~1500,shaped:1200~1500,shaped:1200~1800,shaped:1500~1800,shaped:1500~2100,\
1500~1800,1800~2100"

echo "============================================================"
echo " Shaped-blunder calibration — shaped bands vs WASM numeric (n=100)"
echo "============================================================"
npx tsx scripts/calibrate-bots.mts \
	--engine scripts/wasm-engine/run.sh --substrate wasm \
	--pairs "$PAIRS" \
	--games 100 \
	--shaped-depth 12 --shaped-multipv 12 \
	--out data/bot-shaped-calib.json

echo "============================================================"
echo " DONE — tell Claude: \"shaped calibration done\""
echo "============================================================"
