#!/usr/bin/env bash
# Build and serve the Flutter web app.
#
#   ./serve-web.sh              release build (what a user would get)
#   ./serve-web.sh debug        faster build, unminified, DEBUG banner
#   PORT=9000 ./serve-web.sh    serve somewhere else (default 8792)
#
# --no-web-resources-cdn bundles CanvasKit locally rather than fetching it
# from a Google CDN: no third-party dependency at runtime, works on an
# airgapped or LAN host, and a prerequisite for real offline support.
#
# Offline DOES work: build-web.sh installs our own service worker in place of
# Flutter's self-unregistering no-op. Full offline lands after one reload,
# since CanvasKit is fetched before the worker takes control.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
MODE="${1:-release}"
PORT="${PORT:-8792}"

case "$MODE" in
  release|debug|profile) ;;
  *) echo "usage: $0 [release|debug|profile]   (got '$MODE')" >&2; exit 2 ;;
esac

# via build-web.sh, NOT `flutter build web`: a raw build ships sw.js with its
# manifest placeholder unreplaced, which registers nothing and looks exactly
# like working offline support. This was the one remaining path that produced
# that artifact.
BUILD_MODE="$MODE" ./build-web.sh

echo
echo "serving http://localhost:$PORT  (ctrl-c to stop)"
cd build/web && exec python3 -m http.server "$PORT"
