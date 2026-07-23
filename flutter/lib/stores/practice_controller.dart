// Practice: collected mistakes on a Leitner schedule (brain logic, Dart
// persistence in the kv table under the web's key name) and the drill
// session — serve item, check the attempt with a depth-14 search, record
// pass/fail, hints in tiers. Find-best drill only for now (blundercheck
// is a later pass, like the web's second drill mode).

import 'dart:convert';

import 'package:dartchess/dartchess.dart';
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

// The "continue the line" search budget. Deliberately the SAME depth/time as
// the checkAttempt verdict search (see there): the opponent's reply and the
// next target are found at the depth the puzzle itself is graded at, and the
// full-NNUE native engine's slower per-node cost is the same argument for a
// snappy 1.5s cap here as it is there.
const int kLineSearchDepth = 12;
const int kLineSearchMs = 1500;

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

  /// "Continue the line" state (#143). After a PASSED puzzle the player can keep
  /// playing forward: the engine answers, the position one move later is served
  /// as a fresh target, and the drill walks the line the puzzle came from.
  ///
  /// [continuing] is true while the two back-to-back searches run — the reply
  /// and the next target — and locks the board like an in-flight check does.
  bool continuing = false;

  /// How many "continue" steps past the stored puzzle we are. Zero is the
  /// scheduler-served puzzle; anything above is an EPHEMERAL line continuation
  /// that must not touch the Leitner schedule (guarded in [checkAttempt]) — you
  /// are drilling a line, not re-answering the collected position.
  int lineDepth = 0;

  /// Set when a continued line runs to its end (checkmate/stalemate): there is
  /// no next target, so the drill stops with a note instead of a puzzle.
  String? lineNote;

  /// The position AFTER the graded attempt, captured by [checkAttempt] so
  /// [continueLine] knows where to play the opponent's reply from. Null unless
  /// an attempt has just committed against the puzzle on screen.
  String? _fenAfterAttempt;

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

  /// Bias each session toward easier puzzles before the hard ones (the web's
  /// `botvinnik-practice-easein`, on by default). Off is strict due order —
  /// what spaced repetition asks for. Defaults on when settings hasn't been
  /// injected yet, matching the pre-setting hardcoded behaviour.
  bool get _easeIn => settings?.easeIn ?? true;

  /// Items at or above the configured threshold — what practice serves.
  List<Map<String, dynamic>> get servable => items
      .where((i) => ((i['drop'] as num?)?.toDouble() ?? 0) >= threshold)
      .toList();

  /// The positions (item ids / fens) one game's blunders map to, while a
  /// "practise this game's mistakes" session (#197) is running; null the rest
  /// of the time. Session-only, never persisted — the same discipline as
  /// [motifFilter]: a scope is a property of the session you are sitting in,
  /// not of the collection, and reopening the app onto three positions from a
  /// game you reviewed weeks ago would read as the queue being broken.
  Set<String>? gameScope;

  bool get inGameSession => gameScope != null;

  /// What a running session actually draws from. A game session serves EVERY
  /// collected mistake in scope, threshold or not — you picked the game
  /// deliberately, the way [serveItem] drills a hand-picked sub-threshold
  /// position — so it draws from the whole collection filtered to the scope,
  /// not from the threshold-gated [servable]. A normal session draws
  /// [servable].
  List<Map<String, dynamic>> get _pool {
    final scope = gameScope;
    if (scope == null) return servable;
    return items.where((i) => scope.contains(i['id'] as String)).toList();
  }

  /// How many collected puzzles fall on the positions [fens] (a reviewed
  /// game's move-before fens) — what the Review affordance labels itself with
  /// and gates on. Counted over the whole collection, matching [_pool]'s game
  /// branch, so the number the button shows is the number the session serves.
  int countForGame(Set<String> fens) =>
      items.where((i) => fens.contains(i['id'] as String)).length;

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

  /// Collect many at once — the import path.
  ///
  /// A loop of [maybeCollect] is quadratic on this side, not the brain's: each
  /// call marshals the whole growing collection into a JS expression, decodes
  /// the whole result back, re-encodes it for the kvPut, and notifies — which
  /// makes the nav badge re-count over the bridge too. Measured for a 300-game
  /// import (~1500 seeds): 986MB of expression text, 493MB written, 9.3s on a
  /// desktop VM with no JS engine running at all.
  ///
  /// One bridge call, one write, one notify.
  Future<int> collectAll(
      List<({Map<String, dynamic> move, String? setupUci})> seeds,
      {int minDepth = 8}) async {
    if (!loaded) await load();
    final data = <Map<String, dynamic>>[];
    for (final s in seeds) {
      final drop = (s.move['wcDrop'] as num?)?.toDouble() ?? 0;
      final depth = (s.move['depth'] as num?)?.toInt() ?? 0;
      if (drop < kCollectMin || depth < minDepth) continue;
      final d = _api.itemData(s.move, s.setupUci);
      if (d != null) data.add(d);
    }
    if (data.isEmpty) return 0;
    final before = items.length;
    final next = _api.addItems(items, data);
    if (next == null) return 0; // every one a duplicate
    items = next;
    await _persist();
    notifyListeners();
    return items.length - before;
  }

  // ---- session ----

  void startSession() {
    // A fresh general session leaves any game scope behind: without this, a
    // scope set weeks ago would still be silently narrowing the queue the next
    // time the tab opened itself onto an empty board.
    gameScope = null;
    sessionSolved = 0;
    sessionStreak = 0;
    _serve(_api.nextItem(_pool, motif: motifFilter, easyFirst: _easeIn));
  }

  /// Practise one reviewed game's own mistakes (#197): restrict the session to
  /// [fens] — that game's blunder positions — and serve the first at once.
  ///
  /// A scope over the LIVE collection, not a snapshot copied out of it: the
  /// items stay the real ones, so passing or failing them moves the real
  /// Leitner boxes and the drill counts toward the same spaced-repetition
  /// schedule as any other. It filters rather than forks — the whole point is
  /// that these positions are already collected, so there is nothing to build.
  void startGameSession(Set<String> fens) {
    gameScope = fens;
    // A game scope is its own filter; stacking a leftover motif on top of it
    // could empty the pool and land the tab on "nothing tagged X" over a game
    // that has plenty.
    motifFilter = null;
    sessionSolved = 0;
    sessionStreak = 0;
    _serve(_api.nextItem(_pool, easyFirst: _easeIn));
  }

  /// Leave the game scope and return to the full queue, serving the next
  /// general puzzle at once — the way out the Practice tab offers while a game
  /// session is running. Counters carry over; it is the same sitting.
  void exitGameSession() {
    if (gameScope == null) return;
    gameScope = null;
    _serve(_api.nextItem(_pool, motif: motifFilter, easyFirst: _easeIn));
  }

  void nextPuzzle() {
    final id = current?['id'] as String?;
    // The exclusion means "don't hand me the same one twice running", not "run
    // out". Under a motif filter down to a single item, honouring it empties
    // the pool and the tab announces there is nothing to practise while
    // holding a puzzle — so fall back to the unexcluded draw.
    final next = _api.nextItem(_pool,
            excludeId: id, motif: motifFilter, easyFirst: _easeIn) ??
        _api.nextItem(_pool, motif: motifFilter, easyFirst: _easeIn);
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
    _serve(_api.nextItem(_pool, motif: motif, easyFirst: _easeIn));
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
    // Serving a scheduler-drawn puzzle leaves any line behind — this is also
    // the cleanup point for a [continueLine] abandoned mid-flight: it captures
    // the generation and returns without touching state once _gen has moved, so
    // continuing/lineDepth/lineNote/_fenAfterAttempt are reset HERE for it.
    continuing = false;
    lineDepth = 0;
    lineNote = null;
    _fenAfterAttempt = null;
    notifyListeners();
  }

  void retry() {
    attempt = null;
    pendingUci = null;
    checking = false;
    // A fresh attempt has not been graded yet, so the position it would
    // continue from is stale — clear it until the next check commits.
    _fenAfterAttempt = null;
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
    // Where a passed attempt can be continued FROM (#143). Set for every graded
    // move, on the puzzle now on screen — the gen guard above has already
    // dropped a verdict that outlived its puzzle, so this only lands for the
    // current one.
    _fenAfterAttempt = fenAfter;

    // Line continuations (lineDepth > 0) are an ephemeral drill of the line, not
    // the collected position — they must not move a Leitner box or count toward
    // session progress. Only the stored puzzle (lineDepth 0) is spaced
    // repetition. (A continuation's synthetic id is not in `items` anyway, so
    // recordResult would no-op — but the session counters would not, so the
    // guard is load-bearing, not belt-and-braces.)
    if (!_resultRecorded && lineDepth == 0) {
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

  /// Keep playing FORWARD from a puzzle you just passed (#143).
  ///
  /// Turns a one-move puzzle into a drill of the line it came from: play the
  /// engine's reply to the move you found, then re-serve the position one move
  /// later as a fresh target, and let you find the next move too. Was app-level
  /// orchestration in the web's `+page.svelte`, never exported from the brain;
  /// every primitive it needs is already here (the arbiter's depth-bounded
  /// search, [GradingApi.winChance], dartchess SAN).
  ///
  /// Off a PASS only — continuing a line from a move that lost is not a drill of
  /// the line, it is compounding the mistake. Two searches run back to back (the
  /// reply, then the next best move), so this holds the SAME stale-verdict guard
  /// [checkAttempt] does: the generation captured on entry is re-checked across
  /// every await, and a Skip / delete / browser pick that serves a different
  /// puzzle mid-flight makes this drop everything rather than land a target on
  /// the wrong board. `_serve` has already reset the continue state for that
  /// abandoned run, so the early return needs no cleanup of its own — exactly
  /// like the checkAttempt guard.
  Future<void> continueLine() async {
    final att = attempt;
    final fromFen = _fenAfterAttempt;
    if (current == null ||
        att == null ||
        !att.pass ||
        checking ||
        continuing ||
        fromFen == null) {
      return;
    }
    final gen = _gen;
    continuing = true;
    lineNote = null;
    notifyListeners();

    Position afterAttempt;
    try {
      afterAttempt = Chess.fromSetup(Setup.parseFen(fromFen));
    } catch (_) {
      // A FEN we cannot parse is not a position to continue — bail cleanly.
      if (gen == _gen) {
        continuing = false;
        notifyListeners();
      }
      return;
    }

    // 1. The opponent's reply to the move just played.
    final replyLines = await _arbiter.search(
      fen: fromFen,
      depth: kLineSearchDepth,
      multiPv: 1,
      movetimeMs: kLineSearchMs,
      priority: SearchPriority.practiceCheck,
    );
    if (gen != _gen) return; // a different puzzle was served mid-flight — drop
    final replyUci = (replyLines != null &&
            replyLines.isNotEmpty &&
            replyLines.first.pv.isNotEmpty)
        ? replyLines.first.pv.first
        : null;
    final replyMove = replyUci == null ? null : NormalMove.fromUci(replyUci);
    if (replyMove == null || !afterAttempt.isLegal(replyMove)) {
      continuing = false;
      notifyListeners();
      return;
    }
    final (_, replySan) = afterAttempt.makeSan(replyMove);
    final afterReply = afterAttempt.playUnchecked(replyMove);

    if (afterReply.isGameOver) {
      // The line ran to its end — no next target to serve. End the drill with a
      // note rather than a puzzle; the tab shows it on the idle banner.
      lineDepth++;
      continuing = false;
      current = null;
      attempt = null;
      pendingUci = null;
      _fenAfterAttempt = null;
      lineNote = 'Line over after $replySan.';
      notifyListeners();
      return;
    }

    // 2. The next target: the best move in the position the reply leaves.
    final targetFen = afterReply.fen;
    final targetLines = await _arbiter.search(
      fen: targetFen,
      depth: kLineSearchDepth,
      multiPv: 1,
      movetimeMs: kLineSearchMs,
      priority: SearchPriority.practiceCheck,
    );
    if (gen != _gen) return;
    final best = (targetLines != null &&
            targetLines.isNotEmpty &&
            targetLines.first.pv.isNotEmpty)
        ? targetLines.first
        : null;
    if (best == null) {
      // The engine gave us nothing to aim at — stop rather than serve a puzzle
      // with no best move.
      continuing = false;
      current = null;
      attempt = null;
      pendingUci = null;
      _fenAfterAttempt = null;
      lineNote = 'Line over after $replySan.';
      notifyListeners();
      return;
    }
    final bestUci = best.pv.first;
    final (_, bestSan) = afterReply.makeSan(NormalMove.fromUci(bestUci));
    // best.score is the side-to-move's perspective, and after the reply it is
    // the player's move again — so it is already the player's eval, matching the
    // `evalBestPawns` a stored item carries and what checkAttempt's best branch
    // reads back. Feed winChance null pawns when it is a mate, as everywhere.
    final wcBest =
        _grading.winChance(best.mate == null ? best.score : null, best.mate);

    // Install the ephemeral target. Bump the generation like [_serve] does so a
    // check still in flight against the previous position is dropped, then swap
    // the board over. The synthetic id is the fen — unique to the position and,
    // not being in `items`, harmless if a stale recordResult ever reached it.
    _gen++;
    lineDepth++;
    current = {
      'id': targetFen,
      'fen': targetFen,
      'bestUci': bestUci,
      'bestSan': bestSan,
      'bestPv': best.pv,
      'motifs': const <String>[],
      'evalBestPawns': best.score,
      'mateBest': best.mate,
      'wcBest': wcBest,
      'drop': 0,
      'playedSan': replySan,
      'lastResult': null,
      'attempts': 0,
      'correct': 0,
    };
    attempt = null;
    pendingUci = null;
    hintTier = 0;
    revealBest = false;
    _resultRecorded = false;
    checking = false;
    continuing = false;
    lineNote = null;
    _fenAfterAttempt = null;
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
      _serve(_api.nextItem(_pool, motif: motifFilter, easyFirst: _easeIn));
    }
    await _persist();
    notifyListeners();
  }
}
