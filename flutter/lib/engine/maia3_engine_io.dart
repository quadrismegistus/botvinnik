// Maia-3 on macOS/iOS: the web worker's three pieces replaced one for one,
// exactly as maia_engine_io.dart did for Maia-1 —
//
//   ort-web + Worker    -> package:onnxruntime (ORT's C API over dart:ffi)
//   fetch + IndexedDB   -> HttpClient + a file under Application Support
//   the worker's encode -> brain.js's encodeBoard, via the app's ONE JsBridge
//
// That last line is the divergence from Maia-1, and it is a simplification:
// Maia-3's encode/decode live in the MAIN brain bundle (BRAIN_VERSION 2),
// so this engine borrows the JsBridge the app already booted instead of
// owning a second JavaScriptCore context and a second versioned bundle.
//
// The failure handling is maia_engine_io's, shrunk to one model instead of
// three bands: a `.part` rename so a half-arrived download never reads as a
// cache hit, and repeated failures latch after three strikes.
//
// One hard-won difference from Maia-1: sessions here are SINGLE-USE. The
// second run on a reused native session returns all-NaN logits for this
// model (byte-identical inputs; wasm unaffected; Maia-1's convnet
// unaffected) — see maia3_nan_probe_test.dart, which keeps a canary on the
// bug. Each analyze builds a fresh session and releases it when the run
// really finishes.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import '../brain/js_bridge.dart';
import '../brain/maia3_api.dart';
import 'maia_progress.dart';

/// CSSLab's "simplified" Maia-3 export — the same URL the web worker fetches,
/// and for the same licensing reason (AGPL weights, fetched not shipped).
const String kMaia3ModelUrl =
    'https://raw.githubusercontent.com/CSSLab/maia-platform-frontend/main/public/maia3/maia3_simplified.onnx';

const int _kPolicyVocabSize = 4352;
const int _kWdlSize = 3;
const int _kTokensPerBoard = 64 * 12;

const Duration _kFetchTimeout = Duration(seconds: 30);
const Duration _kRunTimeout = Duration(seconds: 15);

class _Net {
  const _Net(this.session, this.tokensName, this.eloSelfName, this.eloOppoName,
      this.moveName, this.valueName);
  final OrtSession session;
  final String tokensName;
  final String eloSelfName;
  final String eloOppoName;
  final String moveName;
  final String valueName;
}

class Maia3Engine {
  /// macOS and iOS, like Maia-1 and for Maia-1's reason: Android's JS half
  /// is unverified (#46), and here the encode runs through the same bridge.
  static bool get supported => Platform.isMacOS || Platform.isIOS;

  /// Model download / graph build, for the panel to narrate the first-use
  /// pause. Null once inference is what's left.
  final void Function(MaiaProgress?)? onProgress;

  final JsBridge _bridge;

  Maia3Engine(JsBridge bridge, {this.onProgress}) : _bridge = bridge;

  static bool _envReady = false;

  Future<_Net>? _net;
  Future<void> _chain = Future.value();
  int _gen = 0;
  int _retirements = 0;
  static const int _kMaxRetirements = 3;
  bool _dead = false;
  bool _disposed = false;

  /// One in-flight download, whoever asked.
  Future<Uint8List>? _downloading;
  bool _builtOnce = false;

  void warmUp() {
    if (_disposed || _dead) return;
    unawaited(_session().then((_) {}, onError: (_) {}));
  }

  /// One batched inference: raw policy + WDL logits at every rung of
  /// [eloInputs] for [fen], or null on any failure. Requests run one at a
  /// time and a new call supersedes whatever was queued — the chart only
  /// wants the latest position.
  Future<Maia3Raw?> analyze(String fen, List<int> eloInputs) {
    if (_disposed || _dead || eloInputs.isEmpty) return Future.value(null);
    final gen = ++_gen;
    final done = Completer<Maia3Raw?>();
    _chain = _chain.then((_) async {
      if (_disposed || gen != _gen) {
        if (!done.isCompleted) done.complete(null);
        return;
      }
      try {
        final raw = await _analyze(fen, eloInputs, gen);
        if (!done.isCompleted) done.complete(gen == _gen ? raw : null);
      } catch (e) {
        debugPrint('[maia3] $e');
        if (!done.isCompleted) done.complete(null);
      }
    });
    return done.future.timeout(
      // generous: the first call is a ~6MB download plus the graph build.
      const Duration(seconds: 90),
      onTimeout: () => null,
    ).whenComplete(() {
      if (_gen == gen) onProgress?.call(null);
    });
  }

  Future<Maia3Raw?> _analyze(String fen, List<int> eloInputs, int gen) async {
    // Encode before the download, like Maia-1: this is also the "FEN the
    // brain cannot read" check, and it should fail without pulling 6MB.
    final encoded = _bridge.call('encodeBoardArray', args: [fen]);
    if (encoded is! List) return null;
    final board = Float32List(encoded.length);
    for (var i = 0; i < encoded.length; i++) {
      board[i] = (encoded[i] as num).toDouble();
    }
    if (board.length != _kTokensPerBoard) {
      throw StateError('encodeBoard returned ${board.length} floats, '
          'expected $_kTokensPerBoard');
    }

    final net = await _session();
    // Claim the session: Maia-3 sessions are SINGLE-USE on this native ORT.
    // The second run on a reused session returns all-NaN logits — proven with
    // byte-identical inputs by maia3_nan_probe_test (sync and isolate paths
    // alike; wasm is fine, Maia-1's convnet is fine). Arena flags and graph-
    // optimization levels don't change it, and the dart API exposes no
    // DisableMemPattern. So: one session, one run, release when the run
    // really finishes. Build cost is ~330ms against a ~520ms inference —
    // acceptable at debounced chart cadence.
    _net = null;
    if (_disposed || gen != _gen) {
      net.session.release();
      return null;
    }

    final batch = eloInputs.length;
    final tokens = Float32List(batch * _kTokensPerBoard);
    for (var b = 0; b < batch; b++) {
      tokens.setAll(b * _kTokensPerBoard, board);
    }
    final elos =
        Float32List.fromList(eloInputs.map((e) => e.toDouble()).toList());

    final tokensT =
        OrtValueTensor.createTensorWithDataList(tokens, [batch, 64, 12]);
    final eloSelfT = OrtValueTensor.createTensorWithDataList(elos, [batch]);
    final eloOppoT = OrtValueTensor.createTensorWithDataList(
        Float32List.fromList(elos), [batch]);
    final runOptions = OrtRunOptions();
    final run = net.session.runAsync(
      runOptions,
      {
        net.tokensName: tokensT,
        net.eloSelfName: eloSelfT,
        net.eloOppoName: eloOppoT,
      },
      [net.moveName, net.valueName],
    );
    void releaseInputs() {
      tokensT.release();
      eloSelfT.release();
      eloOppoT.release();
      runOptions.release();
    }

    if (run == null) {
      releaseInputs();
      net.session.release();
      return null;
    }
    // Inputs — and the single-use session — are freed when the run REALLY
    // finishes, not when we stop waiting: ORT reads them from its own isolate
    // (see maia_engine_io), and release mid-run is a use-after-free. On a
    // timeout this still runs whenever ORT eventually returns, so nothing
    // leaks even on the retire path.
    final finished = run.then<List<OrtValue?>?>((o) => o, onError: (Object e) {
      debugPrint('[maia3] inference failed: $e');
      return null;
    }).whenComplete(() {
      releaseInputs();
      net.session.release();
    });

    List<OrtValue?>? outputs;
    try {
      outputs = await finished.timeout(_kRunTimeout);
    } on TimeoutException {
      _retire('inference exceeded ${_kRunTimeout.inSeconds}s');
      return null;
    }
    if (outputs == null || outputs.length < 2) {
      _retire('inference failed');
      return null;
    }

    final policyFlat = <double>[];
    final wdlFlat = <double>[];
    _flatten(outputs[0]?.value, policyFlat);
    _flatten(outputs[1]?.value, wdlFlat);
    for (final o in outputs) {
      o?.release();
    }
    if (policyFlat.length != batch * _kPolicyVocabSize ||
        wdlFlat.length != batch * _kWdlSize) {
      _retire('unexpected output shape: ${policyFlat.length}/${wdlFlat.length} '
          'for batch $batch');
      return null;
    }

    return Maia3Raw(
      elos: List.of(eloInputs),
      policyByElo: [
        for (var b = 0; b < batch; b++)
          policyFlat.sublist(b * _kPolicyVocabSize, (b + 1) * _kPolicyVocabSize),
      ],
      wdlByElo: [
        for (var b = 0; b < batch; b++)
          wdlFlat.sublist(b * _kWdlSize, (b + 1) * _kWdlSize),
      ],
    );
  }

  static void _flatten(Object? value, List<double> out) {
    if (value is num) {
      out.add(value.toDouble());
    } else if (value is List) {
      for (final v in value) {
        _flatten(v, out);
      }
    }
  }

  /// Count a run that failed or stalled. Sessions are single-use (claimed
  /// and released by the run itself), so there is nothing to tear down here —
  /// this only keeps the give-up latch: a model that keeps failing should
  /// stop being asked.
  void _retire(String why) {
    _retirements++;
    if (_retirements >= _kMaxRetirements) {
      _dead = true;
      debugPrint('[maia3] retired $_retirements times, giving up: $why');
    } else {
      debugPrint('[maia3] retiring session ($_retirements/$_kMaxRetirements): $why');
    }
  }

  // ---- weights and session ---------------------------------------------

  Future<_Net> _session() {
    final existing = _net;
    if (existing != null) return existing;
    final loading = _load();
    _net = loading;
    loading.then((_) {}, onError: (Object e) {
      _net = null;
      // A model ORT would not open has been deleted; the next request
      // re-downloads once. Unlike Maia-1 there is no per-move fallback to
      // protect, so nothing latches on load failures — only on retirements.
      debugPrint('[maia3] load failed: $e');
    });
    return loading;
  }

  Future<_Net> _load() async {
    final file = await _fileFor();
    Uint8List bytes;
    if (await file.exists()) {
      bytes = await file.readAsBytes();
    } else {
      bytes = await (_downloading ??= _download(file).whenComplete(() {
        _downloading = null;
      }));
    }
    // Sessions are single-use (see _analyze), so _load runs per inference —
    // only the FIRST build gets narrated, or every position would flash a
    // "starting" note over a ~330ms rebuild that is just how inference works.
    if (!_builtOnce) {
      onProgress?.call(const MaiaProgress('starting'));
      // a frame to draw that in: building the graph is synchronous FFI
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    try {
      final net = _buildSession(bytes);
      _builtOnce = true;
      return net;
    } catch (e) {
      // A cached model that will not open would fail identically forever.
      try {
        await file.delete();
      } catch (_) {
        // never fatal; the point is the next load re-downloads
      }
      rethrow;
    }
  }

  Future<File> _fileFor() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/maia3/maia3.onnx');
  }

  Future<Uint8List> _download(File file) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request =
          await client.getUrl(Uri.parse(kMaia3ModelUrl)).timeout(_kFetchTimeout);
      final response = await request.close().timeout(_kFetchTimeout);
      if (response.statusCode != 200) {
        throw StateError('$kMaia3ModelUrl fetch failed: ${response.statusCode}');
      }
      final total = math.max(response.contentLength, 0);
      final step = total > 0 ? math.max(total ~/ 25, 65536) : 262144;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      var reported = 0;
      onProgress?.call(MaiaProgress('fetching', received: 0, total: total));
      await for (final chunk in response.timeout(_kFetchTimeout)) {
        builder.add(chunk);
        received += chunk.length;
        if (received - reported >= step) {
          reported = received;
          onProgress?.call(
              MaiaProgress('fetching', received: received, total: total));
        }
      }
      final bytes = builder.takeBytes();

      // Land it through a rename: a partial write must never be readable as
      // a cache hit.
      final part = File('${file.path}.part');
      await part.parent.create(recursive: true);
      try {
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(file.path);
      } catch (_) {
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

  static _Net _buildSession(Uint8List bytes) {
    if (!_envReady) {
      OrtEnv.instance.init();
      _envReady = true;
    }
    // A batch of 21 on a small net still shares a phone with the UI; single
    // threads keep it off the scheduler's back, same call as Maia-1.
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(1)
      ..setInterOpNumThreads(1);
    try {
      final session = OrtSession.fromBuffer(bytes, options);
      final inputs = session.inputNames;
      final outputs = session.outputNames;
      String pick(List<String> names, String needle, String what) =>
          names.firstWhere((n) => n.toLowerCase().contains(needle),
              orElse: () => throw StateError(
                  'maia3 model has no $what input/output among $names'));
      return _Net(
        session,
        pick(inputs, 'token', 'tokens'),
        pick(inputs, 'self', 'elo_self'),
        pick(inputs, 'oppo', 'elo_oppo'),
        pick(outputs, 'move', 'logits_move'),
        pick(outputs, 'value', 'logits_value'),
      );
    } finally {
      options.release();
    }
  }

  /// Abandon every outstanding request without tearing the session down.
  void cancelPending() => _gen++;

  void dispose() {
    _disposed = true;
    _gen++;
    // Only an UNCLAIMED warm-up session can be sitting in _net — a running
    // one was claimed (nulled) by its run and releases itself when the run
    // really finishes. So releasing here is always safe.
    _net?.then((n) => n.session.release(), onError: (_) {});
    _net = null;
  }
}
