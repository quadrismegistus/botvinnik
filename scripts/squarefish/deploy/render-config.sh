#!/usr/bin/env bash
# Render ~/lichess-bot/config.yml from lichess-bot's own default + our
# config.overrides.yml, then inject the token and the engine dir.
#
#   bash scripts/squarefish/deploy/render-config.sh
#
# On an existing box the token is read back out of the current config.yml, so
# updating never means handling the secret again. A first install has no
# config.yml and must pass LICHESS_TOKEN=<bot:play token>.
#
# Split out of setup-vps.sh so an EXISTING deployment can pick up a config
# change — new chat, different time controls — without re-running a script that
# also installs packages and rewrites the systemd unit. A `git pull` does NOT
# re-render the config; this is what does.
#
# Idempotent. Prints the absolute path it wrote, because the path depends on
# which user the service runs as and hardcoding it in docs got it wrong (#149).
set -euo pipefail

BOT_DIR="${BOT_DIR:-$HOME/lichess-bot}"
REPO_DIR="${REPO_DIR:-$HOME/botvinnik-web}"

[ -f "$BOT_DIR/config.yml.default" ] || {
	echo "error: no config.yml.default at $BOT_DIR — is lichess-bot cloned there?" >&2
	exit 1
}

# Reuse the token already in config.yml when one is not supplied. Updating an
# existing deployment should not mean handling the secret again: it is already
# on the box, and asking for it invites pasting it into a shell history or a
# chat window. A first install has no config.yml and must pass LICHESS_TOKEN.
if [ -z "${LICHESS_TOKEN:-}" ] && [ -f "$BOT_DIR/config.yml" ]; then
	LICHESS_TOKEN="$(cd "$BOT_DIR" && ./venv/bin/python -c \
		"import yaml;print(yaml.safe_load(open('config.yml')).get('token',''))")"
	[ -n "$LICHESS_TOKEN" ] && echo "reusing the token already in config.yml"
fi
: "${LICHESS_TOKEN:?set LICHESS_TOKEN (bot:play scope) — no existing config.yml to reuse it from}"

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


def drop_nulls(node):
    """A null in the overrides DELETES the key.

    lichess-bot's default config is written for a full Stockfish and sends
    every uci_option to whatever engine it launches, so an option our engine
    does not declare crashes the handshake. There is no value that works —
    the key has to be gone.
    """
    if isinstance(node, dict):
        for k in [k for k, v in node.items() if v is None]:
            del node[k]
        for v in node.values():
            drop_nulls(v)


drop_nulls(cfg)
cfg['token'] = os.environ['LICHESS_TOKEN']
cfg.setdefault('engine', {})['dir'] = repo

# Fail loudly if the bridge has renamed a greeting key, because the symptom
# otherwise is a bot that silently stops talking.
#
# Checked against the DEFAULT, not the merged config. The first version of this
# checked the merge — which our own overrides populate, so all four keys were
# always present and the guard could never fail. A guard a missing subject
# satisfies is not a guard.
# lichess silently drops a chat message over 140 characters — the bridge logs a
# warning and moves on, so the only symptom is a greeting nobody ever sees.
#
# Measured AFTER substitution, which is the whole point. The first version of
# this counted the template: `{me}` is 4 characters here and 14 on the wire as
# `SquareFish-900`, so a line that measured 135 arrived as 145 and was dropped —
# a length guard that passed the exact message it existed to catch. Worst case
# assumed, since lichess usernames run to 20 characters.
LONGEST_NAME = 'x' * 20
for key, text in (cfg.get('greeting') or {}).items():
    if not isinstance(text, str):
        continue
    on_the_wire = text.replace('{me}', LONGEST_NAME).replace('{opponent}', LONGEST_NAME)
    if len(on_the_wire) > 140:
        raise SystemExit(
            f'greeting.{key} reaches {len(on_the_wire)} characters once {{me}}/'
            f'{{opponent}} are substituted (template is {len(text)}); lichess '
            'drops anything over 140 and says nothing to the player.'
        )

default_greeting = yaml.safe_load(open('config.yml.default')).get('greeting', {})
for key in ('hello', 'goodbye', 'hello_spectators', 'goodbye_spectators'):
    if key not in default_greeting:
        raise SystemExit(
            f'greeting.{key} is not in this lichess-bot\'s config.yml.default — '
            'renamed upstream? Our override would write a key nothing reads.'
        )

# Back up whatever is there before overwriting it. config.yml has historically
# been hand-edited on the server and nowhere else (#149) — this script replaced
# one such file and took the SquareFish uci_options trim with it, crash-looping
# the bot. Cheap insurance against the next thing that was only on this box.
if os.path.exists('config.yml'):
    import shutil
    from time import time
    shutil.copy2('config.yml', f'config.yml.bak-{int(time())}')

with open('config.yml', 'w') as f:
    yaml.safe_dump(cfg, f, sort_keys=False, allow_unicode=True)
print('wrote', os.path.abspath('config.yml'))
PY
