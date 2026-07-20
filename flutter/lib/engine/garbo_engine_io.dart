// Garbochess on native: the 2011 worker, running in a Dart isolate instead.
//
// The web loads garbochess.js into a Web Worker and talks to it by
// postMessage. Native has neither, so this supplies both halves:
//
//   * **A worker shim, four lines of JavaScript.** garbochess.js assigns
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
// **A killed isolate does not free its JavaScriptCore.** `Isolate.kill`
// reclaims the Dart heap and nothing else; the JSC context group is native
// memory that only `JavascriptRuntime.dispose()` releases, and flutter_js
// registers no finalizer. garbochess allocates a 4M-slot hash table per
// ResetGame, so this is not a rounding error: a review measured ~167MB leaked
// per disposed engine, monotone over ten cycles, against a flat control that
// reused one engine. So teardown ASKS the child to shut itself down, and only
// falls back to killing it if it never does.
//
// The surface and the failure shapes are garbo_engine_web.dart's otherwise:
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

/// Asks the child to dispose its runtime and let its isolate end.
const String _kShutdown = 'shutdown';

/// What the engine expects the browser to have provided.
///
/// `alert` is the only browser global garbochess touches outside the worker
/// protocol. It is in fact unreachable from either client — only
/// GetMoveFromString calls it, and neither host ever sends a bare move — but a
/// four-line shim that leaves one global undefined is a trap for whoever next
/// sends this engine something new.
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
    worker?.shutdown();
  }

  /// Garbochess's move for [fen], or null on any failure.
  ///
  /// A second call while a search is running does NOT cancel the first —
  /// garbochess honours its own `g_timeout` and cannot be interrupted — so the
  /// second waits out the first and can take up to twice its budget. The
  /// caller is protected by the timeout below rather than by cancellation, and
  /// the superseded caller gets its null immediately.
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
      // identical(), not just "is it complete": without it a search that
      // outlived its request would answer the NEXT position with this one's
      // move, which is legal often enough to be played.
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

  /// Long enough that a child finishing an ordinary search always beats it,
  /// short enough that a wedged one is not a permanent leak.
  static const _kShutdownGrace = Duration(seconds: 30);

  late final Future<void> _ready;
  final ReceivePort _rx = ReceivePort();

  /// Separate from [_rx] so an onExit `null` or an onError `[error, stack]`
  /// can never be mistaken for a `[id, move]` reply.
  final ReceivePort _lifecycle = ReceivePort();

  Isolate? _isolate;
  SendPort? _tx;
  Timer? _backstop;
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
      if (msg is List && msg.length == 2 && msg[0] is int) {
        final done = _pending.remove(msg[0]);
        if (done != null && !done.isCompleted) done.complete(msg[1] as String?);
      }
    });
    // Without this a child that dies — a bad evaluate, a throw in the handler
    // — is invisible, and every later move waits out its full timeout before
    // falling back. The web client's worker.onerror reports in milliseconds.
    _lifecycle.listen((Object? msg) {
      if (msg != null) debugPrint('[garbo] isolate error: $msg');
      _reap();
    });

    final spawned = await Isolate.spawn(
      _garboMain,
      _Boot(_rx.sendPort, source),
      onExit: _lifecycle.sendPort,
      onError: _lifecycle.sendPort,
      debugName: 'garbo',
    );
    // shutdown() can land inside this window, when there was no isolate yet to
    // tell. Nothing else will ever reach this one, so it goes now — and it can
    // only be killed, since it has not yet said hello.
    if (_dead) {
      spawned.kill(priority: Isolate.immediate);
      return;
    }
    _isolate = spawned;
    _tx = await handshake.future;
    if (_dead) _sendShutdown();
  }

  Future<String?> search(String fen, int movetimeMs) async {
    await _ready;
    final tx = _tx;
    if (_dead || tx == null) return null;
    final id = _nextId++;
    final done = Completer<String?>();
    _pending[id] = done;
    tx.send([id, fen, movetimeMs]);
    return done.future;
  }

  /// Stop this engine — by asking, not by killing.
  ///
  /// The ask is what frees the JavaScriptCore; a kill would leave it, and the
  /// context is measured in hundreds of megabytes. A child mid-search takes
  /// its message after the search returns, which is why the backstop is
  /// generous.
  void shutdown() {
    if (_dead) return;
    _dead = true;
    for (final p in _pending.values) {
      if (!p.isCompleted) p.complete(null);
    }
    _pending.clear();
    if (_tx == null) {
      // still booting: _start() sees _dead and cleans up whatever it spawned
      return;
    }
    _sendShutdown();
  }

  void _sendShutdown() {
    _tx?.send(_kShutdown);
    _backstop = Timer(_kShutdownGrace, () {
      debugPrint('[garbo] isolate did not shut down; killing it');
      _isolate?.kill(priority: Isolate.immediate);
      _reap();
    });
  }

  /// The child is gone (or is never coming back). Release this end.
  void _reap() {
    _backstop?.cancel();
    _backstop = null;
    _dead = true;
    for (final p in _pending.values) {
      if (!p.isCompleted) p.complete(null);
    }
    _pending.clear();
    _isolate = null;
    _tx = null;
    _rx.close();
    _lifecycle.close();
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
  // here, asynchronously, and with errorsAreFatal that kills this isolate.
  // Garbo has no use for fetch: it is one file, already in memory.
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
    if (msg == _kShutdown) {
      // The whole point of the shutdown message: this call is the only thing
      // that frees the JavaScriptCore context group, and the parent cannot
      // make it — the runtime lives here.
      rx.close();
      js.dispose();
      return;
    }
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
