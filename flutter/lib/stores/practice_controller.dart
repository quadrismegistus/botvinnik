// Practice: collected mistakes on a Leitner schedule (brain logic, Dart
// persistence in the kv table under the web's key name) and the drill
// session — serve item, check the attempt with a depth-14 search, record
// pass/fail, hints in tiers. Find-best drill only for now (blundercheck
// is a later pass, like the web's second drill mode).

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../brain/grading_api.dart';
import '../brain/practice_api.dart';
import '../db/app_db.dart';
import '../engine/arbiter.dart';
import 'settings_store.dart';

const _kvKey = 'botvinnik-practice-v1'; // web's localStorage key name
const double kPassDrop = 5; // ≤5% win-chance loss passes (web PASS_DROP)
// Collect EVERYTHING ≥5% (the floor) — the settings threshold filters at
// serve time, so tightening or loosening it later applies retroactively
// to the whole collection instead of only to future games.
const double kCollectMin = 5;

class AttemptOutcome {
  final String san;
  final String uci;
  final bool pass;
  final double drop;
  final double? evalPawns;
  final String? refutationUci; // the punishing reply when the attempt fails
  const AttemptOutcome({
    required this.san,
    required this.uci,
    required this.pass,
    required this.drop,
    required this.evalPawns,
    this.refutationUci,
  });
}

class PracticeController extends ChangeNotifier {
  final AppDb _db;
  final PracticeApi _api;
  final GradingApi _grading;
  final SearchArbiter _arbiter;
  SettingsStore? settings; // injected post-boot (threshold filter)

  List<Map<String, dynamic>> items = [];
  bool loaded = false;

  // session state
  Map<String, dynamic>? current;
  AttemptOutcome? attempt;
  String? pendingUci; // attempt applied to the board while the check runs
  bool checking = false;
  int hintTier = 0; // 0 none, 1 text, 2 origin square, 3 reveal best
  bool revealBest = false;
  bool _resultRecorded = false;
  int sessionSolved = 0;
  int sessionStreak = 0;

  PracticeController(this._db, this._api, this._grading, this._arbiter);

  /// Items at or above the configured threshold — what practice serves.
  List<Map<String, dynamic>> get servable {
    final threshold = settings?.collectThreshold ?? 15;
    return items
        .where((i) => ((i['drop'] as num?)?.toDouble() ?? 0) >= threshold)
        .toList();
  }

  int get due => loaded ? _api.dueCount(servable) : 0;

  Future<void> load() async {
    final raw = await _db.kvGet(_kvKey);
    if (raw != null) {
      try {
        items = (jsonDecode(raw) as List)
            .map((i) => (i as Map).cast<String, dynamic>())
            .toList();
      } catch (_) {/* corrupted store: start empty */}
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _persist() =>
      _db.kvPut(_kvKey, jsonEncode(items));

  /// Auto-collection: called by GameController for every backfilled grade.
  /// [storedMove] is the web StoredMove shape; collects when the drop is big
  /// enough and the position isn't already a puzzle.
  Future<void> maybeCollect(Map<String, dynamic> storedMove,
      {String? setupUci, int minDepth = 8}) async {
    if (!loaded) await load();
    final drop = (storedMove['wcDrop'] as num?)?.toDouble() ?? 0;
    final depth = (storedMove['depth'] as num?)?.toInt() ?? 0;
    if (drop < kCollectMin || depth < minDepth) return;
    final data = _api.itemData(storedMove, setupUci);
    if (data == null) return;
    final next = _api.addItem(items, data);
    if (next == null) return; // duplicate fen
    items = next;
    await _persist();
    notifyListeners();
  }

  // ---- session ----

  void startSession() {
    sessionSolved = 0;
    sessionStreak = 0;
    _serve(_api.nextItem(servable, easyFirst: true));
  }

  void nextPuzzle() =>
      _serve(_api.nextItem(servable, excludeId: current?['id'] as String?,
          easyFirst: true));

  void _serve(Map<String, dynamic>? item) {
    current = item;
    attempt = null;
    pendingUci = null;
    hintTier = 0;
    revealBest = false;
    _resultRecorded = false;
    checking = false;
    notifyListeners();
  }

  void retry() {
    attempt = null;
    pendingUci = null;
    checking = false;
    notifyListeners();
  }

  void hint() {
    if (hintTier >= 3) return;
    hintTier++;
    if (hintTier >= 3) revealBest = true;
    notifyListeners();
  }

  void reveal() {
    revealBest = true;
    notifyListeners();
  }

  /// The user played [uci] from the puzzle position. Checks it against the
  /// stored best (depth-14 search of the resulting position, practiceCheck
  /// priority — preempts background analysis, waits behind nothing).
  Future<void> checkAttempt(String uci, String san, String fenAfter) async {
    final item = current;
    if (item == null || checking) return;
    checking = true;
    pendingUci = uci; // show the move on the board while we check
    notifyListeners();

    double? evalPawns;
    String? refutation;
    double drop;
    if (uci == item['bestUci']) {
      evalPawns = (item['evalBestPawns'] as num?)?.toDouble();
      drop = 0;
    } else {
      // depth 12 / 1.5s: the full-NNUE native engine evaluates slower per
      // node than the web's lite build — a snappy verdict beats two extra
      // plies of certainty here
      final lines = await _arbiter.search(
        fen: fenAfter,
        depth: 12,
        multiPv: 1,
        movetimeMs: 1500,
        priority: SearchPriority.practiceCheck,
      );
      if (lines == null || lines.isEmpty) {
        checking = false;
        pendingUci = null;
        notifyListeners();
        return;
      }
      final top = lines.first;
      // child eval is the opponent's perspective — negate for the mover
      evalPawns = -top.score;
      final mate = top.mate == null ? null : -top.mate!;
      final wcAfter = _grading.winChance(evalPawns, mate);
      drop = ((item['wcBest'] as num).toDouble() - wcAfter).clamp(0.0, 100.0);
      refutation = top.pv.isEmpty ? null : top.pv.first;
    }

    final pass = drop <= kPassDrop;
    attempt = AttemptOutcome(
      san: san,
      uci: uci,
      pass: pass,
      drop: drop,
      evalPawns: evalPawns,
      refutationUci: pass ? null : refutation,
    );
    checking = false;

    if (!_resultRecorded) {
      _resultRecorded = true;
      items = _api.recordResult(items, item['id'] as String, pass,
          hinted: hintTier > 0);
      await _persist();
      if (pass) {
        sessionSolved++;
        sessionStreak = hintTier == 0 ? sessionStreak + 1 : 0;
      } else {
        sessionStreak = 0;
      }
    }
    notifyListeners();
  }

  Future<void> remove(String id) async {
    items = _api.removeItem(items, id);
    if (current?['id'] == id) _serve(null);
    await _persist();
    notifyListeners();
  }
}
