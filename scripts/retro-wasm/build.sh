#!/usr/bin/env bash
# Build vendor/retro/retro.wasm from the pinned morlock revision, and record
# what it was built from.
#
#   ./scripts/retro-wasm/build.sh
#
# This replaces the recipe that used to live as a comment in main.go. A recipe
# in a comment cannot check itself out, cannot write down what it did, and had
# already drifted once — it named a directory (static/retro/) that no longer
# existed. The three claims that comment made by hand are now made by this
# script and checked by scripts/check-retro-provenance.sh in CI.
#
# NOTE it does NOT refresh wasm_exec.js. The old recipe's `cp` from $(go env
# GOROOT) is what drops the local patch, so this build leaves the shipped shim
# alone and instead TELLS you when the toolchain's copy has moved on. See the
# LOCAL PATCH note at the top of vendor/retro/wasm_exec.js.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR="$HERE/../../vendor/retro"

command -v go >/dev/null || { echo "error: Go is not installed (need 1.26+)" >&2; exit 1; }

REV="$("$HERE/../sync-morlock.sh")"
GOVER="$(go version | awk '{print $3}')"
LDFLAGS="-s -w"

# sha256sum on Linux, shasum on macOS. This script runs on a developer's Mac;
# check-retro-provenance.sh reads what it writes on an Ubuntu runner.
sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

echo "building retro.wasm ($GOVER, morlock ${REV:0:12})" >&2
( cd "$HERE" && GOOS=js GOARCH=wasm go build -ldflags="$LDFLAGS" -o retro.wasm . )
cp "$HERE/retro.wasm" "$VENDOR/retro.wasm"

# The toolchain's shim is the source of the two wasm_exec.js copies here. If it
# has moved, the shipped one is stale against the runtime this wasm was built
# for — a mismatch that shows up as a runtime failure in a browser and nowhere
# else. Warn rather than fail: refreshing it means reapplying the local patch,
# which is a deliberate act, not something a build should do behind your back.
GOROOT_SHIM="$(go env GOROOT)/lib/wasm/wasm_exec.js"
if [ -f "$GOROOT_SHIM" ] && ! diff -q <(tail -n +4 "$HERE/wasm_exec.js") "$GOROOT_SHIM" >/dev/null; then
  echo >&2
  echo "WARNING: $GOVER's wasm_exec.js differs from the vendored copy." >&2
  echo "         Refresh scripts/retro-wasm/wasm_exec.js and vendor/retro/wasm_exec.js" >&2
  echo "         from it, then REAPPLY the local patch to the vendor/ one." >&2
  echo >&2
fi

# Provenance, written by the build rather than asserted by a human. No
# timestamp on purpose: everything here is a function of the build's inputs, so
# rebuilding the same revision with the same toolchain reproduces this file
# byte for byte, and the commit that touches it carries the date anyway.
cat > "$VENDOR/BUILD.txt" <<EOF
# How the retro artefacts were built. Written by scripts/retro-wasm/build.sh —
# do not edit by hand. CI (scripts/check-retro-provenance.sh) checks that
# morlock-rev matches vendor/retro/MORLOCK_REV and that the sha256 below
# matches the committed wasm, so neither a rebuild from the wrong source nor a
# pin bumped without a rebuild can merge.
morlock-repo    https://github.com/herohde/morlock
morlock-rev     $REV
go              $GOVER
target          js/wasm
ldflags         $LDFLAGS
retro.wasm      sha256:$(sha256 "$VENDOR/retro.wasm")

# The native artefacts are gitignored, so their provenance cannot be recorded
# here — but they do not need to be taken on trust either. Each is built from
# inside the morlock checkout, so Go stamps the revision into the binary:
#
#   go version -m flutter/macos/Runner/Resources/retro/turochamp | grep vcs.revision
#
# and their build scripts (flutter/stage-macos-engines.sh,
# flutter/stage-ios-engines.sh) check out the pin above before building. The
# wasm is the one that cannot self-attest: its build runs from this repo, so Go
# stamps a botvinnik revision instead. Hence this file.
EOF

echo "wrote $VENDOR/retro.wasm and $VENDOR/BUILD.txt" >&2
