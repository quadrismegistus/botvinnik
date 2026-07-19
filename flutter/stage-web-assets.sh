#!/usr/bin/env bash
# Stage the two web assets that are copies rather than sources:
#
#   web/brain.js   <- assets/brain.js   (built by `npm run build:brain`)
#   web/wasm/      <- ../static/wasm/   (the Stockfish WASM the Svelte app ships)
#   web/retro/     <- ../static/retro/  (the historical engines, wasm + worker)
#   web/garbo/     <- ../static/garbo/  (Garbochess-JS 2011, worker + LICENSE)
#
# All four are gitignored, so a fresh clone has none. Run this before ANY
# `flutter build web` — without brain.js the app fails loudly at boot, and
# without the engine it used to boot fine and then never move (now it fails
# loudly too, see WebEngine.start).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

[ -f assets/brain.js ] || {
  echo "error: assets/brain.js is missing — run 'npm run build:brain' first" >&2
  exit 1
}
cp assets/brain.js web/brain.js

# refresh rather than skip-if-present: a stale engine copy would silently
# invalidate persona calibration, which is pinned to a specific build
rm -rf web/wasm
cp -R ../static/wasm web/wasm

# retro: the three historical engines share one wasm binary, selected by the
# {engine, ply} boot message. Unlike the Stockfish copy these ARE committed
# (static/retro/ is tracked), so this is only ever a copy, never a build.
rm -rf web/retro
cp -R ../static/retro web/retro

# garbo: 82KB of hand-written 2011 JavaScript, committed. The LICENSE beside
# it is BSD and must travel with the engine — copy the directory, not the file.
rm -rf web/garbo
cp -R ../static/garbo web/garbo

echo "staged web/brain.js, web/wasm/ ($(ls web/wasm | tr '\n' ' ')), web/retro/ and web/garbo/"
