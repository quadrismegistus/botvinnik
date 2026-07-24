// The moves-by-rating chart's store (issue #221): position in, per-rung
// human-move curves out.
//
// One inference covers the whole ELO ladder (the batch dimension), so the
// unit of work here is a POSITION, and the store's whole job is deciding
// when a position is worth that inference:
//
//   * debounced — stepping through a game with arrow keys must not queue an
//     inference per keypress; only the position that survives the pause runs
//   * cached — revisiting a position while browsing answers from memory,
//     because the model is deterministic per FEN
//   * latest-wins — a reply for a position no longer shown is dropped, never
//     drawn over the current one
//
// Lazy like the Maia-1 engine: nothing pays for the worker/session (or the
// ~6MB model download) until the chart panel actually asks for a position.

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../brain/js_bridge.dart';
import '../brain/maia3_api.dart';
import '../engine/maia3_engine.dart';
import '../engine/maia_progress.dart';

class Maia3Store extends ChangeNotifier {
  Maia3Store(JsBridge bridge)
      : _api = Maia3Api(bridge),
        _bridge = bridge;

  /// For unit tests: no bridge, so [debugAnalyze], [debugDecode] and
  /// [debugLadder] must all be set before the first [setPosition].
  @visibleForTesting
  Maia3Store.test()
      : _api = null,
        _bridge = null;

  /// The platform gate is the transport's (iPhone-web WASM ceiling on web,
  /// macOS/iOS on native). The panel shows an honest absence, not a stand-in.
  static bool get supported => Maia3Engine.supported;

  final Maia3Api? _api;
  final JsBridge? _bridge;

  Maia3Engine? _engine;
  List<int>? _ladder;

  /// What the chart draws: the curves for [shownFen], or null while nothing
  /// has been computed yet (loading, unsupported, or failed — see the flags).
  Maia3MoveCurves? curves;

  /// The position [curves] belongs to. Set only WITH curves, so the pair is
  /// always coherent.
  String? shownFen;

  /// True from the moment a position is requested until its curves land or
  /// fail. The debounce window counts: the panel should say "thinking", not
  /// flash old curves as settled truth.
  bool loading = false;

  /// The last request failed (after the transport's own retries). Cleared by
  /// the next request; the panel offers a retry by just asking again.
  bool failed = false;

  /// Model download / wasm compile narration for the first-use pause.
  MaiaProgress? progress;

  static const Duration _kDebounce = Duration(milliseconds: 250);

  /// Answered positions, FEN → curves. Small and LRU: browsing a game back
  /// and forth is the case it serves, and 64 positions is a whole game.
  static const int _kCacheLimit = 64;
  final _cache = <String, Maia3MoveCurves>{};

  Timer? _debounce;
  String? _wanted;
  int _seq = 0;
  bool _disposed = false;

  /// Test seam: replaces the engine's analyze. The decode still runs through
  /// the real brain path unless [debugDecode] is also set.
  @visibleForTesting
  Future<Maia3Raw?> Function(String fen, List<int> elos)? debugAnalyze;
  @visibleForTesting
  Maia3MoveCurves Function(String fen, Maia3Raw raw)? debugDecode;
  @visibleForTesting
  List<int>? debugLadder;

  /// Start the model download and session build off any position's clock —
  /// called when the chart panel is OPENED, so first curves come up in the
  /// pause between opening and looking. Fire-and-forget, no-op if unsupported.
  void warmUp() {
    if (!supported || _disposed || debugAnalyze != null) return;
    _ensureEngine().warmUp();
  }

  /// Show curves for [fen]. Debounced and cached; a second call supersedes
  /// the first. Null-safe against rapid browsing: whatever position is
  /// current when the debounce fires is the one that runs.
  void setPosition(String fen) {
    if (!supported || _disposed) return;
    if (fen == shownFen && curves != null) {
      _wanted = fen;
      _debounce?.cancel();
      if (loading) {
        loading = false;
        notifyListeners();
      }
      return;
    }
    _wanted = fen;
    final cached = _cache.remove(fen);
    if (cached != null) {
      _cache[fen] = cached; // LRU refresh
      // Cancel any pending timer too: harmless today (the _wanted guard in
      // _run neutralizes a stray firing), but every other branch maintains
      // the one-live-timer invariant locally and this one should not lean on
      // a downstream guard.
      _debounce?.cancel();
      _show(fen, cached);
      return;
    }
    if (!loading || failed) {
      loading = true;
      failed = false;
      notifyListeners();
    }
    _debounce?.cancel();
    _debounce = Timer(_kDebounce, () => _run(fen));
  }

  Future<void> _run(String fen) async {
    if (_disposed || fen != _wanted) return;
    final seq = ++_seq;
    final ladder = debugLadder ?? (_ladder ??= _api!.eloLadder());
    final analyze =
        debugAnalyze ?? ((f, e) => _ensureEngine().analyze(f, e));
    Maia3Raw? raw;
    try {
      raw = await analyze(fen, ladder);
    } catch (e) {
      debugPrint('[maia3] analyze failed: $e');
      raw = null;
    }
    if (_disposed || seq != _seq || fen != _wanted) return;
    if (raw == null) {
      loading = false;
      failed = true;
      progress = null;
      notifyListeners();
      return;
    }
    Maia3MoveCurves decoded;
    try {
      decoded = (debugDecode ?? _api!.computeMoveCurves)(fen, raw);
    } catch (e) {
      // A decode failure is a bug (shape drift between model and brain), not
      // weather — surface it as a failure rather than throwing into a Timer.
      debugPrint('[maia3] decode failed: $e');
      loading = false;
      failed = true;
      progress = null;
      notifyListeners();
      return;
    }
    _cache[fen] = decoded;
    while (_cache.length > _kCacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    _show(fen, decoded);
  }

  void _show(String fen, Maia3MoveCurves value) {
    curves = value;
    shownFen = fen;
    loading = false;
    failed = false;
    progress = null;
    notifyListeners();
  }

  Maia3Engine _ensureEngine() => _engine ??= Maia3Engine(_bridge!, onProgress: (p) {
        if (_disposed) return;
        progress = p;
        notifyListeners();
      });

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _engine?.dispose();
    super.dispose();
  }
}
