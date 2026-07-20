#!/usr/bin/env bash
#
# Retro cohort: herohde/morlock's re-implementations of TUROCHAMP (1948),
# BERNSTEIN (1957) and SARGON (1978), at the same configs as their lichess
# bots — which have big-sample human-pool ratings (bernstein-2ply ≈ 1198
# rapid, sargon-1ply ≈ 1228, turochamp-1ply ≈ 1300). More two-sided bridges
# in the beginner band, plus cross-family texture vs Squares/dala/jsce.
# (Ryan lost to bernstein-2ply on lichess, so this cohort is personal.)
#
#     bash scripts/run-retro-gym.sh     # n=60, resumable
#
set -euo pipefail
cd "$(dirname "$0")/.."

for f in scripts/engines/retro/bernstein scripts/engines/retro/sargon scripts/engines/retro/turochamp; do
	[ -x "$f" ] || { echo "missing $f — build with: (cd scripts/engines/morlock-src && go build -o ../retro/NAME ./cmd/NAME)"; exit 1; }
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

PAIRS="bernstein:2ply~sargon:1ply,sargon:1ply~turochamp:1ply,turochamp:1ply~bernstein:2ply,\
bernstein:2ply~shaped:900,bernstein:2ply~shaped:1200,sargon:1ply~shaped:900,turochamp:1ply~shaped:1200,\
bernstein:2ply~dala:900,sargon:1ply~dala:900,\
bernstein:2ply~jsce:2,\
turochamp:1ply~ucielo:1320:mt400,\
shaped:1200~ucielo:1320:mt400"

echo "============================================================"
echo " Retro cohort — 1948/1957/1978 vs our scale (n=60)"
echo "============================================================"
npx tsx scripts/calibrate-bots.mts \
	--engine scripts/wasm-engine/run.sh --substrate wasm \
	--ext-config scripts/gym-ext.json \
	--pairs "$PAIRS" \
	--games 60 \
	--shaped-depth 12 --shaped-multipv 12 \
	--out data/bot-retro-gym.json

echo "============================================================"
echo " DONE — tell Claude: \"retro gym done\""
echo "============================================================"
