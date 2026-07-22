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

  /// Everywhere a Worker and WebAssembly run — the web — EXCEPT iOS Safari.
  ///
  /// ort-web's ~13MB runtime cannot instantiate alongside Flutter's under
  /// mobile Safari's per-tab memory ceiling: it throws `no available backend ·
  /// RangeError: Out of memory`, every time, on any connection (confirmed on an
  /// iPhone; desktop has the headroom and is fine). Since it can never run
  /// there, we do not OFFER it there — a persona that is always a Stockfish
  /// stand-in is worse than one that is simply absent — rather than falling back
  /// per move. iOS gets the real Maia in the native app (package:onnxruntime
  /// over FFI, no browser cap); the web on iOS does not.
  ///
  /// iPadOS Safari reports as macOS (desktop-class, far more memory), so it is
  /// NOT excluded — it has the headroom an iPhone does not.
  static bool get supported => defaultTargetPlatform != TargetPlatform.iOS;

  /// Called as a move waits on something other than inference: the weights
  /// arriving, then the runtime compiling. Null once it is genuinely thinking.
  final void Function(MaiaProgress?)? onProgress;

  /// Per-band lifecycle, for the selection UI (see [MaiaStatus]). Fires for
  /// moves AND warm-ups: a [progress] while it loads, an [error] when it gives
  /// up (the worker's verbatim reason), and both-null when the band is ready.
  /// Distinct from [onProgress], which is the in-GAME bar and only for moves.
  final void Function(int band, {MaiaProgress? progress, String? error})?
      onBandStatus;

  JsWorker? _worker;
  bool _disposed = false;
  int _nextId = 1;
  final Map<int, Completer<String?>> _pending = {};

  /// The band each in-flight request (move or warm-up) is for, so a worker
  /// reply — which carries only the request id — can be attributed to a band.
  final Map<int, int> _bandOf = {};

  MaiaEngine({this.onProgress, this.onBandStatus}) {
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
      final band = _bandOf[id];
      final status = data['status'];
      if (status == 'fetching' || status == 'starting') {
        final progress = MaiaProgress(
          status as String,
          received: (data['received'] as num?)?.toInt() ?? 0,
          total: (data['total'] as num?)?.toInt() ?? 0,
        );
        // The in-game bar, only for a move still wanted. The worker keeps
        // working on a cancelled request, so without this an abandoned download
        // could re-raise the progress line after a new game had cleared it.
        if (_pending.containsKey(id)) onProgress?.call(progress);
        // The selection-UI bar, for moves and warm-ups alike.
        if (band != null) onBandStatus?.call(band, progress: progress);
        return;
      }
      final error = data['error'];
      _bandOf.remove(id);
      if (error != null) {
        debugPrint('[maia] $error');
        if (band != null) onBandStatus?.call(band, error: '$error');
      } else if (band != null) {
        // A move or a warm-up came back without an error: this band's weights
        // and session are up. (A null move is "no legal moves", still a load
        // that worked.)
        onBandStatus?.call(band);
      }
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
      //
      // This is the likeliest hard failure on a phone (ort-web will not load),
      // and the one that reads only as an unexplained stand-in — so every band
      // waiting on this worker is reported failed with the reason.
      for (final band in _bandOf.values.toSet()) {
        onBandStatus?.call(band, error: 'engine failed to load: $detail');
      }
      _bandOf.clear();
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
    _bandOf[id] = band;
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

  /// Start this band's download and session build in the background, off any
  /// move's clock, so a later move for it answers at once instead of standing
  /// in while a phone pulls 3.5MB of weights and compiles ~13MB of WebAssembly.
  ///
  /// Called when a Maia opponent is CHOSEN — the New Game sheet — rather than
  /// on its first move, which is the whole point: the setup-to-first-move
  /// window is where the load should happen. Fire-and-forget; a failure just
  /// means the first move falls back exactly as before. Idempotent per band in
  /// the worker, so a second warm-up, or a move that arrives mid-load, joins
  /// the same download rather than starting another.
  ///
  /// Deliberately NOT tracked in [_pending]: its only job is to warm the cache
  /// and session, so its progress and its (empty) answer are both irrelevant —
  /// a real move narrates itself if it arrives before this finishes.
  void warmUp(int band) {
    if (_disposed) return;
    if (_worker == null) _spawn();
    final worker = _worker;
    if (worker == null) return;
    final id = _nextId++;
    _bandOf[id] = band;
    worker.postMessage({'id': id, 'band': band, 'preload': true}.jsify());
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
