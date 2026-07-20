# Third-party notices

botvinnik is licensed under the **GNU General Public License v3.0 or later**
(see [LICENSE](LICENSE)). It has to be: the chess engine and the board and
rules libraries it is built on are GPLv3, and a work combining them is
covered by the same terms.

Source for this app is at <https://github.com/quadrismegistus/botvinnik>,
which is how the GPL's requirement to provide corresponding source is met.

## GPLv3 — the components that set the project's license

| Component | Used for | Upstream |
|---|---|---|
| **Stockfish** | the chess engine, in every build: compiled in on iOS/Android, a bundled binary on macOS, WebAssembly on the web | <https://github.com/official-stockfish/Stockfish> |
| **dartchess** (Lichess) | position, move generation and SAN in the Flutter app — vendored as a fork with web support, see `vendor/dartchess/FORK.md` | <https://github.com/lichess-org/dartchess> |
| **chessground** (Lichess) | the board widget, both the Dart and the web versions | <https://github.com/lichess-org/flutter-chessground> · <https://github.com/lichess-org/chessground> |

Any modifications this project makes to these are published in the same
repository as the rest of the source.

## Permissive components

| Component | License |
|---|---|
| chess.js | BSD-2-Clause |
| Roboto (Christian Robertson) — the app typeface, bundled into the Flutter build so the web app fetches no fonts from Google | Apache-2.0 |
| js-chess-engine (Josef Jadrny) — the "Horizon" bot personas; bundled into `flutter/assets/brain.js` and served to the web in a lazy chunk | MIT |
| morlock (Henning Rohde) — the "retro" bot engines (TUROCHAMP, BERNSTEIN, SARGON), re-implementations built three ways from one source: WebAssembly at `retro/retro.wasm`, native binaries inside the macOS bundle, and a static archive linked into the iOS app | MIT |
| Garbochess-JS (Gary Linscott) — the "Garbo" bot persona; the 2011 engine verbatim, served at `garbo/garbochess.js` with its LICENSE alongside | BSD-3-Clause |
| `wasm_exec.js` (The Go Authors) — the Go↔WASM runtime shim the retro engines load | BSD-3-Clause |
| The Go runtime (The Go Authors) — statically linked into the retro engines on macOS and iOS, as any Go binary carries it | BSD-3-Clause |
| Svelte / SvelteKit | MIT |
| onnxruntime-web — the ONNX runtime for the Maia bots, on the web | MIT |
| ONNX Runtime (Microsoft), via the `onnxruntime` Flutter plugin — the same runtime for the Maia bots on macOS/iOS, linked as a native library | MIT |
| flutter_js | MIT |
| flutter_colorpicker | MIT |
| sqflite | BSD-2-Clause |
| chessboardjs-themes (Joshua Kunst) — board theme colours | MIT |

## Data

| Source | Terms |
|---|---|
| Lichess open database (used to bake the offline opening book) | CC0 |
| lichess-org/chess-openings (opening names) | CC0 |
| Maia weights (CSSLab; via shermansiu/maia-\*) — the neural nets for the "Maia" bots, **fetched at runtime from HuggingFace and never redistributed with this app** | GPL-3.0 |
| Dala / lc0 weights — the neural nets for the desktop-only "Dala" bots, **fetched to disk at runtime, never bundled** | GPL-3.0 |

The two neural-net sets are data, not code, and are downloaded on first use
rather than shipped in any build — so this app never redistributes them, and
the obligation to provide *their* source stays with their upstreams. They are
listed here as attribution.

## What the GPL asks of you

If you distribute this app, or a modified version, you must pass on the same
freedoms: ship the license text, say what you changed, and make the
corresponding source available to whoever receives the binary.
