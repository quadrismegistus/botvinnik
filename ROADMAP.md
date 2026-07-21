# Roadmap

**Open work is tracked in [GitHub issues](https://github.com/quadrismegistus/botvinnik/issues), not here.** This file is the orientation and the load-bearing design invariants; the shipped record is in [CHANGELOG.md](CHANGELOG.md). Before 2026-07-19 this was a 945-line document that mixed all three — that history is in git.

## Where the project is (2026-07-19)

The **Flutter web app is live at botvinnik.app** and at roster parity: 32 of 35 personas, which is the ceiling for any browser (Dala needs a native lc0 sidecar). Since 2026-07-20 **macOS and iOS offer the same 32**. It is a real offline PWA and makes no third-party request unless you pick a Maia.

The **SvelteKit app the project began as was retired on 2026-07-20**, having shipped the site until 2026-07-19 and been frozen since. It is preserved whole at the `svelte-eol` tag; `brain/` is what outlived it. One app, one codebase, one review.

The **synchronous brain bridge** is the constraint that shaped the port: one eval in, one JSON string out, so a brain function returning a Promise crosses as `{}`. The last three families sidestepped it entirely by running in Web Workers their Dart clients drive directly (retro, Garbo, Maia) — the bridge only constrains work that must go *through the brain*. See `ARCHITECTURE.md`.

## What's next

Grouped by GitHub-issue label. Nothing here blocks the deploy — the roster is closed.

- **[native-port](https://github.com/quadrismegistus/botvinnik/labels/native-port)** — Dala's lc0 sidecar (#45) and Android, which needs JavaScriptCore rather than QuickJS (#46, measured). The roster gap CLOSED on 2026-07-20: Maia (#44), iOS retro (#80) and Garbo (#43) all landed, so macOS and iOS now offer the same 32 personas the web does.
- **[compliance](https://github.com/quadrismegistus/botvinnik/labels/compliance)** — the App Store submission chores, gated on one **[decision](https://github.com/quadrismegistus/botvinnik/labels/decision)**: the GPLv3-on-App-Store posture (recommended: the Lichess one).
- **[roster](https://github.com/quadrismegistus/botvinnik/labels/roster)** — the bot-feel and anchoring work: a position-adaptive weak-bot sampler, sampled/Maia-3 personas, the SquareFish lichess accounts, and engine scouting.
- **[ui](https://github.com/quadrismegistus/botvinnik/labels/ui)** — the Flutter UI backlog: new-game flow, keyboard shortcuts, panel order, PGN import.
- **[tech-debt](https://github.com/quadrismegistus/botvinnik/labels/tech-debt)** — analysis-budget tuning, the non-rotating ort cache, native Square recalibration.

## How to add work

Open an issue. Put the hard-won detail *in the issue* — measured numbers, file paths, gotchas — the way the entries below the fold used to. That detail is the point; it is why this document existed.

## Design notes / known quirks

**Linux and Windows are the PWA, not a native build** (decided 2026-07-21).
`flutter_js` uses JavaScriptCore only on iOS and macOS; Windows, Linux and
Android all get QuickJS, and the QuickJS it ships has no BigInt — so `brain.js`
fails to *parse* there and the app would not boot (#46). The BigInt is
chess.js's incrementally-maintained Zobrist hash, so it cannot be dropped.

Android has a route out (JavaScriptCore via the `fastdev-jsruntimes-jsc` AAR).
Linux and Windows do not: there is no equivalent prebuilt, so it would mean
shipping our own JSC or forking flutter_js's QuickJS bridge to rebuild it with
`CONFIG_BIGNUM`. Against that, the web app is already an offline-capable PWA
with the full 32-persona roster on those platforms today. Installing it is the
supported answer.


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
  **That description is the retired Svelte app's.** The invariant survives it:
  Flutter enforces the same ordering with a four-level preempting priority
  queue (`botMove > practiceCheck > threatProbe > analysis`,
  `engine/arbiter.dart`) plus a 1.5s "sprint" wait that lets your move's
  analysis reach depth 10 before the bot's search preempts it. Kept here
  because the *reason* — never truncate a bot's calibrated search — outlives
  both implementations.
- localhost and the deployed site are separate origins with separate
  storage; Export/Import data is the bridge.
