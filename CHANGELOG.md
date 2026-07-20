# Changelog

Shipped work, newest first. Open work lives in
[GitHub issues](https://github.com/quadrismegistus/botvinnik/issues); this file
is the record of what landed. Design rationale that is still load-bearing lives
in [ROADMAP.md](ROADMAP.md); the blow-by-blow for anything here is in the git
history of the referenced PR.

The full pre-2026-07-19 roadmap — with the complete calibration saga and every
design note as it was written — is preserved in git history (it was this file's
predecessor, `ROADMAP.md` before the 2026-07-19 trim).

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
