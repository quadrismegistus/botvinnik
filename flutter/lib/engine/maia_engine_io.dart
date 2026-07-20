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
// comments in web_src/maia-worker.ts. Kept here: one request at a time, a
// per-band load cache, and latching only on TIMEOUTS so a fast failure stays
// retryable. Added here, because a file cache can be corrupt in a way
// IndexedDB's cannot: a model that fails to open is deleted, and a download
// lands through a `.part` rename so a truncated file is never a cache hit.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import '../brain/js_bridge_shared.dart';
import 'maia_progress.dart';

/// Bump in lockstep with MAIA_BRAIN_VERSION in native_src/maia-brain.ts.
const int _kExpectedMaiaBrainVersion = 1;

/// Community pre-conversions of the CSSLab lc0 weights, one repo per band —
/// the same URLs the web worker uses. GPL-3.0, which is why they are fetched
/// rather than redistributed with the app (see ARCHITECTURE.md), and why this
/// is the app's only third-party request on native as well.
///
/// The two platforms run ORT versions two years apart (1.15.1 through the pod
/// here, 1.27 through onnxruntime-web there). That is fine for a net this
/// simple and is checked rather than assumed — the parity fixtures in
/// integration_test/maia_native_test.dart are the thing that would notice, and
/// they are the first place to look if a band ever starts disagreeing.
String _modelUrl(int band) =>
    'https://huggingface.co/shermansiu/maia-$band/resolve/main/model.onnx';

/// 30s matches the web worker: a 3.5MB body that has not landed in thirty
/// seconds is not about to. Applied per chunk, so a stalled connection is
/// caught rather than only a slow one.
const Duration _kLoadTimeout = Duration(seconds: 30);
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
  /// and never answers, or a session that cannot be trusted, would otherwise
  /// cost its full failure on every move, forever.
  ///
  /// The web worker latches only on TIMEOUTS, on the grounds that a fast
  /// failure is cheap to retry. Native latches wider, because here a retry is
  /// not cheap: the cache is a FILE, a model ORT cannot open is deleted, and
  /// the retry is therefore another 3.5MB download — every move, unbounded.
  /// A 404 is still not latched, since that is one cheap request.
  final Set<int> _deadBands = {};

  /// Requests are handled one at a time. ORT's isolate session takes the first
  /// result off a broadcast stream, so two overlapping runs can be handed each
  /// other's output — the native shape of the same hazard the web worker
  /// serialises against.
  Future<void> _chain = Future.value();

  /// Bumped by every request and by [cancelPending]. A reply belongs to the
  /// current generation or to nobody.
  int _gen = 0;

  /// Requests that have asked and not yet been answered.
  ///
  /// Progress gates on this rather than on a generation, because a download is
  /// cached per BAND and outlives the request that started it: the generation
  /// it was born under is stale by the time the move that is actually waiting
  /// for it arrives, and gating on that generation blanked the bar for the
  /// whole rest of the download.
  int _waiting = 0;

  /// True while an ORT run is dispatched and has not come back. `dispose` must
  /// not release a session out from under one — `OrtSession.release` tears the
  /// native session down without waiting for its isolate to stop.
  bool _running = false;

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
    _waiting++;
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
    ).whenComplete(() => _waiting--);
  }

  Future<String?> _move(
    List<String> fenHistory,
    int band,
    double temperature,
    int gen,
  ) async {
    final js = await _runtime();
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
    _running = true;
    final finished = run.then<List<OrtValue?>?>((o) => o, onError: (Object e) {
      debugPrint('[maia] inference failed: $e');
      return null;
    }).whenComplete(() {
      _running = false;
      input.release();
      runOptions.release();
    });

    List<OrtValue?>? outputs;
    try {
      outputs = await finished.timeout(_kRunTimeout);
    } on TimeoutException {
      // The run is still out there. Abandoning the WAIT is not abandoning the
      // run, and ORT's isolate session hands results out on a BROADCAST
      // stream that this call is still subscribed to — so the next run on this
      // session would be handed whichever result arrived first, and could
      // answer a new position with the old one's policy. A wrong move is worse
      // than no move, so the session is retired instead: the next request
      // builds a fresh one, whose stream the abandoned run cannot reach.
      _retire(band, 'inference exceeded ${_kRunTimeout.inSeconds}s');
      return null;
    }
    // Same reasoning for a run that FAILED rather than stalled: the isolate is
    // spawned with errorsAreFatal, so a throw inside it kills the isolate while
    // the session keeps pointing at its dead port, and every later run on this
    // session would hang forever.
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
  /// Deliberately a leak: a run may still be inside it, and `release()` tears
  /// the native session down without waiting for its isolate to stop. One
  /// stranded session per pathological inference is a far better trade than a
  /// use-after-free, and the band is latched so it cannot happen repeatedly.
  void _retire(int band, String why) {
    debugPrint('[maia] retiring maia-$band: $why');
    _nets.remove(band);
    _deadBands.add(band);
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
      // A stalled network and a model that will not open both cost 3.5MB to
      // retry. A 404 costs one request, so it stays retryable.
      if (e is TimeoutException || e is _ModelUnreadable) _deadBands.add(band);
    });
    return loading;
  }

  Future<_Net> _load(int band) async {
    final file = await _modelFile(band);
    final bytes = await file.exists()
        ? await file.readAsBytes()
        : await _download(band, file);

    // ORT builds and optimises the graph here. It reports nothing and there is
    // no total to divide by, so this phase gets a name rather than a bar.
    _report(const MaiaProgress('starting'));
    // and a frame to draw it in: _session below is synchronous FFI that holds
    // this isolate for the whole graph build, so without a yield the phase the
    // report announces is never actually painted.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    try {
      return _session(bytes);
    } catch (e) {
      // A cached model that will not open would fail identically forever, so
      // it goes — but the band is latched too (see _net), because otherwise
      // "delete and retry" is an unbounded re-download, once per move.
      try {
        await file.delete();
      } catch (_) {
        // never fatal
      }
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

  static Future<File> _modelFile(int band) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/maia/maia-$band.onnx');
  }

  Future<Uint8List> _download(int band, File file) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request =
          await client.getUrl(Uri.parse(_modelUrl(band))).timeout(_kLoadTimeout);
      final response = await request.close().timeout(_kLoadTimeout);
      if (response.statusCode != 200) {
        throw StateError('maia-$band fetch failed: ${response.statusCode}');
      }
      final total = math.max(response.contentLength, 0);
      // Report every ~4% rather than every chunk: each report crosses into the
      // controller and rebuilds a widget. The last chunk always reports, so
      // the line always finishes.
      final step = total > 0 ? math.max(total ~/ 25, 65536) : 262144;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      var reported = 0;
      _report(MaiaProgress('fetching', received: 0, total: total));
      await for (final chunk in response.timeout(_kLoadTimeout)) {
        builder.add(chunk);
        received += chunk.length;
        if (received - reported >= step) {
          reported = received;
          _report(MaiaProgress('fetching', received: received, total: total));
        }
      }
      _report(MaiaProgress('fetching',
          received: received, total: total > 0 ? total : received));
      final bytes = builder.takeBytes();

      // Land it through a rename: a partial write must never be readable as a
      // cache hit, and an interrupted download is the ordinary case here.
      final part = File('${file.path}.part');
      await part.parent.create(recursive: true);
      try {
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(file.path);
      } catch (_) {
        // do not leave 3.5MB of orphan behind on a full or read-only disk
        try {
          await part.delete();
        } catch (_) {
          // never fatal
        }
        rethrow;
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  void _report(MaiaProgress progress) {
    // Only while somebody is actually waiting. A cancelled request leaves its
    // download running — the weights are cached per band, so finishing is the
    // right thing — but without this it would re-raise the progress line on a
    // game that is not downloading anything.
    if (_disposed || _waiting == 0) return;
    onProgress?.call(progress);
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
    if (!_running) {
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
