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
| **Rodent IV** (Pawel Koziol) | the "Rodent" bot personas — its playing-STYLE files (Tal, Botvinnik, Petrosian, …) are bundled under `flutter/assets/rodent/personalities/`; the engine binary itself is downloaded on demand, not shipped | <https://github.com/nescitus/rodent-iv> |

Any modifications this project makes to these are published in the same
repository as the rest of the source.

## Permissive components

| Component | License |
|---|---|
| chess.js | BSD-2-Clause |
| Roboto (Christian Robertson) — the app typeface, bundled into the Flutter build so the web app fetches no fonts from Google | Apache-2.0 |
| js-chess-engine (Josef Jadrny) — the "Horizon" bot personas; bundled into `flutter/assets/brain.js` and served to the web in a lazy chunk | MIT |
| morlock (Henning Rohde) — the "retro" bot engines (TUROCHAMP, BERNSTEIN, SARGON), re-implementations built three ways from one source: WebAssembly at `retro/retro.wasm`, native binaries inside the macOS bundle, and a static archive linked into the iOS app | MIT |
| Garbochess-JS (Gary Linscott) — the "Garbo" bot persona; the 2011 engine verbatim, served at `garbo/garbochess.js` on the web and bundled as an asset on macOS/iOS, with its LICENSE alongside in both | BSD-3-Clause |
| `wasm_exec.js` (The Go Authors) — the Go/WASM runtime shim the retro engines load | BSD-3-Clause |
| The Go runtime (The Go Authors) — statically linked into the retro engines on macOS and iOS, as any Go binary carries it | BSD-3-Clause |
| onnxruntime-web — the ONNX runtime for the Maia bots, on the web | MIT |
| ONNX Runtime (Microsoft), via the `onnxruntime` Flutter plugin — the same runtime for the Maia bots on macOS/iOS, linked as a native library | MIT |
| flutter_js | MIT |
| flutter_colorpicker | MIT |
| sqflite | BSD-2-Clause |
| chessboardjs-themes (Joshua Kunst) — board theme colours | MIT |
| cryptography_plus (emz-hanauer.com; the maintained fork of Gohilla's `cryptography`) — the cross-device sync crypto (#203): PBKDF2 (phrase → key), HKDF (key split), AES-256-GCM (the blob cipher), run via WebCrypto on web | Apache-2.0 |
| archive — gzip for the sync payload before it is encrypted; the cross-platform codec (incl. web) that `dart:io`'s GZipCodec is not | MIT |
| flutter_secure_storage (German Saprykin) — device-local storage of the derived sync keys: Keychain / Keystore / WebCrypto-encrypted localStorage | BSD-3-Clause |
| unorm_dart (Yasuhiro Shimizu) — Unicode NFC normalization of a sync phrase, so its NFD and NFC forms derive one key | MIT |

## Data

| Source | Terms |
|---|---|
| Lichess open database (used to bake the offline opening book) | CC0 |
| lichess-org/chess-openings (opening names) | CC0 |
| Maia weights (CSSLab; via shermansiu/maia-\*) — the neural nets for the "Maia" bots, **fetched at runtime from HuggingFace and never redistributed with this app** | GPL-3.0 |
| EFF "large" wordlist (Electronic Frontier Foundation) — the 7776 diceware words every generated sync phrase is drawn from, embedded verbatim in `flutter/lib/sync/eff_wordlist.dart` | CC BY 3.0 US |

The Maia weights are data, not code, and are downloaded on first use rather
than shipped in any build — so this app never redistributes them, and the
obligation to provide *their* source stays with their upstream. They are
listed here as attribution.

### The Dala nets are not used, and are not licensed

The roster data names three "Dala" personas, and earlier versions of this file
listed their weights as GPL-3.0. **That was wrong on both counts and has been
corrected.**

`hrschubert/dala-training` states no licence at all — no `LICENSE` file, and
no licence reported by GitHub — so no permission to use or redistribute those
weights has been granted, and none has been sought. The GPL-3.0 claim appears
to have come from conflating them with **lc0**, the engine that would run them,
which *is* GPL-3.0.

Nothing in this app touches either. The Dala family is not offered by the
roster picker on any platform, there is no lc0 binary in any build, and no
Dala weights are ever fetched — the only build that could run them was the
Tauri desktop shell, retired 2026-07-20. The personas exist as three rows of
roster data and nothing else.

If Dala is ever implemented, the licence has to be settled with the author
first. That is tracked in issue #47.

## What the GPL asks of you

If you distribute this app, or a modified version, you must pass on the same
freedoms: ship the license text, say what you changed, and make the
corresponding source available to whoever receives the binary.
