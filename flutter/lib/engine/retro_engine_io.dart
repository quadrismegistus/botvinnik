// Retro bots on native: the morlock re-implementations of TUROCHAMP (1948),
// BERNSTEIN (1957) and SARGON (1978), built from the vendored Go source
// (`scripts/engines/morlock-src`) into small UCI binaries and spawned as child
// processes. macOS today; iOS is a separate, harder path (see the note at the
// bottom).
//
// This is the native twin of `retro_engine_web.dart`, and it makes the same
// two deliberate choices for the same reasons:
//
//   * **Its own process, never the arbiter.** A 1948 engine has no business in
//     the queue that serialises the one Stockfish every grade depends on.
//   * **Not a UciSearcher / ProcessEngine.** UciProtocol resolves a search
//     from the `info … pv …` lines it parses, and these engines are under no
//     obligation to emit any — the `bestmove` line is the only thing worth
//     reading, which is exactly what this reads. Reusing ProcessEngine would
//     resolve every retro move to an empty list.
//
// The shipped `retro.wasm` (GOOS=js) can't be reused here — hence real
// binaries, staged into the app bundle by `stage-macos-engines.sh` and copied
// into `Contents/Resources/retro/` by the "Bundle chess engine" build phase.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class RetroEngine {
  final String engine;
  final int ply;

  /// True only where a retro binary can actually be found and spawned. Gating
  /// on real presence — not just `Platform.isMacOS` — keeps the roster picker
  /// honest: if the binaries were never staged, retro is not offered rather
  /// than offered-and-silently-falling-back-to-Stockfish (the substitution
  /// the picker exists to prevent). iOS can't spawn processes at all, so it is
  /// false there regardless.
  static bool get supported => Platform.isMacOS && _resolveDir() != null;

  Process? _proc;
  /// Resolves true when the engine answered `uci`, false if it never will.
  /// A bool, not an error: a failed boot must reach the caller as a null move
  /// (→ Stockfish fallback), not an unhandled async error.
  final Completer<bool> _booted = Completer<bool>();
  Completer<String?>? _move;
  bool _alive = true;

  RetroEngine(this.engine, this.ply) {
    final dir = _resolveDir();
    if (dir == null) {
      _die('no retro binary directory found');
      return;
    }
    final path = '$dir/$engine';
    if (!File(path).existsSync()) {
      _die('no retro binary for "$engine" at $path');
      return;
    }
    _start(path);
  }

  /// Where the retro binaries live: bundled in the app. Only the bundled case
  /// works under the macOS sandbox — Process.start on a path outside the
  /// container is denied — so an external override is dev-only and the app
  /// never depends on it.
  static String? _resolveDir() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final candidates = <String>[
      // macOS: Contents/MacOS/<app> → Contents/Resources/retro
      '${exeDir.parent.path}/Resources/retro',
      // dev only, and only for a NON-sandboxed run
      if (Platform.environment['BOTVINNIK_RETRO_DIR'] != null)
        Platform.environment['BOTVINNIK_RETRO_DIR']!,
    ];
    for (final c in candidates) {
      // require turochamp as the sentinel — a dir with a partial set is worse
      // than none, since the missing engine would fall back mid-roster
      if (File('$c/turochamp').existsSync()) return c;
    }
    return null;
  }

  Future<void> _start(String path) async {
    try {
      final proc = await Process.start(path, const []);
      if (!_alive) {
        proc.kill();
        return;
      }
      _proc = proc;
      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine,
              onError: (Object _) => _die('stdout error'),
              onDone: () => _die('stdout closed'));
      // stderr MUST be drained: a full pipe (~64KB) blocks the child
      // mid-search, and morlock chatters to stderr through glog.
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((l) => debugPrint('[retro] $l'), onError: (Object _) {});
      proc.exitCode.then((c) => _die('exited ($c)'));
      _send('uci');
      _send('setoption name Depth value $ply');
      _send('isready');
    } catch (e) {
      _die('spawn failed: $e');
    }
  }

  void _onLine(String line) {
    if (line == 'uciok') {
      if (!_booted.isCompleted) _booted.complete(true);
      return;
    }
    if (line.startsWith('bestmove')) {
      final uci = line.split(RegExp(r'\s+')).elementAtOrNull(1);
      _finish(uci == null || uci == '(none)' || uci == '0000' ? null : uci);
    }
  }

  void _send(String command) {
    if (!_alive) return;
    try {
      _proc?.stdin.writeln(command);
    } catch (_) {
      // stdin closed under us — the exitCode/onDone handlers will _die
    }
  }

  /// The engine is gone. Every waiter gets null, which is the contract: the
  /// caller falls back to Stockfish at the persona's rating.
  void _die(String reason) {
    if (!_alive) return;
    _alive = false;
    debugPrint('[retro] $engine: $reason');
    if (!_booted.isCompleted) _booted.complete(false);
    _finish(null);
    _proc?.kill();
  }

  void _finish(String? uci) {
    final pending = _move;
    _move = null;
    if (pending != null && !pending.isCompleted) pending.complete(uci);
  }

  /// This engine's move for [fen], or null on any failure — a dead process, a
  /// boot that never finished, a search that never answered.
  Future<String?> move(String fen, {int movetimeMs = 500}) async {
    if (!_alive) return null;
    final ok = await _booted.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _die('did not answer uci in 10s');
        return false;
      },
    );
    if (!ok || !_alive) return null;
    // One search at a time; a new game or undo arriving mid-think cancels the
    // previous request to null rather than handing back a move for a gone
    // position.
    _finish(null);
    final pending = _move = Completer<String?>();
    _send('position fen $fen');
    _send('go movetime $movetimeMs');
    return pending.future.timeout(
      Duration(milliseconds: movetimeMs + 8000),
      onTimeout: () {
        _finish(null);
        return null;
      },
    );
  }

  void dispose() {
    if (_alive) _send('quit');
    _die('disposed');
  }
}

// ── iOS ──────────────────────────────────────────────────────────────────
// Still deferred, and genuinely harder: iOS has no child processes, so the
// spawn path above cannot work. The route is the c-archive proven on
// 2026-07-19 — `CGO_ENABLED=1 GOOS=ios GOARCH=arm64 -buildmode=c-archive`
// gives a static lib exporting a C symbol, callable from dart:ffi, with the
// stdin UCI loop replaced by a `retro_send(line)` entry point plus an output
// callback (morlock's main.go already has that shape for JS — swap
// `syscall/js` for `//export`). One archive covers all three engines selected
// by name. That is a separate issue from this macOS work.
