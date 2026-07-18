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

import 'dart:js_interop';

import 'uci_protocol.dart';

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

class WebEngine extends UciProtocol {
  final _Worker _worker;
  bool _alive = true;

  WebEngine._(this._worker) {
    _worker.onmessage = ((_MessageEvent e) {
      final line = e.data?.dartify();
      if (line is String) handleLine(line);
    }).toJS;
    _worker.onerror = ((JSAny? _) {
      if (!_alive) return;
      _alive = false;
      failSearch(StateError('stockfish worker error'));
    }).toJS;
  }

  static Future<WebEngine> start() async {
    final engine = WebEngine._(_Worker('wasm/stockfish.js'));
    engine.send('uci');
    engine.send('setoption name Threads value 1');
    engine.send('isready');
    return engine;
  }

  @override
  void send(String command) {
    if (_alive) _worker.postMessage(command.toJS);
  }

  @override
  void dispose() {
    _alive = false;
    _worker.terminate();
  }
}
