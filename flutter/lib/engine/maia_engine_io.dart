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

  /// Bands whose weights TIMED OUT. Not retried this session — a network that
  /// accepts and never answers would otherwise cost a full timeout on every
  /// move, forever. Only timeouts latch: a 404 or a corrupt model is cheap to
  /// retry, and latching on those silently substitutes Stockfish for the rest
  /// of the session.
  final Set<int> _timedOutBands = {};

  /// Requests are handled one at a time. ORT's isolate session takes the first
  /// result off a broadcast stream, so two overlapping runs can be handed each
  /// other's output — the native shape of the same hazard the web worker
  /// serialises against.
  Future<void> _chain = Future.value();

  /// Bumped by every request and by [cancelPending]. A reply, and a progress
  /// report, belong to the current generation or to nobody.
  int _gen = 0;
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
    );
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

    final net = await _net(band, gen);
    if (gen != _gen) return null;

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
    final finished = run.then<List<OrtValue?>?>((o) => o, onError: (Object e) {
      debugPrint('[maia] inference failed: $e');
      return null;
    }).whenComplete(() {
      input.release();
      runOptions.release();
    });
    final outputs = await finished.timeout(_kRunTimeout);
    if (outputs == null) return null;

    final policy = <double>[];
    _flatten(outputs.isEmpty ? null : outputs.first?.value, policy);
    for (final o in outputs) {
      o?.release();
    }
    if (policy.isEmpty) return null;

    final picked = _call(js, 'maiaPick', args: [policy, fen, temperature]);
    return picked is String ? picked : null;
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

  Future<_Net> _net(int band, int gen) {
    final existing = _nets[band];
    if (existing != null) return existing;
    // checked only on a miss, so a band already loaded keeps working whatever
    // happened to any other
    if (_timedOutBands.contains(band)) {
      return Future.error(
          StateError('maia-$band timed out earlier this session'));
    }
    final loading = _load(band, gen);
    _nets[band] = loading;
    // consume the failure on this branch only; the caller still awaits
    // `loading` itself and sees the error there
    loading.then((_) {}, onError: (Object e) {
      _nets.remove(band);
      if (e is TimeoutException) _timedOutBands.add(band);
    });
    return loading;
  }

  Future<_Net> _load(int band, int gen) async {
    final file = await _modelFile(band);
    final bytes = await file.exists()
        ? await file.readAsBytes()
        : await _download(band, file, gen);

    // ORT builds and optimises the graph here. It reports nothing and there is
    // no total to divide by, so this phase gets a name rather than a bar.
    _report(gen, const MaiaProgress('starting'));
    try {
      return _session(bytes);
    } catch (_) {
      // A cached model that will not open would fail identically forever.
      // Deleting it costs one re-download and is the only way out.
      try {
        await file.delete();
      } catch (_) {
        // never fatal
      }
      rethrow;
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
    final session = OrtSession.fromBuffer(bytes, options);
    final outputs = session.outputNames;
    final policyName = outputs.firstWhere(
      (n) => n.toLowerCase().contains('policy'),
      orElse: () => outputs.first,
    );
    return _Net(session, session.inputNames.first, policyName);
  }

  static Future<File> _modelFile(int band) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/maia/maia-$band.onnx');
  }

  Future<Uint8List> _download(int band, File file, int gen) async {
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
      _report(gen, MaiaProgress('fetching', received: 0, total: total));
      await for (final chunk in response.timeout(_kLoadTimeout)) {
        builder.add(chunk);
        received += chunk.length;
        if (received - reported >= step) {
          reported = received;
          _report(gen,
              MaiaProgress('fetching', received: received, total: total));
        }
      }
      _report(
        gen,
        MaiaProgress('fetching',
            received: received, total: total > 0 ? total : received),
      );
      final bytes = builder.takeBytes();

      // Land it through a rename: a partial write must never be readable as a
      // cache hit, and an interrupted download is the ordinary case here.
      final part = File('${file.path}.part');
      await part.parent.create(recursive: true);
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  void _report(int gen, MaiaProgress progress) {
    // Only for the request still wanted: an abandoned download keeps running,
    // and without this it could re-raise the progress line on a new game that
    // is not downloading anything.
    if (_disposed || gen != _gen) return;
    onProgress?.call(progress);
  }

  /// Abandon every outstanding request without tearing the sessions down.
  /// Called when the game they belonged to is gone.
  void cancelPending() => _gen++;

  void dispose() {
    _disposed = true;
    _gen++;
    for (final net in _nets.values) {
      net.then((n) => n.session.release(), onError: (_) {});
    }
    _nets.clear();
    _js?.dispose();
    _js = null;
  }
}
