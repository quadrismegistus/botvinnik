// The tactics axis's peer half (#268): Maia-3's per-position answer to "how
// often does a typical player at each rating find THIS shot?", swept over the
// archive's tactical positions in the background and cached.
//
// Why a sweep at all: the lichess peer tables carry no best lines (T7 is
// struck — the dumps' [%eval] comments have no move in them), so the tactics
// card cannot read its peer column from a table. Maia-3's batched ladder
// (#221) answers per POSITION instead — one forward pass covers all 21 rungs
// — which also conditions the baseline on the actual difficulty of the
// positions this player faced, something a pooled table never could.
//
// Manners, borrowed from BackgroundGrader: lowest priority (pause whenever a
// live game wants the machine), per-position checkpoints, and the wipe-epoch
// guard — sample when the archive is LISTED, re-check before every write, so
// a sweep in flight across a "Clear local games" cannot write conclusions
// about an archive that no longer exists.
//
// The unit of cached work is `key` = epdKey(fen)|bestUci, handed down by the
// brain's selector (reportTactics.ts) — the ONE authority on which positions
// the axis is made of; this store never selects, it only answers. The cached
// value is P(best move) at every ladder rung, so changing the band dropdown
// never re-runs inference.

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
  /// facts about ONE set of weights. (kMaia3ModelUrl is pinned upstream; this
  /// is the manual latch that says "those numbers no longer apply".)
  static const int kDocVersion = 1;

  /// Curves are rounded to 4 decimals before persisting — a probability's
  /// fifth decimal is noise, and the kv document holds 21 of them per
  /// position for a whole archive.
  static const int _kRoundDp = 10000;

  /// Persist every N computed positions: a checkpoint cadence, so an
  /// interrupted sweep (app close, live game) resumes roughly where it was.
  static const int _kPersistEvery = 8;

  final AppDb _db;
  final Maia3Api? _api;
  final ReportApi? _reportApi;
  final JsBridge? _bridge;
  final Listenable? _liveGame;
  final bool Function() _isLiveGameActive;

  Maia3Engine? _engine;
  List<int>? _ladder;

  /// key → P(bestSan) per ladder rung. The whole point of the store.
  final Map<String, List<double>> _curves = {};
  bool _loaded = false;

  /// Distinct positions this sweep still owes an answer. For the card's
  /// progress line use [coveredOf] over the slice's own keys instead.
  int get pending => _pending;
  int _pending = 0;

  bool _running = false;
  bool _resumeWanted = false;
  bool _disposed = false;

  /// Test seams, mirroring Maia3Store's: the transport, the decode, the
  /// ladder, and — new here — the brain's selector.
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
    // Resolved on demand, NOT only during a sweep: a restart with a fully
    // warm cache never runs inference, and an answerable cache that cannot
    // name its rungs would leave the card on "analysing N of N" forever.
    final ladder = debugLadder ?? (_ladder ??= _api?.eloLadder());
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

  /// Kick a sweep if none is running. Called when the report screen opens —
  /// the model download (~6MB, once) and the inference bill are only ever
  /// paid by someone who actually looks at the report.
  Future<void> ensureStarted() async {
    if (_running || _disposed || !maiaUsable) return;
    _running = true;
    try {
      await _sweep();
    } catch (e) {
      debugPrint('[maia-tactics] sweep failed: $e');
    } finally {
      _running = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _sweep() async {
    await _loadDoc();

    final games = await _db.listGames();
    // Sampled AFTER the list, exactly like BackgroundGrader: the epoch vouches
    // for this snapshot, and every write below re-checks it first.
    final epoch = _db.wipeEpoch;
    final projected = [for (final g in games) reportGameProjection(g)];
    final report = (debugTactics ?? _reportApi!.skillReportTactics)(projected);
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
      await _persist(epoch);
    }

    final todo = <String, Map<String, dynamic>>{};
    for (final p in positions) {
      final key = p['key'] as String;
      if (!_curves.containsKey(key)) todo[key] = p;
    }
    _pending = todo.length;
    if (todo.isEmpty) return;
    notifyListeners();

    final ladder = debugLadder ?? (_ladder ??= _api!.eloLadder());
    final analyze = debugAnalyze ?? ((f, e) => _ensureEngine().analyze(f, e));

    var sinceWrite = 0;
    for (final entry in todo.entries) {
      if (_disposed) return;
      if (_db.wipeEpoch != epoch) return; // the position list is fiction now
      if (_isLiveGameActive()) {
        // Yield the machine whole: the live game's search and Maia's session
        // build are both CPU-bound. _onLiveGameChanged resumes the sweep.
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
        curve = _curveOfBest(curves, p['bestSan'] as String);
      } catch (e) {
        debugPrint('[maia-tactics] decode failed: $e');
      }
      // A missing SAN key would mean the selector and the decoder disagree
      // about the move's spelling — a bug, never a zero. Leave uncached.
      if (curve == null) continue;

      _curves[entry.key] = curve;
      _pending -= 1;
      if (++sinceWrite >= _kPersistEvery) {
        await _persist(epoch);
        sinceWrite = 0;
      }
      if (_disposed) return;
      notifyListeners();
    }
    await _persist(epoch);

    // Drained: return the session/worker memory. The engine rebuilds lazily
    // if new games bring new positions.
    _engine?.dispose();
    _engine = null;
  }

  /// P(bestSan) at each rung, in ladder order. The SAN keys and [bestSan]
  /// are both chess.js renderings of the same move in the same position
  /// (decoding.ts and reportTactics.ts respectively), so this lookup matches
  /// exactly or reveals a bug — no fuzzy matching that could hide one.
  List<double>? _curveOfBest(Maia3MoveCurves curves, String bestSan) {
    final out = <double>[];
    for (final rung in curves.perElo) {
      final p = rung.moveProbabilities[bestSan];
      if (p == null) return null;
      out.add((p * _kRoundDp).round() / _kRoundDp);
    }
    return out;
  }

  Future<void> _loadDoc() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await _db.kvGet(_kvKey);
    if (raw == null) return;
    try {
      final doc = (jsonDecode(raw) as Map).cast<String, dynamic>();
      if ((doc['v'] as num?)?.toInt() != kDocVersion) return; // stale weights
      final curves = (doc['curves'] as Map).cast<String, dynamic>();
      curves.forEach((k, v) {
        _curves[k] = [for (final n in (v as List)) (n as num).toDouble()];
      });
    } catch (e) {
      debugPrint('[maia-tactics] cache unreadable, resweeping: $e');
      _curves.clear();
    }
  }

  Future<void> _persist(int epoch) async {
    if (_disposed || _db.wipeEpoch != epoch) return;
    await _db.kvPut(
        _kvKey, jsonEncode({'v': kDocVersion, 'curves': _curves}));
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
