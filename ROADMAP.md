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
  seams.
  **FIRST RESULTS (2026-07-13, native SF, 440 games, anchored on the
  UCI_Elo band):** label→fitted: 100→47, 300→348, 500→686, 700→955,
  800→1425, 1000→1758, 1200→2009, 1320→1428 (⚠ NON-MONOTONIC, −580 vs
  1200), 1600→1697, 2000→1795. Findings: (1) the Skill/depth band is
  wildly overpowered — even Skill 0 at depth 1 plays ~1425; (2) the
  700→800 seam is a ~470-Elo cliff AND a genuine coverage gap (no setting
  produces ~1000–1400); (3) the UCI_Elo band is compressed (680 nominal
  spread → ~370 measured at movetime 400) and sits entirely inside the
  skill band's range. NEXT: redesign the bands, not just relabel — extend
  the sampler band upward to fill the gap, re-map the skill band onto its
  measured 1400–2000 range, reserve UCI_Elo for the top (likely at a
  longer movetime, extend the ladder past 2000 to measure it), rerun to
  verify; eventually rerun with the app's actual WASM lite-single via
  `--engine` (the native big net inflates the fixed-depth bands somewhat).
  Raw data: data/bot-calibration.json (local, gitignored).
  **REDESIGN SHIPPED (5d47024):** botSpec maps requested ELO through
  measured knots — sampler (α 0.1→8, geometric interp) covers 100–2100
  continuously, UCI_Elo covers the top; Skill band deleted.
  **CALIBRATION CLOSED on native engine (9498d21):** the 560-game verify
  ladder fit is monotonic with every rung's slope within n=40 noise of 1.0
  once two flagged spots were resolved — (1) the 2700→3000 top rung bought
  only ~+80 real Elo (engine saturated at UCI_Elo 3190; movetime stretch
  buys nothing), so the movetime knot is gone and the slider caps at **2800**
  (the honest ceiling); (2) the 900→1100 "+236" kink was a 3/40 tail sample
  — an 80-game re-measure put the real gap at 283 (+83, ~1σ, within
  tolerance), so no knot changed.
  **WASM SUBSTRATE CALIBRATED (5cf16ff) — both engines now honest.** The app
  runs two engines: native (desktop/Tauri, big net) and Stockfish.js (web,
  small lite-single net), so botRecipe holds two measured knot tables behind
  `setBotSubstrate()` — web defaults wasm, Tauri flips to native. The WASM
  table was measured on the app's real engine (scripts/wasm-engine runs
  static/wasm/stockfish.js as a node UCI process — the build has node mode
  built in; the flaky drop-bestmoves shim was the separate npm cli.js). The
  sampler knots come from a 2,600-game high-N ladder (sampler games are ~free
  at 2000/min): requested 700–2100 lands within ±32 of nominal, floor ~90
  (eloMin 100), seam at 2485. The UCI_Elo top bands were later re-measured at
  n=200 too (movetime ladders run in a real shell via
  scripts/run-mt-calibration.sh, since background Bash caps at 10 min) and
  their knots refined — so **every band on both substrates is now n=200**.
  Per-engine absolute scales are each honest but not cross-comparable
  (different nets), and both are anchored to Stockfish UCI_Elo, which runs
  soft vs chess.com — a human re-anchor is a possible future lever.
  Bot ELO calibration is COMPLETE. Lesson banked in project memory: calibrate
  the free (sampler) bands at high N; movetime bands need a real shell.
- **Bot "feel" — make weak play human, not swingy** (research done
  2026-07-14, see `docs/bot-weakening.md`). The calibration is honest but the
  sub-1320 sampler blunders _uniformly_ (incl. in easy positions), which feels
  random/inhuman. Two-track plan: (1) evolve `selectBotMove` into a bounded,
  position-adaptive sampler — win-probability window, collapse it in
  easy/forcing/low-reply positions, per-game-stable width — plus a
  free-material guard so it never misses a hanging piece (near-zero cost, stays
  in Stockfish.js + MultiPV); (2) **add Maia as an in-browser ONNX move
  provider** for the low bands (`src/lib/engine/maia.ts`, slotting in at
  `maybeBotMove`) — human-imitation, characteristic beginner errors, small net,
  no search, runs via onnxruntime-web alongside Stockfish. Stockfish stays for
  analysis/hints and the strong bands. GPL-3.0 weights — check licensing.
- **Maia-3 in-browser port** — fill the roster's 1750–2100 slots with
  human-style opponents (currently a jump from Maia IX 1700 straight to
  Fish 1800). Maia-3 is one skill-conditioned net with a real ~600-pt ELO
  dial, measured ~1500–2100 lichess-equiv in the anchoring runs. Different
  pipeline from the shipped Maia-1: token input (64×12 one-hot) + two
  scalar ELO inputs, 4352-move policy, single 44MB ONNX
  (CSSLab/maia-platform-frontend `public/maia3/`, encoding in that repo's
  `src/lib/engine/tensor.ts`). Already works in the calibration harness
  (`scripts/maia-node.mts`); the port is the browser side: encoding module,
  IndexedDB model cache, Worker inference (44MB on the main thread would
  jank). Not urgent — the staircase action is at 1200–1500 where coverage
  is already good.
- **Patricia as a second honest ruler (and maybe a persona)** —
  https://github.com/Adam-Kulju/Patricia (MIT, CCRL ~3500, "most
  aggressive engine"). Why it matters here: `UCI_LimitStrength`/`UCI_Elo`
  claims a **500 floor** (vs Stockfish's 1320), calibrated by
  engine-vs-engine matches, plus `Skill_Level` 1–20 starting at 500 —
  potentially the missing honest reference BELOW SF-1320 for the
  shaped-bot curve, whose sub-1320 placement currently hangs off the
  internal BT chain alone. Its `human.h` is a cp-loss BUDGET accumulator
  (multipv; play a move whose eval_diff fits the accumulated budget;
  sacrifice bonus for style) — i.e. the frequent-small-bounded-errors
  design we measured at 2000+ and abandoned; their own comment table says
  80cp loss/move ≈ 1200, nothing weaker. So treat its labels skeptically
  at the bottom: verify vs ucielo:1320 before trusting, and expect
  ruler-vs-ruler disagreement to be informative rather than clean. Also
  two more lichess human anchors: @PatriciaBot 2741 blitz / 2705 rapid,
  @littlePatricia 1800 blitz / 2069 rapid over 11k human games. Native
  binaries only (macOS = build from source, plain C++ make) — harness
  ruler first; as a roster persona it would be native-substrate (Tauri)
  only unless someone emscriptens it. An "aggressive" family would be a
  genuinely different personality (Squares=blind engine, Maia=human,
  Fish=cold, Patricia=violent).
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
