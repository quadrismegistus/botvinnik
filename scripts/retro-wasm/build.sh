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
CHECK=""
[ "${1:-}" = "--check" ] && CHECK=1

command -v go >/dev/null || { echo "error: Go is not installed (need 1.26+)" >&2; exit 1; }

REV="$("$HERE/../sync-morlock.sh")"
GOVER="$(go version | awk '{print $3}')"

# -trimpath -buildvcs=false is what makes the output a function of the inputs
# recorded below, and it was NOT here at first. Go stamps buildvcs for the repo
# the build RAN IN, which for the wasm is botvinnik-web rather than morlock, so
# the artefact carried this repo's commit, a build timestamp, and
# `vcs.modified=true` — the wasm shipped from a dirty tree by the very script
# that refuses to build from a dirty morlock tree. It also embedded 54 copies
# of the builder's home directory. Two consequences, both now gone: rebuilding
# to verify produced a spurious diff, and the artefact could not be reproduced
# by anyone who cloned to a different path.
#
# The natives deliberately do NOT pass -buildvcs=false: being built from inside
# the morlock checkout is exactly what lets them stamp the revision and
# self-attest. They do pass -trimpath, for the home-directory leak.
LDFLAGS="-s -w"
FLAGS=(-trimpath -buildvcs=false -ldflags="$LDFLAGS")
FLAGS_TEXT="-trimpath -buildvcs=false -ldflags=\"$LDFLAGS\""

# sha256sum on Linux, shasum on macOS. This script runs on a developer's Mac;
# check-retro-provenance.sh reads what it writes on an Ubuntu runner.
sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

OUT="$HERE/retro.wasm"
[ -n "$CHECK" ] && OUT="$(mktemp -t retro-wasm-check).wasm"

echo "building retro.wasm ($GOVER, morlock ${REV:0:12})" >&2
( cd "$HERE" && GOOS=js GOARCH=wasm go build "${FLAGS[@]}" -o "$OUT" . )

# --check rebuilds and compares instead of installing, so CI can verify the
# CHAIN — source revision to bytes — rather than verifying that two strings the
# same local run wrote agree with each other. Reproducibility is what makes
# this possible at all, which is why the flags above are load-bearing rather
# than hygiene.
if [ -n "$CHECK" ]; then
  want="$(awk '$1=="retro.wasm"{print $2; exit}' "$VENDOR/BUILD.txt" | sed 's/^sha256://' | tr -d '[:space:]')"
  got="$(sha256 "$OUT")"
  rm -f "$OUT"
  if [ "$want" != "$got" ]; then
    echo "error: rebuilding morlock ${REV:0:12} did not reproduce the committed wasm." >&2
    echo "       committed  ${want:0:16}…" >&2
    echo "       rebuilt    ${got:0:16}…" >&2
    echo "       Same Go toolchain? BUILD.txt records $GOVER, this is $(go version | awk '{print $3}')." >&2
    exit 1
  fi
  echo "rebuild reproduces the committed wasm ($GOVER, morlock ${REV:0:12})" >&2
  exit 0
fi

cp "$OUT" "$VENDOR/retro.wasm"

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
# timestamp on purpose: with -trimpath -buildvcs=false the output depends only
# on what is listed here, so the same revision and toolchain reproduce both
# this file and the wasm byte for byte — which is what lets CI rebuild and
# compare. The commit that touches it carries the date anyway.
cat > "$VENDOR/BUILD.txt" <<EOF
# How the retro artefacts were built. Written by scripts/retro-wasm/build.sh —
# do not edit by hand.
#
# CI checks this three ways: morlock-rev against vendor/retro/MORLOCK_REV, the
# sha256 below against the committed bytes (scripts/check-retro-provenance.sh),
# and — the one that checks the chain rather than the label — by rebuilding
# from source and comparing (\`build.sh --check\`). So a pin bumped without a
# rebuild, a wasm dropped in by hand, and a wasm that simply did not come from
# the revision it claims all fail before merge.
#
# The reproducibility is not free: it needs the SAME Go version recorded below.
# A different toolchain produces different bytes from identical source, and the
# --check failure says so.
morlock-repo    https://github.com/herohde/morlock
morlock-rev     $REV
go              $GOVER
target          js/wasm
buildflags      $FLAGS_TEXT
retro.wasm      sha256:$(sha256 "$VENDOR/retro.wasm")

# The native artefacts are gitignored, so their provenance cannot be recorded
# here — but they do not need to be taken on trust either. Each is built from
# inside the morlock checkout, so Go stamps the revision into the binary:
#
#   go version -m flutter/macos/Runner/Resources/retro/turochamp | grep vcs.revision
#
# and their build scripts (flutter/stage-macos-engines.sh,
# flutter/stage-ios-engines.sh) check out the pin above before building.
#
# The wasm is the one that cannot self-attest, and that asymmetry is the whole
# reason this file exists: its build runs from THIS repo, so Go would stamp a
# botvinnik revision and a build timestamp into it rather than a morlock one.
# Since that stamp is worse than useless here — wrong repo, and it made the
# artefact unreproducible — the wasm turns it off and writes the revision down
# instead. The natives keep it, because for them it is right.
EOF

echo "wrote $VENDOR/retro.wasm and $VENDOR/BUILD.txt" >&2
