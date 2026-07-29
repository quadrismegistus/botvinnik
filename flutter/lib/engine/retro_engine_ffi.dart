// Retro on iOS: the same morlock engines, reached through a Go c-archive
// instead of a child process.
//
// iOS has no child processes, so `retro_engine_io.dart`'s Process.start path
// cannot work there. The archive (`scripts/retro-ffi/main.go`, staged by
// `stage-ios-engines.sh`) replaces morlock's stdin loop with three C symbols;
// everything else — the engines, the ply, the UCI dialogue — is unchanged, so
// this plays the opponent the calibration measured.
//
// Two things about the boundary are load-bearing:
//
//   * **The callback is a NativeCallable.listener.** Go emits lines from its
//     own goroutines, on threads Dart knows nothing about, and only a listener
//     may be invoked from a foreign thread. It does not run when invoked — it
//     posts to this isolate's event loop — which is why the archive hands over
//     a malloc'd copy and this frees it with retro_free_line rather than the
//     Go side freeing on return.
//   * **Symbols, not a platform check.** `supported` asks whether the archive
//     is actually linked in. A build that skipped staging then does not offer
//     retro at all, rather than offering it and silently substituting
//     Stockfish — the same gate the macOS side applies to its binaries.

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'retro_engine_io.dart';

typedef _LineCallback = Void Function(Int32, Pointer<Utf8>);

typedef _StartNative = Int32 Function(
    Pointer<Utf8>, Int32, Pointer<NativeFunction<_LineCallback>>);
typedef _StartDart = int Function(
    Pointer<Utf8>, int, Pointer<NativeFunction<_LineCallback>>);

typedef _SendNative = Void Function(Int32, Pointer<Utf8>);
typedef _SendDart = void Function(int, Pointer<Utf8>);

typedef _HandleNative = Void Function(Int32);
typedef _HandleDart = void Function(int);

typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

/// The archive's C surface, or null when it was never linked in.
class _RetroLib {
  _RetroLib._(this.start, this.send, this.stop, this.freeLine);

  final _StartDart start;
  final _SendDart send;
  final _HandleDart stop;
  final _FreeDart freeLine;

  static _RetroLib? _cached;
  static bool _tried = false;

  static _RetroLib? get instance {
    if (_tried) return _cached;
    _tried = true;
    try {
      // The archive is linked into the app binary, so its symbols live in the
      // process rather than in a dylib of their own.
      final lib = DynamicLibrary.process();
      if (!lib.providesSymbol('retro_start')) return null;
      _cached = _RetroLib._(
        lib.lookupFunction<_StartNative, _StartDart>('retro_start'),
        lib.lookupFunction<_SendNative, _SendDart>('retro_send'),
        lib.lookupFunction<_HandleNative, _HandleDart>('retro_stop'),
        lib.lookupFunction<_FreeNative, _FreeDart>('retro_free_line'),
      );
    } catch (e) {
      debugPrint('[retro] archive not available: $e');
    }
    return _cached;
  }
}

/// One engine session over FFI. The surface is the same as the process-backed
/// RetroEngine's, because GameController must not care which it got.
class RetroFfiEngine implements RetroEngine {
  /// Always: a spawned process or a linked archive lives as long as this
  /// object does. Only the web worker's Go program ends on its own.
  @override
  bool get alive => true;

  RetroFfiEngine(this.engine, this.ply) {
    final lib = _RetroLib.instance;
    if (lib == null) {
      _die('archive not linked');
      return;
    }
    _callback = NativeCallable<_LineCallback>.listener(_onNativeLine);
    final name = engine.toNativeUtf8();
    try {
      _handle = lib.start(name, ply, _callback!.nativeFunction);
    } finally {
      malloc.free(name);
    }
    if (_handle == 0) {
      // The archive rejects a name it has no engine for, which is what makes
      // this reachable — and what keeps iOS honest with macOS, where a missing
      // binary is a null move rather than a different engine under the same
      // persona's name.
      _die('retro_start rejected "$engine"');
      return;
    }
    _send('uci');
    _send('setoption name Depth value $ply');
    _send('isready');
  }

  final String engine;
  final int ply;

  static bool get supported => _RetroLib.instance != null;

  NativeCallable<_LineCallback>? _callback;
  int _handle = 0;
  bool _alive = true;
  final Completer<bool> _booted = Completer<bool>();
  Completer<String?>? _move;

  void _onNativeLine(int handle, Pointer<Utf8> line) {
    // The archive malloc'd this and handed it over; free it whatever we decide
    // to do with the contents.
    String text;
    try {
      text = line.toDartString();
    } finally {
      _RetroLib.instance?.freeLine(line);
    }
    if (!_alive || handle != _handle) return;
    if (text == 'uciok') {
      if (!_booted.isCompleted) _booted.complete(true);
      return;
    }
    if (text.startsWith('bestmove')) {
      final uci = text.split(RegExp(r'\s+')).elementAtOrNull(1);
      _finish(uci == null || uci == '(none)' || uci == '0000' ? null : uci);
    }
  }

  void _send(String command) {
    if (!_alive || _handle == 0) return;
    final lib = _RetroLib.instance;
    if (lib == null) return;
    final p = command.toNativeUtf8();
    try {
      lib.send(_handle, p);
    } finally {
      malloc.free(p);
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
    if (_handle != 0) _RetroLib.instance?.stop(_handle);
    _handle = 0;
    // Only after the session is stopped — closing the callable first would
    // leave Go holding a function pointer into freed trampoline memory — and
    // only after a turn of the event loop.
    //
    // A NativeCallable.listener is a RawReceivePort, and closing one DISCARDS
    // whatever it has queued. Every queued line is a malloc'd string this end
    // owns and frees in _onNativeLine, so closing in the same turn as stop()
    // strands all of them. Go's lock guarantees no new line can start after
    // stop() returns, so one turn is enough to drain the ones already posted.
    final callback = _callback;
    _callback = null;
    Future<void>.delayed(Duration.zero, () => callback?.close());
  }

  void _finish(String? uci) {
    final pending = _move;
    _move = null;
    if (pending != null && !pending.isCompleted) pending.complete(uci);
  }

  /// A dead session, a boot that never finished, a search that never answered
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
    // One search at a time; a new game arriving mid-think cancels the previous
    // request to null rather than handing back a move for a gone position.
    _finish(null);
    final pending = _move = Completer<String?>();
    // `ucinewgame` FIRST, every time, and it is load-bearing rather than
    // tidy. morlock's UCI driver treats a `position` line that PREFIXES the
    // last one as a continuation of the game and parses the remainder as
    // moves (pkg/engine/uci/uci.go, "Continuation of game") — so an IDENTICAL
    // line leaves an empty remainder, `Move(ctx, "")` fails, and the driver
    // RETURNS. That ends the driver, which ends `<-driver.Closed()` in
    // scripts/retro-wasm/main.go, which ends the Go program. In a worker that
    // is a silent death; the client then waits out its whole move timeout and
    // hands the turn to a Stockfish stand-in, for the rest of the game.
    //
    // Honest split of the blame, because it decides where the fix belongs.
    // UCI says a GUI SHOULD send `ucinewgame` when the new position is from a
    // different game than the last one — morlock quotes that line in the
    // source directly above the branch that bites. This client never sent it,
    // so the new-game half of this is our omission, and the line below is us
    // complying rather than working around anybody.
    //
    // The engine's half is that an identical line is a degenerate case its
    // parser does not handle (`strings.Split("", " ")` yields one EMPTY
    // element), and that it answers unparseable input by ending the session
    // rather than ignoring it, which UCI asks engines to do. That half is
    // reachable with no protocol sin at all: take a move back and play the
    // same move again, and the engine is legitimately asked to move from a
    // position it has already been sent, FEN counters and all. Reported
    // upstream; the one-line guard is theirs to take.
    //
    // The report that found it: play a game where the retro bot moves first,
    // start another, and its opening `position fen <start>` is
    // character-identical to the last line the engine saw.
    //
    // This costs nothing: we always send a whole FEN and never a `moves` list,
    // so the continuation branch could never fire usefully for us — a
    // different FEN always takes the engine's "New position" reset path, which
    // is exactly what `ucinewgame` forces. Same work, minus the cliff.
    _send('ucinewgame');
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

  @override
  void dispose() {
    // No 'quit', unlike the process transport. morlock handles it by returning
    // out of its driver loop without clearing the active-search flag, so a
    // search still finishing sends on a closed channel — a Go panic, which is
    // an invisible engine death in a child process and SIGABRT in this one.
    // The archive refuses the line as well; ending the session is retro_stop's
    // job here and it does it in an order that cannot race.
    _die('disposed');
  }
}
