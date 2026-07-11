# Roadmap

What's planned, roughly in priority order. See [README](README.md) for what's already shipped.

## Next up

### Import games from chess.com / unanalysed Lichess games (phase 2)
Shipped so far:
- **Phase 1**: the Games panel imports any Lichess user's **analysed** games
  via the server's per-move evals — instant, no engine time.
- **Offline archive analyzer** (`scripts/analyze-chesscom.mts`): downloads a
  chess.com player's full archive, analyzes every position with native
  Stockfish (parallel workers, in-run FEN dedupe, resumable per-month
  checkpoints, ~18 games/min on an M-series laptop), grades with the same
  code as the Lichess importer, and writes a backup JSON for "Import data".
  Run: `brew install stockfish && npx tsx scripts/analyze-chesscom.mts <user>`.

Remaining:
- **In-app trickle importer** for new chess.com games and unanalysed Lichess
  games: browser background queue at depth 12–14 (~2 min/game) with progress,
  for people who won't run a terminal command.
- Explanations for imported moves (fact detectors over the stored best
  variations as a cheap pass).

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
Tiered hints before the full reveal, all computed from facts the explanation
layer already detects on the stored best line:
1. **First click** — name the fact family, no squares: "there's a fork
   available", "you can win material", "there's a mate".
2. **Second click** — highlight the piece that should move (origin square
   only, not the destination).
3. **Third click** — full reveal (today's "Show best").
Each hint tier used could scale the spaced-repetition credit (a pass after
two hints counts less than a cold pass).

### Line meaning summaries
Narrate the material story of a PV: "rooks get traded, then your queen is
lost", "wins a pawn, with check". Zero engine cost — the line is already
computed; a `summarizeLine()` walks it with chess.js, pairs captures into
trades (recapture on the same square) vs. net wins/losses by piece class, and
notes checks/promotions/mate. Slots into the facts-first explanation layer and
its templates; the quiet-ply rule from material claims applies here too.

## Later

- **Win-chance chart** — small collapsible chart of White vs Black win chance
  over the course of the game (the per-ply evals already live in the move
  grades and in stored games, so this is pure rendering); also useful inside
  game review as a click-to-jump timeline.
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
- **Resign button** — ends the current game as a loss for the resigner and
  **always** archives it to the Games tab (unlike New, which only auto-saves
  abandoned games of 10+ plies). Result stored as 1-0/0-1, PGN gets a
  "resignation" termination comment.
- **Keyboard shortcuts** — n = next puzzle, r = retry, arrows = review nav.
- **File System Access autosave** — beyond Export/Import: write backups
  directly to a user-chosen local file (Chromium-only).
- **Desktop shell (Tauri)** — wrap this same SvelteKit app in Tauri with a
  native Stockfish sidecar: full-strength NNUE on all cores (10–50× the
  single-threaded WASM engine, which is capped by GitHub Pages' lack of
  COOP/COEP headers → no SharedArrayBuffer → no threads). Would fold the
  offline analyzer into the app itself. Full circle: en-croissant, which this
  project simplified away from, is exactly this architecture.
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
