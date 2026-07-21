// Background grading (#170): brings scripts/analyze-chesscom.mts into the app.
//
// A chess.com import (#166), a lichess import without server analysis, or a
// pasted PGN (stores/pgn_import.dart) all land in the archive UNGRADED — moves
// with fenBefore / fenAfter / san / uci / color / ply and a label on none. The
// terminal script fixes this by running Stockfish over every position and
// grading with the app's own import code; most people will never run it. This
// does the same job inside the app, in the background, and seeds practice from
// the blunders it finds — the seeded-blunder half is what made lichess import
// (#134) worth building, and chess.com import does not get it without this.
//
// It reuses the LIVE grade path exactly: [GradingApi.gradeMove] from the
// pre-move lines, then [GradingApi.backfillGrade] from the search of the
// position the move created — the same two calls GameController makes per ply.
// The only thing new here is where the searches come from (a background pass,
// not the live analysis stream) and where the results go (back into the
// archived game, and into practice via [PracticeController.collectAll]).
//
// ---- THE CONSTRAINT: do not spoil live play ----
//
// Background searches run at [SearchPriority.backgroundGrade], the arbiter's
// lowest, so any real search — a bot move, a practice check, a threat probe, an
// analysis — preempts one instantly. That is the floor. On top of it, this
// service refuses to run at all while a real game is on the board: it watches
// the live GameController and pauses the whole pass the moment a game becomes
// active, dropping its in-flight search rather than grinding the battery
// through someone's game. The failure mode being designed against is not
// slowness; it is a live game that stutters or a bot move that waits.
//
// ---- design decisions (the questions #170 asks) ----
//
// WHERE IT RUNS / CHECKPOINTING. A web pass survives only while the tab is
// open, so it must resume, not restart. The checkpoint is per GAME and the
// archive itself is the checkpoint: a game is graded in full and written back
// atomically, or not written at all. A finished game now carries labels, so the
// next sweep skips it ([_needsGrading]); an interrupted one carries none, so the
// next sweep redoes it from scratch — cheap, on a warm transposition table. No
// side-car progress file to keep in step with the archive.
//
// BATTERY / THERMALS ON MOBILE. Automatic, but heavily gated: it runs on launch
// and after each live game ends, never DURING one, always at the lowest
// priority. A charging-only gate or an explicit "grade my imported games"
// button would be gentler still, but the first needs a battery plugin and the
// second needs UI, both out of this change's scope. The service is built to
// take either later without change — [start] is the trigger and the live-game
// pause is automatic — so a button would simply call [start] on demand instead
// of at boot.
//
// OWN MOVES, OR ALL? All moves are graded; only the human's become practice
// seeds. Grading only your own moves would not save the expensive part: to
// grade your move you need the search of the position it created, which is your
// opponent's next pre-move position — and positions chain, so every position is
// searched regardless (~one search per ply). What halving buys is a few cheap
// bridge calls, not engine time, and grading every move also fills the archived
// game's labels, accuracy and best-move arrows for Review.
//
// QUALITY. depth 16 / MultiPV 1 with a movetime backstop — the script's own
// offline setting (300k nodes ≈ depth 16-18, MultiPV 1), whose output "merges
// cleanly and produces practice items", so this quality is already proven
// adequate for grading→practice. Cheaper than live analysis (depth 22 /
// MultiPV 5 / 10s), which is right for a bulk pass and keeps throughput near
// the ~15s/game #170 measured. MultiPV 1 is enough because the played move's
// eval comes from the negated child eval in backfillGrade — the multi-line
// pre-move spread the live board needs for its arrows is not needed to grade.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../brain/grading_api.dart';
import '../brain/types.dart';
import '../db/app_db.dart';
import '../engine/arbiter.dart';
import 'practice_controller.dart';

/// Per-position search budget. See the "QUALITY" note above for why these
/// numbers — the analyze-chesscom.mts defaults, translated to the arbiter's
/// depth+movetime shape.
const int kBgGradeDepth = 16;
const int kBgGradeMultiPv = 1;

/// A backstop for a pathological position, not the routine limit (depth 16 is
/// that): stops the sweep stalling on the one position that will not settle.
const int kBgGradeMovetimeMs = 4000;

class BackgroundGrader {
  final SearchArbiter _arbiter;
  final AppDb _db;
  final GradingApi _grading;
  final PracticeController _practice;

  /// The live game, watched for start/stop, and the one question this service
  /// asks of it. Typed as [Listenable] + a predicate rather than GameController
  /// so this service does not depend on the controller's shape — only on "is a
  /// game being played right now".
  final Listenable _liveGame;
  final bool Function() _isLiveGameActive;

  BackgroundGrader(this._arbiter, this._db, this._grading, this._practice,
      this._liveGame, this._isLiveGameActive);

  bool _started = false;
  bool _paused = false;
  bool _disposed = false;
  bool _passRunning = false;

  /// Games whose moves cannot be graded — empty movetext (chess.com summary
  /// games keep only PGN past the archiver's deep-past window). Skipped for the
  /// life of the process rather than re-scanned every sweep; a relaunch retries
  /// them, finds them still empty, and skips them again, which costs nothing.
  final Set<String> _ungradeable = {};

  /// The current sweep, exposed only so tests can await it.
  Future<void>? _pass;
  @visibleForTesting
  Future<void>? get pass => _pass;

  /// Begin watching the live game and, if none is active, start a sweep. Safe
  /// to call once; a second call is a no-op.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _liveGame.addListener(_onLiveGameChanged);
    _paused = _isLiveGameActive();
    _pump();
  }

  void dispose() {
    _disposed = true;
    if (_started) _liveGame.removeListener(_onLiveGameChanged);
    _arbiter.cancelBackgroundGrades();
  }

  void _onLiveGameChanged() {
    final active = _isLiveGameActive();
    if (active && !_paused) {
      _paused = true;
      // Drop the in-flight search this instant, rather than letting the current
      // position finish: the priority floor already keeps it from delaying the
      // game, and this keeps it from burning the battery through the game.
      _arbiter.cancelBackgroundGrades();
    } else if (!active && _paused) {
      _paused = false;
      _pump();
    }
  }

  void _pump() {
    if (_passRunning || _paused || _disposed) return;
    _passRunning = true;
    _pass = _runPass().then((drained) {
      _passRunning = false;
      // A resume that arrived while the last sweep was unwinding was swallowed
      // by the guard above; if the sweep stopped because it was interrupted
      // (not because the archive is clean), pick it back up.
      if (!drained && !_paused && !_disposed) _pump();
    }, onError: (Object e, StackTrace s) {
      _passRunning = false;
      debugPrint('BackgroundGrader: sweep failed: $e');
    });
  }

  /// One sweep of the archive, newest first. Returns true when it reached the
  /// end with nothing left to grade (drained), false when it stopped early
  /// (paused, disposed, or a search went stale). The archive is read ONCE per
  /// sweep — the same whole-archive read Review already does — not per game.
  Future<bool> _runPass() async {
    final games = await _db.listGames();
    for (final game in games) {
      if (_paused || _disposed) return false;
      final id = game['id'] as String?;
      if (id == null || _ungradeable.contains(id) || !_needsGrading(game)) {
        continue;
      }
      final done = await _gradeGame(game);
      if (!done) return false; // interrupted before this game finished
    }
    return true;
  }

  /// A game worth grading: it has moves, and none is graded. "Graded" is
  /// carrying a `label` — the field [GradingApi.backfillGrade] assigns and every
  /// already-graded path writes (played games; lichess-with-analysis imports,
  /// #134). "No move labelled" rather than "some move unlabelled" is deliberate:
  /// a fully graded game can end on a move with no label (a mate has no lines to
  /// backfill from), so one unlabelled move is a false positive while a whole
  /// game of them is the real thing. Source-agnostic by design (#170): whatever
  /// produced the moves, if none is labelled it needs grading.
  static bool _needsGrading(Map<String, dynamic> game) {
    final moves = game['moves'];
    if (moves is! List || moves.isEmpty) return false;
    for (final m in moves) {
      if (m is Map && m['label'] != null) return false;
    }
    return true;
  }

  /// Grade every move of [game] and seed practice from the human's blunders.
  /// Returns false, having written nothing, if the sweep was interrupted partway
  /// — the game stays ungraded and the next sweep starts it over. This per-GAME
  /// atomicity IS the checkpoint (#170): a finished game is written back and
  /// skipped forever after; an interrupted one is never left half-written.
  Future<bool> _gradeGame(Map<String, dynamic> game) async {
    final id = game['id'] as String;
    final rawMoves = (game['moves'] as List)
        .map((m) => (m as Map).cast<String, dynamic>())
        .toList();
    if (rawMoves.isEmpty) {
      _ungradeable.add(id);
      return false;
    }

    // Consecutive positions chain: the child search of move N (the position it
    // created) IS the pre-move search of move N+1. So each position is searched
    // ONCE and reused as both — ~one search per ply, the ~15s/game #170
    // measured — rather than twice.
    var pre = await _search(rawMoves.first['fenBefore'] as String);
    if (pre == null) return false;

    final human = _humanColor(game);
    final graded = <Map<String, dynamic>>[];
    final seeds = <({Map<String, dynamic> move, String? setupUci})>[];

    for (var i = 0; i < rawMoves.length; i++) {
      if (_paused || _disposed) return false;
      final m = rawMoves[i];
      final child = await _search(m['fenAfter'] as String);
      if (child == null) return false;

      final grade = _grading.backfillGrade(
        _grading.gradeMove(
          ply: m['ply'] as int,
          fenBefore: m['fenBefore'] as String,
          san: m['san'] as String,
          uci: m['uci'] as String,
          color: m['color'] as String,
          preLines: pre!,
        ),
        child,
      );
      final storedMove = _withGrade(m, grade);
      graded.add(storedMove);

      // Practice only ever drills YOUR mistakes, so only the human's moves
      // become seeds; the opponent's moves are graded purely so the next
      // position has its pre-move lines — which the chain above did for free.
      // collectAll applies the collect threshold and dedupes on fen.
      if (human != null && m['color'] == human) {
        seeds.add((
          move: storedMove,
          // the opponent's move INTO this position (the preceding ply), for the
          // drill's replay — same as GameController's `moves[record.ply - 2]`
          // (ply is 1-based there; here i is 0-based) and the lichess importer's
          // `moves[i - 1]`
          setupUci: i >= 1 ? rawMoves[i - 1]['uci'] as String? : null,
        ));
      }

      pre = child; // chain into the next ply
    }

    final updated = <String, dynamic>{
      ...game,
      'moves': graded,
      'whiteAccuracy': _grading.gameAccuracy(graded, 'w'),
      'blackAccuracy': _grading.gameAccuracy(graded, 'b'),
      'labelCounts': {
        'w': _grading.labelCounts(graded, 'w'),
        'b': _grading.labelCounts(graded, 'b'),
      },
      'labelVersion': 1,
    };

    // Seed BEFORE the write, so a crash between the two leaves the game
    // ungraded (re-graded next sweep) rather than graded-but-uncollected (its
    // blunders lost). collectAll dedupes on fen, so the redo double-collects
    // nothing. One bridge round trip for the whole game, not one per seed —
    // the per-seed loop was a measured 986MB-of-expression bug.
    if (seeds.isNotEmpty) await _practice.collectAll(seeds);
    await _db.saveGame(updated);
    return true;
  }

  /// One background-priority search, or null when it must be abandoned: the
  /// sweep was paused/disposed (its in-flight search cancelled), or the arbiter
  /// went stale (a new game bumped the generation), or the engine never booted.
  /// A completed search is trusted at whatever depth it reached — a
  /// [kBgGradeMovetimeMs] backstop caps the rare position rather than stalling.
  Future<List<EngineMove>?> _search(String fen) async {
    final lines = await _arbiter.search(
      fen: fen,
      depth: kBgGradeDepth,
      multiPv: kBgGradeMultiPv,
      movetimeMs: kBgGradeMovetimeMs,
      priority: SearchPriority.backgroundGrade,
    );
    if (_paused || _disposed) return null; // our in-flight search was cancelled
    if (lines == null || lines.isEmpty) return null; // stale, or no engine
    return lines;
  }

  /// Fold a fresh [g] into the stored move, matching
  /// GameController._storedMoveOf field for field so a background-graded game is
  /// indistinguishable from a played one downstream (Review, accuracy,
  /// practice). ply / san / uci / color / fenBefore / fenAfter pass through.
  Map<String, dynamic> _withGrade(Map<String, dynamic> move, MoveGrade g) {
    // A copy of GameController._wcDrop, kept identical on purpose: the collector
    // filters on this number and the review card prints it, and two formulas
    // for "how much win% the move gave away" would drift.
    final wcDrop = (_grading.winChance(g.bestEval, g.bestMate) -
            _grading.winChance(g.evalPawns, g.mate))
        .clamp(0.0, 100.0);
    return {
      ...move,
      'evalPawns': g.evalPawns,
      'mate': g.mate,
      'pctBest': g.pctBest,
      'wcDrop': wcDrop,
      'depth': g.depth,
      if (g.label != null) 'label': g.label,
      'bestSan': g.bestSan,
      'bestUci': g.bestUci,
      if (g.explanation != null) 'explanation': g.explanation!.raw,
    };
  }

  /// The side the human played, or null when the record does not say (a pasted
  /// PGN names no "you"). botColor is "the side the human did NOT play"
  /// (gameStore.ts), which the import paths set from the importing username, so
  /// the human is its opposite. With no human, the game is still graded — Review
  /// gets its labels and accuracy — but nothing is seeded, since practice only
  /// holds YOUR mistakes.
  static String? _humanColor(Map<String, dynamic> game) {
    switch (game['botColor']) {
      case 'w':
        return 'b';
      case 'b':
        return 'w';
      default:
        return null;
    }
  }
}
