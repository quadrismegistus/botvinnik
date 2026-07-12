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

- **In-app importer**: Games panel form with progress bar and Cancel;
  dedicated import engine pool (one WASM worker on web, native sidecar pool
  on desktop) so live play keeps its own engine. Live on web and desktop.


## Later

- **Unified Moves tab** — the last unported en-croissant visualization:
  opening-book stats from the Lichess Explorer API (games played, win rates,
  master games) merged with engine lines.
- **PGN import** — paste/upload a PGN for review/analysis (export shipped).
- **Practice history detail** — per-item pass/fail trail in the practice list
  (attempts/correct are already stored), maybe a small sparkline.
- **Bot ELO calibration harness** — bots play each other headlessly
  (Playwright or node) to estimate each band's true strength; the labels
  ("1800") are currently taken on faith from UCI_Elo / Skill Level.
- **File System Access autosave** — beyond Export/Import: write backups
  directly to a user-chosen local file (Chromium-only).
- **Engine settings panel** — a small "Engine" section (sidebar SidePanel,
  persisted like the bot settings) now that web/desktop hardware profiles
  genuinely differ:
  - *Analysis effort*: time slice + depth ceiling, presented as
    quick / normal / deep / unlimited presets with the raw numbers visible
  - *Lines* (MultiPV 1–5) — note MULTIPV is baked into the analysis-cache
    key, so changing it namespaces the cache (old entries just age out)
  - *Threads / Hash* — native shell only; default cores−2 / 256MB
  Deliberately NOT exposed: grading standards (practice d14, collect gates,
  batch node budgets) — verdicts should mean the same thing on every
  machine and every day, so they stay fixed constants. The collect
  *threshold* (win%-drop) stays where it is in the Practice panel — that's
  taste, not measurement.
- **Mobile layout** — the panel architecture ports as-is; the shell around it
  changes. Chess apps converge on: board fixed at top (full width in
  portrait), everything else in a draggable **bottom sheet with tabs**
  (Insights / Lines / Practice / Games) rather than a scrolling sidebar.
  Phased:
  1. CSS breakpoint pass on the web app (board 100vw, panels stack, sticky
     section-jump strip) — makes the deployed site usable on phones cheaply.
  2. Real bottom-sheet + tab shell behind a viewport check.
  3. Touch replacements for hover affordances: LineHover previews become
     tap-to-toggle/long-press; everything else (tree pan, move grid,
     promotion picker) is already touch-fine.
  Engine on mobile: WASM works day one in any mobile webview. A native
  mobile engine can't use the sidecar trick (iOS forbids spawning
  processes) — it means compiling Stockfish into the app and speaking UCI
  over an in-process channel, which slots into the existing transport
  interface as a third implementation (Tauri 2 does target iOS/Android).
- **LLM polish layer for explanations** — optional, user-supplied API key,
  constrained to restating the detected facts (every SAN token in the output
  must appear in the supplied lines, else fall back to templates). The
  [chess-reviews-from-youtube](https://www.kaggle.com/datasets/huberthamelin/chess-reviews-from-youtube)
  dataset could also be phrase-mined to make the templates sound more human
  without any model at all.
- **Release-build blank window on Linux** — the release binary's embedded-
  asset webview stalls at about:blank on ubuntu runners (debug + devUrl works
  fine, macOS unaffected); investigate before shipping Linux bundles.

## Design notes / known quirks

- Testing layout: vitest = `src/**/*.test.ts` (pure logic; 31 tests),
  `e2e/` = @playwright/test against the built bundle (6 tests; local Chrome
  via `npm run test:e2e`, chromium in CI), `npm run test:rust` = bridge unit
  tests, tauri e2e = Linux CI only (no macOS WebDriver backend).

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
