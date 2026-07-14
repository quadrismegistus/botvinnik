#!/usr/bin/env bash
#
# Overnight gym: locate third-party engines on our WASM scale.
#
#   - js-chess-engine levels 1-5 (via scripts/shims/jsce-uci.mjs — a JS
#     library given a UCI face). Level 1 has horizon-effect blunders: the
#     first candidate that might be ARCHITECTURALLY weak in the human range.
#   - Patricia 5.0 Skill_Level 1/3/5/7 (built from source in
#     scripts/engines/patricia-src; v5 dropped UCI_Elo — the README's
#     "skill 1 = 500" table is v3-era, so treat labels as unknown).
#
# Each engine gets: an internal ladder (is the dial monotonic?), brackets vs
# our calibrated shaped bands (cross-type placement + exploitability check),
# and honest ucielo rulers where it might reach. One shaped~ucielo pair ties
# the whole graph to the ruler. Raw ucielo specs aren't fit anchors — rebase
# on ucielo:1320 = 1320 when reading.
#
#     bash scripts/run-gym-overnight.sh     # ~2h at n=80, resumable
#
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f scripts/engines/patricia-src/engine/patricia ]; then
	echo "Patricia binary missing — build it first:"
	echo "  git clone --depth 1 https://github.com/Adam-Kulju/Patricia scripts/engines/patricia-src"
	echo "  make -C scripts/engines/patricia-src/engine"
	exit 1
fi
if [ ! -f scripts/wasm-engine/stockfish.js ]; then
	echo ">> setting up scripts/wasm-engine"
	mkdir -p scripts/wasm-engine
	cp static/wasm/stockfish.js scripts/wasm-engine/stockfish.js
	cp static/wasm/stockfish.wasm scripts/wasm-engine/stockfish.wasm
	printf '{"type":"commonjs"}\n' >scripts/wasm-engine/package.json
	printf '#!/bin/sh\nDIR=$(cd "$(dirname "$0")" && pwd)\nexec node "$DIR/stockfish.js"\n' >scripts/wasm-engine/run.sh
	chmod +x scripts/wasm-engine/run.sh
fi

PAIRS="jsce:1~jsce:2,jsce:2~jsce:3,jsce:3~jsce:4,jsce:4~jsce:5,\
patricia:s1~patricia:s3,patricia:s3~patricia:s5,patricia:s5~patricia:s7,\
jsce:1~shaped:600,jsce:1~shaped:900,jsce:2~shaped:900,jsce:3~shaped:1200,\
jsce:3~ucielo:1320:mt400,jsce:4~ucielo:1320:mt400,jsce:5~ucielo:1600:mt400,\
patricia:s1~shaped:600,patricia:s1~shaped:900,patricia:s3~shaped:1200,\
patricia:s3~ucielo:1320:mt400,patricia:s5~ucielo:1320:mt400,patricia:s7~ucielo:1600:mt400,\
jsce:3~patricia:s3,\
shaped:1200~ucielo:1320:mt400"

echo "============================================================"
echo " Engine gym — js-chess-engine + Patricia vs our scale (n=80)"
echo "============================================================"
npx tsx scripts/calibrate-bots.mts \
	--engine scripts/wasm-engine/run.sh --substrate wasm \
	--ext-config scripts/gym-ext.json \
	--pairs "$PAIRS" \
	--games 80 \
	--shaped-depth 12 --shaped-multipv 12 \
	--out data/bot-gym-ext.json

echo "============================================================"
echo " DONE — tell Claude: \"gym done\""
echo "============================================================"
