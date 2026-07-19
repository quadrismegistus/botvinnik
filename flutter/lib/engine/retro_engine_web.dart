// Retro bots on the web: the historical engines compiled to WebAssembly and
// driven in their own Web Worker (web/retro/, staged from static/retro/ by
// stage-web-assets.sh). This is the Dart translation of the Svelte client,
// svelte/src/lib/engine/retro.ts, and speaks the same worker protocol:
// one `{engine, ply}` object to boot, then plain UCI strings both ways.
//
// Deliberately NOT a UciSearcher, and deliberately not behind the arbiter.
// Both halves of that are load-bearing:
//
//   * A retro bot must never touch the analysis engine or its cache. The
//     arbiter exists to serialise the one Stockfish every position's grade
//     depends on; a second engine answering "what would 1948 play here" has
//     no business in that queue, and would evict analysis to say it.
//   * UciProtocol resolves a search from the `info … pv …` lines it collected,
//     so a bestmove with no parsed info line resolves to an EMPTY list. These
//     engines are under no obligation to emit MultiPV info at all — the
//     bestmove line is the only thing worth reading, which is exactly what
//     the Svelte client reads.

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(String scriptUrl);
  external void postMessage(JSAny? message);
  external set onmessage(JSFunction? handler);
  external set onerror(JSFunction? handler);
  external void terminate();
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
}

/// The worker's error event carries the actual failure — a 404 for the script,
/// or a thrown exception. Without reading `message` every failure reports as
/// the same useless string.
extension type _ErrorEvent._(JSObject _) implements JSObject {
  external String? get message;
}

/// The boot message. retro-worker.js tells it from a UCI line by
/// `typeof e.data === 'object'`, so this must cross as an object literal.
extension type _InitMessage._(JSObject _) implements JSObject {
  external factory _InitMessage({String engine, int ply});
}

class RetroEngine {
  static const _scriptUrl = 'retro/retro-worker.js';

  /// The wasm build runs anywhere a Worker does, so on the web: always.
  static bool get supported => true;

  final String engine;
  final int ply;

  final _Worker _worker;
  /// Resolves true when the engine answered `uci`, false if it never will.
  ///
  /// A bool rather than an error: [preload] constructs the engine and awaits
  /// nothing, so completing this with an error would surface a failed boot as
  /// an unhandled async error — a red screen for a condition every caller
  /// already handles by falling back to Stockfish.
  final Completer<bool> _booted = Completer<bool>();
  Completer<String?>? _move;
  bool _alive = true;

  RetroEngine(this.engine, this.ply) : _worker = _Worker(_scriptUrl) {
    _worker.onmessage = ((_MessageEvent e) {
      final data = e.data?.dartify();
      if (data is! String) return; // '__ready__' aside, everything is UCI
      if (data == 'uciok') {
        if (!_booted.isCompleted) _booted.complete(true);
        return;
      }
      if (data.startsWith('bestmove')) {
        final uci = data.split(RegExp(r'\s+')).elementAtOrNull(1);
        _finish(uci == null || uci == '(none)' || uci == '0000' ? null : uci);
      }
    }).toJS;
    _worker.onerror = ((JSAny? event) {
      final detail = (event as _ErrorEvent?)?.message ?? 'unknown error';
      _die('retro worker failed ($_scriptUrl): $detail');
    }).toJS;
    _worker.postMessage(_InitMessage(engine: engine, ply: ply));
    // queued worker-side until the wasm is up — see retro-worker.js
    _worker.postMessage('uci'.toJS);
  }

  /// The engine is gone. Every waiter gets null, which is the contract:
  /// the caller falls back to Stockfish at the persona's rating.
  void _die(String reason) {
    if (!_alive) return;
    _alive = false;
    debugPrint('[retro] $reason');
    if (!_booted.isCompleted) _booted.complete(false);
    _finish(null);
  }

  void _finish(String? uci) {
    final pending = _move;
    _move = null;
    if (pending != null && !pending.isCompleted) pending.complete(uci);
  }

  /// This engine's move for [fen], or null on any failure — a dead worker, a
  /// boot that never finished, a search that never answered.
  Future<String?> move(String fen, {int movetimeMs = 500}) async {
    if (!_alive) return null;
    final ok = await _booted.future.timeout(
      // generous: 4.4MB of wasm to fetch and compile, and on a cold cache
      // that is a real download. It only needs to be short enough that a
      // MISSING worker is fallen back from rather than hung on.
      const Duration(seconds: 30),
      onTimeout: () {
        _die('engine did not boot in 30s — is $_scriptUrl served? '
            '(stage-web-assets.sh stages it)');
        return false;
      },
    );
    if (!ok || !_alive) return null;
    // One search at a time. The bot has one turn at a time, but a new game or
    // an undo can arrive mid-think: whoever was waiting gets null and falls
    // back, rather than being handed a bestmove for a position that is gone.
    _finish(null);
    final pending = _move = Completer<String?>();
    _worker.postMessage('position fen $fen'.toJS);
    _worker.postMessage('go movetime $movetimeMs'.toJS);
    return pending.future.timeout(
      Duration(milliseconds: movetimeMs + 10000),
      onTimeout: () {
        _finish(null);
        return null;
      },
    );
  }

  void dispose() {
    _alive = false;
    _worker.terminate();
    // terminate() fires no event, so nothing else would resolve a search in
    // flight or a boot that never landed
    if (!_booted.isCompleted) _booted.complete(false);
    _finish(null);
  }
}
