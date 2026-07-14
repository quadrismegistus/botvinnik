#!/usr/bin/env bash
#
# Full human-anchoring pass built on Maia-3 (the ELO-conditioned net that
# actually spans the range). Connects three scales in one Bradley-Terry fit:
#
#   our WASM Stockfish bands  <->  Maia-3 (dialed)  <->  Maia-1 bands
#
# Maia-1 bands have REAL lichess ratings (@maia1=1572 rapid, @maia5=1643,
# @maia9=1701), so the Maia-1 bridge pins Maia-3's dial to measured lichess
# ratings, and the WASM-vs-Maia-3 pairs then place OUR scale in those terms —
# across the whole range, not just the club cluster Maia-1 alone gave us.
#
#     bash scripts/run-maia3-anchor.sh
#
# SLOW (~1-1.5 hr): Maia-vs-Maia games run long and inference is serialized.
# Resume-safe (checkpointed). Downloads the 44MB Maia-3 net + Maia-1 nets on
# first run. When done, tell Claude "maia3 anchor done".
#
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f scripts/wasm-engine/stockfish.js ]; then
	echo ">> setting up scripts/wasm-engine"
	mkdir -p scripts/wasm-engine
	cp static/wasm/stockfish.js scripts/wasm-engine/stockfish.js
	cp static/wasm/stockfish.wasm scripts/wasm-engine/stockfish.wasm
	printf '{"type":"commonjs"}\n' >scripts/wasm-engine/package.json
	printf '#!/bin/sh\nDIR=$(cd "$(dirname "$0")" && pwd)\nexec node "$DIR/stockfish.js"\n' >scripts/wasm-engine/run.sh
	chmod +x scripts/wasm-engine/run.sh
fi

# Maia-3 internal spacing (is the dial even across the range?) +
# Maia-3<->Maia-1 bridge (pin to measured lichess ratings) +
# Maia-3<->our WASM bands (place our scale). Numeric ids = our requested ELO
# through the WASM botSpec.
PAIRS="maia3:600~maia3:900,maia3:900~maia3:1200,maia3:1200~maia3:1500,maia3:1500~maia3:1900,maia3:600~maia3:1900,\
maia3:1100~maia:1100,maia3:1500~maia:1500,maia3:1900~maia:1900,\
900~maia3:900,1200~maia3:1200,1500~maia3:1500,1800~maia3:1800"

echo "============================================================"
echo " Maia-3 anchoring — WASM bands <-> Maia-3 <-> Maia-1 (n=100)"
echo "============================================================"
npx tsx scripts/calibrate-bots.mts \
	--engine scripts/wasm-engine/run.sh --substrate wasm \
	--pairs "$PAIRS" \
	--games 100 --max-plies 120 \
	--out data/bot-maia3-anchor.json

echo "============================================================"
echo " DONE — tell Claude: \"maia3 anchor done\""
echo "============================================================"
