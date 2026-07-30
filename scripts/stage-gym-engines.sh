#!/usr/bin/env bash
# Build the retro engines the calibration gym drives, from the pinned revision.
#
#   ./scripts/stage-gym-engines.sh
#     -> scripts/engines/retro/{turochamp,bernstein,sargon}
#
# These are the binaries scripts/run-retro-gym.sh and scripts/puzzle-rating/
# spawn, and therefore the ones whose games produced the roster's advertised
# ratings. Until now the only instruction for producing them was a sentence
# inside run-retro-gym.sh's error message, which meant the engines the gym
# measured and the engines the app ships were related by nothing stronger than
# whoever built them last having not moved the checkout in between.
#
# Same source as the app's, enforced the same way: vendor/retro/MORLOCK_REV.
# Gitignored (built, not committed), like every other retro artefact.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/engines/morlock-src"
DEST="$HERE/engines/retro"

command -v go >/dev/null || { echo "error: Go is not installed (need 1.26+)" >&2; exit 1; }

"$HERE/sync-morlock.sh" >/dev/null

mkdir -p "$DEST"
for eng in turochamp bernstein sargon; do
  # Build from inside $SRC so Go stamps the morlock revision into the binary;
  # `go version -m` then answers "which engine did the gym measure?".
  ( cd "$SRC" && go build -o "$DEST/$eng" "./cmd/$eng" )
  chmod +x "$DEST/$eng"
done

echo "staged $DEST/ ($(ls "$DEST" | tr '\n' ' '))"
