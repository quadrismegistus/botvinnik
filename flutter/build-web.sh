#!/usr/bin/env bash
# The Flutter web build, end to end. Use this rather than `flutter build web`
# directly: the service worker's precache manifest is generated from the built
# output, so a raw build produces a worker whose placeholder was never
# replaced — which sw.js turns into a loud install failure rather than a
# silently empty cache.
set -euo pipefail
cd "$(dirname "$0")"

./stage-web-assets.sh

# --no-web-resources-cdn is REQUIRED, not a preference. Without it Flutter
# loads CanvasKit from https://www.gstatic.com/flutter-canvaskit/ — a different
# origin, so the service worker cannot cache it and the app has no renderer
# offline. It appears to work anyway while the browser's own HTTP cache still
# holds the file, which is exactly how a false pass looks: the first offline
# test here passed for that reason and proved nothing.
flutter build web --release --no-web-resources-cdn "$@"

node tool/gen-sw-manifest.mjs build/web

echo "built flutter/build/web (offline-capable)"
