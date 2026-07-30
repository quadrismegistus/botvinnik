#!/usr/bin/env bash
# The committed retro.wasm must match the provenance recorded beside it.
#
#   ./scripts/check-retro-provenance.sh
#
# Two failures this catches, both of which used to be invisible:
#
#   1. The pin moved but nobody rebuilt. vendor/retro/MORLOCK_REV would name
#      one revision while the shipped wasm came from another, and the file
#      claiming to record provenance would be the thing lying about it.
#   2. The wasm was rebuilt from something else — a dirty checkout, a local
#      experiment — and copied in by hand. The recorded sha256 would not match
#      the bytes.
#
# Runs in CI (ubuntu) and locally (macOS); both hash tools are handled.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V="$HERE/../vendor/retro"

fail() { echo "error: $*" >&2; exit 1; }

[ -f "$V/MORLOCK_REV" ] || fail "vendor/retro/MORLOCK_REV is missing"
[ -f "$V/BUILD.txt" ] || fail "vendor/retro/BUILD.txt is missing — run scripts/retro-wasm/build.sh"
[ -f "$V/retro.wasm" ] || fail "vendor/retro/retro.wasm is missing"

# `tr -d` on every value, not just the pin: a CRLF checkout leaves \r on the
# BUILD.txt fields, and since both are truncated to 12 chars in the error the
# result was "X says 63db3e6adb6b but the wasm was built from 63db3e6adb6b".
# Fails closed either way, but an impossible-looking message is its own bug.
pinned="$(grep -v '^[[:space:]]*#' "$V/MORLOCK_REV" | grep -v '^[[:space:]]*$' | head -1 | tr -d '[:space:]')"
recorded="$(awk '$1=="morlock-rev"{print $2; exit}' "$V/BUILD.txt" | tr -d '[:space:]')"
want="$(awk '$1=="retro.wasm"{print $2; exit}' "$V/BUILD.txt" | tr -d '[:space:]' | sed 's/^sha256://')"

[ -n "$recorded" ] || fail "BUILD.txt records no morlock-rev"
[ -n "$want" ] || fail "BUILD.txt records no retro.wasm sha256"

if [ "$pinned" != "$recorded" ]; then
  fail "MORLOCK_REV says ${pinned:0:12} but the committed wasm was built from ${recorded:0:12}.
       Rebuild it: ./scripts/retro-wasm/build.sh (and restage the native engines)."
fi

if command -v sha256sum >/dev/null; then
  got="$(sha256sum "$V/retro.wasm" | cut -d' ' -f1)"
else
  got="$(shasum -a 256 "$V/retro.wasm" | cut -d' ' -f1)"
fi

if [ "$want" != "$got" ]; then
  fail "retro.wasm does not match the sha256 in BUILD.txt.
       recorded ${want:0:16}…
       actual   ${got:0:16}…
       Whatever produced that wasm did not write its provenance. Rebuild it:
       ./scripts/retro-wasm/build.sh"
fi

echo "retro provenance ok: morlock ${pinned:0:12}, wasm ${got:0:16}…"
