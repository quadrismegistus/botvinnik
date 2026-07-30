#!/usr/bin/env bash
# Build the retro engine binaries into the macOS app's staging dir.
#
#   macos/Runner/Resources/retro/{turochamp,bernstein,sargon}
#
# The "Bundle chess engine" Xcode build phase copies that dir into
# Contents/MacOS/retro/ at build time and signs each binary, and
# retro_engine_io.dart spawns from there. Contents/MacOS rather than
# Contents/Resources because executable code in Resources fails notarization.
# This directory is only the staging source; it stays where it is.
# Gitignored (built, not committed) — like the Stockfish binary beside it.
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

# Check the pinned revision out rather than building whatever is on disk. Go
# stamps it into each binary (`go version -m <binary> | grep vcs.revision`),
# because the build below runs from inside $SRC — so these artefacts can be
# checked against vendor/retro/MORLOCK_REV after the fact.
../scripts/sync-morlock.sh >/dev/null

mkdir -p "$DEST"
for eng in turochamp bernstein sargon; do
  # -trimpath keeps the builder's home directory out of a shipped binary; note
  # it does NOT suppress the vcs stamp, which is what makes these self-attest.
  ( cd "$SRC" && go build -trimpath -o "$(cd - >/dev/null; pwd)/$DEST/$eng" "./cmd/$eng" )
  chmod +x "$DEST/$eng"
done

echo "staged $DEST/ ($(ls "$DEST" | tr '\n' ' '))"
