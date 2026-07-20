// Garbochess on native: the 2011 worker, running in a Dart isolate instead.
//
// The web loads garbochess.js into a Web Worker and talks to it by
// postMessage. Native has neither, so this supplies both halves:
//
//   * **A worker shim, seven lines of JavaScript.** garbochess.js assigns
//     `self.onmessage` and calls `postMessage`; the shim gives it a `self` to
//     assign to and a `postMessage` that appends to an array. Because the
//     engine's search is one long SYNCHRONOUS call, everything it emits during
//     a search is already in that array by the time the call returns — so
//     there is no message loop to get wrong, only a buffer to read.
//   * **A background isolate.** The search runs for ~1s. On the UI isolate
//     that is a frozen app for ~1s, which is why this was deferred rather than
//     shipped with retro. flutter_js's JavaScriptCore path is pure dart:ffi
//     with no root-isolate dependency, so it starts perfectly well off the
//     main isolate; the engine SOURCE is the one thing that cannot be read
//     there (rootBundle is main-isolate only), so it is read here and passed
//     across as a string.
//
// The surface and the failure shapes are garbo_engine_web.dart's, deliberately:
// one search at a time, a crash is recoverable rather than fatal, and every
// failure is a null move and a fallback to Stockfish.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';

/// A move as garbochess formats it (FormatMove), and nothing else. Every other
/// string it emits is progress chatter.
final _uci = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

/// What the engine expects the browser to have provided.
///
/// `alert` is the only browser global garbochess touches outside the worker
/// protocol — one call, on an internal consistency failure. In a Worker it is
/// undefined and throws, which is why the web client treats a crash as
/// recoverable; here it is routed to the same place as everything else it
/// says, so the failure reports itself instead of exploding.
const _shim = '''
var __out = [];
var self = {};
function postMessage(s) { __out.push(String(s)); }
function alert(s) { __out.push('message ' + s); }
''';

class GarboEngine {
  /// Wherever flutter_js has JavaScriptCore. Not Android: that is QuickJS, and
  /// nothing has checked it can run this file (#46).
  static bool get supported => Platform.isMacOS || Platform.isIOS;

  GarboEngine();

  _GarboIsolate? _worker;
  Completer<String?>? _move;
  bool _disposed = false;

  void _finish(String? uci) {
    final pending = _move;
    _move = null;
    if (pending != null && !pending.isCompleted) pending.complete(uci);
  }

  void _kill() {
    final worker = _worker;
    _worker = null;
    worker?.kill();
  }

  /// Garbochess's move for [fen], or null on any failure.
  Future<String?> move(String fen, {int movetimeMs = 1000}) async {
    if (_disposed) return null;
    // One search at a time. A new game or an undo can arrive mid-think:
    // whoever was waiting gets null and falls back, rather than being handed a
    // move for a position that is gone.
    _finish(null);
    final pending = _move = Completer<String?>();

    // a crash nulled the isolate; the next position deserves a fresh one
    _worker ??= _GarboIsolate();
    final worker = _worker!;
    unawaited(worker.search(fen, movetimeMs).then((uci) {
      if (identical(_move, pending)) _finish(uci);
    }, onError: (Object e) {
      debugPrint('[garbo] $e');
      // Recoverable, unlike retro: 2011 code paths can throw and the next
      // position may well be fine. Scrapping the isolate costs 82KB of
      // JavaScript to re-parse.
      _kill();
      if (identical(_move, pending)) _finish(null);
    }));

    return pending.future.timeout(
      Duration(milliseconds: movetimeMs + 10000),
      onTimeout: () {
        // The search overran its own budget by ten seconds, so the isolate is
        // not coming back on its own schedule. Whoever was waiting falls back.
        _kill();
        _finish(null);
        return null;
      },
    );
  }

  void dispose() {
    _disposed = true;
    _kill();
    _finish(null);
  }
}

/// The isolate half: one JavaScriptCore, one loaded engine, one search at a
/// time.
class _GarboIsolate {
  _GarboIsolate() {
    _ready = _start();
  }

  late final Future<void> _ready;
  final ReceivePort _rx = ReceivePort();
  Isolate? _isolate;
  SendPort? _tx;
  final Map<int, Completer<String?>> _pending = {};
  int _nextId = 1;
  bool _dead = false;

  Future<void> _start() async {
    // rootBundle only exists on the main isolate, so the source crosses as a
    // string rather than being loaded over there.
    final source = await rootBundle.loadString('assets/garbo/garbochess.js');
    final handshake = Completer<SendPort>();
    _rx.listen((Object? msg) {
      if (msg is SendPort) {
        if (!handshake.isCompleted) handshake.complete(msg);
        return;
      }
      if (msg is List && msg.length == 2) {
        final done = _pending.remove(msg[0] as int);
        if (done != null && !done.isCompleted) done.complete(msg[1] as String?);
      }
    });
    _isolate = await Isolate.spawn(
      _garboMain,
      _Boot(_rx.sendPort, source),
      debugName: 'garbo',
    );
    _tx = await handshake.future;
  }

  Future<String?> search(String fen, int movetimeMs) async {
    await _ready;
    if (_dead) return null;
    final id = _nextId++;
    final done = Completer<String?>();
    _pending[id] = done;
    _tx!.send([id, fen, movetimeMs]);
    return done.future;
  }

  void kill() {
    if (_dead) return;
    _dead = true;
    for (final p in _pending.values) {
      if (!p.isCompleted) p.complete(null);
    }
    _pending.clear();
    // Immediate, but a kill only lands at a safepoint — an isolate inside a
    // long synchronous FFI call finishes it first. That is survivable because
    // garbochess enforces its own g_timeout, so the call always returns.
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _rx.close();
  }
}

class _Boot {
  const _Boot(this.reply, this.source);
  final SendPort reply;
  final String source;
}

/// Runs on the spawned isolate. Everything here is synchronous by nature: one
/// eval loads the engine, and each search is a single blocking call.
void _garboMain(_Boot boot) {
  final rx = ReceivePort();
  boot.reply.send(rx.sendPort);

  // xhr: false is load-bearing, not a tidy-up. getJavascriptRuntime's default
  // installs a fetch polyfill by reading its source from rootBundle, and
  // rootBundle does not exist off the main isolate — so the default would fail
  // here, asynchronously, in a place with nobody to report it to. Garbo has no
  // use for fetch: it is one file, already in memory.
  final js = getJavascriptRuntime(xhr: false);
  js.evaluate(_shim);
  final loaded = js.evaluate(boot.source);
  if (loaded.isError) {
    debugPrint('[garbo] engine failed to evaluate: ${loaded.stringResult}');
    rx.close();
    js.dispose();
    return;
  }

  rx.listen((Object? msg) {
    if (msg is! List || msg.length != 3) return;
    final id = msg[0] as int;
    boot.reply.send([id, _search(js, msg[1] as String, msg[2] as int)]);
  });
}

String? _search(JavascriptRuntime js, String fen, int movetimeMs) {
  // `position` resets the game and parses the FEN; `search` runs to
  // g_timeout and calls back into postMessage as it goes. Both are the exact
  // strings the Worker protocol takes, so the two hosts drive the same engine
  // the same way.
  final feed = js.evaluate('''
    __out = [];
    self.onmessage({data: ${jsonEncode('position $fen')}});
    self.onmessage({data: ${jsonEncode('search $movetimeMs')}});
    JSON.stringify(__out);
  ''');
  if (feed.isError) {
    debugPrint('[garbo] search failed: ${feed.stringResult}');
    return null;
  }
  final out = jsonDecode(feed.stringResult);
  if (out is! List) return null;
  // Read backwards: the last bare UCI string is the answer, and everything
  // else — 'pv …' as it thinks, 'message …' from a bad FEN — is chatter.
  for (final line in out.reversed) {
    if (line is String && _uci.hasMatch(line)) return line;
  }
  return null;
}
