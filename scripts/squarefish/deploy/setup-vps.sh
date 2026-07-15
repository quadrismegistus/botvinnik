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
cp static/wasm/stockfish.js static/wasm/stockfish.wasm scripts/wasm-engine/
printf '{"type":"commonjs"}\n' >scripts/wasm-engine/package.json
printf '#!/bin/sh\nDIR=$(cd "$(dirname "$0")" && pwd)\nexec node "$DIR/stockfish.js"\n' >scripts/wasm-engine/run.sh
chmod +x scripts/wasm-engine/run.sh

cd "$HOME"
[ -d lichess-bot ] || git clone https://github.com/lichess-bot-devs/lichess-bot
cd lichess-bot
python3 -m venv venv && ./venv/bin/pip -q install -r requirements.txt
python3 - <<PY
import re
cfg = open('config.yml.default').read()
cfg = cfg.replace('token: "xxxxxxxxxxxxxxxxx"', 'token: "${LICHESS_TOKEN}"')
cfg = re.sub(r'dir: "\./engines/"', 'dir: "$HOME/botvinnik-web"', cfg)
cfg = re.sub(r'name: "engine_name"', 'name: "scripts/squarefish/squarefish.sh"', cfg)
open('config.yml','w').write(cfg)
print('config.yml written — REVIEW IT (time_controls, concurrency) before enabling')
PY

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
echo "Review ~/lichess-bot/config.yml, then: sudo systemctl enable --now squarefish"
