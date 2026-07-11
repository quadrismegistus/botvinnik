# Botvinnik

A personal chess practice app — play, get graded, collect your mistakes, and drill them as puzzles. Everything runs in the browser: no server, no accounts, no API keys.

Ported and distilled from a fork of [en-croissant](https://github.com/franciscoBSalgueiro/en-croissant) into a minimal SvelteKit app.

## Features

- **Engine analysis** — Stockfish 18 (lite WASM build) as a web worker, MultiPV 5, with an IndexedDB analysis cache (revisited positions grade in ~70ms instead of ~2s)
- **Move insights** — every move graded against the engine's best: eval, %-of-best, win-chance delta, chess.com-style labels (brilliant → blunder), and fact-based prose explanations (detected mates, hanging pieces, forks, material over a quoted line — never an unverified claim)
- **Lines Tree** — a persistent SVG graph of engine lines explored during the game; y-axis/color/label switchable between eval, win %, %-best, and confidence
- **Line previews** — hover any engine line or best-move reference for a small board that animates through the line
- **Practice mode** — moves that drop ≥N% win chance are collected automatically and replayed as puzzles on a Leitner spaced-repetition schedule
- **Bot opponents** — 100–3600 ELO via a three-band scheme (UCI_Elo / Skill Level + shallow depth / depth-1 softmax sampling)
- **Game review** — finished games auto-save to IndexedDB with PGN, per-move grades, and explanations; reviewable move-by-move
- **Lichess import** — pull any user's server-analysed games straight into the archive: labels, accuracies and practice puzzles are mined from Lichess's own evals, no local engine time
- **YouTube commentary** — positions matched against ~27k human commentary snippets mined from game-review videos ([Kaggle dataset](https://www.kaggle.com/datasets/huberthamelin/chess-reviews-from-youtube)), with timestamped links to the source video
- **Blind mode**, promotion picker, refutation arrows

See [ROADMAP.md](ROADMAP.md) for what's planned next.

## Development

```sh
npm install
npm run dev
```

`npm run check` type-checks. Playwright (against installed Chrome) is used for end-to-end verification scripts.

## Desktop app (Tauri)

The same app ships as a desktop shell with a native Stockfish sidecar —
full-strength NNUE on all cores instead of the single-threaded WASM build,
plus a background archive analyzer. Requires Rust and a stockfish binary:

```sh
brew install stockfish   # or apt-get install stockfish
npm run tauri:setup      # stages the sidecar binary (gitignored)
npx tauri dev            # or: npx tauri build
```

Stockfish is GPL-3.0 and runs as a separate sidecar process; bundles that
include the binary must comply with its license (source: stockfishchess.org).

## Static build / deploy

The app is fully client-side, so `npm run build` (adapter-static) emits a plain HTML/JS bundle in `build/` that runs on any static file host — `npx serve build` works; `file://` does not (workers and fetch need HTTP).

Pushes to `main` deploy to GitHub Pages via `.github/workflows/pages.yml`, which builds with `BASE_PATH=/botvinnik` for the project-site URL. All asset URLs go through SvelteKit's `base`, so builds without `BASE_PATH` serve from the domain root.

## Commentary data

`static/commentary.json` is derived from the CC BY-NC [chess-reviews-from-youtube](https://www.kaggle.com/datasets/huberthamelin/chess-reviews-from-youtube) dataset (non-commercial use only). To regenerate, download the dataset to `data/kaggle.huberthamelin.chess-reviews-from-youtube/` and run:

```sh
python3 scripts/build-commentary.py
```
