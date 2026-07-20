#!/usr/bin/env bash
#
# Sampled-Maia placement. Our argmax Maia bands all measured ~1850
# (strength-compressed); lichess's @Humaia (same maia-1400 net, moves SAMPLED
# from the policy) rates 1330-1380 over 20k+ human games — at label. This run
# measures our maia-t1:BAND (temperature-1 sampling) against the calibrated
# shaped bands and honest ucielo rulers to see whether sampling recovers the
# nominal ladder. If it does, the roster's Maias can drop to their real bands
# and cover 1100-1900 honestly.
#
#     bash scripts/run-maia-sampled.sh     # n=60, ~30-60 min, resumable
#
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f scripts/wasm-engine/stockfish.js ]; then
	echo ">> setting up scripts/wasm-engine"
	mkdir -p scripts/wasm-engine
	cp vendor/wasm/stockfish.js scripts/wasm-engine/stockfish.js
	cp vendor/wasm/stockfish.wasm scripts/wasm-engine/stockfish.wasm
	printf '{"type":"commonjs"}\n' >scripts/wasm-engine/package.json
	printf '#!/bin/sh\nDIR=$(cd "$(dirname "$0")" && pwd)\nexec node "$DIR/stockfish.js"\n' >scripts/wasm-engine/run.sh
	chmod +x scripts/wasm-engine/run.sh
fi

# sampled ladder + brackets vs shaped bands + honest rulers + one argmax
# control pair (same net, both selection rules — isolates the sampling effect)
PAIRS="maia-t1:1100~maia-t1:1500,maia-t1:1500~maia-t1:1900,\
maia-t1:1100~shaped:900,maia-t1:1100~shaped:1200,maia-t1:1500~shaped:1200,\
maia-t1:1500~ucielo:1320:mt400,maia-t1:1900~ucielo:1320:mt400,maia-t1:1900~ucielo:1600:mt400,\
maia-t1:1500~maia:1500,\
shaped:1200~ucielo:1320:mt400"

echo "============================================================"
echo " Sampled Maia (temperature 1) vs our scale (n=60)"
echo "============================================================"
npx tsx scripts/calibrate-bots.mts \
	--engine scripts/wasm-engine/run.sh --substrate wasm \
	--pairs "$PAIRS" \
	--games 60 \
	--shaped-depth 12 --shaped-multipv 12 \
	--out data/bot-maia-sampled.json

echo "============================================================"
echo " DONE — tell Claude: \"maia sampled run done\""
echo "============================================================"
