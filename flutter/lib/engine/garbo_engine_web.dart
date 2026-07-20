// Garbochess-JS (Gary Linscott, 2011, BSD — vendored in static/garbo/ with
// its LICENSE): a hand-written JavaScript engine from before compiling C to
// the browser was practical. Fruit-era eval — PSQ, mobility, bishop pair, all
// pre-NNUE. The Dart translation of svelte/src/lib/engine/garbo.ts.
//
// Strength anchor: @GarboBot on lichess runs this engine and holds ~1931
// blitz / ~2021 rapid over 90k+ human games. We run ~1s a move, in that
// neighbourhood. Provenance footnote: Linscott went on to create fishtest and
// found Leela.
//
// Simpler than [RetroEngine], and the differences are the interesting part:
//
//   * No handshake. The worker protocol is built into the engine file — send
//     `position <fen>` then `search <ms>`, and the move comes back as a bare
//     UCI string. There is nothing to wait for at boot, so no boot completer.
//   * Failure is RECOVERABLE, so this respawns where RetroEngine gives up for
//     good. 2011 code paths call `alert()`, which is undefined in a worker,
//     so a crash is a live possibility rather than a theoretical one — and
//     the next position may well be fine. Scrapping the worker and starting
//     over costs 82KB of already-cached JavaScript.
//
// Like retro, this deliberately does not go through the arbiter: Garbo is an
// opponent, not an analysis of anything.

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'js_worker.dart';

/// A move as garbochess formats it (FormatMove), and nothing else. Every
/// other string the worker emits is progress chatter.
final _uci = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

class GarboEngine {
  static const _scriptUrl = 'garbo/garbochess.js';

  /// Plain JavaScript in a Worker, so: anywhere the web runs.
  static bool get supported => true;

  JsWorker? _worker;
  Completer<String?>? _move;

  /// A search has been posted and not yet answered.
  ///
  /// It matters because a running search cannot be cancelled — garbochess
  /// honours its own g_timeout and is inside one synchronous call — so its
  /// answer arrives AFTER the next request has been made, and this client
  /// completes whatever is currently waiting. That is a move for the previous
  /// position handed to the current one: often illegal and dropped upstream,
  /// but not always, and "not always" is a move nobody chose being played.
  bool _busy = false;
  bool _disposed = false;

  GarboEngine() {
    _spawn();
  }

  void _spawn() {
    if (_disposed) return;
    final worker = JsWorker(_scriptUrl);
    _worker = worker;
    worker.onmessage = ((WorkerMessage e) {
      final data = e.data?.dartify();
      if (data is! String) return;
      // 'pv …' is the line it is currently considering, 'message …' is an
      // error from InitializeFromFen. Neither is an answer.
      if (data.startsWith('pv ') || data.startsWith('message ')) return;
      _busy = false;
      _finish(_uci.hasMatch(data) ? data : null);
    }).toJS;
    worker.onerror = ((JSAny? event) {
      final detail = (event as WorkerError?)?.message ?? 'unknown error';
      debugPrint('[garbo] worker failed ($_scriptUrl): $detail');
      // Fail NOW rather than after the timeout, and scrap the worker so the
      // next move starts from a clean one. Whoever was waiting falls back to
      // Stockfish, which is the contract for every failure path here.
      _kill();
      _finish(null);
    }).toJS;
  }

  void _kill() {
    final worker = _worker;
    _worker = null;
    _busy = false;
    try {
      worker?.terminate();
    } catch (_) {
      // already gone
    }
  }

  void _finish(String? uci) {
    final pending = _move;
    _move = null;
    if (pending != null && !pending.isCompleted) pending.complete(uci);
  }

  /// Garbochess's move for [fen], or null on any failure.
  Future<String?> move(String fen, {int movetimeMs = 1000}) {
    if (_disposed) return Future.value(null);
    // A search still running would answer this request with the previous
    // position's move. Scrapping the worker is the only way to be sure it
    // cannot, and costs 82KB of already-cached JavaScript to re-parse — the
    // same trade this client already makes for a crash. The native client gets
    // there differently, by matching the reply to the request it belongs to;
    // here there is nothing in the protocol to match on.
    if (_busy) _kill();
    // a crash nulled the worker; the next position deserves a fresh one
    if (_worker == null) _spawn();
    final worker = _worker;
    if (worker == null) return Future.value(null);
    // One search at a time. A new game or an undo can arrive mid-think:
    // whoever was waiting gets null and falls back, rather than being handed
    // a move for a position that is gone.
    _finish(null);
    final pending = _move = Completer<String?>();
    _busy = true;
    worker.postMessage('position $fen'.toJS);
    worker.postMessage('search $movetimeMs'.toJS);
    return pending.future.timeout(
      Duration(milliseconds: movetimeMs + 10000),
      onTimeout: () {
        _finish(null);
        return null;
      },
    );
  }

  void dispose() {
    _disposed = true;
    _kill();
    // terminate() fires no event, so nothing else would resolve a search that
    // is in flight
    _finish(null);
  }
}
