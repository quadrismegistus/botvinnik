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

# Flutter substitutes {{flutter_js}} and {{flutter_build_config}} into our
# bootstrap template, and web_template.dart returns the token UNCHANGED when a
# built-in is missing rather than warning. An SDK upgrade that renames one
# would emit a literal `{{flutter_js}}`, i.e. a ReferenceError and a dead app —
# with green CI, which builds but never boots the page.
if grep -q '{{' build/web/flutter_bootstrap.js; then
  echo "error: unsubstituted {{token}} left in build/web/flutter_bootstrap.js" >&2
  grep -o '{{[a-z_]*}}' build/web/flutter_bootstrap.js | sort -u >&2
  exit 1
fi

echo "built flutter/build/web (offline-capable)"
