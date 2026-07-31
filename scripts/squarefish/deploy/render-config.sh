#!/usr/bin/env bash
# Render ~/lichess-bot/config.yml from lichess-bot's own default + our
# config.overrides.yml, then inject the token and the engine dir.
#
#   LICHESS_TOKEN=<bot:play token> bash scripts/squarefish/deploy/render-config.sh
#
# Split out of setup-vps.sh so an EXISTING deployment can pick up a config
# change — new chat, different time controls — without re-running a script that
# also installs packages and rewrites the systemd unit. A `git pull` does NOT
# re-render the config; this is what does.
#
# Idempotent. Prints the absolute path it wrote, because the path depends on
# which user the service runs as and hardcoding it in docs got it wrong (#149).
set -euo pipefail

: "${LICHESS_TOKEN:?set LICHESS_TOKEN (bot:play scope)}"
BOT_DIR="${BOT_DIR:-$HOME/lichess-bot}"
REPO_DIR="${REPO_DIR:-$HOME/botvinnik-web}"

[ -f "$BOT_DIR/config.yml.default" ] || {
	echo "error: no config.yml.default at $BOT_DIR — is lichess-bot cloned there?" >&2
	exit 1
}

cd "$BOT_DIR"
LICHESS_TOKEN="$LICHESS_TOKEN" REPO_DIR="$REPO_DIR" ./venv/bin/python - <<'PY'
import os
import yaml

repo = os.environ['REPO_DIR']
overrides = yaml.safe_load(open(f'{repo}/scripts/squarefish/deploy/config.overrides.yml'))
cfg = yaml.safe_load(open('config.yml.default'))


def merge(base, over):
    """Deep-merge, so upstream's schema stays authoritative and we carry deltas."""
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            merge(base[k], v)
        else:
            base[k] = v


merge(cfg, overrides)
cfg['token'] = os.environ['LICHESS_TOKEN']
cfg.setdefault('engine', {})['dir'] = repo

# Fail loudly rather than writing a config that quietly means nothing. If the
# bridge renames these, the merge would leave dead keys and the bot would go
# silent with no error anywhere — which is how the chat went undocumented for
# months in the first place.
for key in ('hello', 'goodbye', 'hello_spectators', 'goodbye_spectators'):
    if key not in cfg.get('greeting', {}):
        raise SystemExit(f'greeting.{key} missing after merge — has lichess-bot renamed it?')

with open('config.yml', 'w') as f:
    yaml.safe_dump(cfg, f, sort_keys=False, allow_unicode=True)
print('wrote', os.path.abspath('config.yml'))
PY
