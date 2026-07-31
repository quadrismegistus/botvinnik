# SquareFish — a Square on lichess

The shaped bot as a UCI engine, deployable under the standard
[lichess-bot](https://github.com/lichess-bot-devs/lichess-bot) bridge. Purpose:
after ~100 rated human games, the bot account has a REAL lichess rating — the
definitive human-pool anchor for our scale's low end, where no reference bot
exists (every borrowed anchor — maia, dala, the retros — was someone else's
config; this one is exactly ours).

## The engine

```
npx tsx scripts/squarefish/squarefish-uci.mts --label 1050
```

Same code path the website's Squares use: the app's WASM lite-single
Stockfish (MultiPV-12 at the label's calibrated depth) + `shapedBotMove`
(miss-the-tactic, sticky per-game misses, directional conversion). The seed
re-rolls on `ucinewgame`. Clock parameters are ignored — moves take well under
a second, so any time control from blitz up is safe (avoid bullet: the bridge
overhead, not the engine, would lose on time).

Pick the label from the CURRENT wasm knot table in `brain/bot.ts` — e.g. if
the target is "play like lichess ~900", find the label whose measured strength
is ≈ 900 + 240 (the internal-scale offset). Re-check after any recalibration.

## One-time lichess setup (human steps)

1. Create a FRESH lichess account (it must have played zero games). Name it
   something honest, e.g. `SquareFish-900`. Lichess allows bot accounts; one
   account per bot.
2. Create a personal API token for that account with the **bot:play** scope:
   https://lichess.org/account/oauth/token
3. Upgrade the account to a BOT (irreversible for that account):
   `curl -d '' https://lichess.org/api/bot/account/upgrade -H "Authorization: Bearer <token>"`

## Bridge setup

```
git clone https://github.com/lichess-bot-devs/lichess-bot
cd lichess-bot && python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
```

**Do not hand-edit `config.yml`.** Everything about this bot's behaviour lives
in `deploy/config.overrides.yml`, which `deploy/setup-vps.sh` deep-merges into
lichess-bot's own `config.yml.default` before injecting the token and the engine
dir. That file is the record: engine wiring, what challenges are accepted, and
the chat — including what SPECTATORS are told, which is different from what the
opponent is told and is where this account explains what it is.

Until #149 the config existed only on the server, in no repo, so a rebuild of
the box would have silently lost it and nothing here documented the chat at all.

The merge keeps upstream authoritative: `config.yml.default` ships with whatever
bridge version is installed, so our file only has to carry the deltas and cannot
rot against a schema change. The setup script asserts the four `greeting` keys
survive the merge, because a renamed key would otherwise leave the bot silently
mute with no error anywhere.

`squarefish.sh` (committed alongside) execs the tsx entrypoint with the
chosen label. Run the bridge with `./venv/bin/python lichess-bot.py` on any
machine that stays up (this Mac, or a $4 VPS + a clone of botvinnik-web).

## Reading the result

Rating stabilizes after ~50-100 rated games (weak bots get farmed quickly —
that's how maia1 collected 8M games). Compare the account's rapid rating to
the label's intended display elo: agreement within ~±100 validates the whole
scale bottom; disagreement is the measurement we've been unable to make any
other way.

## VPS deployment (recommended — rating collection wants uptime)

WASM is the right substrate for lichess: it's byte-identical to what the
website runs (the rating anchors the public product), and it needs no
compiled chess software on the server — Node 24 is the only requirement.

```
export LICHESS_TOKEN=<bot:play token>
export SQUAREFISH_LABEL=<label from the current wasm knots>
bash scripts/squarefish/deploy/setup-vps.sh
# the script PRINTS the absolute config.yml path it wrote — review that, then:
sudo systemctl enable --now squarefish
journalctl -fu squarefish     # watch it accept its first challenges
```

The service restarts on failure and survives reboots. Expect ~1-3s/move on a
modest VPS — keep bullet out of config.yml's time_controls.

## Updating a running deployment

The bot runs `brain/` **sources** through tsx, not the built `brain.js`, so a
pull is genuinely enough — there is no bundle step on the server.

```
ssh <vps>
cd ~/botvinnik-web && git pull && npm ci
sudo systemctl restart squarefish
journalctl -fu squarefish
```

**Add a `deployments.json` entry every time**, and check first whether anything
in `brain/bot.ts` or its imports actually changed. That file is what makes the
rating series interpretable: this account's rating is a measurement instrument,
and any change to `shapedBotMove` invalidates the games played before it. An
update that changes nothing should say so explicitly — that is what licenses
pooling the games either side of it.

What to check, and it is narrower than it looks. The bot calls exactly
`shapedBotMove`, `shapedSearchDepth` and `avoidRepetition`. `shapedSearchDepth`
is arithmetic on the label; `shapedBotMove` reads no calibration table. The
`SHAPED_KNOTS*` tables are consumed only by `shapedLabelFor` and
`shapedStrengthRange`, which convert between a target Elo and a label — and the
bot is GIVEN its label, so a re-measured grid does not reach it.
