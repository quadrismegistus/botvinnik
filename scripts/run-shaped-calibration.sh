#!/usr/bin/env bash
#
# Locate the shaped-blunder sampler (shapedBotMove) on our calibrated WASM ELO
# scale. shaped:N runs a STRONG depth-12 MultiPV search and picks its move with
# the human-error model (shapedParams(N)); the weakening is all in the params,
# not the search. This run measures (a) shaped's own internal spread and
# monotonicity, and (b) where each shaped band lands against our anchored numeric
# bands — so we can then tune shapedParams to hit the target ELOs.
#
# Run in your own terminal (resume-safe, checkpointed):
#
#     bash scripts/run-shaped-calibration.sh            # full grid, ~1 hour
#     bash scripts/run-shaped-calibration.sh --quick    # tuning loop, ~10 min
#     bash scripts/run-shaped-calibration.sh --native   # full grid vs the Tauri
#                                                       # sidecar (desktop knots)
#
# --quick plays a small n=30 set (shaped:600/900/1200 vs nearby numeric bands +
# one anchor pair) into data/bot-shaped-quick.json — enough to eyeball whether
# the current shapedParams land in the right neighbourhood before committing to
# the full grid. Delete data/bot-shaped-quick.json* between quick runs after a
# params change (the checkpoint would otherwise resume stale results).
#
# Slower than the sampler runs (depth-12 searches, not depth-1): ballpark
# 15-25 games/min on WASM. Ctrl-C and re-run to resume. When done, tell Claude
# "shaped calibration done" (or "quick run done").
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

# Full grid: shaped internal ladder at 150-pt label steps (fine enough to see
# the curve's shape — the first honest quick run showed a 700-pt cliff between
# labels 900 and 1200) + the upper shaped bands vs honest UCI_Elo rulers. The
# lower bands (600-1050) score ~0 vs any honest ruler, so their placement comes
# from the internal chain via BT. Raw ucielo specs aren't fit anchors — rebase
# the fit on ucielo:1320:mt400 = 1320 when reading the output. The result is
# the label→strength curve, to be INVERTED into a knot table for the app
# (like the sampler's alpha knots), not tuned by hand.
PAIRS="shaped:600~shaped:750,shaped:750~shaped:900,shaped:900~shaped:1050,shaped:1050~shaped:1200,shaped:1200~shaped:1350,shaped:1350~shaped:1500,\
shaped:600~shaped:900,shaped:900~shaped:1200,shaped:1200~shaped:1500,\
shaped:1050~ucielo:1320:mt400,shaped:1200~ucielo:1320:mt400,shaped:1350~ucielo:1320:mt400,shaped:1500~ucielo:1320:mt400,\
shaped:1350~ucielo:1600:mt400,shaped:1500~ucielo:1600:mt400,shaped:1500~ucielo:2000:mt400"
GAMES=50
OUT=data/bot-shaped-calib.json
LABEL="full honest grid (n=50, ~25 min)"
ENGINE=scripts/wasm-engine/run.sh
SUBSTRATE=wasm

# Desktop knots: measure against the EXACT binary the Tauri app ships (the
# big-net sidecar — much stronger than the web's lite-single at equal depth,
# so the WASM knot table mislabels desktop Squares).
# flags combine: --native picks the substrate, --scan picks the model, and
# each (out, state) pairing stays distinct so no baseline is ever overwritten
for arg in "$@"; do
case "$arg" in
--native)
	ENGINE=src-tauri/binaries/stockfish-aarch64-apple-darwin
	[ -x "$ENGINE" ] || { echo "sidecar missing: $ENGINE"; exit 1; }
	SUBSTRATE=native
	OUT=data/bot-shaped-native-calib.json
	LABEL="full honest grid vs Tauri sidecar (native substrate)"
	;;
--scan)
	SCAN_ARG="--scan"
	LABEL="v4 scan model, $LABEL"
	;;
--games=*)
	GAMES="${arg#--games=}"
	;;
esac
done
# v4 runs write scan-suffixed outputs per substrate
if [ -n "${SCAN_ARG:-}" ]; then
	OUT="${OUT%.json}"; OUT="${OUT%-calib}"
	case "$OUT" in *shaped) OUT="$OUT-scan-calib.json";; *) OUT="$OUT-scan-calib.json";; esac
	OUT=$(echo "$OUT" | sed 's/shaped-native-scan/shaped-scan-native/')
fi

# Quick tuning mode. NB the numeric bands below the WASM seam (samplerMax 2485)
# are the SOFTMAX SAMPLER — the exploitable thing shaped replaces — so playing
# shaped against them measures the sampler's exploitability, not shaped's
# strength (shaped:600 "beat 900" 97% that way). The honest reference is raw
# UCI_Elo at its 1320 floor: ucielo:1320:mt400. Raw WIN RATES are the signal
# (raw specs aren't fit anchors): shaped:600 should score LOW vs 1320 —
# lichess-600 ≈ ~840 on our computer-hot scale ⇒ target ≲15%; near 50% means
# it's still playing ~1320.
if [ "${1:-}" = "--quick" ]; then
	PAIRS="shaped:600~ucielo:1320:mt400,shaped:900~ucielo:1320:mt400,shaped:1200~ucielo:1320:mt400,shaped:1200~ucielo:1600:mt400"
	GAMES=30
	OUT=data/bot-shaped-quick.json
	LABEL="quick tuning set vs honest UCI_Elo floor (n=30, ~15 min)"
fi

echo "============================================================"
echo " Shaped-blunder calibration — $LABEL"
echo "============================================================"
npx tsx scripts/calibrate-bots.mts \
	--engine "$ENGINE" --substrate "$SUBSTRATE" \
	--pairs "$PAIRS" \
	--games "$GAMES" \
	--shaped-depth 12 --shaped-multipv 12 \
	${SCAN_ARG:-} \
	--out "$OUT"

echo "============================================================"
echo " DONE — tell Claude: \"shaped calibration done\""
echo "============================================================"
