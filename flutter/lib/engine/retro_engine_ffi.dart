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
      _die('retro_start returned 0');
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
    // Only after the session is stopped: closing the callable first would
    // leave Go holding a function pointer into freed trampoline memory.
    _callback?.close();
    _callback = null;
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
    if (_alive) _send('quit');
    _die('disposed');
  }
}
