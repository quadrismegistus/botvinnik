# Changelog

Shipped work, newest first. Open work lives in
[GitHub issues](https://github.com/quadrismegistus/botvinnik/issues); this file
is the record of what landed. Design rationale that is still load-bearing lives
in [ROADMAP.md](ROADMAP.md); the blow-by-blow for anything here is in the git
history of the referenced PR.

The full pre-2026-07-19 roadmap — with the complete calibration saga and every
design note as it was written — is preserved in git history (it was this file's
predecessor, `ROADMAP.md` before the 2026-07-19 trim).

## 2026-07-23 — practice from your own games, deeper Insights

A practice-focused batch: drill the mistakes from a game you just reviewed, keep
playing a line past a puzzle you solved, and read the "why" on the Insights card.

- **#197** — **practise this game's own mistakes from Review.** A game's blunder
  positions are already collected as you play; the Review screen now scopes a
  practice session to just that game's positions and jumps you to the drill. The
  session is finite — it walks each mistake once and ends with the way back to
  the full queue (an earlier build looped forever, or re-served a lone mistake
  endlessly; fixed).
- **#143 (part 2)** — **"continue the line" from a passed puzzle.** After you
  find the strong move, the engine answers and the position one move later is
  served as a fresh target, so a one-move puzzle becomes a drill of the line it
  came from. Off a pass only; line continuations don't touch the schedule.
- **#123** — the **Insights card states the practice verdict** (whether the move
  was collected, and why) and **speaks the concrete threat** in words, not just
  an arrow.
- **#147** — blind mode no longer leaks hidden scores through a layout gap.

## 2026-07-23 — review mode, ratings, and a backlog sweep

A batch of finished-but-unmerged work plus two waves of small fixes.

- **#202** — **review mode: a win-chance chart, reachable from game-over**
  (#195, #198). The curve draws over a finished game in Review — one dot per
  graded ply, coloured by its label, fed from each game's stored evals through
  the brain's own `whitePovWinChance` so it matches the line the live chart
  drew. The ply you're on is ringed, tapping a point seeks the board there, and
  the game-over recap gains a "Review this game" button.
- **#201** — **downloaded/custom-engine games now count toward the player
  rating**, with a gym seam; and the bot picker's Elo-cap sliders snap to whole
  hundreds and clamp to each engine's real `UCI_Elo` range.
- **#164** — the Insights card gets **two play buttons** — "Best line" and "Your
  move" — instead of one control that silently meant either.
- **#143** — practice **"ease in" is a setting** now, not hardcoded: a switch in
  Settings → Practice picks easy-first warm-up vs strict due-order.
- **#144** — the won-clean **crowns gain their footer legend** (solid = clean
  win; outline = won with help).
- **Housekeeping:** #118 (ROADMAP testing docs rewritten), #120 (the maia3 spike
  removed from the typecheck), and #133 / #155 / #200 (regression tests and
  verification for the opponent-change reset, the stale practice verdict, and
  rated-undo enforcement — all already fixed, now locked in or confirmed).

## 2026-07-23 — private cross-device sync

- **#203** — **end-to-end-encrypted cross-device sync** (#210). The game archive
  and practice collection now sync across web/macOS/iOS with no account and no
  server that can read them — a device joins by entering the same phrase. The
  phrase becomes keys by PBKDF2-HMAC-SHA256 → HKDF (PBKDF2 not Argon2id: dart2js
  Argon2id benchmarked at 31s, so a WebCrypto primitive was the only viable KDF
  across web and native); the blob is AES-256-GCM in a self-describing,
  AAD-bound envelope, gzipped. The `blobId` is derived from the phrase too, so
  the server can't even enumerate blobs. Transport is a dumb Cloudflare R2 store
  behind a small Worker (`worker/`) with compare-and-swap over HTTP-native
  conditional PUT and a per-IP rate limit. The merge is `BackupService`'s
  convergent one (#138), so sync is transport + apply-on-read rather than a
  distributed-systems problem — proven by a two-device convergence test. Turn it
  on in Settings → Sync; it then syncs on launch, resume, after a game, while
  you practise, and on leaving. Phrases are NFC-normalized so an NFD and NFC form
  derive one key. Reviewed by four adversarial subagents — six findings fixed and
  independently verified.

- **engine orphan guard** (#210) — a UCI engine subprocess no longer outlives
  the app. `dispose()` only covered a clean exit; a force-quit, hot-restart, or
  crash left the child reparented to launchd and, if mid-search, burning a core
  (an orphaned velvet was found at 100% for 23h). Now killed on SIGINT/SIGTERM
  and app-detach, with a boot-time sweep reaping whatever a crash still leaked.
  Desktop only.

## 2026-07-21 — the Squares play at their labels again

The only change this month that alters how the app *plays*.

- **#113** — **native Squares were using the web's calibration table** (#104).
  The brain keeps two, because a persona label means different things
  depending on the engine underneath it; it defaults to `wasm`, and the only
  thing that ever flipped it was the Tauri shell, which is gone. So on macOS
  and iOS twelve of thirty-two personas mapped their labels through the WASM
  table while playing Stockfish 18 over FFI or a spawned process. Measured
  against the fresh native curve, **every Square was playing 17-150 points
  below its label**, 91 on average. The fix is one line at boot; each Square
  now picks a label 18-135 points higher and searches up to 2 ply deeper.

  The old in-source note guessed the opposite — "desktop Squares will play
  above label" — because it described the stale table rather than what the app
  was doing with it.

- **#110** — **the native grid, remeasured** (#70), against the Stockfish 18
  the macOS app actually bundles, n=100/pair on the same grid as the live wasm
  run. Every knot moved up, as the saturated-loss fix predicts. The more
  interesting result is that the substrates **re-converged**: the mean gap to
  wasm fell from ~200 to ~93, restoring the older finding that the choice layer
  dominates so completely that backbone quality barely moves strength — and
  reframing the large gap as evidence of a stale table rather than a real
  difference between engines.

  iOS needs no separate grid: `package:stockfish` vendors the same Stockfish 18
  with the same two nets, and the shaped search is depth-bounded, so it visits
  identical nodes on any hardware.

- **#111, #112** — 25 files of Gradle build cache, swept into #110 by
  `git add -A` and removed again. An Android scaffold on a spike branch carries
  its own `.gitignore`; checking out a branch without it deletes the rules
  while leaving the untracked cache on disk. `.gradle/` and `flutter/android/`
  are now ignored at the root, where it holds on any branch.

- Decision recorded: **Linux and Windows are the PWA**, not a native build.
  `flutter_js` gives JavaScriptCore only to iOS and macOS; Windows, Linux and
  Android all get a QuickJS with no BigInt, so `brain.js` does not parse and
  the app does not boot. Android has a route out (#109, confirmed on a real
  emulator); Linux and Windows would mean shipping our own JavaScriptCore,
  against a web app that already offers the full roster there offline.

## 2026-07-21 — one app

The SvelteKit app the project began as is gone, and the last two open
questions before an App Store attempt got answered rather than deferred.

- **#106** — **the Svelte app and the Tauri shell retired.** They shipped
  botvinnik.app until 2026-07-19 and were frozen the same day; keeping them
  cost a second implementation of every feature, fix and review for an app
  with no users. Preserved whole at the annotated tag `svelte-eol`.
  `static/{wasm,retro,garbo}` became `vendor/` — they are third-party engine
  builds the *Flutter* web build stages, and were only ever called "static"
  because SvelteKit named the directory. `lichessImport.ts` and
  `chesscomCore.ts` were rescued into `brain/`, where the offline harness
  still needs them.

  The load-bearing part was the type-checker. `npm run check` was
  `svelte-check`, whose include list came from `.svelte-kit/tsconfig.json` —
  so it reached `brain/` only through the Svelte files importing it, and never
  reached `scripts/` at all. Replacing it with a plain `tsc` surfaced 19
  pre-existing errors, one of which was that the **live lichess bot's UCI
  wrapper still imported a path deleted in the #26 restructure**. It could not
  have run from a current checkout; only the VPS's older copy kept SquareFish
  alive, and it would have broken on the next pull.

- **#103** — **notarization layout** (#67, structurally): the bundled engines
  move to `Contents/MacOS` and are signed with the app's identity in the same
  build phase. Executable code in `Contents/Resources` is a rejection, because
  the hardened runtime treats Resources as data. What remains is a Developer
  ID certificate, which is a purchase rather than a change.

- **#102** — **Android answered** (#46): it needs JavaScriptCore, not QuickJS.
  The BigInt in `brain.js` is **chess.js's**, from its Zobrist hashing — not
  js-chess-engine's as the issue assumed — so nothing can be dropped to avoid
  it, and the QuickJS `flutter_js` ships for Android has no BigInt at all
  (verified against its atom table, and by an A/B of the same QuickJS built
  with and without `CONFIG_BIGNUM`). Both bundles fail to *parse* there.

- **#105** — the architecture diagram still drew Svelte deploying the site.

- Issue hygiene: five shipped issues were closed (#51, #59, #60, #74, #85),
  four of them open only because a PR named them in its title without a
  closing keyword in the body. #74 had been live on lichess four days before
  it was filed. Thirteen more were corrected where their premises had gone
  stale, and **#104** was filed for something no issue described: native
  Squares map their labels through the WASM calibration table while playing a
  different engine, because `setBotSubstrate` is never called from Flutter.

## 2026-07-20 — the native roster closes

macOS and iOS now offer the same **32 personas** the web does. Every remaining
engine crossed in a different way, and none of them the way its stub predicted.

- **#96** — **Maia native** (#44): `package:onnxruntime` replaces ort-web (ORT's
  C API over `dart:ffi`, its isolate session keeping the forward pass off the
  UI thread), `HttpClient` and Application Support replace fetch and IndexedDB.
  The chess did not move: `assets/maia-brain.js` runs the same `brain/maia/`
  encode/decode in an embedded JavaScriptCore, so a move is encode-in-JS →
  infer-in-Dart → decode-in-JS. A second bundle rather than two more exports on
  `brain.js`, which is a script tag on the web and would have carried lc0's
  1858-string policy index to every visitor. Verified against the move the WEB
  plays, three bands across four positions. Brought two things with it: the
  macOS bundle's first outbound socket (`com.apple.security.network.client`),
  and the discovery that nothing type-checked the Flutter app's own TypeScript.
- **#97** — **retro on iOS** (#80): iOS has no child processes, so the same
  morlock source builds with `-buildmode=c-archive` and is driven over
  `dart:ffi`. Three transports now share one `build()` switch, so the
  calibration means the same thing on all of them. The boundary has two
  subtleties that only show up at runtime: a `NativeCallable.listener` runs
  *after* the call returns, so Go hands over a `malloc`'d line and Dart frees
  it; and Go's `emit` takes the same lock as `retro_stop`, so teardown cannot
  race a callback. And two the linker finds: `-force_load` (nothing references
  symbols resolved at runtime, so they get stripped) and `[sdk=…]`-conditional
  paths rather than an xcframework (both slices are arm64).
- **#98** — **Garbo native** (#43): the last web-only family, and the cheapest,
  because replacing a Worker does not mean writing a message loop —
  garbochess's search is one long *synchronous* call, so everything it emits is
  buffered by the time the call returns. Four lines of shim and a background
  isolate, which is what keeps a ~1s search off the UI thread. `Isolate.kill`
  turned out to reclaim the Dart heap and nothing else: the JavaScriptCore
  context is native memory only the child can free, measured at ~167MB per
  disposed engine, so teardown asks rather than kills.
- **#99** — a **crash**: disposing a retro engine mid-search aborted the app.
  Ending a session sent `quit`, and morlock handles that by returning from its
  driver loop without clearing the active-search flag — so a search still
  finishing sends its bestmove on a closed channel. In a Worker or a child
  process that is an invisible engine death; in a `c-archive` it is SIGABRT in
  the app's own process. Reachable by switching bots mid-think.
- Fixes found by review along the way: nothing in CI ever *executed* the Maia
  bundle (a source edit decoding the policy from the wrong side merged green —
  there is a golden fixture and a smoke test now), an ORT run that outlived its
  timeout could hand the next position the previous one's policy, and the
  **web** Garbo client could answer with the previous position's move.

Only Dala (#45) is desktop-only, in both apps, as it always was.

## 2026-07-20 — the UI backlog, and a harness to hold it

The Flutter UI backlog cleared, plus the first tests that reach the state
machine those bugs kept turning up in.

- **#93** — a wide-window **menu bar** (#63): Game (new game, import PGN),
  View (the panel toggles in view-bar order, flip, blind mode), Help. In-app
  rather than a native `PlatformMenuBar`, because the wide layout runs on the
  web too, where that does not exist. The app bar drops its keyboard icon
  while the menu is up rather than offer the same thing twice.
- **#92** — **PGN import** (#48): paste a game, it is archived and opens in
  Review. The parse is a pure function, which is why it is directly testable;
  an import carries no grades and Review already read every one of those as
  nullable. An import also has no *you* in it, so it shows the PGN's players
  instead of Won/Lost and opens from White's side. Plus **per-panel collapse**
  (#63) — folding a panel to its header, which is not the same as closing it.
- **#91** — the **threat line** is playable (#86): the chip gets its own play
  button that runs the line the threat was judged on. Deliberately the judged
  window, not the engine's raw pv — `gain` is counted over the settled
  exchange, so replaying further would show captures the number never
  credited. `judgeTacticalWin` gained the same field for the green mirror.
- **#90** — a pure-Dart **GameController test harness** (fake engine deps, no
  browser, no device), and with it the botThinking clobber (#87) and the
  practice-collect guard pinned as regressions. Each was verified RED against
  its own pre-fix code first.
- **#88** — **FEN input** (#85): start from a pasted position, which doubles as
  the way to reproduce a reported board state instead of playing into it.
  **Panel reorder** (#59), and **tab-aware keyboard shortcuts** (#60) — blind
  mode in Play, `r`/`n`/`b`/`?` in Practice, arrows in Review, with the help
  sheet grouped by tab from one source.
- Fixes: practice no longer collects puzzles on the analysis board (that is
  exploration, not blunders to drill); undo and browse-to-start return to the
  FEN a game began from rather than the standard start; a new game during a
  bot's turn no longer clobbers the fresh turn's state; the frozen Svelte
  MaterialBar valued a rook at 3.
- Process: `main ← develop ← PRs`, so work lands on `develop` and only a
  release deploys.

## 2026-07-20 — App Store prep, native retro on macOS, and the board's second pass

Everything after the deploy: getting the native app submittable, and a second
pass over the play surface.

- **#84** — board player plates (name + captured material, above and below) and
  a bot-vs-bot move-delay setting. The same pass reworked the play surface: the
  plates reserve their height so the column never scrolls; a light tray so the
  black captures read on the dark ground; a **NavigationRail** on wide windows,
  handing the bottom bar's height to a board that is height-bound in the split
  view; and the under-board **grade strip removed** — its verdict already lived
  in the Insights card, so the threat (now a chip) and the Maia loading bar
  moved there and the board reclaimed the ~66px. Follow-ups filed: #85 (FEN
  input), #86 (full threat line).
- **#83** — new-game flow: choose a player per side (you or any bot), which
  yields bot-vs-bot for free; Practice only collects when it is your move;
  opponent selection moved out of the app-bar title into the New Game sheet.
- **#82** — App Store code-side prep: the encryption-exemption flag and the
  `PrivacyInfo.xcprivacy` manifests wired into the macOS/iOS bundles, plus the
  submission docs.
- **#81** — in-app source link and licence text for GPL-3.0 compliance on the
  App Store (the Lichess posture, decided in #76).
- **#79** — native retro on macOS: the three morlock engines build to UCI
  binaries, bundled in the app and spawned with `Process.start` (sandbox-safe
  only from inside the bundle). iOS is the harder half, split to #80.
- **#78** — Review opens at the start of a game, not the end (#61).
- Housekeeping (late 2026-07-19): the 945-line `ROADMAP.md` migrated to GitHub
  issues and trimmed to an index of design invariants, with this CHANGELOG
  split out; third-party notices completed (retro/morlock MIT, Garbo BSD-3,
  Go `wasm_exec.js` BSD-3, Maia/Dala weights GPL-3.0).

## 2026-07-19 — the roster closes and Flutter takes the deploy

Flutter web reached **parity** (32 of 35 personas; Dala needs a native lc0
sidecar and is desktop-only in both apps) and took the botvinnik.app apex from
the frozen Svelte app.

- **#41** — Maia download shows real streamed progress. The old "downloading"
  line lived in `statusLine`, which only renders when the game is over, so it
  was never once shown — the actual reason the first Maia move looked like a
  hang. Now a live bar in the grade strip: streamed `{received, total}` while
  the weights arrive, a named indeterminate phase while the runtime compiles.
- **#40** — the phone board takes the full width. It was height-capped by a
  96px reserve meant to keep some panel on screen — worth it on a desktop
  window, 13% of the board on a phone that has the height to spare. Now
  width-conditional; Review had the same defect and got the same fix.
- **#39** — deploy switch. `pages.yml` builds and ships `flutter/`. The
  load-bearing piece is a tombstone at the Svelte worker's path
  (`flutter/web/service-worker.js`): SvelteKit's worker is cache-first for the
  shell, so without it a returning browser serves cached Svelte forever and the
  new app never loads. Verified by simulating the deploy on one origin.
- **#38** — Maia on Flutter web. Six personas, three ONNX nets, one Worker.
  The pure encoding/decoding moved to `brain/maia/` and is now shared by both
  apps. Nothing about Maia lands in git (built at stage time; runtime from the
  pinned `onnxruntime-web`). The app's only third-party request, and only on
  first use of a Maia.
- **#37** — Garbo (Gary Linscott's 2011 hand-written JS engine) on Flutter
  web, and the three Worker clients folded onto one `js_worker.dart` interop.
- **#36** — retro bots (TUROCHAMP 1948, BERNSTEIN 1957, SARGON 1978) on
  Flutter web, as wasm in their own Worker. The Flutter app's first browser
  tests (`flutter/e2e/`).
- **#35** — Flutter web is a real offline PWA: shell-only precache,
  cache-on-first-use, no third-party requests, content-hashed cache version.
- **#33** — Practice/Review wide-window layout, the analysis-budget change,
  and the **Svelte freeze** (see `svelte/FROZEN.md`).
- **#32** — Horizon (js-chess-engine) plays on Flutter, the first roster
  family to cross the synchronous brain bridge (20 → 22 personas).
- **#31** — `ARCHITECTURE.md` added; ROADMAP brought current.
- **#30** — stop shipping Maia weights and the commentary corpus to every
  visitor; entry chunk 188KB → 82KB gz.
- **#29** — wide-window UX and the board-overlay grammar (threat/win rings,
  control wash, the three-fact rule).

## 2026-07-18 — the platform split

- **#28** — GPL-3.0 license and third-party notices.
- **#27** — wide-window panels and the Lines pane.
- **#26** — repo layout: `brain/`, `svelte/`, `flutter/` as peers, with the
  brain consumed by both apps.
- **#24** — Flutter on the web: a dartchess fork splitting the 64-bit bitboard
  into 32-bit halves for the JS number path.
- **#23** — Flutter board theming, overlay controls, and a macOS build.

## 2026-07-17 — PWA, deploy, explanations

- **#22** — app icon (robot knight), PWA + desktop.
- **#21** — installable + offline PWA (manifest, service worker, icons).
- **#20** — deploy to botvinnik.app, dropping the `/botvinnik` base path.
- **#19** — move-explanation sprint: audit vs cook.py themes, mate-pattern /
  promotion / sacrifice detectors, absurd-claim fixes.

## 2026-07-11 — the Svelte app

- **#1** — the browser-only chess practice app: client-side Stockfish, the
  grading pipeline, practice and review, game storage, and (later parked) a
  Tauri desktop shell with a native engine and in-app importer.

Between #1 and #19, the Svelte app grew its sidebar redesign, game review UI,
bot-weakening research and the shaped choice-layer, and the persona roster and
its calibration against human-pool anchors — recorded in the pre-trim ROADMAP
(git history) and in the project memory notes.
