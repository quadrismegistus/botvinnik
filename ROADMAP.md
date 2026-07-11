# Roadmap

What's planned, roughly in priority order. See [README](README.md) for what's already shipped.

## Next up

### Import games from Lichess / chess.com and mine them for puzzles
Both sites have public, CORS-enabled APIs for downloading any player's games
(Lichess: NDJSON stream per user; chess.com: monthly PGN archives). Imported
games land in the Games archive and their mistakes feed the practice list via
the existing collector (win-chance threshold, labels, explanations).

- **Phase 1 — Lichess with server evals.** The export API's `evals` option
  includes per-move computer evaluations for any game Lichess has analyzed —
  win-chance drops fall straight out, no local engine time. Instant mistake
  extraction for those games.
- **Phase 2 — local analysis queue.** For chess.com games and unanalyzed
  Lichess games: background queue at depth 12–14, ~1.5–2 min per game
  (~80 positions × ~1s), with a progress bar. The analysis cache makes
  repeated openings progressively free.

### "Practice this" from game review
Archived games already store fenBefore / best move / explanation for every
graded move. One button on a reviewed blunder turns it into a practice item —
review feeds the drill loop, zero new analysis.

### More motif detectors
Port the remaining lichess-puzzler `cook.py` detectors: pin, skewer,
discovered attack, trapped piece. Unlocks:
- richer explanations ("this pins the knight against the queen")
- **motif-tagged practice** — drill only back-rank mistakes, only forks, etc.

### Hint button in practice
Show the detected fact ("there's a fork here") before revealing the move.
The explanation layer already computes it; this is UI only.

## Later

- **Unified Moves tab** — the last unported en-croissant visualization:
  opening-book stats from the Lichess Explorer API (games played, win rates,
  master games) merged with engine lines.
- **Commentary in review mode** — the YouTube commentary lookup already works
  in play mode; run the same placement match on stored review positions.
- **PGN export/import buttons** — per-game download from the archive (the PGN
  is already stored); import a pasted PGN for review/analysis.
- **Practice history detail** — per-item pass/fail trail in the practice list
  (attempts/correct are already stored), maybe a small sparkline.
- **Bot ELO calibration harness** — bots play each other headlessly
  (Playwright or node) to estimate each band's true strength; the labels
  ("1800") are currently taken on faith from UCI_Elo / Skill Level.
- **Keyboard shortcuts** — n = next puzzle, r = retry, arrows = review nav.
- **File System Access autosave** — beyond Export/Import: write backups
  directly to a user-chosen local file (Chromium-only).
- **LLM polish layer for explanations** — optional, user-supplied API key,
  constrained to restating the detected facts (every SAN token in the output
  must appear in the supplied lines, else fall back to templates). The
  [chess-reviews-from-youtube](https://www.kaggle.com/datasets/huberthamelin/chess-reviews-from-youtube)
  dataset could also be phrase-mined to make the templates sound more human
  without any model at all.
- **Formalize e2e tests** — the Playwright verification scripts (engine flow,
  practice loop, game review, layout) live outside the repo today; port them
  to `@playwright/test` and run against the built bundle in CI (~1 min of
  engine time per run).

## Design notes / known quirks

- Practice pass = the attempt labels **good or better** (win-chance loss
  < 5%, the good/inaccuracy boundary) so the ✓/✗ can never contradict the
  label chip. %Best was rejected as the pass metric: it's uniform in
  centipawns, so it fails "excellent" moves at equality and nearly everything
  in won positions.
- Material claims in explanations count captures only up to the last quiet
  ply and quote exactly the counted window — never trust a PV material count
  that ends mid-exchange.
- localhost and the deployed site are separate origins with separate
  storage; Export/Import data is the bridge.
