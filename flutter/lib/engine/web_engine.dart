// Web transport: Stockfish compiled to WASM, running in a Worker.
//
// This is the SAME engine build the Svelte app uses (static/wasm/stockfish.js,
// the single-threaded "lite" build). That matters beyond convenience: the
// persona labels were calibrated against exactly this engine, so the web build
// is the only one whose bot strength is right by construction — mobile embeds
// SF16 and desktop spawns whatever binary it finds.
//
// A Worker is just another way to move UCI lines, so it plugs into the same
// UciProtocol as the FFI and child-process transports.

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'js_worker.dart';
import 'uci_protocol.dart';

class WebEngine extends UciProtocol {
  static const _scriptUrl = 'wasm/stockfish.js';

  final JsWorker _worker;
  bool _alive = true;
  final Completer<void> _ready = Completer<void>();

  WebEngine._(this._worker) {
    _worker.onmessage = ((WorkerMessage e) {
      final data = e.data?.dartify();
      if (data is! String) {
        debugPrint('[engine] non-string message from worker: $data');
        return;
      }
      // readyok answers the isready sent at startup; everything else is UCI
      if (data.startsWith('readyok') && !_ready.isCompleted) {
        _ready.complete();
        return;
      }
      handleLine(data);
    }).toJS;
    _worker.onerror = ((JSAny? event) {
      final detail = (event as WorkerError?)?.message ?? 'unknown error';
      _die('stockfish worker failed ($_scriptUrl): $detail');
    }).toJS;
  }

  /// The engine is gone. Fail the search in flight so the arbiter recovers,
  /// and fail startup if we never got going, so boot reports it rather than
  /// leaving a board that renders perfectly and never moves.
  void _die(String reason) {
    if (!_alive) return;
    _alive = false;
    final error = StateError(reason);
    if (!_ready.isCompleted) _ready.completeError(error);
    failSearch(error);
  }

  /// Waits for the engine to answer `isready` before boot continues.
  ///
  /// Unlike a child process, `new Worker(url)` does NOT throw when the script
  /// is missing — it reports asynchronously. Without this await, a 404 (the
  /// default state of a fresh clone, since web/wasm/ is a build-time copy)
  /// produced an app that booted cleanly and then silently never moved.
  static Future<WebEngine> start() async {
    final engine = WebEngine._(JsWorker(_scriptUrl));
    engine.send('uci');
    engine.send('setoption name Threads value 1');
    engine.send('isready');
    await engine._ready.future.timeout(
      // generous: this is compiling ~7MB of WASM, and a slow machine or a
      // cold cache can take a while. It only needs to be short enough that a
      // MISSING engine is reported rather than hung on.
      const Duration(seconds: 45),
      onTimeout: () => throw StateError(
          'stockfish worker did not start — is $_scriptUrl served? '
          '(flutter/serve-web.sh stages it)'),
    );
    return engine;
  }

  @override
  void send(String command) {
    if (!_alive) {
      // the completer for this search already exists; without failing it the
      // arbiter waits on a bestmove that can never arrive, forever
      failSearch(StateError('stockfish worker is not running'));
      return;
    }
    _worker.postMessage(command.toJS);
  }

  @override
  void dispose() {
    _alive = false;
    _worker.terminate();
    // terminate() fires no event, so nothing else would resolve a search that
    // is in flight (ProcessEngine gets this for free from exitCode)
    failSearch(StateError('engine disposed'));
  }
}
