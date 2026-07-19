# Changelog

Shipped work, newest first. Open work lives in
[GitHub issues](https://github.com/quadrismegistus/botvinnik/issues); this file
is the record of what landed. Design rationale that is still load-bearing lives
in [ROADMAP.md](ROADMAP.md); the blow-by-blow for anything here is in the git
history of the referenced PR.

The full pre-2026-07-19 roadmap — with the complete calibration saga and every
design note as it was written — is preserved in git history (it was this file's
predecessor, `ROADMAP.md` before the 2026-07-19 trim).

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
