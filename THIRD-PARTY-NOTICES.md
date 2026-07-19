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
| js-chess-engine (Josef Jadrny) — the "Horizon" bot personas; bundled into `flutter/assets/brain.js` and served to the web in a lazy chunk | MIT |
| Svelte / SvelteKit | MIT |
| onnxruntime-web | MIT |
| flutter_js | MIT |
| flutter_colorpicker | MIT |
| sqflite | BSD-2-Clause |
| chessboardjs-themes (Joshua Kunst) — board theme colours | MIT |

## Data

| Source | Terms |
|---|---|
| Lichess open database (used to bake the offline opening book) | CC0 |
| lichess-org/chess-openings (opening names) | CC0 |

## What the GPL asks of you

If you distribute this app, or a modified version, you must pass on the same
freedoms: ship the license text, say what you changed, and make the
corresponding source available to whoever receives the binary.
