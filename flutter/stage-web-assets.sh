#!/usr/bin/env bash
# Stage the two web assets that are copies rather than sources:
#
#   web/brain.js   <- assets/brain.js   (built by `npm run build:brain`)
#   web/wasm/      <- ../static/wasm/   (the Stockfish WASM the Svelte app ships)
#
# Both are gitignored, so a fresh clone has neither. Run this before ANY
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

echo "staged web/brain.js and web/wasm/ ($(ls web/wasm | tr '\n' ' '))"
