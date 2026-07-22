// The Maia bots on macOS/iOS: the same human-imitation nets the web plays,
// with the browser's three pieces replaced one for one.
//
//   ort-web + Worker    -> package:onnxruntime (ORT's C API over dart:ffi),
//                          run through its own isolate so a forward pass does
//                          not land on the UI thread
//   fetch + IndexedDB   -> HttpClient + a file under Application Support
//   the worker's import -> assets/maia-brain.js in an embedded JS runtime
//
// What did NOT move is the chess: encoding a FEN history into lc0's
// [1,112,8,8] input and decoding its 1858-wide policy head are the same
// brain/maia/ sources the web worker imports, bundled for JavaScriptCore.
// Native contributes no chess logic of its own, which is the only reason the
// two platforms' Maia can be said to be the same opponent.
//
// The order of a move is therefore: encode in JS -> infer in Dart -> decode in
// JS. Two crossings, each a JSON array (7168 mostly-binary floats out, 1858
// logits back), against an inference measured in tens of milliseconds.
//
// The failure shapes are the web's, for the web's reasons — see the long
// comments in web_src/maia-worker.ts. Kept here: one request at a time, and a
// per-band load cache that a stalled network latches permanently.
//
// Where native diverges, it is because a file cache can be corrupt in a way
// IndexedDB's cannot, and because an ORT session here is a native object with
// its own isolate rather than a Worker somebody else owns. So: a download
// lands through a `.part` rename, a model that will not open is deleted and
// granted exactly one re-download, and a session whose run stalls is retired
// rather than reused — but the BAND stays playable, because the alternative
// is a persona that quietly becomes Stockfish after one slow frame.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:onnxruntime/onnxruntime.dart';

import '../brain/js_bridge_shared.dart';
import 'maia_progress.dart';
import 'maia_weights.dart';

/// Bump in lockstep with MAIA_BRAIN_VERSION in native_src/maia-brain.ts.
const int _kExpectedMaiaBrainVersion = 1;

/// The weights themselves — where they are cached, and the one downloader for
/// them — live in maia_weights_io.dart, because the roster picker and the
/// prefetch (#130) both need them and neither should have to import ORT to
/// ask. The download's shape is unchanged: 30s per chunk, and a `.part`
/// rename so a half-arrived file is never readable as a cache hit.
///
/// The two platforms run ORT versions two years apart (1.15.1 through the pod
/// here, 1.27 through onnxruntime-web there). That is fine for a net this
/// simple and is checked rather than assumed — the parity fixtures in
/// integration_test/maia_native_test.dart are the thing that would notice, and
/// they are the first place to look if a band ever starts disagreeing.
const Duration _kRunTimeout = Duration(seconds: 15);

class _Net {
  const _Net(this.session, this.inputName, this.policyName);
  final OrtSession session;
  final String inputName;
  final String policyName;
}

class MaiaEngine {
  static const _asset = 'assets/maia-brain.js';

  MaiaEngine({this.onProgress});

  /// macOS and iOS. Not Android: package:onnxruntime covers it, but the JS
  /// half would run under QuickJS rather than JavaScriptCore and nothing has
  /// checked that it can (#46). Claiming a persona the app cannot actually
  /// play is worse than not offering it.
  static bool get supported => Platform.isMacOS || Platform.isIOS;

  /// Called as a move waits on something other than inference: the weights
  /// arriving, then ORT building the session. Null once it is genuinely
  /// thinking — the caller clears it when the move lands.
  final void Function(MaiaProgress?)? onProgress;

  /// ORT's environment is process-global and `init` leaks one on every call.
  static bool _envReady = false;

  JavascriptRuntime? _js;
  final Map<int, Future<_Net>> _nets = {};

  /// Bands this session has given up on. Not retried — a network that accepts
  /// and never answers, or weights that cannot be read, would otherwise cost
  /// their full failure on every move, forever.
  ///
  /// The web worker latches only on TIMEOUTS, on the grounds that a fast
  /// failure is cheap to retry. Native latches wider, because here a retry is
  /// not cheap: the cache is a FILE, a model ORT cannot open is deleted, and
  /// the retry is therefore another 3.5MB download — every move, unbounded.
  /// A 404 is still not latched, since that is one cheap request.
  ///
  /// It deliberately does NOT latch on a slow inference. Latching there was a
  /// worse bug than the one it fixed: one 15s overrun — a thermal-throttled
  /// phone, a backgrounded app — and that Maia played as Stockfish under
  /// Maia's name for the rest of the run, which is the substitution this whole
  /// layer exists to prevent, and it never self-healed.
  final Set<int> _deadBands = {};

  /// Sessions retired per band, and the point at which retiring stops being
  /// worth it.
  ///
  /// A retired session is rebuilt from the cached FILE — no download, tens of
  /// milliseconds — so a transient overrun costs almost nothing and heals. A
  /// band that keeps doing it is genuinely broken and each retirement strands
  /// a session, so it latches in the end.
  final Map<int, int> _retirements = {};
  static const int _kMaxRetirements = 3;

  /// Times a band's weights would not open. One retry (a fresh download), then
  /// the band is given up on — see [_net].
  final Map<int, int> _unreadable = {};

  /// Requests are handled one at a time. ORT's isolate session takes the first
  /// result off a broadcast stream, so two overlapping runs can be handed each
  /// other's output — the native shape of the same hazard the web worker
  /// serialises against.
  Future<void> _chain = Future.value();

  /// Bumped by every request and by [cancelPending]. A reply belongs to the
  /// current generation or to nobody.
  int _gen = 0;

  /// Bands with a request outstanding, and how many.
  ///
  /// Progress gates on this rather than on a generation, because a download is
  /// cached per BAND and outlives the request that started it: the generation
  /// it was born under is stale by the time the move that is actually waiting
  /// for it arrives, and gating on that generation blanked the bar for the
  /// whole rest of the download. Per band and not just a count, so an
  /// abandoned download cannot narrate itself over a move waiting on a
  /// different one.
  final Map<int, int> _waiting = {};

  /// ORT runs dispatched and not yet back. `dispose` must not release a
  /// session out from under one — `OrtSession.release` tears the native
  /// session down without waiting for its isolate to stop.
  ///
  /// A count, not a flag: a run abandoned at its timeout is still outstanding
  /// while the next one runs, and with a flag its late completion cleared the
  /// guard for a run that was very much still going.
  int _running = 0;

  bool _disposed = false;

  /// Maia's move for the position at the end of [fenHistory], or null on any
  /// failure — no weights, no network, no legal moves.
  ///
  /// [fenHistory] is oldest-first with the current position last.
  Future<String?> move(
    List<String> fenHistory, {
    required int band,
    double temperature = 0,
  }) {
    if (_disposed || fenHistory.isEmpty) return Future.value(null);
    final gen = ++_gen;
    _waiting.update(band, (n) => n + 1, ifAbsent: () => 1);
    final done = Completer<String?>();
    _chain = _chain.then((_) async {
      // whoever bumped the generation has moved on; do not start its work
      if (_disposed || gen != _gen) {
        if (!done.isCompleted) done.complete(null);
        return;
      }
      try {
        final uci = await _move(fenHistory, band, temperature, gen);
        if (!done.isCompleted) done.complete(gen == _gen ? uci : null);
      } catch (e) {
        debugPrint('[maia] $e');
        if (!done.isCompleted) done.complete(null);
      }
    });
    return done.future.timeout(
      // generous on purpose: the first call for a band is a 3.5MB download
      // plus building the session. Later calls answer in tens of ms.
      const Duration(seconds: 90),
      onTimeout: () => null,
    ).whenComplete(() {
      final left = (_waiting[band] ?? 1) - 1;
      if (left > 0) {
        _waiting[band] = left;
      } else {
        _waiting.remove(band);
      }
    });
  }

  Future<String?> _move(
    List<String> fenHistory,
    int band,
    double temperature,
    int gen,
  ) async {
    final js = await _runtime();
    if (_disposed) return null;
    final fen = fenHistory.last;

    // Before the download, not after: this is also the "no legal moves" check,
    // and a broken bundle should fail without pulling 3.5MB first.
    final encoded = _call(js, 'maiaPlanes', args: [fenHistory]);
    if (encoded is! List) return null;
    final planes = Float32List(encoded.length);
    for (var i = 0; i < encoded.length; i++) {
      planes[i] = (encoded[i] as num).toDouble();
    }

    final net = await _net(band);
    if (_disposed || gen != _gen) return null;

    // This band's weights are on disk now, so filling in the other two cannot
    // compete with a download somebody is watching — which is why the prefetch
    // is started HERE rather than when the engine is built. Idempotent: the
    // first call that gets through does the work, the rest join it. Its
    // failures are its own (see MaiaWeights.prefetch) and cannot retire a band
    // this session has not been asked to play.
    unawaited(MaiaWeights.prefetch());

    final input = OrtValueTensor.createTensorWithDataList(planes, [1, 112, 8, 8]);
    final runOptions = OrtRunOptions();
    final run = net.session.runAsync(
      runOptions,
      {net.inputName: input},
      [net.policyName],
    );
    if (run == null) {
      input.release();
      runOptions.release();
      return null;
    }
    // Free the inputs when the run REALLY finishes, not when we stop waiting
    // for it. ORT reads them from its own isolate, so releasing them on the
    // timeout path would be a use-after-free rather than a tidy-up — a crash
    // instead of the fallback every other failure here degrades to.
    _running++;
    final finished = run.then<List<OrtValue?>?>((o) => o, onError: (Object e) {
      debugPrint('[maia] inference failed: $e');
      return null;
    }).whenComplete(() {
      _running--;
      input.release();
      runOptions.release();
    });

    List<OrtValue?>? outputs;
    try {
      outputs = await finished.timeout(_kRunTimeout);
    } on TimeoutException {
      // The run is still out there. Abandoning the WAIT is not abandoning the
      // run, and ORT's isolate session hands results out on a BROADCAST stream
      // that this call is still subscribed to — so the next run on the SAME
      // session could be handed whichever result arrived first, and answer a
      // new position with the old one's policy. A wrong move is worse than no
      // move, so the session is retired: the next request builds a fresh one,
      // and the broadcast stream is per session, so the abandoned run cannot
      // reach it.
      _retire(band, 'inference exceeded ${_kRunTimeout.inSeconds}s');
      return null;
    }
    // Same reasoning for a run that FAILED rather than stalled — and in
    // practice the isolate is spawned with errorsAreFatal, so a throw inside
    // it kills the isolate and the run future never completes at all. Either
    // way the session keeps pointing at a dead port and every later run on it
    // would hang, so either way it is retired.
    if (outputs == null) {
      _retire(band, 'inference failed');
      return null;
    }

    final policy = <double>[];
    _flatten(outputs.isEmpty ? null : outputs.first?.value, policy);
    for (final o in outputs) {
      o?.release();
    }
    if (policy.isEmpty) return null;

    // The JS runtime can have been released while ORT was working — dispose()
    // frees the JavaScriptCore context, and evaluating in a freed context is a
    // crash rather than an error.
    if (_disposed || gen != _gen) return null;
    final picked = _call(js, 'maiaPick', args: [policy, fen, temperature]);
    return picked is String ? picked : null;
  }

  /// Drop a session that can no longer be trusted, without releasing it.
  ///
  /// The leak is deliberate: a run may still be inside it, and `release()`
  /// tears the native session down without waiting for its isolate to stop. A
  /// stranded session is a far better trade than a use-after-free.
  ///
  /// The band stays PLAYABLE. Rebuilding reads the cached file — no download,
  /// tens of milliseconds — so a phone that throttled through one inference
  /// gets its Maia back on the next move. Only a band that keeps doing it is
  /// given up on, because by then each retirement is stranding a session and
  /// the evidence is no longer of a hiccup.
  void _retire(int band, String why) {
    final count = (_retirements[band] ?? 0) + 1;
    _retirements[band] = count;
    _nets.remove(band);
    if (count >= _kMaxRetirements) {
      _deadBands.add(band);
      debugPrint('[maia] maia-$band retired $count times, giving up: $why');
    } else {
      debugPrint('[maia] retiring maia-$band ($count/$_kMaxRetirements): $why');
    }
  }

  /// The policy head arrives as a nested list shaped like the output tensor
  /// ([1, 1858]); the decoder wants it flat.
  static void _flatten(Object? value, List<double> out) {
    if (value is num) {
      out.add(value.toDouble());
    } else if (value is List) {
      for (final v in value) {
        _flatten(v, out);
      }
    }
  }

  // ---- the JS half ---------------------------------------------------------

  Future<JavascriptRuntime> _runtime() async {
    final existing = _js;
    if (existing != null) return existing;
    final js = getJavascriptRuntime();
    // Every throw below is reachable on EVERY move — a version mismatch is
    // permanent — so leaving the half-built context behind would leak a whole
    // JavaScriptCore context per move for the life of the session.
    try {
      final src = await rootBundle.loadString(_asset);
      final result = js.evaluate(src);
      if (result.isError) {
        throw StateError('$_asset failed to evaluate: ${result.stringResult}');
      }
      final version =
          _call(js, 'MAIA_BRAIN_VERSION', isProperty: true, global: 'maiaBrain');
      if (version != _kExpectedMaiaBrainVersion) {
        throw StateError(
            '$_asset version $version, app expects $_kExpectedMaiaBrainVersion — '
            'run `npm run build:maia-brain` and rebuild');
      }
    } catch (_) {
      js.dispose();
      rethrow;
    }
    _js = js;
    return js;
  }

  dynamic _call(
    JavascriptRuntime js,
    String fn, {
    List<Object?> args = const [],
    bool isProperty = false,
    String global = 'maiaBrain',
  }) {
    final r = js.evaluate(buildBrainExpr(fn, args, isProperty, global: global));
    if (r.isError) {
      throw StateError('$global.$fn failed: ${r.stringResult}');
    }
    return decodeBrainResult(r.stringResult);
  }

  // ---- weights and sessions ------------------------------------------------

  Future<_Net> _net(int band) {
    final existing = _nets[band];
    if (existing != null) return existing;
    // checked only on a miss, so a band already loaded keeps working whatever
    // happened to any other
    if (_deadBands.contains(band)) {
      return Future.error(StateError('maia-$band gave up earlier this session'));
    }
    final loading = _load(band);
    _nets[band] = loading;
    // consume the failure on this branch only; the caller still awaits
    // `loading` itself and sees the error there
    loading.then((_) {}, onError: (Object e) {
      _nets.remove(band);
      // A network that accepts and never answers costs a full 30s on every
      // move; nothing about that improves by trying again.
      // NOT a JoinedDownloadFailure: that timeout belonged to a download this
      // move merely joined — usually the boot prefetch — so it says nothing
      // about how long THIS request waited. Latching it meant a background
      // download nobody asked for could retire a persona for the session, and
      // never retry even once the network recovered.
      if (e is TimeoutException) _deadBands.add(band);
      // A model ORT will not open has already been deleted, so the retry is a
      // fresh 3.5MB download. Worth exactly one — the file really can be
      // corrupt — and no more, because unbounded means once per move forever.
      // Counted rather than latched at the first failure so that a throw from
      // something transient (memory pressure while ORT builds the graph) does
      // not cost the persona for the rest of the run.
      if (e is _ModelUnreadable) {
        final n = (_unreadable[band] ?? 0) + 1;
        _unreadable[band] = n;
        if (n >= 2) _deadBands.add(band);
      }
      // A 404 stays retryable: that is one cheap request.
    });
    return loading;
  }

  Future<_Net> _load(int band) async {
    // Cached file or fresh download, and the same single downloader either
    // way — so a move that arrives while the prefetch is on this band joins
    // that download (and its progress bar) rather than starting a second one
    // onto the same `.part`.
    final bytes =
        await MaiaWeights.load(band, onProgress: (p) => _report(band, p));

    // ORT builds and optimises the graph here. It reports nothing and there is
    // no total to divide by, so this phase gets a name rather than a bar.
    _report(band, const MaiaProgress('starting'));
    // and a frame to draw it in: _session below is synchronous FFI that holds
    // this isolate for the whole graph build, so without a yield the phase the
    // report announces is never actually painted.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    try {
      return _session(bytes);
    } catch (e) {
      // A cached model that will not open would fail identically forever, so
      // it goes — but only one re-download is granted (see _net), because
      // otherwise "delete and retry" is once per move, forever.
      await MaiaWeights.discard(band);
      throw _ModelUnreadable('maia-$band: $e');
    }
  }

  static _Net _session(Uint8List bytes) {
    if (!_envReady) {
      OrtEnv.instance.init();
      _envReady = true;
    }
    // One policy evaluation on a small net: extra threads cost more in
    // scheduling than they save, and this shares a phone with the UI.
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(1)
      ..setInterOpNumThreads(1);
    try {
      final session = OrtSession.fromBuffer(bytes, options);
      final outputs = session.outputNames;
      final policyName = outputs.firstWhere(
        (n) => n.toLowerCase().contains('policy'),
        orElse: () => outputs.first,
      );
      return _Net(session, session.inputNames.first, policyName);
    } finally {
      // ORT copies what it needs at create time; the options are ours to free
      // either way, and one leak per band adds up over a roster of six.
      options.release();
    }
  }

  void _report(int band, MaiaProgress progress) {
    // Only while somebody is actually waiting on THIS band. A cancelled
    // request leaves its download running — the weights are cached per band,
    // so finishing is the right thing — but without this it would narrate
    // itself over a game that is not downloading anything, or worse, over one
    // waiting on a different band, where the line names the wrong persona.
    if (_disposed || !_waiting.containsKey(band)) return;
    onProgress?.call(progress);
  }

  /// Pre-download and build this band's session off the move path, so the
  /// first move does not pay the 3.5MB download and the graph build. Called
  /// when a Maia opponent is CHOSEN rather than on its first move. Idempotent:
  /// [_net] caches per band, so a move that arrives first simply awaits the
  /// same future. Fire-and-forget — a warm-up failure is swallowed here (the
  /// move path keeps its own handling), and a band this session already gave up
  /// on is left alone.
  void warmUp(int band) {
    if (_disposed || _deadBands.contains(band)) return;
    unawaited(_net(band).then((_) {}, onError: (_) {}));
  }

  /// Abandon every outstanding request without tearing the sessions down.
  /// Called when the game they belonged to is gone.
  void cancelPending() => _gen++;

  void dispose() {
    _disposed = true;
    _gen++;
    // Not while a run is out. `OrtSession.release` kills the native session
    // without waiting for the isolate that is inside `OrtRun` on it, so
    // releasing here would be a use-after-free in native code. Stranding the
    // session at teardown costs nothing anyone will notice; crashing on the
    // way out costs a crash report.
    if (_running == 0) {
      for (final net in _nets.values) {
        net.then((n) => n.session.release(), onError: (_) {});
      }
    }
    _nets.clear();
    _js?.dispose();
    _js = null;
  }
}

/// A model file ORT would not open. Its own type because it is the one load
/// failure that must latch the band — retrying it means downloading 3.5MB
/// again, and again, once per move.
class _ModelUnreadable implements Exception {
  const _ModelUnreadable(this.message);
  final String message;
  @override
  String toString() => 'maia model unreadable: $message';
}
