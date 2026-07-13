#!/usr/bin/env bash
#
# n=200 movetime-band calibration for both engines. Run this in your OWN
# terminal (no 10-min background-task cap), from anywhere:
#
#     bash scripts/run-mt-calibration.sh
#
# It resumes from checkpoints, so Ctrl-C and re-run is safe — it picks up
# where it left off. Takes ~1.5-2 hr total (movetime games are 400ms/move).
# When it finishes, tell Claude "movetime calibration done" and it will invert
# the results into the UCI_Elo top-band knots, gate, and commit.
#
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

# The WASM engine wrapper is gitignored (7MB net copy). Rebuild it from the
# shipped build if it's missing, so this script is self-contained.
if [ ! -f scripts/wasm-engine/stockfish.js ]; then
	echo ">> setting up scripts/wasm-engine (node UCI wrapper of the web engine)"
	mkdir -p scripts/wasm-engine
	cp static/wasm/stockfish.js scripts/wasm-engine/stockfish.js
	cp static/wasm/stockfish.wasm scripts/wasm-engine/stockfish.wasm
	printf '{"type":"commonjs"}\n' >scripts/wasm-engine/package.json
	cat >scripts/wasm-engine/run.sh <<'SH'
#!/bin/sh
DIR=$(cd "$(dirname "$0")" && pwd)
exec node "$DIR/stockfish.js"
SH
	chmod +x scripts/wasm-engine/run.sh
fi

echo "============================================================"
echo " [1/2] NATIVE movetime band (desktop engine) — n=200"
echo "       points 2000,2200,2400,2600,2800  (2000 = sampler bridge)"
echo "============================================================"
npx tsx scripts/calibrate-bots.mts \
	--points "2000,2200,2400,2600,2800" \
	--games 200 \
	--out data/bot-native-mt200.json

echo "============================================================"
echo " [2/2] WASM movetime band (web engine) — n=200"
echo "       points 2400,2500,2650,2800  (2400 = sampler bridge)"
echo "============================================================"
npx tsx scripts/calibrate-bots.mts \
	--engine scripts/wasm-engine/run.sh --substrate wasm \
	--points "2400,2500,2650,2800" \
	--games 200 \
	--out data/bot-wasm-mt200.json

echo "============================================================"
echo " DONE — both movetime bands calibrated (n=200)."
echo " Tell Claude: \"movetime calibration done\""
echo "============================================================"
