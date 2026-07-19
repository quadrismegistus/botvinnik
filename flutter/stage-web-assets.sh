#!/usr/bin/env bash
# Stage the two web assets that are copies rather than sources:
#
#   web/brain.js   <- assets/brain.js   (built by `npm run build:brain`)
#   web/wasm/      <- ../static/wasm/   (the Stockfish WASM the Svelte app ships)
#   web/retro/     <- ../static/retro/  (the historical engines, wasm + worker)
#   web/garbo/     <- ../static/garbo/  (Garbochess-JS 2011, worker + LICENSE)
#   web/maia/      <- BUILT here, plus ort's runtime from node_modules
#
# All five are gitignored, so a fresh clone has none. Run this before ANY
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

# maia: unlike brain.js this worker is BUILT here rather than committed, so
# there is no bundle for CI to diff against its source — nothing about Maia
# lands in git at all. Its runtime comes straight from the pinned
# onnxruntime-web devDependency, so the version is package-lock's problem.
#
# Both ort files are needed. The "bundle" build is documented as self-contained
# and is not: it still dynamically imports ort-wasm-simd-threaded.mjs at
# runtime, which fails as "no available backend found" — a message that says
# nothing about a missing file. Staging only the .wasm is the mistake to avoid.
# esbuild is resolved by npm hoisting, not by a direct dependency — it arrives
# transitively via tsx and vite. `npm run build:brain` already relies on this,
# so it is a pre-existing arrangement rather than one this script introduced,
# but it is load-bearing in one more place now. If vite's move to rolldown ever
# drops esbuild, this fails as "could not determine executable to run", and the
# fix is to add esbuild to devDependencies.
ORT=../node_modules/onnxruntime-web/dist
for f in ort-wasm-simd-threaded.wasm ort-wasm-simd-threaded.mjs; do
  [ -f "$ORT/$f" ] || {
    echo "error: $ORT/$f is missing — run 'npm ci' first" >&2
    exit 1
  }
done
rm -rf web/maia
mkdir -p web/maia
npx --no-install esbuild web_src/maia-worker.ts \
  --bundle --format=iife --platform=browser --target=es2022 \
  --outfile=web/maia/maia-worker.js --log-level=warning
cp "$ORT/ort-wasm-simd-threaded.mjs" "$ORT/ort-wasm-simd-threaded.wasm" web/maia/

echo "staged web/brain.js, web/wasm/ ($(ls web/wasm | tr '\n' ' ')), web/retro/, web/garbo/ and web/maia/"
