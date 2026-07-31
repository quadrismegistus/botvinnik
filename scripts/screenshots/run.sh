#!/usr/bin/env bash
# Build the web app, serve it, shoot it, put the server back.
#
#   npm run shots               every shot, both viewports
#   npm run shots -- roster     just one (names are the keys of SHOTS)
#
# The build goes through build-web.sh rather than `flutter build web` for the
# same reason the e2e config does: a raw build ships sw.js with its manifest
# placeholder unreplaced, so the pictures would be of an artifact nobody
# deploys.
#
# Port 4400 is the e2e suite's, deliberately — if a server is already up there
# (from `npx playwright test -c flutter/playwright.config.ts`, which leaves one
# running outside CI) this reuses it and skips a two-minute rebuild.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

PORT="${SHOTS_PORT:-4400}"
SERVER=""

# `trap` rather than a kill at the end: the capture script can fail on a shot,
# and a stranded http.server on 4400 would then silently serve a stale build to
# the next run — which looks like a screenshot that ignored your change.
cleanup() { [ -n "$SERVER" ] && kill "$SERVER" 2>/dev/null || true; }
trap cleanup EXIT

if curl -fsS --max-time 2 "http://localhost:$PORT" >/dev/null 2>&1; then
  echo "reusing the server already on :$PORT"
else
  (cd flutter && ./build-web.sh >/dev/null)
  (cd flutter/build/web && exec python3 -m http.server "$PORT" >/dev/null 2>&1) &
  SERVER=$!
  for _ in $(seq 1 30); do
    curl -fsS --max-time 1 "http://localhost:$PORT" >/dev/null 2>&1 && break
    sleep 1
  done
fi

SHOTS_URL="http://localhost:$PORT" npx tsx scripts/screenshots/capture.mts "$@"
