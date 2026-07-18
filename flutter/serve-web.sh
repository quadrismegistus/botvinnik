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
# NOTE: offline does NOT work yet. Flutter 3.44 generates a self-unregistering
# no-op service worker, so the built app currently has no offline caching of
# its own — see the PR description.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
MODE="${1:-release}"
PORT="${PORT:-8792}"

case "$MODE" in
  release|debug|profile) ;;
  *) echo "usage: $0 [release|debug|profile]   (got '$MODE')" >&2; exit 2 ;;
esac

./stage-web-assets.sh
flutter build web --"$MODE" --no-web-resources-cdn

echo
echo "serving http://localhost:$PORT  (ctrl-c to stop)"
cd build/web && exec python3 -m http.server "$PORT"
