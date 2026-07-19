// The Maia bots on the web: a human-imitation net (McIlroy-Young et al.) that
// answers "what would a human of this rating play here" in one ONNX policy
// pass. No search, no eval — so like retro and Garbo it is an opponent rather
// than an analysis, and it never touches the arbiter.
//
// The work happens in web/maia/maia-worker.js (built from web_src/); this is
// only the Dart end of its protocol. Three things make it unlike the other
// two worker clients:
//
//   * **It needs the game's FEN HISTORY, not a position.** Maia was trained
//     with eight plies of history and its move distribution sharpens with
//     real history — passing only the current FEN works but plays worse.
//   * **First use downloads ~3.5MB of weights** from HuggingFace (GPL-3.0, so
//     deliberately not redistributed with the app). The worker announces that
//     as it goes, and [onProgress] exists so the UI can show it out loud
//     rather than showing a mystery pause.
//   * **Requests are correlated by id.** A model download can outlive the
//     position that triggered it, so a reply has to be matched rather than
//     assumed to belong to whoever is waiting.

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'js_worker.dart';
import 'maia_progress.dart';

class MaiaEngine {
  static const _scriptUrl = 'maia/maia-worker.js';

  /// ort-web runs anywhere a Worker and WebAssembly do, so on the web: always.
  /// Whether the *weights* can be fetched is a per-move question, answered by
  /// falling back rather than by refusing to offer the persona.
  static bool get supported => true;

  /// Called as a move waits on something other than inference: the weights
  /// arriving, then the runtime compiling. Null once it is genuinely thinking.
  final void Function(MaiaProgress?)? onProgress;

  JsWorker? _worker;
  bool _disposed = false;
  int _nextId = 1;
  final Map<int, Completer<String?>> _pending = {};

  MaiaEngine({this.onProgress}) {
    _spawn();
  }

  void _spawn() {
    if (_disposed) return;
    final worker = JsWorker(_scriptUrl);
    _worker = worker;
    worker.onmessage = ((WorkerMessage e) {
      final data = e.data?.dartify();
      if (data is! Map) return;
      final id = (data['id'] as num?)?.toInt();
      if (id == null) return;
      final status = data['status'];
      if (status == 'fetching' || status == 'starting') {
        // Only for a request still wanted. The worker keeps working on a
        // cancelled request, so without this an abandoned download could
        // re-raise the progress line after a new game had cleared it.
        if (_pending.containsKey(id)) {
          onProgress?.call(MaiaProgress(
            status as String,
            received: (data['received'] as num?)?.toInt() ?? 0,
            total: (data['total'] as num?)?.toInt() ?? 0,
          ));
        }
        return;
      }
      final error = data['error'];
      if (error != null) debugPrint('[maia] $error');
      // 'move' is present and null for a position with no legal moves, absent
      // on error — both mean the same thing to the caller, so both resolve.
      _resolve(id, error == null ? data['move'] as String? : null);
    }).toJS;
    worker.onerror = ((JSAny? event) {
      final detail = (event as WorkerError?)?.message ?? 'unknown error';
      debugPrint('[maia] worker failed ($_scriptUrl): $detail');
      // ort-web is unavailable in this browser, or the script is missing.
      // Fail everyone waiting and scrap the worker; the next move respawns
      // and, if it fails again, falls back again. Cheap either way.
      _worker = null;
      try {
        worker.terminate();
      } catch (_) {
        // already gone
      }
      _failAll();
    }).toJS;
  }

  void _resolve(int id, String? uci) {
    final pending = _pending.remove(id);
    if (pending != null && !pending.isCompleted) pending.complete(uci);
  }

  void _failAll() {
    final waiting = _pending.values.toList();
    _pending.clear();
    for (final c in waiting) {
      if (!c.isCompleted) c.complete(null);
    }
  }

  /// Maia's move for the position at the end of [fenHistory], or null on any
  /// failure — no weights, no ort, no legal moves, or a browser that cannot
  /// run either.
  ///
  /// [fenHistory] is oldest-first with the current position last. Pass the
  /// real game history when there is one.
  Future<String?> move(
    List<String> fenHistory, {
    required int band,
    double temperature = 0,
  }) {
    if (_disposed || fenHistory.isEmpty) return Future.value(null);
    if (_worker == null) _spawn();
    final worker = _worker;
    if (worker == null) return Future.value(null);

    // One request in flight, which the worker's protocol comment claims and
    // this did not honour until a review caught it. RetroEngine and
    // GarboEngine both cancel the previous request before posting; without
    // the same here, hitting New Game during a slow first download left the
    // old request pinned for up to 90s and put a second `session.run()` on
    // the same InferenceSession. Each impatient click added another.
    //
    // The ids are still worth having: they discard a LATE reply for a
    // cancelled request, which cancelling alone would not.
    _failAll();
    final id = _nextId++;
    final pending = Completer<String?>();
    _pending[id] = pending;
    worker.postMessage({
      'id': id,
      'fenHistory': fenHistory,
      'band': band,
      'temperature': temperature,
    }.jsify());
    return pending.future.timeout(
      // generous on purpose: the FIRST call for a band can be a 3.5MB download
      // plus ~13MB of WebAssembly to compile. Later calls answer in ~10ms.
      const Duration(seconds: 90),
      onTimeout: () {
        _resolve(id, null);
        return null;
      },
    );
  }

  /// Abandon every outstanding request without tearing the worker down.
  ///
  /// Called when the game they belonged to is gone. Without it the ids stay
  /// in [_pending], so a late `status:'fetching'` from an abandoned download
  /// still passes the "is this wanted" check and re-raises the downloading
  /// flag on a game that is not downloading anything.
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
    // terminate() fires no event, so nothing else would resolve a search in
    // flight
    _failAll();
  }
}
