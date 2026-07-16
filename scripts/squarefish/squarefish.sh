#!/bin/sh
# lichess-bot entrypoint: exec SquareFish at the deployed label.
# Label choice: see README.md (map target lichess elo through the wasm knots).
DIR=$(cd "$(dirname "$0")/../.." && pwd)
cd "$DIR"
# SQUAREFISH_SCAN=1 enables the v4 scan model (label must be a v4-curve label)
exec npx tsx scripts/squarefish/squarefish-uci.mts --label "${SQUAREFISH_LABEL:-1050}" ${SQUAREFISH_SCAN:+--scan}
