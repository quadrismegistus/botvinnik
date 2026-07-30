#!/usr/bin/env bash
# Put scripts/engines/morlock-src at the revision vendor/retro/MORLOCK_REV
# names, and refuse to proceed if it cannot.
#
# Every retro build sources its engines from that checkout, which is
# gitignored: the wasm, the macOS binaries, the iOS c-archive and the gym
# binaries. Before this script they all trusted whatever happened to be on
# disk. Nothing recorded what that was, and nothing noticed when two artefacts
# were built weeks apart from different states of it.
#
# Prints the revision on stdout (progress goes to stderr), so callers can do:
#   REV="$(../sync-morlock.sh)"
#
# Deliberately REFUSES on a dirty checkout rather than stashing or resetting.
# A dirty tree is exactly the provenance hole this exists to close, and a
# script that silently discards someone's local engine experiment to close it
# would be a worse bug than the one it fixes.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/engines/morlock-src"
PIN="$HERE/../vendor/retro/MORLOCK_REV"
REPO="https://github.com/herohde/morlock"

[ -f "$PIN" ] || { echo "error: no pin file at $PIN" >&2; exit 1; }

# first non-comment, non-blank line
REV="$(grep -v '^[[:space:]]*#' "$PIN" | grep -v '^[[:space:]]*$' | head -1 | tr -d '[:space:]')"
[ -n "$REV" ] || { echo "error: $PIN names no revision" >&2; exit 1; }

if [ ! -d "$SRC/.git" ]; then
  echo "cloning morlock into $SRC" >&2
  git clone --quiet "$REPO" "$SRC" >&2
fi

if [ -n "$(git -C "$SRC" status --porcelain)" ]; then
  echo "error: $SRC has uncommitted changes." >&2
  echo "       Refusing to check out $REV over them. Commit, stash or discard" >&2
  echo "       them yourself — an artefact built from a dirty tree is exactly" >&2
  echo "       what vendor/retro/MORLOCK_REV exists to prevent." >&2
  exit 1
fi

if [ "$(git -C "$SRC" rev-parse HEAD)" != "$REV" ]; then
  # Fetch only when the revision is not already present: the common case is a
  # checkout that already has it, and that case should work offline.
  if ! git -C "$SRC" cat-file -e "$REV^{commit}" 2>/dev/null; then
    echo "fetching $REV" >&2
    git -C "$SRC" fetch --quiet origin >&2
  fi
  git -C "$SRC" checkout --quiet --detach "$REV" >&2
fi

# Belt and braces: verify rather than assume the checkout did what we asked.
HEAD="$(git -C "$SRC" rev-parse HEAD)"
[ "$HEAD" = "$REV" ] || { echo "error: $SRC is at $HEAD, wanted $REV" >&2; exit 1; }
[ -d "$SRC/cmd" ] || { echo "error: $SRC has no cmd/ — wrong repository?" >&2; exit 1; }

echo "morlock at ${REV:0:12}" >&2
echo "$REV"
