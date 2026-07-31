#!/usr/bin/env bash
# SquareFish VPS setup (Debian/Ubuntu-ish). Run as a normal user with sudo.
# Installs node 24, clones botvinnik-web + lichess-bot, wires the systemd
# service. You supply: the lichess BOT token and the label.
set -euo pipefail

: "${SQUAREFISH_LABEL:?set SQUAREFISH_LABEL (see scripts/squarefish/README.md)}"
: "${LICHESS_TOKEN:?set LICHESS_TOKEN (bot:play scope, account already upgraded to BOT)}"

# node 24 (js-chess-engine devDependency demands >=24 for npm ci)
if ! command -v node >/dev/null || [ "$(node -e 'console.log(process.versions.node.split(".")[0])')" -lt 24 ]; then
	curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
	sudo apt-get install -y nodejs
fi
sudo apt-get install -y git python3-venv

cd "$HOME"
[ -d botvinnik-web ] || git clone https://github.com/quadrismegistus/botvinnik.git botvinnik-web
cd botvinnik-web && git pull && npm ci
# stage the WASM engine wrapper the same way the calibration scripts do
mkdir -p scripts/wasm-engine
cp vendor/wasm/stockfish.js vendor/wasm/stockfish.wasm scripts/wasm-engine/
printf '{"type":"commonjs"}\n' >scripts/wasm-engine/package.json
printf '#!/bin/sh\nDIR=$(cd "$(dirname "$0")" && pwd)\nexec node "$DIR/stockfish.js"\n' >scripts/wasm-engine/run.sh
chmod +x scripts/wasm-engine/run.sh

cd "$HOME"
[ -d lichess-bot ] || git clone https://github.com/lichess-bot-devs/lichess-bot
cd lichess-bot
python3 -m venv venv && ./venv/bin/pip -q install -r requirements.txt
# Render config.yml from lichess-bot's default + our committed overrides. Its
# own script, so an existing box can re-render after a config change without
# re-running any of the above (#149).
LICHESS_TOKEN="$LICHESS_TOKEN" bash "$HOME/botvinnik-web/scripts/squarefish/deploy/render-config.sh"

sudo tee /etc/systemd/system/squarefish.service >/dev/null <<UNIT
[Unit]
Description=SquareFish lichess bot
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/lichess-bot
Environment=SQUAREFISH_LABEL=$SQUAREFISH_LABEL
ExecStart=$HOME/lichess-bot/venv/bin/python lichess-bot.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
echo "Review the config.yml path printed above, then: sudo systemctl enable --now squarefish"
