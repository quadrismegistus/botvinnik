// Retro bots on native: not yet. [RetroEngine.supported] is false, so the
// roster picker does not offer the three retro personas here at all.
//
// This is a gap, not a wall — it was measured on 2026-07-19, and the findings
// are in ROADMAP.md. In short:
//
//   * The shipped retro.wasm is GOOS=js (scripts/retro-wasm/main.go imports
//     syscall/js), so it can NEVER run in a plain wasm runtime. Reusing the
//     web artifact on native is not an option.
//   * But the morlock source is vendored (scripts/engines/morlock-src) and Go
//     builds it fine: `go build ./cmd/turochamp` gives a 3.7MB darwin binary
//     that answers UCI — which ProcessEngine can already drive, so macOS is
//     mostly a bundling and notarisation question.
//   * iOS needs `CGO_ENABLED=1 GOOS=ios GOARCH=arm64 -buildmode=c-archive`,
//     which produces a valid 3.5MB archive callable from dart:ffi. No
//     gomobile needed.
//
// What is missing is the plumbing and the binaries in the bundle. Note that
// `go build ./cmd/<engine>` is one binary PER engine (~3.7MB each, so ~11MB
// for three) — the single-archive figure above is the iOS c-archive route,
// where one archive covers all three selected by name.
//
// Licensing is NOT a blocker here, contrary to an earlier note in this file:
// morlock is MIT (scripts/engines/morlock-src/LICENSE), so the retro binaries
// carry no copyleft obligation at all. The GPLv3-on-the-App-Store question is
// real, but it belongs to Stockfish and to this repo's own GPL-3.0-or-later
// licence, and it is already live on every platform — retro neither creates
// nor worsens it. See ROADMAP.md.

class RetroEngine {
  RetroEngine(this.engine, this.ply);

  final String engine;
  final int ply;

  static bool get supported => false;

  Future<String?> move(String fen, {int movetimeMs = 500}) async => null;

  void dispose() {}
}
