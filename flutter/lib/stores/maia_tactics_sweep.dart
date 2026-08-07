// The tactics axis's engine room (#268): SELECTION of the archive's tactical
// positions, and Maia-3's per-position answer to "how often does a typical
// player at each rating find THIS shot?" — both computed here, in the
// background, and cached.
//
// Why selection lives HERE and not on the screen: the selector costs ~0.5 ms
// of synchronous bridge time per stored ply (motifTags), which is ~19 SECONDS
// of UI freeze on a 500-game archive if called whole (#294 review, measured).
// So this store walks the archive ONE GAME PER BRIDGE CALL (~tens of ms
// each), yielding the event loop between games, and publishes the merged
// result as [tactics] — the ONE source the card reads for its user numbers,
// its keys, and its population counts alike.
//
// Why a sweep for the peer half: the lichess peer tables carry no best lines
// (T7 is struck — the dumps' [%eval] comments have no move in them), so the
// tactics card cannot read its peer column from a table. Maia-3's batched
// ladder (#221) answers per POSITION instead — one forward pass covers all
// 21 rungs — which also conditions the baseline on the actual difficulty of
// the positions this player faced, something a pooled table never could.
//
// Manners, borrowed from BackgroundGrader: lowest priority (pause whenever a
// live game wants the machine), per-position checkpoints, and the wipe-epoch
// guard — sampled BEFORE the archive is listed (a wipe can land while the
// list query is in flight, and an epoch read afterwards vouches for rows
// that no longer exist — #294 review, run-proven on the grader) and
// re-checked before every write.
//
// The unit of cached work is `key` = epdKey(fen)|bestUci, handed down by the
// brain's selector (reportTactics.ts). The cached value is P(best move) at
// every ladder rung — KEYED BY RUNG at extraction time and stored with the
// ladder it was computed under, so a reordered transport reply or a ladder
// change can never serve one rung's number under another's label (#294
// review: bare positional arrays inverted cleanly under a reversed reply).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../brain/js_bridge.dart';
import '../brain/maia3_api.dart';
import '../brain/report_api.dart';
import '../db/app_db.dart';
import '../engine/maia3_engine.dart';

class MaiaTacticsSweep extends ChangeNotifier {
  MaiaTacticsSweep(
    this._db,
    JsBridge bridge,
    Listenable this._liveGame,
    this._isLiveGameActive,
  )   : _api = Maia3Api(bridge),
        _reportApi = ReportApi(bridge),
        _bridge = bridge {
    _liveGame!.addListener(_onLiveGameChanged);
  }

  /// For unit tests: no bridge, so [debugAnalyze], [debugDecode],
  /// [debugLadder] and [debugTactics] must all be set before [ensureStarted].
  @visibleForTesting
  MaiaTacticsSweep.test(this._db,
      {bool Function()? isLiveGameActive, Listenable? liveGame})
      : _api = null,
        _reportApi = null,
        _bridge = null,
        // Not an initializing formal: a named parameter cannot be private,
        // and `liveGame` should read like the public ctor's.
        // ignore: prefer_initializing_formals
        _liveGame = liveGame,
        _isLiveGameActive = isLiveGameActive ?? (() => false) {
    _liveGame?.addListener(_onLiveGameChanged);
  }

  /// The platform gate is the transport's — same rule as [Maia3Store.usable]
  /// and for the same reason: an injected [debugAnalyze] has no platform left
  /// to be unsupported by, and without that reading the whole suite is
  /// silently a macOS-only suite ([[ci-host-platform-gates]]).
  /// [debugUsableOverride] exists for the opposite direction: the card's
  /// "not available on this device" state must be testable on hosts where
  /// Maia IS supported, or that branch is silently a CI-only branch.
  bool get maiaUsable =>
      debugUsableOverride ?? (debugAnalyze != null || Maia3Engine.supported);

  @visibleForTesting
  bool? debugUsableOverride;

  static const String _kvKey = 'botvinnik-maia-tactics-v1';

  /// Bump when the model file or its vocab changes: cached probabilities are
  /// facts about ONE set of weights. A LADDER change needs no bump — the
  /// document records the ladder it was computed under and is discarded on
  /// mismatch (see [_loadDoc]).
  static const int kDocVersion = 1;

  /// Curves are rounded to 4 decimals before persisting — a probability's
  /// fifth decimal is noise, and the kv document holds 21 of them per
  /// position for a whole archive.
  static const int _kRoundDp = 10000;

  final AppDb _db;
  final Maia3Api? _api;
  final ReportApi? _reportApi;
  final JsBridge? _bridge;
  final Listenable? _liveGame;
  final bool Function() _isLiveGameActive;

  Maia3Engine? _engine;
  List<int>? _ladder;

  /// key → P(bestSan) per ladder rung, in [_ladderNow] order.
  final Map<String, List<double>> _curves = {};
  bool _loaded = false;

  /// The merged selector output over the whole archive — the brain's
  /// TacticsReport shape (positions, byClass, games), assembled one game per
  /// bridge call. Null until the first selection pass completes; the card
  /// renders "reading your games" from that null rather than a stale zero.
  /// Published only WHOLE — a half-merged archive shown as "your found-rate"
  /// would be a number about nothing.
  Map<String, dynamic>? get tactics => _tactics;
  Map<String, dynamic>? _tactics;

  bool _running = false;
  bool _kickWanted = false;
  bool _resumeWanted = false;
  bool _disposed = false;

  /// Test seams, mirroring Maia3Store's: the transport, the decode, the
  /// ladder — and the whole selection phase (a canned TacticsReport for the
  /// archive, replacing the per-game bridge walk).
  @visibleForTesting
  Future<Maia3Raw?> Function(String fen, List<int> elos)? debugAnalyze;
  @visibleForTesting
  Maia3MoveCurves Function(String fen, Maia3Raw raw)? debugDecode;
  @visibleForTesting
  List<int>? debugLadder;
  @visibleForTesting
  Map<String, dynamic> Function(List<Map<String, dynamic>> projected)?
      debugTactics;

  /// Seed cached curves directly — for widget tests that want a finished
  /// sweep without running one.
  @visibleForTesting
  void debugSeed(Map<String, List<double>> curves) {
    _curves.addAll(curves);
    _loaded = true;
  }

  /// Seed the published selection — for widget tests of the card.
  @visibleForTesting
  void debugSeedTactics(Map<String, dynamic> report) {
    _tactics = report;
  }

  List<double>? curveFor(String key) => _curves[key];

  /// How many of [keys] (occurrences, duplicates included — the user side
  /// counts a repeated position every time it was faced, so the peer side
  /// must too) already have a cached curve.
  int coveredOf(Iterable<String> keys) =>
      keys.where((k) => _curves.containsKey(k)).length;

  /// Mean P(best move) at the ladder rung for [band], over [keys] —
  /// "a typical [band] facing these positions finds N%". Null unless EVERY
  /// key is covered: a partial mean silently reweights the position set
  /// toward whatever happened to be swept first.
  double? peerFoundRate(List<String> keys, int band) {
    if (keys.isEmpty) return null;
    final ladder = _ladderNow();
    if (ladder == null || ladder.isEmpty) return null;
    final rung = band.clamp(ladder.first, ladder.last);
    final i = ladder.indexOf(rung);
    if (i < 0) return null;
    var sum = 0.0;
    for (final k in keys) {
      final curve = _curves[k];
      if (curve == null || i >= curve.length) return null;
      sum += curve[i];
    }
    return sum / keys.length;
  }

  /// Resolved on demand, NOT only during a sweep: a restart with a fully
  /// warm cache never runs inference, and an answerable cache that cannot
  /// name its rungs would leave the card on "analysing N of N" forever.
  List<int>? _ladderNow() => debugLadder ?? (_ladder ??= _api?.eloLadder());

  /// Kick a sweep if none is running; if one IS running, latch a rerun — the
  /// running pass's work list was frozen when it started, so a kick that
  /// arrives mid-pass (an import landing, the grader stamping a game) must
  /// not be silently dropped (#294 review). The model download (~6MB, once)
  /// and the inference bill are only ever paid by someone who actually looks
  /// at the report.
  ///
  /// Runs even where Maia CANNOT: the selection phase is what feeds the
  /// card's user half, and a device without Maia still gets an absolute-only
  /// card — gating the whole sweep on the transport left iPhone-web reading
  /// its games forever.
  Future<void> ensureStarted() async {
    if (_disposed) return;
    if (_running) {
      _kickWanted = true;
      return;
    }
    _running = true;
    try {
      do {
        _kickWanted = false;
        await _sweep();
      } while (_kickWanted && !_disposed && !_resumeWanted);
    } catch (e) {
      debugPrint('[maia-tactics] sweep failed: $e');
    } finally {
      _running = false;
      // Return the session/worker memory on EVERY exit — completion, pause,
      // wipe, throw. The pause is the ordinary exit (a game started), and on
      // web the worker holds the compiled wasm and the model session for as
      // long as it lives (#294 review). Rebuilt lazily on resume.
      _engine?.dispose();
      _engine = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _sweep() async {
    // Epoch BEFORE the list: a wipe landing while the query is in flight
    // bumps the epoch first and resolves the query with pre-wipe rows —
    // sampling afterwards would vouch for a snapshot that no longer exists.
    final epoch = _db.wipeEpoch;
    final games = await _db.listGames();

    // ---- selection phase: one game per synchronous bridge call ----
    // Before anything Maia: this half needs no transport, and it is the
    // card's user column on every platform.
    final report = await _select(games, epoch);
    if (report == null) return; // paused, wiped, or disposed mid-selection
    _tactics = report;
    if (_disposed) return;
    notifyListeners();

    if (!maiaUsable) return; // absolute-only device: no peer half to compute
    final ladder = _ladderNow();
    if (ladder == null || ladder.isEmpty) return;
    await _loadDoc(ladder);

    final positions = [
      for (final p in (report['positions'] as List))
        (p as Map).cast<String, dynamic>(),
    ];

    final liveKeys = {for (final p in positions) p['key'] as String};
    // Prune before counting: keys whose games left the archive stop being
    // work and stop being bytes. (After a wipe this empties the document.)
    final stale = _curves.keys.where((k) => !liveKeys.contains(k)).toList();
    if (stale.isNotEmpty) {
      stale.forEach(_curves.remove);
      await _persist(epoch, ladder);
    }

    final todo = <String, Map<String, dynamic>>{};
    for (final p in positions) {
      final key = p['key'] as String;
      if (!_curves.containsKey(key)) todo[key] = p;
    }
    if (todo.isEmpty) return;

    // ---- inference phase: one batched-ladder forward pass per position ----
    final analyze = debugAnalyze ?? ((f, e) => _ensureEngine().analyze(f, e));
    var sinceWrite = 0;
    for (final entry in todo.entries) {
      if (_disposed) return;
      if (_db.wipeEpoch != epoch) return; // the position list is fiction now
      if (_isLiveGameActive()) {
        // Yield the machine whole — but checkpoint first: the pause is for a
        // game that may outlive this process, and answers since the last
        // write would be re-inferred after a restart (#294 review).
        await _persist(epoch, ladder);
        _resumeWanted = true;
        return;
      }

      final p = entry.value;
      Maia3Raw? raw;
      try {
        raw = await analyze(p['fen'] as String, ladder);
      } catch (e) {
        debugPrint('[maia-tactics] analyze failed: $e');
        raw = null;
      }
      if (raw == null) continue; // left uncached: retried by the next sweep

      List<double>? curve;
      try {
        // Resolved here, not before the loop: a store whose analyze never
        // answers must never touch the api at all (.test has none).
        final decode = debugDecode ?? _api!.computeMoveCurves;
        final curves = decode(p['fen'] as String, raw);
        curve = _curveOfBest(curves, p['bestSan'] as String, ladder);
      } catch (e) {
        debugPrint('[maia-tactics] decode failed: $e');
      }
      // A missing SAN key or rung would mean the selector and the decoder
      // disagree about the move or the ladder — a bug, never a zero. Leave
      // uncached.
      if (curve == null) continue;

      _curves[entry.key] = curve;
      // Checkpoint cadence grows with the document: rewriting the whole map
      // every 8 positions is quadratic bytes (26× amplification measured at
      // 400 positions, #294 review). Resume granularity only matters early.
      if (++sinceWrite >= _persistEvery()) {
        await _persist(epoch, ladder);
        sinceWrite = 0;
      }
      if (_disposed) return;
      notifyListeners();
    }
    await _persist(epoch, ladder);
  }

  int _persistEvery() {
    final n = _curves.length;
    return n < 64 ? 8 : n ~/ 8;
  }

  /// The selector, one game per bridge call with the event loop yielded
  /// between — each call is ~tens of ms of synchronous JS, and the whole
  /// archive at once was ~19s of platform-thread freeze (#294 review).
  /// Returns null when interrupted (pause, wipe, dispose): a partial merge
  /// must never be published.
  Future<Map<String, dynamic>?> _select(
      List<Map<String, dynamic>> games, int epoch) async {
    final projected = [for (final g in games) reportGameProjection(g)];
    if (debugTactics != null) return debugTactics!(projected);

    Map<String, dynamic>? merged;
    for (final g in projected) {
      if (_disposed || _db.wipeEpoch != epoch) return null;
      if (_isLiveGameActive()) {
        _resumeWanted = true;
        return null;
      }
      final one = _reportApi!.skillReportTactics([g]);
      merged = merged == null ? one : _mergeTactics(merged, one);
      await Future<void>.delayed(Duration.zero); // let the UI breathe
    }
    return merged ?? _reportApi!.skillReportTactics(const []);
  }

  /// Sum two TacticsReports: positions concatenate, every counter adds.
  /// Shape-coupled to brain/reportTactics.ts's return on purpose — a key
  /// this misses is a key the card silently under-reports, so the test
  /// pins the merge against the real single-call answer.
  static Map<String, dynamic> _mergeTactics(
      Map<String, dynamic> a, Map<String, dynamic> b) {
    Map<String, dynamic> sumMaps(Map am, Map bm) => {
          for (final k in am.keys)
            k: (am[k] is Map)
                ? sumMaps(am[k] as Map, (bm[k] ?? const {}) as Map)
                : (am[k] as num) + ((bm[k] ?? 0) as num),
        };
    return {
      'positions': [...(a['positions'] as List), ...(b['positions'] as List)],
      'byClass': sumMaps(a['byClass'] as Map, b['byClass'] as Map),
      'games': sumMaps(a['games'] as Map, b['games'] as Map),
    };
  }

  /// P(bestSan) at each of [ladder]'s rungs, LOOKED UP BY RUNG — the reply's
  /// order is not trusted, and a rung the reply lacks fails the position
  /// rather than shifting every number one column over.
  List<double>? _curveOfBest(
      Maia3MoveCurves curves, String bestSan, List<int> ladder) {
    final byElo = {
      for (final rung in curves.perElo) rung.elo: rung.moveProbabilities[bestSan],
    };
    final out = <double>[];
    for (final e in ladder) {
      final p = byElo[e];
      if (p == null) return null;
      out.add((p * _kRoundDp).round() / _kRoundDp);
    }
    return out;
  }

  Future<void> _loadDoc(List<int> ladder) async {
    if (_loaded) return;
    // The read stays OUTSIDE the try, and only a read that returned marks
    // the doc loaded: a transient kvGet failure here used to latch _loaded
    // with an empty map, and the next checkpoint then overwrote the
    // still-valid document with it (#294 review). A throw aborts the pass;
    // the next one retries the read.
    final raw = await _db.kvGet(_kvKey);
    _loaded = true;
    if (raw == null) return;
    try {
      final doc = (jsonDecode(raw) as Map).cast<String, dynamic>();
      if ((doc['v'] as num?)?.toInt() != kDocVersion) return; // stale weights
      final docLadder =
          [for (final e in (doc['ladder'] as List? ?? const [])) (e as num).toInt()];
      if (!listEquals(docLadder, ladder)) return; // rungs moved: all stale
      final curves = (doc['curves'] as Map).cast<String, dynamic>();
      curves.forEach((k, v) {
        _curves[k] = [for (final n in (v as List)) (n as num).toDouble()];
      });
    } catch (e) {
      // Unreadable CONTENT (bad JSON, drifted shape) is a corrupt document,
      // not weather — start over rather than abort every future pass on it.
      debugPrint('[maia-tactics] cache unreadable, resweeping: $e');
      _curves.clear();
    }
  }

  Future<void> _persist(int epoch, List<int> ladder) async {
    if (_disposed || _db.wipeEpoch != epoch) return;
    await _db.kvPut(
        _kvKey,
        jsonEncode(
            {'v': kDocVersion, 'ladder': ladder, 'curves': _curves}));
  }

  void _onLiveGameChanged() {
    if (_disposed || !_resumeWanted || _isLiveGameActive()) return;
    _resumeWanted = false;
    unawaited(ensureStarted());
  }

  Maia3Engine _ensureEngine() => _engine ??= Maia3Engine(_bridge!);

  @override
  void dispose() {
    _disposed = true;
    _liveGame?.removeListener(_onLiveGameChanged);
    _engine?.dispose();
    super.dispose();
  }
}
