#!/usr/bin/env bash
# Build the retro engine binaries into the macOS app's staging dir.
#
#   macos/Runner/Resources/retro/{turochamp,bernstein,sargon}
#
# The "Bundle chess engine" Xcode build phase copies that dir into
# Contents/Resources/retro/ at build time, and retro_engine_io.dart spawns
# from there. Gitignored (built, not committed) — like the Stockfish binary
# beside it.
#
# Stockfish itself is staged separately (drop a binary at
# Runner/Resources/stockfish, or the app falls back to a brew install).
#
# Run before a macOS build that should offer the retro bots:
#   ./stage-macos-engines.sh
#
# The morlock engines are MIT (scripts/engines/morlock-src/LICENSE); they carry
# no copyleft obligation. Go 1.26+ required.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SRC="../scripts/engines/morlock-src"
DEST="macos/Runner/Resources/retro"

command -v go >/dev/null || { echo "error: Go is not installed (need 1.26+)" >&2; exit 1; }
[ -d "$SRC/cmd" ] || { echo "error: morlock source missing at $SRC" >&2; exit 1; }

mkdir -p "$DEST"
for eng in turochamp bernstein sargon; do
  ( cd "$SRC" && go build -o "$(cd - >/dev/null; pwd)/$DEST/$eng" "./cmd/$eng" )
  chmod +x "$DEST/$eng"
done

echo "staged $DEST/ ($(ls "$DEST" | tr '\n' ' '))"
