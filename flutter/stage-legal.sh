#!/usr/bin/env bash
# Copy the repo-root licence files into the Flutter asset bundle, so the GPL
# obligation — the licence text and third-party notices travelling with the
# binary — is met on every platform (Settings → About reads these).
#
#   assets/legal/LICENSE               <- ../LICENSE
#   assets/legal/THIRD-PARTY-NOTICES.md <- ../THIRD-PARTY-NOTICES.md
#
# These copies ARE committed (unlike brain.js they need no build), and CI runs
# this script then `git diff --exit-code` — so a change to the root files that
# is not mirrored here fails the build rather than shipping a stale licence.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

mkdir -p assets/legal
cp ../LICENSE assets/legal/LICENSE
cp ../THIRD-PARTY-NOTICES.md assets/legal/THIRD-PARTY-NOTICES.md

echo "staged assets/legal/ (LICENSE, THIRD-PARTY-NOTICES.md)"
