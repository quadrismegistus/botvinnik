#!/usr/bin/env bash
#
# Anchor our (web / WASM) bot ELO scale to Maia's lichess-anchored human bands.
# Plays our WASM Stockfish bands against Maia nets (maia:1100…1900) plus internal
# ladders, then Bradley-Terry fits. Run in your own terminal:
#
#     bash scripts/run-maia-calibration.sh
#
# Fast (no movetime — sampler + Maia moves are ~instant), ~a few minutes. It
# downloads the 5 Maia nets (~17 MB total) to data/maia-models on first run and
# the WASM engine wrapper if missing. Resume-safe (checkpointed). When done, tell
# Claude "maia calibration done" and it will read the fit (our scale in lichess
# terms) and cross-check against the real @maia lichess bot ratings.
#
set -euo pipefail
cd "$(dirname "$0")/.."

# rebuild the WASM engine wrapper (gitignored) if missing
if [ ! -f scripts/wasm-engine/stockfish.js ]; then
	echo ">> setting up scripts/wasm-engine"
	mkdir -p scripts/wasm-engine
	cp vendor/wasm/stockfish.js scripts/wasm-engine/stockfish.js
	cp vendor/wasm/stockfish.wasm scripts/wasm-engine/stockfish.wasm
	printf '{"type":"commonjs"}\n' >scripts/wasm-engine/package.json
	printf '#!/bin/sh\nDIR=$(cd "$(dirname "$0")" && pwd)\nexec node "$DIR/stockfish.js"\n' >scripts/wasm-engine/run.sh
	chmod +x scripts/wasm-engine/run.sh
fi

# Maia internal ladder (does each band really sit ~100 apart, or is it
# compressed?) + our WASM bands bracketed against Maia + our internal ladder.
# Numeric ids are our requested ELO through the WASM botSpec; maia:N is a net.
PAIRS="maia:1100~maia:1300,maia:1300~maia:1500,maia:1500~maia:1700,maia:1700~maia:1900,maia:1100~maia:1500,maia:1500~maia:1900,\
1100~maia:1100,1300~maia:1300,1500~maia:1500,1700~maia:1700,1900~maia:1900,\
1300~maia:1500,1500~maia:1300,1700~maia:1500,\
1100~1300,1300~1500,1500~1700,1700~1900"

echo "============================================================"
echo " Maia anchoring run — WASM bands vs Maia (n=200)"
echo "============================================================"
npx tsx scripts/calibrate-bots.mts \
	--engine scripts/wasm-engine/run.sh --substrate wasm \
	--pairs "$PAIRS" \
	--games 200 \
	--out data/bot-maia-anchor.json

echo "============================================================"
echo " DONE — tell Claude: \"maia calibration done\""
echo "============================================================"
