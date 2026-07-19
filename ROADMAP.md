# Roadmap

What's planned, roughly in priority order. See [README](README.md) for what's already shipped.

## Platform split (decided 2026-07-18)

Two apps, one brain. `brain/` holds everything that decides a move or grades
one; `svelte/` and `flutter/` are consumers and neither depends on the other.

- **Flutter owns mobile and desktop.** The Tauri shell is parked, not deleted
  (see [docs/desktop.md](docs/desktop.md)). Sharing one UI across phone,
  tablet and desktop beat Tauri's one real advantage: it runs the same
  Stockfish WASM the web app does, so its calibration is right by
  construction, where the Flutter desktop build spawns whatever binary it
  finds.
- **Svelte still owns the web deploy**, and is now **frozen** — see below.
  botvinnik.app stays SvelteKit until Flutter web closes the remaining gaps:
  the persona roster and the payload. (Offline was the third; closed
  2026-07-19.)
- Flutter web works and is measured (9.22MB gzipped, 26 requests as of
  2026-07-18) but is not a deploy candidate yet. Since that measurement,
  `brain.js` has grown ~24KB gzipped from bundling js-chess-engine for the
  Horizon personas — and note it is script-tagged *synchronously ahead of*
  `main.dart.js`, so it sits on the critical boot path.

### Consolidating on Flutter — DECIDED 2026-07-19: Svelte is FROZEN

**No new features in `svelte/`.** It keeps serving botvinnik.app, keeps its
bug fixes, and keeps working when the shared brain changes — but effort goes
to Flutter from here. It is **not** deleted, and the distinction is the point:
the focus comes from this decision, not from moving code. A branch would
archive nothing anyway, since the history stays in `main` regardless; a branch
only matters if Svelte is then deleted from `main`, which is what waits on the
gate below. When that day comes a **tag** is the better archive than a branch:
immutable, and it does not invite drift.

Retiring the Svelte app is the one step that cannot be walked back cheaply,
so here is what has to be true first.

**Three gaps, all measured. One is now closed:**
1. ~~**Offline.**~~ **CLOSED 2026-07-19** — Flutter web is a real PWA: boots
   with no network, and makes no third-party requests either (the fonts it
   used to fetch from Google are bundled). See the service-worker item below
   for what precaches and why. **Two gaps left.**
2. **Payload.** Svelte deploys ~270KB gzipped of JS. Flutter web is 9.22MB
   gzipped over 26 requests — **about 34×**. Acceptable for an app you install;
   a different proposition for a link someone opens.
3. **Roster.** 22 of 35 personas. And note *what* the missing ones are: the
   Svelte app is the **reference implementation** for Maia, retro, Garbo and
   Dala. Removing it while porting exactly those is removing the thing being
   ported from.

What keeping it actually costs while frozen, so the trade is honest: the
`web-e2e` CI job, and the discipline of keeping both apps working whenever the
shared brain changes. That second one has caught real bugs in both directions,
so it is not purely a tax.

**Next toward this**: the roster (M5 — retro is the next family), since it is
the gap with the most work in it. The payload gap is the one to think about
rather than grind at: 9.22MB is what a CanvasKit app costs, so closing it
means questioning the renderer, not trimming assets.

### Flutter UI backlog (raised 2026-07-19)

- ~~**Practice and Review overflow on a wide window.**~~ **FIXED (#33).** Not
  a missing port — both tabs existed and worked; they had never been given
  #29's wide-window layout, and sized the board to `constraints.maxWidth` with
  no height cap, so a square board was as tall as the window was wide (945px
  and 871px of overflow, action row and scrub bar off-screen). The root cause
  was three widgets each deciding board size independently, so the arithmetic
  now lives in one place: `stackedBoardSize(width, height, chrome)`, with
  `narrowBoardSize` as Play's chrome through it. Both screens also gained the
  board-beside-the-furniture wide branch.
- **New-game flow.** Opponent selection belongs in the New Game sheet, not
  behind the app-bar title — choosing who you play is part of starting a game,
  not a persistent global setting. While there: allow **both** sides to be
  bots, which also gives us bot-vs-bot games for free (useful for calibration
  spot-checks and genuinely fun to watch).
- **Panel order.** "Lines" should sit directly above "Moves", so "Tree" and
  "Chart" come above "Lines" — analysis first, then the line list, then the
  move list. Affects the `_tabs` order in `main.dart` and the persisted panel
  indices in settings, so it needs a migration or index-independent keys.
- **Keyboard shortcuts in Practice and Review, and blind mode in Play.**
  These are one job, because they force the same structural change. The
  keyboard layer is currently tab-**gated**: `KeyboardControls` wraps the shell
  and returns `ignored` unless `_tab.value == 0` (main.dart), which is what
  stops ⌘Z reaching a hidden board. What is wanted is tab-**aware** — a
  per-tab action map rather than one map switched off.

  Wanted bindings:
  - **Play:** `h` toggles blind mode — "hide". Both keys are free; `h` was
    chosen over `b` precisely because it leaves `b` to mean "show best" and
    nothing else, in any tab. The residual tension is that Practice has a
    Hint action, so if that ever wants a key it cannot have `h`.
  - **Review:** ← / → step between moves, and it should be possible to review
    with the keyboard alone. `ReviewController` already has `prev`, `next`,
    `goto`, `canPrev`, `canNext` — this is wiring, not new logic.
  - **Practice:** `r` retries, `n` next puzzle, `b` shows best, `?` hints.
    The arrows stay unbound here — `r` already covers retry, and Practice has
    no move history to step through. `PracticeController` already has `retry`,
    `nextPuzzle`, `reveal`, `hint`.

    `?` over `q` or `s`: it is the near-universal help convention, it escalates
    the way the feature does (press again for more), and it is the only one of
    the three that is not arbitrary — `q` conventionally means quit, and `s`
    for "show" would collide semantically with `b` for "show best", which is
    exactly the memorability problem dropping the left-arrow binding removed.
    Implementable as-is: `boardActionFor` excludes only Alt on the
    non-modifier path, so a bare `?` (Shift+`/`) arrives normally — match
    `LogicalKeyboardKey.question`, and consider accepting `slash` too, since
    `?` sits elsewhere on non-US layouts.

    Note hint and reveal **converge**: `hint()` escalates a tier per press and
    sets `revealBest` at tier 3, so `?` three times lands where `b` does. That
    is good progressive disclosure, not a bug — but wire them knowing it, so
    the two do not fight over `revealBest`.

  **No key means two things.** Worth keeping it that way: ← / → mean "step
  through the moves of a game" everywhere they are bound, and are simply
  absent where there is no game to step through. Tab scoping would have made
  a collision *safe*, but not memorable.

  The per-tab sets still differ (Play has `f`, space, `h`, ⌘Z; Practice has
  `r`, `n`, `b`), so `KeyboardControls.bindingsFor` — the single list the help
  sheet renders, so that the sheet cannot drift from the bindings — has to
  grow a tab dimension. **Show all of them, grouped under per-tab headings,
  rather than only the active tab's**: one dialog with no context threaded
  into it, and you learn Practice's keys while sitting in Play, which is where
  you would want to have learned them. The load-bearing part is unchanged —
  the same structure must drive both the dialog and the dispatch, or the
  drift guarantee it exists for is gone. If the dialog covers every tab, its
  app-bar button probably should not stay Play-only either. Also decide
  whether
  `n`/`r`/`b` should repeat on key-hold; the existing `_repeatable` set says
  browse keys yes, state-changing keys no, and all three of these change
  state.
- **Review should open at the start, not the end.** `review_controller.dart`
  `open()` sets `cursor = moves.length` ("land on the final position"), so a
  game opens at the last move and must be scrubbed backwards. Reviewing runs
  forwards. One line — but decide between `cursor = 0` (the start position,
  verdict strip reads "Start position") and `cursor = 1` (after the first
  move, so the first verdict is already showing). `0` is the truer
  "beginning"; `1` avoids opening on a screen with nothing to say.
- **Default board texture → Olive.** `kDefaultBoardTexture` is `'newspaper'`
  (`settings_store.dart:22`); `'olive'` already exists (`board_theme.dart:73`).
  One-word change, but it only applies to profiles with no stored preference —
  `prefs.getString('botvinnik-board-texture') ?? kDefaultBoardTexture` — so
  anyone who has already opened Settings keeps what they have. Decide whether
  that is the intent or whether existing newspaper-by-default users should be
  migrated; also `resetToDefaults` at `:339` reads the same constant.

### Analysis budget — one search already, but a modest one

Worth recording because the instinct is to look for a redundant search, and
there isn't one. **Arrows are not capped below the panels.** `engineArrowUcis`,
the Lines pane, the Tree and the bot's repetition guard all read the same
`currentLines` (`_partials[position.fen]`) — one analysis, one source of truth.

The only *extra* engine run is the threat probe, and it cannot be folded in:
it searches the **null-move position** (side to move flipped), which is not a
node in the current position's tree. The opponent replies that *do* appear in
your PVs are replies to **your move** — which is precisely what a threat is
not. There is nothing to merge. It is deliberately cheap and outranks analysis
in the arbiter (depth 14, MultiPV 1, 500ms).

**But it could refine as it deepens, and the plumbing already exists.**
`_probeThreat` passes no `onUpdate`, so it is one-shot: one search, one answer.
`SearchArbiter.search` already takes `onUpdate` — that is how the engine arrows
stream. Passing one, and giving the probe a longer budget, would make threat
arrows sharpen the way engine arrows do. Two cautions before doing it:
- **One engine.** Threat and analysis are serialized whatever the priorities.
  The probe outranks analysis *because* it is short; making it long and
  high-priority would starve the thing it jumps ahead of.
- **Deeper is not obviously better here.** The overlay was built around
  *immediate* threats — that is what the three-fact ring rule enforces. A much
  deeper probe surfaces remoter, more speculative threats, i.e. exactly what
  those rules exist to filter out. Test whether the rings get better or just
  noisier before committing to a bigger budget.

So when the arrows feel weak against a full-strength engine, the cause is the
**budget**: depth 22 / MultiPV 5, on the single-threaded lite WASM build.
MultiPV 5 is the expensive part — five principal variations prune far less than
one, so the same milliseconds buy materially less depth.

**Measured** in a real browser on the app's own engine, time to reach depth 22:
start 3755ms, open middlegame 5954ms (7437ms to finish), complex midgame
4180ms, pawn endgame 2010ms. The old 3000ms cap therefore truncated **three of
four** positions around depth 19-21 — the arrows never reached the depth they
advertised. Flutter's cap is now 10000ms, a backstop rather than the routine
limit (`kAnalysisMovetimeMs`, with `kSaveGradeWaitSeconds` above it because a
grade pipeline awaits its position's analysis).

**Not changed on the web, deliberately.** Flutter ranks `threatProbe` and
`botMove` above `analysis` and preempts, so a longer analysis yields the
instant anything else needs the engine. The web is a single-slot supersede
queue and runs `computeThreat` only after `await analyze(...)` returns, so the
same change there would delay every threat arrow by the same amount. Fixing
that means giving the web real priorities, not a bigger number.

Still open: drop to MultiPV 1 for the *arrow* while keeping 5 for the panels
(two reads of one search, not two searches); give native its own budget, since
it is not on lite WASM and reaches depth far sooner; and decide whether mobile
wants a smaller cap, since this is CPU spent while you think. Control tinting
costs nothing either way — it is pure chess.js.

### In order

1. ~~**Wide-window UI.**~~ **SHIPPED 2026-07-19 (#29).** Multiple panels
   visible at once (inclusive view bar, selection persisted), keyboard
   navigation scoped to the Play tab, resizable and persisted split, macOS
   minimum window size — plus the board-overlay grammar that came with it
   (threat/win rings, control rings vs wash; see ARCHITECTURE.md).
   **Still open from the original scope: a menu bar, and per-panel collapse.**
2. **M5 — the rest of the roster.** The brain ships 35 personas across 7
   families; Flutter plays 22 — `square`, `fish`, and `horizon` since #32.
   Missing: 6 Maia, 3 retro, 3 Dala, 1 Garbo. This is the real parity gap and
   the reason Svelte still owns the web.

   **The constraint that decides the order** (learned doing Horizon): the Dart
   bridge is synchronous — one eval in, one JSON string out — so a brain
   function returning a Promise crosses as `{}`. *Anything async is not
   expressible through it*, and the calls run on the UI isolate, so anything
   slow cannot use it as-is either. Horizon fit because js-chess-engine is
   synchronous and answers in ~2ms. The other four each need their own
   mechanism on the Dart side first:
   - **retro — NEXT (Ryan's call, 2026-07-19).** Three personas for one
     mechanism, and the best-anchored ratings on the roster (the morlock bots'
     real lichess numbers over 15k–48k human games). A Go module compiled to
     wasm that already speaks minimal UCI, so the shape of the work is a wasm
     runtime plus a UCI pump rather than a new protocol invented from scratch.
     The open question is what runs the wasm on native Flutter — the web build
     has `WebAssembly` for free, so it may land on Flutter web first.
   - **Garbo** — a Worker script with its own postMessage protocol, and
     flutter_js has no Worker. Needs an onmessage/postMessage shim *and* a
     background isolate, since its ~1s search would block the UI.
   - **Maia** — the `onnxruntime` pub package. Import it lazily from day one;
     see the payload note below for what the eager version cost the web.
   - **Dala** — stays desktop-only; needs the native lc0 sidecar.

   Useful trick from #32: a dependency imported **only** from
   `brain/brain-entry.ts` reaches `brain.js` but never the Svelte bundle,
   because the web imports brain modules individually and never the entry
   barrel. That is how js-chess-engine got to Flutter for +104 eager bytes on
   the web.
3. ~~**A real service worker for Flutter web.**~~ **SHIPPED 2026-07-19.**
   `web/sw.js` + `tool/gen-sw-manifest.mjs`, built by `build-web.sh` (which CI
   now calls). Verified offline in a real browser with every cross-origin
   request aborted at the route level, so the browser's own HTTP cache could
   not stand in: the app boots complete — board, engine arrows, control
   tinting — with no network.

   What the build measured, and what it decided: a boot is 28 requests /
   16.8MB, so **20 files (11.5MB) precache** — shell, `main.dart.js`,
   `brain.js`, `sqlite3.wasm` and Stockfish — while CanvasKit (the browser
   picks one of several variants) and the 14.6MB of piece sets and boards
   (a session uses one of each) **cache on first use**. The cache version is a
   hash of the precached bytes, so a cache can never mix builds; that is not
   fastidiousness, since a new `main.dart.js` beside a stale `brain.js` trips
   the BRAIN_VERSION assert and refuses to boot rather than degrading.

   **Two things worth knowing.** `--no-web-resources-cdn` is now *required*,
   not a preference: without it CanvasKit comes from `www.gstatic.com`, which
   the worker cannot cache — and the app still appears to work offline while
   the browser's HTTP cache holds it, which is precisely how the first test
   here produced a false pass. And full offline lands after one **reload**,
   not one visit: CanvasKit is fetched before the worker takes control, so it
   is cached on the second load.

   **The fonts are closed too.** Flutter web fetched Roboto *and* Noto Sans
   Symbols from `fonts.gstatic.com` at runtime. Roboto is now bundled
   (Apache-2.0, from the SDK's own artifacts) and named in the theme, which is
   what makes the web build stop asking Google for it.

   Noto was subtler and needed measuring: Flutter downloads a fallback font
   for any glyph no bundled font contains. Checking Roboto's cmap against
   every non-ASCII character in `lib/` found **nine** it lacks — `→ ⌘ ✓ ⇧ 🔥
   ✗ ← ↑ ↓` — of which eight were actually rendered, in the roster picker
   (`▦ ◆ ◓`), the practice verdict (`✓ ✗`), the streak counter (`🔥`) and the
   keyboard sheet (`⌘ ⇧ ← →`). They are now Material Icons (already bundled
   and tree-shaken) or words. **Verified zero cross-origin requests** across
   boot, roster picker, keyboard help and Practice — a boot-only check would
   have missed all of them, since the offending glyphs live behind modals.

   The lesson generalises: on Flutter web, an exotic Unicode glyph in a
   `Text` is a network request. Prefer `Icons.` — the icon font is bundled and
   tree-shaken, so it costs nothing.
4. **Notarization layout**, before any App Store attempt: the bundled engine
   is ad-hoc signed in `Contents/Resources` and will be rejected. Moving it
   to `Contents/MacOS` and signing it in the same build phase is the fix;
   `ProcessEngine.resolveBinary` already probes that path.

### ~~Free win, independent of all the above~~ — SHIPPED 2026-07-19 (#30)

Three separate leaks, each paid for on a first visit by people who never
touched the feature behind it. The pre-fix note here claimed "6.31MB of ONNX";
measured against a real build it was both smaller and differently distributed,
which is why the fix is described in measured numbers:

- **`commentary.json`, 1.34MB gzipped**, fetched on mount because the effect
  read `game.fen` — so the whole YouTube corpus downloaded whether or not the
  panel was ever opened. Now gated on the panel being shown, which means the
  panel opens *before* its data exists and needed a loading state: the old
  empty message would otherwise claim there is no commentary for a position
  while the corpus is still in flight.
- **onnxruntime-web in the page entry chunk** — a static `import * as ort` in
  `lib/engine/maia.ts`, so every visitor paid for the neural bots. Now a
  dynamic import on first use. Entry chunk **188KB → 82KB gzipped**.
- **26MB of ort wasm precached by the service worker** — `PRECACHE` spread
  `...build` unfiltered, and Vite emits that blob into `_app/immutable/assets`.
  Nothing ever requested it (ort is pointed at a CDN by `wasmPaths`), so it was
  26MB per version bump for a file the app does not use.

`svelte/e2e/payload.spec.ts` pins the property, since one stray static import
undoes it silently.

**Loose end:** Vite still *emits* that 26MB wasm into the build directory even
with the dynamic import. Nothing fetches it and nothing precaches it, but it is
~half of the deploy upload. Excluding it from the build output is unfinished.

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
- **Engine scouting — third-party engines for rulers and personas.**
  Two distinct needs: (a) an honest RULER below SF-1320 to cross-check the
  shaped curve's low end; (b) roster PERSONAS with genuinely distinct
  styles. General lesson so far: minimal-competent search floors at ~1900
  from below, imitation floors at ~1500 from above — nothing off the
  shelf reaches the beginner range honestly, which is why the shaped
  choice-layer exists.

  | engine | strength (anchor) | weak dial | web app | harness | license | role |
  |---|---|---|---|---|---|---|
  | Patricia | CCRL ~3500; @PatriciaBot 2741b/2705r, @littlePatricia 1800b/2069r (11k games). **GYM VERDICT: Skill 1/3/5/7 all ≥2370 our scale, internal pairs ~50% — the dial is a NO-OP down low; v5 dropped UCI_Elo, the "500 floor" is gone** | ~~UCI_Elo 500~~ (v3-era); Skill 1–21 ineffective at the low end | emscripten build needed (hard) | built, scripts/engines/ (gitignored) | MIT | NOT a low-end ruler. At most an aggressive ~2400 native persona someday |
  | Maia-3 | ~1500–2100 lichess-equiv (our anchoring runs) | real ELO-dial input | 44MB ONNX port, pipeline known (medium) | done (`maia-node.mts`) | GPL-3 weights | human-style personas 1750–2100 |
  | sunfish | @sunfish-engine ~1957b/1961r (~1000 games) | none | JS port / pyodide (medium-hard) | today (UCI stdin) | GPL-3 | readable ~1950 character |
  | Garbochess-JS | **@GarboBot: 1931 blitz / 2021 rapid, 90k+ lichess games** — measured! | none | **native JS + WebWorkers — zero port** | thin node UCI shim (~half-day, own API not UCI) | BSD-3 (LICENSE file; GitHub misclassifies) | web-native ~2000 persona, now lichess-anchored |
  | js-chess-engine | **MEASURED (gym n=80, data/bot-gym-ext.json): L1≈775, L2≈1102, L3≈1344, L4≈1661, L5≈1910 our scale (≈535/860/1105/1420/1670 lichess-equiv)** — clean monotonic ladder, ruler-consistent | levels 1–5 + depth/quiescence knobs | **npm import — easiest of all** (TS, zero deps, maintained 2026) | done: `scripts/shims/jsce-uci.mjs` | MIT | the real thing: full-rules engines genuinely in the beginner range; corroborates the shaped curve (Square 600 beats L1 73-27, L2 edges Square 900 — the ladders interleave). Persona family candidate 500-1700 |
  | Wasabi (mhonert/chess) | unmeasured | 6 levels | **already WASM + WebWorkers** (AssemblyScript; that's its point) | standalone UCI build exists (WASI — needs wasmtime or node WASI) | GPL-3 | web-native persona; author's stronger successor is Velvet (Rust) |
  | VanillaJSChess | author: "under 1300"; Ryan easily beat it (he's ~1300 on our ladder) | none | engine tangled into the page — no module, no npm | no UCI; extraction needed | GPL-3, dead 2021 | PASS — same class as jsce (shallow JS minimax) with worse packaging; revisit only if jsce disappoints |
  | sameshi | ~1170 ±60 (honest: 240 games vs SF 1320–1600 — but under CONSTRAINED rules) | none | 2KB C | no castling/en-passant/PROMOTION — can't play full chess | none (unlicensed) | PASS — doesn't play real endgames; useful only as a datum (material-only depth-5 ≈ 1170: search alone defends the beginner floor) |
  | chessJS | claim: "beat SF Level-6 (2300+)" — single-game anecdote, GUI level ≠ ELO | none | page-welded JS minimax | no UCI | custom ToU (NOASSERTION) | PASS — jsce covers the class; unverifiable strength, murky license |

  Per-engine notes:
  - **Patricia** (https://github.com/Adam-Kulju/Patricia): the only
    candidate aimed at the sub-1320 gap. Caution: its `human.h` is a
    cp-loss budget accumulator (multipv + budget + sacrifice bonus) — the
    frequent-small-bounded-errors design we measured at 2000+ and
    abandoned; their own comments bottom out at "80cp/move ≈ 1200". So
    verify UCI_Elo ≤1200 labels against ucielo:1320 before trusting;
    ruler-vs-ruler disagreement is itself data. macOS = build from source.
  - **Maia-3** (CSSLab): not strictly scouting — port task above.
  - **sunfish** (https://github.com/thomasahle/sunfish): 131 lines of
    Python; weakness is ARCHITECTURAL (horizon-blind, materialist,
    bookless), not randomized — a different ~2000 opponent from
    limiter-weakened Fish, and the one bot whose entire mind is readable.
    No dial: starving its clock reopens the weakening-design problem.
  - **Garbochess-JS** (https://github.com/glinscott/Garbochess-JS): Gary
    Linscott (fishtest/Leela founder), 2011-era JS, Fruit-style eval
    (PSQ+mobility+bishop pair, pre-NNUE), WebWorkers built in. Runs in
    the web app as-is; zero strength evidence (no lichess account, no
    CCRL entry for the JS version) and no dial, so measure in the harness
    first. Unmaintained (2012 code, last push 2023); would need a small
    protocol shim both for the harness (node) and for our
    TransportFactory (its worker speaks its own message format, not UCI).
  - **js-chess-engine** (https://github.com/josefjadrny/js-chess-engine)
    — **ADOPTED. Shipped as the "Horizon" family**, web and Flutter (#32).
    The sleeper, and it paid off. Probe: level 1 played Qxf6?? hanging the
    queen — no quiescence at low levels ⇒ horizon-effect blunders, i.e. weak
    the way the shaped bot is DESIGNED to be weak, but architecturally. The
    gym confirmed it (L1≈535, L2≈860 lichess-equiv), so it is both a persona
    family and independent corroboration for the shaped curve's low end.
    Horizon 550 is now the weakest opponent in either app. UCI shim at
    scripts/shims/jsce-uci.mjs; `brain/horizon.ts` for the app path.
  - **Wasabi** (https://github.com/mhonert/chess): AssemblyScript engine
    already built for browser WebWorkers, 6 levels, GPL-3, ships a
    standalone WASI UCI binary (run via wasmtime/node WASI) — gym-ready
    with minor runner glue. Unmeasured; author moved on to Velvet.

- **Gym for third-party engines — BUILT 2026-07-15.** The calibration
  harness accepts external UCI engines via `--ext-config <json>` (per-id
  cmd/options/go; each worker spawns its own instances). First cohort:
  js-chess-engine levels 1–5 + Patricia 5.0 Skill 1/3/5/7 (built from
  source; NB v5 dropped UCI_Elo for Skill_Level 1–21, so the README's
  "500 floor" table is v3-era folklore until measured) —
  `scripts/run-gym-overnight.sh` → data/bot-gym-ext.json.

- **THE LICHESS BOT LADDER (found by Ryan 2026-07-15, via
  lichess.org/player/bots) — the sub-1320 "desert" has real oases.**
  Human-anchored bot accounts, rapid ratings, big samples:
  uSunfish-l0 **1029** (6.5k games, MicroPython sunfish easiest setting) ·
  dala-900 **1095** (1.5k, BT4 transformer trained ONLY on ~900-band human
  games — imitation still runs ~+150-200 hot, but lands far below Maia's
  argmax floor) · bernstein-2ply **1198** (15.5k, re-impl of the 1957
  Bernstein IBM 704 program) · sargon-1ply **1228** (48k, re-impl of 1978
  SARGON at 1 ply) · Humaia **1379** (23k, maia-1400 SAMPLED — see below) ·
  maia1 1572 · sunfish 1961 · GarboBot 2021 · littlePatricia 2069.
  TODO: find the sargon/bernstein/uSunfish sources (they're
  re-implementations, likely on GitHub) — any that run locally become
  two-sided bridges: same config in our gym + real lichess rating.
- **DALA — GYM DONE (data/bot-dala-gym.json, n=60).** The two-sided
  bridges read: dala:700 engine-pool ~780 ↔ human 911 (gap ~130);
  dala:900 ~845 ↔ 1095 (~250); dala:1300 ~945 ↔ 1315 (~370). The
  imitation pool-penalty SHRINKS toward the bottom (maia-1500 was ~400)
  → our engine-pool scale approximates the human scale within ~150-250
  in exactly the beginner range the app serves. Engine pool compresses
  imitation ladders (600 label-pts → ~160 engine-pts). Square 900 beat
  dala:900 65-35: Squares' engine backbone exploits never-calculating
  nets, so the dala bridge reads Squares ~1-2 notches hot vs human-style
  play — while Ryan's own staircase supports the current labels.
  DOCTRINE: no single scale; within-family placement is clean,
  cross-family readings carry ±150-400 predictable pool offsets. Roster
  numbers stay anchored to HUMAN-pool sources (maia bridge + player
  games); the definitive instrument is SquareFish-on-lichess.
  Web-app dala use still open: 59MB nets, BT4→ONNX conversion, NO
  license on weights — email hrschubert first (their modified
  lichess-bot client is also the SquareFish deployment reference).
  Setup for reruns: lc0 MASTER built from source
  (scripts/engines/lc0-src — brew 0.32 can't read 2026-format nets),
  nets in scripts/engines/dala/, select:"policy" in gym-ext.json.
- **slowmate_bot** (~1144 blitz/1312 rapid, few k games): educational UCI
  engine allegedly written entirely by Copilot agents. Gym-ready anchor
  candidate in the 1150-1300 band + a conversation piece. Find repo.
- **ailedbot** (~850 rapid, only ~150 games — provisional): "engine with
  feelings" gimmick, but the buried good idea is STATE-DEPENDENT play:
  human missProb isn't fixed, it spikes after losing material (tilt). A
  per-game tilt multiplier on shapedParams is a cheap future experiment
  for feel.
- **SAMPLED MAIA — MEASURED (data/bot-maia-sampled.json, n=60).**
  Sampling = **−260 Elo** on the same net (direct control pair). But the
  run's bigger lesson is **pool-dependence**: argmax maia:1500 measures
  1455 vs honest engine rulers while @maia5 rates 1643 rapid vs humans
  (≈1880 our scale) — a ~400-pt gap. Imitation bots are tactically blind;
  engines punish that far above their human-pool rating. There is no
  single "true rating" for an imitation bot, only pool-relative ones.
  DECISIONS: roster Maias keep their lichess (human-pool) ratings — the
  player is a human, those are the right numbers. Sampled Maias are a
  roster opportunity at human-bridged ≈1310/1380/1440 (argmax lichess
  − 260; inferred — ship as "estimated" and let the player's games
  refine), filling the 1300-1550 gap. App still plays argmax
  (temperature 0); flip to 1 only when shipping sampled personas.
  Squares look less pool-sensitive: they interleave with jsce + SF
  rulers, and Ryan's staircase tracks the engine-pool scale so far.
- **Put our bots ON lichess (the calibration endgame).** A BOT account
  per Square (e.g. Square-900): create fresh account → upgrade via
  `/api/bot/account/upgrade` (irreversible, needs 0 games played) → run
  the standard `lichess-bot` bridge (Python, wraps any UCI engine) →
  wrap our shaped bot as a UCI engine ("SquareFish": node script = WASM
  lite-single engine + shapedBotMove choice layer, exactly the harness's
  shapedMove logic; ~100 lines, same pattern as jsce-uci.mjs). Weak bots
  farm games fast on lichess (that's how maia1 got 8M) → after ~100
  rated games our Square has a REAL lichess rating — a self-made human
  anchor in the sub-1320 desert where no reference bot exists, replacing
  every borrowed anchor (maia/sunfish/patricia). Needs: a machine that
  stays up (Mac awake or cheap VPS), token with bot:play scope.
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
  toggle — `brain/engine/control.ts`; **rendering reworked in #29**: a soft
  ring around a piece on an occupied square, a flat wash on an empty one,
  because the two are different claims — "this piece is falling where it
  stands" versus "this side owns this territory". Threat/win rings and any
  arrowhead outrank control on the same square; one glyph per square).
  The *semantics* are unchanged, so these remain open: intensity gradation by
  exchange margin, x-ray attackers in the swap lists (batteries are still
  invisible), an option to mark *held* occupied squares (today a square is
  marked only when the piece is outright losable, to avoid repainting the
  board), and skipping the null-move flip so control renders while in check.

## Design notes / known quirks

- Testing layout: vitest = `brain/**/*.test.ts` + `svelte/src/**/*.test.ts`
  (pure logic; 264 tests in 17 files), `svelte/e2e/` = @playwright/test against
  the built bundle (9 tests in 7 files; local Chrome via `npm run test:e2e`,
  chromium in CI), `cd flutter && flutter test` = Dart unit tests (50),
  `npm run test:rust` = bridge unit tests, tauri e2e = Linux CI only (no macOS
  WebDriver backend).
  **Not in CI:** `flutter/integration_test/` needs a real device, so CI only
  *analyses* it. Run those locally against the real bridge with
  `flutter test integration_test/<file>.dart -d macos` — that is JavaScriptCore,
  and it is the only thing that catches marshalling bugs (Dart null vs the
  string `"null"`, precision, dropped fields) that a node replay cannot see.

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
  **This is Svelte-only.** Flutter enforces the same ordering guarantee with
  completely different machinery — a four-level preempting priority queue
  (`botMove > practiceCheck > threatProbe > analysis`, `engine/arbiter.dart`)
  plus a 1.5s "sprint" wait that lets your move's analysis reach depth 10
  before the bot's search preempts it. A fix to one does not carry to the
  other; see ARCHITECTURE.md.
- localhost and the deployed site are separate origins with separate
  storage; Export/Import data is the bridge.
