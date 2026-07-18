#!/usr/bin/env bash
# Build and serve the Flutter web app.
#
#   ./serve-web.sh          release build (what a user would get)
#   ./serve-web.sh debug    faster build, unminified, DEBUG banner
#
# --no-web-resources-cdn bundles CanvasKit locally instead of fetching it from
# a Google CDN: required for the app to work offline and to install as a PWA.
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-release}"
PORT="${PORT:-8792}"

# brain.js and the Stockfish WASM engine are copies, not tracked (see
# .gitignore); refresh them so a rebuilt brain actually reaches the browser
cp assets/brain.js web/brain.js
[ -d web/wasm ] || cp -R ../static/wasm web/wasm

flutter build web --"$MODE" --no-web-resources-cdn

echo
echo "serving http://localhost:$PORT  (ctrl-c to stop)"
cd build/web && exec python3 -m http.server "$PORT"
