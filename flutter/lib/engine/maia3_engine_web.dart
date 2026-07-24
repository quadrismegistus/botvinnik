// Maia-3 on the web: the Dart end of web/maia3/maia3-worker.js's protocol
// (see web_src/maia3-worker.ts for the other half and the reasons).
//
// Unlike the Maia-1 engine this is an ANALYSIS transport, not an opponent:
// one request per shown position, answered with raw per-rung logits that the
// caller hands to Maia3Api.computeMoveCurves. A new position supersedes the
// old request — the chart only ever wants the latest — so requests are
// correlated by id and stale replies are dropped.

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import '../brain/js_bridge.dart';
import '../brain/maia3_api.dart';
import 'js_worker.dart';
import 'maia_progress.dart';

class Maia3Engine {
  static const _scriptUrl = 'maia3/maia3-worker.js';

  /// Same wall as Maia-1: ort-web cannot instantiate alongside Flutter under
  /// iPhone Safari's per-tab memory ceiling (and a PWA is the same WebKit).
  /// iPadOS reports as macOS and has the headroom, so it is not excluded.
  static bool get supported => defaultTargetPlatform != TargetPlatform.iOS;

  /// Model download / wasm compile, for the panel to narrate the first-use
  /// pause. Null once inference is what's left.
  final void Function(MaiaProgress?)? onProgress;

  // The bridge is what the io twin needs (encodeBoard runs in its JS
  // runtime); here the worker encodes for itself. Accepted so the two
  // constructors match and the store compiles on either platform.
  // ignore: avoid_unused_constructor_parameters
  Maia3Engine(JsBridge bridge, {this.onProgress}) {
    _spawn();
  }

  JsWorker? _worker;
  bool _disposed = false;
  int _nextId = 1;
  final Map<int, Completer<Maia3Raw?>> _pending = {};

  void _spawn() {
    if (_disposed) return;
    final worker = JsWorker(_scriptUrl);
    _worker = worker;
    worker.onmessage = ((WorkerMessage e) {
      final data = e.data?.dartify();
      if (data is! Map) return;
      final type = data['type'];
      if (type == 'fetching' || type == 'starting') {
        if (_pending.isNotEmpty) {
          onProgress?.call(MaiaProgress(
            type as String,
            received: (data['received'] as num?)?.toInt() ?? 0,
            total: (data['total'] as num?)?.toInt() ?? 0,
          ));
        }
        return;
      }
      if (type == 'ready' || type == 'error') {
        // init's own replies; analyze answers carry an id instead. An init
        // error is not fatal to later analyzes — they carry their own errors.
        if (type == 'error') debugPrint('[maia3] ${data['message']}');
        return;
      }
      final id = (data['id'] as num?)?.toInt();
      if (id == null) return;
      final error = data['error'];
      if (error != null) {
        debugPrint('[maia3] $error');
        _resolve(id, null);
        return;
      }
      _resolve(id, _decodeRaw(data));
    }).toJS;
    worker.onerror = ((JSAny? event) {
      final detail = (event as WorkerError?)?.message ?? 'unknown error';
      debugPrint('[maia3] worker failed ($_scriptUrl): $detail');
      _worker = null;
      try {
        worker.terminate();
      } catch (_) {
        // already gone
      }
      _failAll();
    }).toJS;
  }

  static Maia3Raw? _decodeRaw(Map<dynamic, dynamic> data) {
    final policyEntries = data['rawPolicyByElo'];
    final wdlEntries = data['rawWdlByElo'];
    if (policyEntries is! List || wdlEntries is! List) return null;
    final elos = <int>[];
    final policies = <List<double>>[];
    for (final entry in policyEntries) {
      final m = entry as Map;
      elos.add((m['elo'] as num).toInt());
      policies.add((m['policy'] as List).cast<num>().map((n) => n.toDouble()).toList());
    }
    final wdls = <List<double>>[
      for (final entry in wdlEntries)
        ((entry as Map)['wdl'] as List).cast<num>().map((n) => n.toDouble()).toList(),
    ];
    return Maia3Raw(elos: elos, policyByElo: policies, wdlByElo: wdls);
  }

  void _resolve(int id, Maia3Raw? raw) {
    final pending = _pending.remove(id);
    if (pending != null && !pending.isCompleted) pending.complete(raw);
    if (_pending.isEmpty) onProgress?.call(null);
  }

  void _failAll() {
    final waiting = _pending.values.toList();
    _pending.clear();
    for (final c in waiting) {
      if (!c.isCompleted) c.complete(null);
    }
    onProgress?.call(null);
  }

  /// Start the model download and wasm compile off any request's clock.
  /// Fire-and-forget; a failure just means the first analyze pays it.
  void warmUp() {
    if (_disposed) return;
    if (_worker == null) _spawn();
    _worker?.postMessage({'type': 'init'}.jsify());
  }

  /// One batched inference: raw policy + WDL logits at every rung of
  /// [eloInputs] for [fen], or null on any failure. A new call supersedes
  /// whatever was pending — the chart only wants the latest position.
  Future<Maia3Raw?> analyze(String fen, List<int> eloInputs) {
    if (_disposed) return Future.value(null);
    if (_worker == null) _spawn();
    final worker = _worker;
    if (worker == null) return Future.value(null);

    _failAll();
    final id = _nextId++;
    final pending = Completer<Maia3Raw?>();
    _pending[id] = pending;
    worker.postMessage({
      'type': 'analyze',
      'id': id,
      'fen': fen,
      'eloInputs': eloInputs,
    }.jsify());
    return pending.future.timeout(
      // generous: the first call can be a ~6MB download plus ~13MB of
      // WebAssembly to compile. Later calls answer in tens of ms.
      const Duration(seconds: 90),
      onTimeout: () {
        _resolve(id, null);
        return null;
      },
    );
  }

  void cancelPending() => _failAll();

  void dispose() {
    _disposed = true;
    final worker = _worker;
    _worker = null;
    try {
      worker?.terminate();
    } catch (_) {
      // already gone
    }
    _failAll();
  }
}
