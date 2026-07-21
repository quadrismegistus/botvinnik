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

  /// Bumped by every `_serve`, i.e. by anything that puts a different puzzle on
  /// screen — Skip/Next, the motif picker, a delete, a new session. An
  /// in-flight [checkAttempt] compares it across its await and drops the
  /// verdict rather than recording it against whatever is there now. Same shape
  /// as `GameController._gen`.
  int _gen = 0;

  PracticeController(this._db, this._api, this._grading, this._arbiter);

  /// The drop a puzzle needs before practice will serve it.
  ///
  /// Read by the collection browser as well as by [servable], from here rather
  /// than from the widget's own SettingsStore: the browser labels the items it
  /// is NOT going to serve, and a browser reading one number while the filter
  /// reads another would label the wrong rows.
  int get threshold => settings?.collectThreshold ?? 15;

  /// Items at or above the configured threshold — what practice serves.
  List<Map<String, dynamic>> get servable => items
      .where((i) => ((i['drop'] as num?)?.toDouble() ?? 0) >= threshold)
      .toList();

  int get due => loaded ? _api.dueCount(servable) : 0;

  /// The motif the drill is restricted to, or null for everything.
  ///
  /// Deliberately not persisted: a filter is a property of the session you are
  /// sitting in, not of the collection. Reopening the app on a "fork only"
  /// queue set weeks ago, with the badge counting puzzles it will not serve,
  /// is a bug report waiting to happen.
  String? motifFilter;

  /// Motifs carried by the items practice would actually serve, commonest
  /// first, with their counts.
  ///
  /// The picker is built from this rather than from the brain's `Motif` union
  /// so it can never offer a filter that matches nothing — and because the
  /// Dart side has no equivalent of the brain's `loadItems` backfill, so items
  /// collected before motif tagging simply carry no tags and are correctly
  /// absent here rather than hiding behind an empty option.
  Map<String, int> get motifCounts {
    final counts = <String, int>{};
    for (final i in servable) {
      for (final m in (i['motifs'] as List?)?.cast<String>() ?? const []) {
        counts[m] = (counts[m] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) =>
          a.value != b.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    return Map.fromEntries(entries);
  }

  // Two brain answers the collection browser asks for, cached against the
  // IDENTITY of `items` — which is replaced wholesale by every mutation
  // (`items = next`), never edited in place, so identity is an exact
  // change signal. Both calls marshal through JSON to the JS host, and the
  // browser asks for them on every frame it paints: mastery once per frame,
  // difficulty once per visible row. Uncached, scrolling the list would put
  // the whole collection back on the wire for every repaint.
  Map<String, int>? _mastery;
  List<Map<String, dynamic>>? _masteryFor;
  final Map<String, String> _difficulty = {};
  List<Map<String, dynamic>>? _difficultyFor;

  /// mastered / learning / fresh / total.
  ///
  /// Over the whole collection, not the servable slice: this is a picture of
  /// what you have learned, and an item you mastered before raising the
  /// threshold did not become less mastered by falling out of the queue.
  Map<String, int> get mastery {
    if (_mastery == null || !identical(_masteryFor, items)) {
      _masteryFor = items;
      _mastery = _api.masteryStats(items);
    }
    return _mastery!;
  }

  /// The brain's difficulty badge for one item — grounded in your own attempt
  /// history once you have one, position features before that.
  String difficultyOf(Map<String, dynamic> item) {
    if (!identical(_difficultyFor, items)) {
      _difficultyFor = items;
      _difficulty.clear();
    }
    return _difficulty[item['id'] as String] ??= _api.puzzleDifficulty(item);
  }

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
    _serve(_api.nextItem(servable, motif: motifFilter, easyFirst: true));
  }

  void nextPuzzle() {
    final id = current?['id'] as String?;
    // The exclusion means "don't hand me the same one twice running", not "run
    // out". Under a motif filter down to a single item, honouring it empties
    // the pool and the tab announces there is nothing to practise while
    // holding a puzzle — so fall back to the unexcluded draw.
    final next = _api.nextItem(servable,
            excludeId: id, motif: motifFilter, easyFirst: true) ??
        _api.nextItem(servable, motif: motifFilter, easyFirst: true);
    _serve(next);
  }

  /// Drill one named item, picked out of the collection browser rather than
  /// drawn by the scheduler.
  ///
  /// Goes through [_serve] like every other route to a different puzzle, which
  /// is what bumps the generation: opening the list mid-check and tapping a row
  /// is a third door onto the stale-verdict hole that Skip and delete already
  /// opened, and the guard in [checkAttempt] only closes doors that come
  /// through here. Unfiltered by [servable] on purpose — the browser lists what
  /// the queue will not serve so you can act on it, and "practise this one
  /// anyway" is one of the actions.
  void serveItem(String id) {
    for (final item in items) {
      if (item['id'] == id) {
        _serve(item);
        return;
      }
    }
  }

  /// Restrict the drill to [motif] (null = everything) and serve at once.
  /// Waiting for the next Skip to feel it reads as the filter not working.
  void setMotifFilter(String? motif) {
    if (motif == motifFilter) return;
    motifFilter = motif;
    _serve(_api.nextItem(servable, motif: motif, easyFirst: true));
  }

  void _serve(Map<String, dynamic>? item) {
    _gen++;
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
    final gen = _gen;
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
      // The puzzle changed under us — Skip/Next, the picker, or a delete of the
      // one being drilled, any of which serves a different item during the ~1.5s
      // this search takes. The grading above is harmless; what must not happen
      // is the commit below, which would move the NEW puzzle's Leitner box on
      // the OLD puzzle's verdict and corrupt the schedule for both, silently.
      //
      // Nothing to clean up: _serve has already reset checking, pendingUci and
      // attempt for the item now on screen, and touching them here would clobber
      // it. (Only this await needs the check — the bestUci branch has none, so
      // it commits in the same turn it was called.)
      if (gen != _gen) return;
      if (lines == null || lines.isEmpty) {
        // null now also means "the engine never started" — the arbiter resolves
        // null rather than throwing so this path is reached instead of leaving
        // `checking` stuck true, which wedged the tab for the app's lifetime
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

  /// Drop a puzzle from the collection for good.
  ///
  /// The only escape hatch there is: nothing else removes an item, and #137
  /// decided that a blunder you took back stays collected, so without this a
  /// position you consider noise is in the queue permanently.
  ///
  /// Deleting the one on screen serves the next rather than emptying the tab —
  /// "this one is noise" is a step through the queue, not the end of it.
  Future<void> remove(String id) async {
    items = _api.removeItem(items, id);
    if (current?['id'] == id) {
      _serve(_api.nextItem(servable, motif: motifFilter, easyFirst: true));
    }
    await _persist();
    notifyListeners();
  }
}
