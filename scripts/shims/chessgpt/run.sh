#!/bin/sh
# What the gym spawns. Mirrors scripts/wasm-engine/run.sh: resolve our own
# directory so the engine works whatever the caller's cwd is, and exec the
# venv's python so no global install is assumed.
DIR=$(cd "$(dirname "$0")" && pwd)
exec "$DIR/venv/bin/python" "$DIR/chessgpt_uci.py" "$@"
