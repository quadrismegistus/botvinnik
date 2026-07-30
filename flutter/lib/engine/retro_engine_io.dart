// Retro bots on native: the morlock re-implementations of TUROCHAMP (1948),
// BERNSTEIN (1957) and SARGON (1978), built from the vendored Go source
// (`scripts/engines/morlock-src`).
//
// Two transports, because the platforms differ in one decisive way and in
// nothing else: macOS builds them into small UCI binaries and spawns them as
// child processes; iOS has no child processes, so it builds the same source
// into a static archive and drives it over dart:ffi (retro_engine_ffi.dart).
// Same engines, same ply, same UCI dialogue — so the calibration means the
// same thing on both, and `RetroEngine` below is only the choice between them.
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
// binaries, staged by `stage-macos-engines.sh` and copied into
// `Contents/MacOS/retro/` by the "Bundle chess engine" build phase, which also
// signs each one. Not `Contents/Resources`: executable code there fails
// notarization, because the hardened runtime treats Resources as data.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'retro_commands.dart';

import 'retro_engine_ffi.dart';

/// One retro engine, whichever way this platform can reach it.
abstract class RetroEngine {
  /// True only where a retro engine can actually be reached — a staged binary
  /// on macOS, a linked archive on iOS. Gating on real presence, not on the
  /// platform, keeps the roster picker honest: a build that skipped staging
  /// does not offer retro rather than offering it and silently falling back to
  /// Stockfish, which is the substitution the picker exists to prevent.
  ///
  /// "Present" means loadable, not merely on disk — see [machOMatchesHost].
  /// The file-exists version of this check let an Intel Mac offer all three
  /// personas and stand in Stockfish for every one of them, which is the exact
  /// outcome the paragraph above promises it prevents.
  static bool get supported => Platform.isIOS
      ? RetroFfiEngine.supported
      : Platform.isMacOS && _resolveDir() != null;

  factory RetroEngine(String engine, int ply) => Platform.isIOS
      ? RetroFfiEngine(engine, ply)
      : _RetroProcess(engine, ply);

  /// This engine's move for [fen], or null on any failure. Null is the whole
  /// contract on both transports: the caller falls back to Stockfish at the
  /// persona's rating rather than seeing an error.
  Future<String?> move(String fen, {int movetimeMs});

  /// Whether this engine died in a way a FRESH one would fix — the engine's
  /// process or program ended, as opposed to it never having started.
  ///
  /// Deliberately narrower than "not alive", and the distinction is the whole
  /// value of the flag. An engine that failed to boot — no binary, a 404 on
  /// the wasm, a boot deadline blown — fails identically next time, so
  /// rebuilding it once a turn buys nothing and costs a spawn or a 4.4MB
  /// fetch each time. Worse, [RetroEngine] on the web latches dead after
  /// [_bootDeadline] precisely so that later turns stop paying the full
  /// per-turn patience; rebuilding on that would hand every turn the 30s wait
  /// again, forever, which is the regression that deadline exists to prevent.
  ///
  /// So: true only for an engine that was running and stopped.
  bool get exited => false;

  void dispose();

  /// Where the retro binaries live: bundled in the app. Only the bundled case
  /// works under the macOS sandbox — Process.start on a path outside the
  /// container is denied — so an external override is dev-only and the app
  /// never depends on it.
  static String? _resolveDir() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final candidates = <String>[
      // macOS: Contents/MacOS/<app> → Contents/MacOS/retro. Executables live
      // here rather than in Resources, because code in Resources fails
      // notarization — the hardened runtime treats Resources as data.
      '${exeDir.path}/retro',
      // Where the bundle used to put them. Kept so a stale build still runs.
      '${exeDir.parent.path}/Resources/retro',
      // dev only, and only for a NON-sandboxed run
      if (Platform.environment['BOTVINNIK_RETRO_DIR'] != null)
        Platform.environment['BOTVINNIK_RETRO_DIR']!,
    ];
    for (final c in candidates) {
      // require turochamp as the sentinel — a dir with a partial set is worse
      // than none, since the missing engine would fall back mid-roster
      final sentinel = File('$c/turochamp');
      if (sentinel.existsSync() && machOMatchesHost(sentinel)) return c;
    }
    return null;
  }

  // Mach-O constants. CPU_TYPE_* are the ABI64 flag (0x01000000) OR'd with the
  // base type — 7 for x86, 12 for ARM.
  static const _cpuTypeX8664 = 0x01000007;
  static const _cpuTypeArm64 = 0x0100000C;

  /// Whether [f] is a Mach-O carrying a slice this process could actually exec.
  ///
  /// `existsSync` was the whole test, and it is arch-blind. The macOS app is
  /// configured universal (`ARCHS = arm64 x86_64`) while `stage-macos-engines.sh`
  /// runs a bare `go build`, which takes the host arch — so an Intel Mac got a
  /// present-but-unloadable arm64 binary, [supported] said true, all three
  /// personas appeared in the picker, and every spawn failed with `Bad CPU type
  /// in executable`. The failure is caught and turned into a null move, so the
  /// player got a Stockfish stand-in for every retro game — precisely the
  /// substitution [supported]'s own contract says it exists to prevent.
  ///
  /// [hostCpuType] is injectable so this is testable off a Mac. Without it the
  /// check would only ever run where `Abi.current()` is a macOS ABI, i.e. never
  /// in CI — the shape that has made a suite silently host-only here before.
  @visibleForTesting
  static bool machOMatchesHost(File f, {int? hostCpuType}) {
    final host = hostCpuType ?? _hostCpuType;
    // Unknown host: do not block on a guess. Preserves the old behaviour rather
    // than hiding retro on a platform whose ABI we simply do not recognise.
    if (host == null) return true;

    final Uint8List head;
    try {
      final raf = f.openSync();
      try {
        head = raf.readSync(4096);
      } finally {
        raf.closeSync();
      }
    } on FileSystemException {
      return false;
    }
    if (head.length < 8) return false;
    final bd = ByteData.sublistView(head);

    // Fat/universal: header and entries are BIG-endian regardless of host.
    final beMagic = bd.getUint32(0, Endian.big);
    if (beMagic == 0xCAFEBABE || beMagic == 0xCAFEBABF) {
      final stride = beMagic == 0xCAFEBABF ? 32 : 20; // fat_arch_64 vs fat_arch
      final count = bd.getUint32(4, Endian.big);
      for (var i = 0; i < count; i++) {
        final off = 8 + i * stride;
        if (off + 4 > head.length) break;
        if (bd.getUint32(off, Endian.big) == host) return true;
      }
      return false;
    }

    // Thin Mach-O: little-endian on every arch we ship.
    final leMagic = bd.getUint32(0, Endian.little);
    if (leMagic == 0xFEEDFACF || leMagic == 0xFEEDFACE) {
      return bd.getUint32(4, Endian.little) == host;
    }
    return false; // not a Mach-O; nothing here is executable
  }

  static int? get _hostCpuType => switch (Abi.current()) {
        Abi.macosArm64 => _cpuTypeArm64,
        Abi.macosX64 => _cpuTypeX8664,
        _ => null,
      };
}

class _RetroProcess implements RetroEngine {
  /// The process ended on its own — morlock's `main` returns when its driver
  /// loop returns, so the binary exits and this is respawnable. Set ONLY
  /// there: the boot timeout and a missing binary are not.
  bool _exited = false;
  @override
  bool get exited => _exited;

  /// Whether this process ever answered `uci`. The gate on [_exited], and it
  /// has to be this rather than the obvious `_alive`: [_die] kills the child,
  /// so a boot that TIMED OUT completes `exitCode` too, and a rebuild on that
  /// respawns every turn and pays the 10s boot wait again — worse than keeping
  /// the corpse. `_alive` does not separate them either, because on a genuine
  /// exit `onDone: 'stdout closed'` lands first and has already cleared it.
  bool _ranOk = false;

  final String engine;
  final int ply;

  Process? _proc;
  /// Resolves true when the engine answered `uci`, false if it never will.
  /// A bool, not an error: a failed boot must reach the caller as a null move
  /// (→ Stockfish fallback), not an unhandled async error.
  final Completer<bool> _booted = Completer<bool>();
  Completer<String?>? _move;
  bool _alive = true;

  _RetroProcess(this.engine, this.ply) {
    final dir = RetroEngine._resolveDir();
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
      proc.exitCode.then((c) {
        // Only an engine that RAN is worth respawning — see [_ranOk].
        if (_ranOk) _exited = true;
        _die('exited ($c)');
      });
      _send('uci');
      _send('setoption name Depth value $ply');
      _send('isready');
    } catch (e) {
      _die('spawn failed: $e');
    }
  }

  void _onLine(String line) {
    if (line == 'uciok') {
      _ranOk = true;
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

  /// A dead process, a boot that never finished, a search that never answered
  /// — all null, per the contract on RetroEngine.move.
  @override
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
    // The command sequence lives in retro_commands.dart, where it is tested.
    for (final c in retroMoveCommands(fen, movetimeMs)) {
      _send(c);
    }
    return pending.future.timeout(
      Duration(milliseconds: movetimeMs + 8000),
      onTimeout: () {
        _finish(null);
        return null;
      },
    );
  }

  @override
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
