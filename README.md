# Botvinnik

A personal chess practice app — play, get graded, collect your mistakes, and drill them as puzzles. Everything runs in the browser: no server, no accounts, no API keys.

Ported and distilled from a fork of [en-croissant](https://github.com/franciscoBSalgueiro/en-croissant) into a minimal SvelteKit app.

## Features

- **Engine analysis** — Stockfish 18 (lite WASM build) as a web worker, MultiPV 5, with an IndexedDB analysis cache (revisited positions grade in ~70ms instead of ~2s)
- **Move insights** — every move graded against the engine's best: eval, %-of-best, win-chance delta, chess.com-style labels (brilliant → blunder), and fact-based prose explanations (detected mates, hanging pieces, forks, material over a quoted line — never an unverified claim)
- **Lines Tree** — a persistent SVG graph of engine lines explored during the game; y-axis/color/label switchable between eval, win %, %-best, and confidence
- **Practice mode** — moves that drop ≥N% win chance are collected automatically and replayed as puzzles on a Leitner spaced-repetition schedule
- **Bot opponents** — 100–3600 ELO via a three-band scheme (UCI_Elo / Skill Level + shallow depth / depth-1 softmax sampling)
- **Game review** — finished games auto-save to IndexedDB with PGN, per-move grades, and explanations; reviewable move-by-move
- **YouTube commentary** — positions matched against ~27k human commentary snippets mined from game-review videos ([Kaggle dataset](https://www.kaggle.com/datasets/huberthamelin/chess-reviews-from-youtube)), with timestamped links to the source video
- **Blind mode**, promotion picker, refutation arrows

## Development

```sh
npm install
npm run dev
```

`npm run check` type-checks. Playwright (against installed Chrome) is used for end-to-end verification scripts.

## Commentary data

`static/commentary.json` is derived from the CC BY-NC [chess-reviews-from-youtube](https://www.kaggle.com/datasets/huberthamelin/chess-reviews-from-youtube) dataset (non-commercial use only). To regenerate, download the dataset to `data/kaggle.huberthamelin.chess-reviews-from-youtube/` and run:

```sh
python3 scripts/build-commentary.py
```
