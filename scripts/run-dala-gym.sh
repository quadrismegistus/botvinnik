#!/usr/bin/env bash
#
# Dala cohort: the two-sided bridge run. The dala nets (hrschubert/dala-training,
# BT4 imitation per lichess bracket, played by POLICY SAMPLING — select:"policy"
# in gym-ext.json) have REAL lichess human-pool ratings: 700→911, 900→1095,
# 1300→1315 rapid. Running the same nets+selection locally against our
# calibrated bots gives, for each: (engine-pool position on our scale) ↔
# (known human-pool lichess rating). Two uses:
#   1. Quantify the imitation pool-penalty at the LOW end (maia showed ~400 pts
#      at 1500; is it smaller at 900?).
#   2. dala-vs-shaped is the best available proxy for "how will a Square feel
#      to a human of that bracket" short of Ryan playing.
#
# Needs: scripts/engines/lc0-src built (master — brew 0.32 can't read the
# nets), dala-{700,900,1300} weights in scripts/engines/dala/.
#
#     bash scripts/run-dala-gym.sh     # n=60, resumable
#
set -euo pipefail
cd "$(dirname "$0")/.."

for f in scripts/engines/lc0-src/build/release/lc0 \
	scripts/engines/dala/dala-700-00235000.pb.gz \
	scripts/engines/dala/dala-900-00285000.pb.gz \
	scripts/engines/dala/dala-1300-00300000.pb.gz; do
	[ -e "$f" ] || { echo "missing $f"; exit 1; }
done
if [ ! -f scripts/wasm-engine/stockfish.js ]; then
	echo ">> setting up scripts/wasm-engine"
	mkdir -p scripts/wasm-engine
	cp vendor/wasm/stockfish.js scripts/wasm-engine/stockfish.js
	cp vendor/wasm/stockfish.wasm scripts/wasm-engine/stockfish.wasm
	printf '{"type":"commonjs"}\n' >scripts/wasm-engine/package.json
	printf '#!/bin/sh\nDIR=$(cd "$(dirname "$0")" && pwd)\nexec node "$DIR/stockfish.js"\n' >scripts/wasm-engine/run.sh
	chmod +x scripts/wasm-engine/run.sh
fi

# internal ladder + vs shaped Squares + vs jsce (cross-family) + one honest
# ruler pair at the top + the shaped~ucielo bridge to tie the graph
PAIRS="dala:700~dala:900,dala:900~dala:1300,\
dala:700~shaped:600,dala:700~shaped:900,dala:900~shaped:900,dala:900~shaped:1200,dala:1300~shaped:1200,\
dala:700~jsce:1,dala:900~jsce:2,\
dala:1300~ucielo:1320:mt400,\
shaped:1200~ucielo:1320:mt400"

echo "============================================================"
echo " Dala cohort — human-pool-rated imitation nets vs our scale (n=60)"
echo "============================================================"
npx tsx scripts/calibrate-bots.mts \
	--engine scripts/wasm-engine/run.sh --substrate wasm \
	--ext-config scripts/gym-ext.json \
	--pairs "$PAIRS" \
	--games 60 \
	--shaped-depth 12 --shaped-multipv 12 \
	--out data/bot-dala-gym.json

echo "============================================================"
echo " DONE — tell Claude: \"dala gym done\""
echo "============================================================"
