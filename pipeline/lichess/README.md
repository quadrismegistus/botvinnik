# Lichess peer-aggregate pipeline (#268)

Boils lichess open-database monthly dumps into small static per-rating-band
tables that give the skill report (#268) its honest peer baseline: real
distributions, real percentiles, and the time-management baseline that Maia-3
structurally cannot provide (it has no clock model). Runs offline on a dev
machine; the app ships only the output tables, like `book.json` — no runtime
lichess dependency (we have been 401'd before).

## The commensurability invariant (do not break this)

Every number in these tables must be computed by **the same code the app
runs**: the pipeline loads the built `flutter/assets/brain.js` into a bare
context (the `scripts/smoke-brain.mjs` pattern) and uses `brain.winChance`,
`brain.epdKey`, the motif detectors, and (when it exists) the phase function
from there. A reimplemented win-chance curve that drifts by a point would
silently shift every percentile — the exact bug class of two formulas for one
number that the app's own code comments keep warning about. If the pipeline
needs a function the brain does not export, the function is added TO THE BRAIN
first and consumed from the bundle.

## Rating scales

Tables are keyed by **lichess rating bands** (800–2600, step 100; open-ended
tails). The app's user ratings live on other scales (internal WASM elo,
chess.com); the report maps the user onto lichess bands through an explicit,
inspectable conversion at read time. Do not bake any conversion into the
tables — scale mapping is a calibration decision that must stay visible (see
the bot-weakening saga for what silent scale mixing costs).

## Populations and provenance

- Standard chess only; rated games only.
- Split by time-control class — `blitz` / `rapid` / `classical` — because
  clock behavior and blunder rates differ structurally by class. Bullet is
  excluded from v1 (the app has no bullet mode to diagnose).
- Eval-dependent tables (T2–T5, T7) draw on the **analysed subset** (games
  with `%eval` comments). This subset over-represents players who request
  analysis; the bias is documented here, carried in `meta.analysedOnly`, and
  the report's methodology note says so. Clock tables (T1–T2) require `%clk`.
- Every table cell carries its sample count `n`. The report renders a cell
  only above its sample floor; the pipeline never smooths or interpolates an
  empty cell into existence.

## Tables (all: per band × time-class; distributions stored as deciles + n)

- **T1 time-allocation** — think-time behavior with no eval needed: share of
  clock spent by ply buckets (opening/middlegame-by-ply/late), median and
  decile think time per remaining-clock bucket, fraction of moves played in
  under 2s ("premoves and reflexes").
- **T2 clock-pressure** — P(blunder | remaining clock bucket), blunder =
  `wcDrop >= 20` via `brain.winChance` over the game's eval comments. The
  axis's headline claim ("you collapse under 30 seconds — a typical 1500
  doesn't") reads from here.
- **T3 while-winning retention** — per-move `wcDrop` distribution restricted
  to positions with win chance ≥ 70 for the mover: mean drop, blunder rate,
  deciles. Powers "keeping a won game" percentiles.
- **T4 while-losing composure** — the same restricted to ≤ 30. Named
  composure, not swindling: recovering is mostly the opponent blundering, and
  the table must not claim otherwise.
- **T5 endgame** — T3/T4-style numbers past the phase boundary, which is
  `brain.endgameStartPly` (lila's divider rule: majors+minors ≤ 6 across both
  sides) — never a local reimplementation. Finding the boundary replays the
  game, the one place this pipeline touches a board, so T5 runs on a
  **sampling budget**: a per-band×class cap of analysed games, first-come in
  dump order, cap recorded in `meta.caps.t5` and the sampled `n` in each
  cell. No smoothing of unsampled cells.
- **T6 opening** — ply of first out-of-book move (book = the vendored
  `chess-openings` ECO dataset, CC0), and `wcDrop` distribution over plies
  1–12 on the analysed subset.
- **~~T7 tactics~~ — struck, by design, not deferred.** The dumps' `[%eval]`
  comments carry evals ONLY — no best move, no variation — so "the best line
  carries a tactical motif" is uncomputable from this source, and a table
  built from anything less would be the invented-cohort mistake wearing a
  different hat. The tactics axis's peer column comes from Maia-3's
  per-position `P_R(bestUci)` at report time, which was the axis design all
  along; the first README draft was wrong to promise it here.

## Output

`pipeline/lichess/out/peer-tables.json` → reviewed, then shipped as
`flutter/assets/peer-tables.json`. Versioned envelope:

```json
{
  "v": 1,
  "source": "lichess_db_standard_rated_YYYY-MM",
  "generatedAt": "…",
  "brainVersion": 2,
  "meta": { "analysedOnly": ["t2","t3","t4","t5","t7"], "caps": {…} },
  "bands": { "1500": { "blitz": { "t1": {…}, … }, … }, … }
}
```

`brainVersion` pins which bundle computed the numbers; if the brain's
win-chance curve ever changes, the tables regenerate or the report refuses
the mismatch — never silently mixes.

## Development vs production runs

Develop against `lichess_db_standard_rated_2013-01.pgn.zst` (~17 MB — tests
the machinery, but predates `%clk`/widespread evals) plus crafted fixture
PGNs for the clock and eval paths (fixtures live in `fixtures/`, asserted in
tests — never describe a PGN in a comment, assert it). A production month is
a multi-GB download and runs only as an explicit, supervised step — never as
a side effect of tests.
