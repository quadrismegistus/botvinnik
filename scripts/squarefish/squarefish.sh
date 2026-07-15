#!/bin/sh
# lichess-bot entrypoint: exec SquareFish at the deployed label.
# Label choice: see README.md (map target lichess elo through the wasm knots).
DIR=$(cd "$(dirname "$0")/../.." && pwd)
cd "$DIR"
exec npx tsx scripts/squarefish/squarefish-uci.mts --label "${SQUAREFISH_LABEL:-1050}"
