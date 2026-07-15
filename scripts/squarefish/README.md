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

Pick the label from the CURRENT wasm knot table in `src/lib/bot.ts` — e.g. if
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
cp config.yml.default config.yml
```

In `config.yml`:

```yaml
token: "<token>"
engine:
  dir: "/Users/ryan/github/botvinnik-web"
  name: "scripts/squarefish/squarefish.sh"   # wrapper below
  protocol: "uci"
  ponder: false
challenge:
  concurrency: 1
  accept_bot: true
  variants: ["standard"]
  time_controls: ["blitz", "rapid", "classical"]
```

`squarefish.sh` (committed alongside) execs the tsx entrypoint with the
chosen label. Run the bridge with `./venv/bin/python lichess-bot.py` on any
machine that stays up (this Mac, or a $4 VPS + a clone of botvinnik-web).

## Reading the result

Rating stabilizes after ~50-100 rated games (weak bots get farmed quickly —
that's how maia1 collected 8M games). Compare the account's rapid rating to
the label's intended display elo: agreement within ~±100 validates the whole
scale bottom; disagreement is the measurement we've been unable to make any
other way.
