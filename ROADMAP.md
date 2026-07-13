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

- **Unified Moves tab** — SHIPPED 2026-07-12 as the "Opening Book" panel
  (desktop sidebar + mobile sheet tab): Lichess Explorer stats (lichess db
  + masters, W/D/L bars, opening names) merged with engine lines and
  softmax confidence. NOTE: the explorer API moved to
  `explorer.lichess.org` and requires an OAuth2 bearer token — the panel
  prompts for a free no-scope lichess token on 401 and keeps it in
  localStorage (`botvinnik-lichess-token`).
- **PGN import** — paste/upload a PGN for review/analysis (export shipped).
- **Practice history detail** — per-item pass/fail trail in the practice list
  (attempts/correct are already stored), maybe a small sparkline.
- **Bot ELO calibration harness** — BUILT 2026-07-13:
  `npx tsx scripts/calibrate-bots.mts` (needs `brew install stockfish`).
  Ladder of settings play each other headlessly (checkpointed/resumable,
  parallel across cores, ~20+ games/min), move selection reuses the app's
  exact band recipe (`engine/botRecipe.ts`, shared with `analyzeBotMove`)
  and `selectBotMove` sampler; results feed a Bradley–Terry fit anchored on
  the UCI_Elo band; the report flags per-point deltas and non-monotonic
  seams. Still to do once the numbers are in: RE-MAP the manual bands
  (α curve, skill/depth line) so the labels mean what they say, then rerun
  to verify. Caveat printed by the script: native SF at movetime 400 is
  stronger than the app's WASM for the ≥1320 band, so treat that anchor as
  an upper bound.
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
- **Mobile layout** — ALL PHASES SHIPPED (2026-07-12). Below 860px: board
  pinned at top, every panel a tab in a draggable bottom sheet
  (`BottomSheet.svelte`: peek/half/full detents, snap-on-release, handle
  tap toggles peek/half). Panel bodies are snippets in `+page.svelte`
  shared verbatim by the desktop sidebar and the sheet tabs — keep it
  that way so the layouts can't drift. LineHover is tap-to-toggle on
  `(hover: none)` (with the synthesized-mouseenter guard). Verified under
  Playwright iPhone-13 emulation.
- **Native mobile app** — Tauri 2 targets iOS/Android and the existing web
  build ships as-is inside its webview. The WASM engine (lite-single,
  7MB) bundles with zero work: single-threaded, so no
  SharedArrayBuffer/COOP/COEP issues under custom URL schemes — a v1
  mobile app needs NO engine changes. The native-engine upgrade
  (multi-threading, ~2-4x per-core) can't use the sidecar trick (iOS
  forbids spawning processes): compile Stockfish into the app and speak
  UCI over an in-process channel — a third `EngineTransport` behind the
  existing `setEngineTransport()` seam. References:
  - Build for ARM: `make -j profile-build ARCH=armv8` (or
    `armv8-dotprod` on recent SoCs, `apple-silicon` on Macs); Android
    cross-compile with `COMP=ndk` (NDK ≥ r21e) — see
    https://official-stockfish.github.io/docs/stockfish-wiki/Compiling-from-source.html
    and https://chess.stackexchange.com/questions/28022/compile-stockfish-optimized-for-arm64-v8a
  - iOS embedding pattern (predates Tauri but the shape holds): compile
    the Stockfish sources into the app target, rename its `main()`, run
    the UCI loop on a background thread, talk to it over in-process
    pipes/queues — an Objective-C++ (or, for Tauri, Rust `cxx`) shim:
    https://stackoverflow.com/questions/37253950/stockfish-chess-engine-integration-with-ios-project-in-swift
  - Note the wiki only documents standalone-binary builds; the
    embed-as-library step (rename `main`, drive `Stockfish::main_loop`
    from a thread) is on us.
- **LLM polish layer for explanations** — optional, user-supplied API key,
  constrained to restating the detected facts (every SAN token in the output
  must appear in the supplied lines, else fall back to templates). The
  [chess-reviews-from-youtube](https://www.kaggle.com/datasets/huberthamelin/chess-reviews-from-youtube)
  dataset could also be phrase-mined to make the templates sound more human
  without any model at all.
- **Release-build blank window on Linux** — the release binary's embedded-
  asset webview stalls at about:blank on ubuntu runners (debug + devUrl works
  fine, macOS unaffected). This is why `release.yml` ships macOS + Windows
  only; add a Linux matrix entry once fixed. Cheapest path to a fix: build a
  local ubuntu+webkit2gtk Docker repro so iterations are minutes, not 15-min
  CI compiles.
- **Verify the Windows desktop build** — `release.yml` bundles Windows
  best-effort but the shell has never been run there; confirm the Rust
  sidecar bridge spawns stockfish.exe and analysis reaches the UI, then drop
  the "unverified" caveat.
- **Review-UI polish** (nits from the 2026-07-13 code review):
  - `WinChanceChart` clips its classification dots (r=4) at extreme win
    chances — the redesign dropped the vertical padding and the frame is
    `overflow: hidden`; the tooltip clamp also assumes ≥120px chart width.
  - The review move table (`.rv-table`, 220px max-height) doesn't scroll the
    selected move into view when stepping with ‹/›, so mid-game the
    highlight goes offscreen.
- **Square control refinements** (v1 shipped 2026-07-13 as the "Control"
  toggle — `engine/control.ts`, tint via chessground `highlight.custom`,
  green = bottom side, red = top): possible next steps are intensity
  gradation by exchange margin, x-ray attackers in the swap lists (batteries
  currently invisible), an option to tint *held* occupied squares (v1 tints
  occupied squares only when the piece is outright winnable, to avoid
  repainting the whole board), and skipping the null-move flip so control
  renders while in check.

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
- Accuracy = lichess's official algorithm (lila `AccuracyPercent.scala`):
  per-move `103.1668·e^(−0.04354·wcDrop) − 3.1669 + 1` clamped 0–100, game
  score per side = (win%-volatility-weighted mean + harmonic mean) / 2. The
  HARMONIC mean is what makes blunders hurt (one 0-accuracy move zeroes it,
  collapsing the score to half the weighted mean) — the previous plain
  arithmetic mean ran ~15 points above chess.com for the same game (Ryan's
  2026-07-13 comparison: 87.6/91.4 vs CAPS 71.3/80.0). chess.com's CAPS is
  proprietary and will still read somewhat lower; our imports also analyze
  at fixed 300K nodes, shallower than their review. Stored games that kept
  full move data are recomputed on load (`refreshAccuracies`); moves-less
  imports keep their import-time numbers.
- Threat probe material rule (2026-07-13): when the probe's PV never reaches
  a quiet ply, the raw line count credits mid-exchange captures (a 1-ply pv
  made "Nxf4" a threat against a queen-defended bishop) — `findThreat` now
  falls back to a static first-capture guess (victim undefended, or worth
  more than the capturer) instead of `materialOverLine`.
- Mini boards (LineHover previews, insight-card boards) take an
  `orientation` prop fed from the main board — they used to orient by the
  evidence line's side to move, which rendered mirrored positions that read
  as stale/different (Ryan's 2026-07-13 report).
- Motif detector invariants (2026-07-13 hardening): a fork/pin/skewer claim
  must survive "so what does the opponent just do?" — the forker can't be en
  prise, the piece behind a pin/skewer must be profitably takeable, a pawn is
  never file-pinned against a non-king (its pushes stay on the ray), a king
  is never a "cheapest attacker" (VAL['k']=0 — it only takes undefended
  pieces), and "traps" claims require the trap to be NEW (pre-move probe with
  the turn flipped). Detector semantics changes must bump MOTIF_TAGS_VERSION
  (re-tags practice items on load) — stored GAME prose is separately
  re-verified by `sanitizeExplanations` (gameStore), which re-runs the
  fork/pin/skewer detectors over saved sentences on every load and rewrites
  or drops what no longer holds.
- **The engine is a single-slot supersede queue** (`queueSearch` in
  stockfish.ts): a new request resolves any *pending* request empty and
  `stop`s the *running* one. Anything that fires a background search after
  analysis settles must mind the ordering — the threat probe once landed a
  few ms after `analyzeBotMove` and stopped the bot's calibrated 400ms
  search mid-think (found in the 2026-07-13 review; `computeThreat` now
  skips positions where the bot is about to reply). Threat arrows are also
  fen-tagged: display checks `threat.fen === game.fen` so a stale arrow
  can't survive a move while the next probe is still running.
- localhost and the deployed site are separate origins with separate
  storage; Export/Import data is the bridge.
