#!/usr/bin/env bash
# Build the retro engines into the iOS app as ONE static archive.
#
#   ios/retro/lib/device/libmorlock.a   (ios-arm64)
#   ios/retro/lib/sim/libmorlock.a      (ios-arm64-simulator)
#   ios/retro/include/retro.h           (cgo-generated)
#
# iOS has no child processes, so the macOS approach — build three UCI binaries
# and spawn them — cannot work there. Instead the same morlock source is built
# with `-buildmode=c-archive`, which produces a static library exporting C
# symbols that dart:ffi can call; `scripts/retro-ffi/main.go` is the shim that
# replaces the stdin UCI loop with `retro_send`.
#
# One archive covers all three engines, selected by name at retro_start, so
# this costs its ~3.5MB once rather than three times.
#
# Two files rather than one fat .a because the device and the simulator slices
# are both arm64: `lipo` cannot hold two slices of the same architecture, and
# the platform is the only thing that distinguishes them. The podspec picks
# between them with an `[sdk=…]`-conditional `-force_load`, which is also what
# keeps the symbols alive — dart:ffi finds them at runtime, so the linker sees
# nothing referencing them and would otherwise strip the lot.
#
# Run before an iOS build that should offer the retro bots:
#   ./stage-ios-engines.sh
#
# Gitignored (built, not committed), like the macOS binaries beside it. The
# Podfile only includes the pod when the xcframework is present, and
# RetroEngine gates on the SYMBOL being there — so a build that skipped this
# simply does not offer retro, rather than offering it and falling back to
# Stockfish wearing the persona's name.
#
# The morlock engines are MIT (scripts/engines/morlock-src/LICENSE). Go 1.26+.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SRC="../scripts/retro-ffi"
DEST="ios/retro"
MIN_IOS=13.0

command -v go >/dev/null || { echo "error: Go is not installed (need 1.26+)" >&2; exit 1; }
[ -d "../scripts/engines/morlock-src/cmd" ] || {
  echo "error: morlock source missing at scripts/engines/morlock-src" >&2
  echo "       git clone https://github.com/herohde/morlock scripts/engines/morlock-src" >&2
  exit 1
}

rm -rf "$DEST/lib" "$DEST/include"
mkdir -p "$DEST/lib/device" "$DEST/lib/sim" "$DEST/include"

# NOTE the absolute out path: the build runs from $SRC (cgo needs the module
# dir), so a relative -o would land inside scripts/retro-ffi/ instead.
build_slice() {
  local sdk="$1" target="$2" out="$PWD/$3"
  local sysroot
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  ( cd "$SRC" && \
    CGO_ENABLED=1 GOOS=ios GOARCH=arm64 \
    CC="$(xcrun --sdk "$sdk" -f clang)" \
    CGO_CFLAGS="-isysroot $sysroot -target $target" \
    CGO_LDFLAGS="-isysroot $sysroot -target $target" \
    go build -buildmode=c-archive -ldflags="-s -w" -o "$out" . )
}

build_slice iphoneos        "arm64-apple-ios$MIN_IOS"           "$DEST/lib/device/libmorlock.a"
build_slice iphonesimulator "arm64-apple-ios$MIN_IOS-simulator" "$DEST/lib/sim/libmorlock.a"

# cgo emits one header per build; they are identical, so either will do. Kept
# for reference — nothing includes it (see Classes/retro_keepalive.m).
mv "$DEST/lib/device/libmorlock.h" "$DEST/include/retro.h"
rm -f "$DEST/lib/sim/libmorlock.h"

echo "staged $DEST/lib ($(du -h "$DEST/lib/device/libmorlock.a" | cut -f1) per slice)"
echo "note: run 'pod install' in ios/ if this is the first staging"
