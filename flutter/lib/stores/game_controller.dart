// The live game: position, bot reply loop, and the grading pipeline —
// the Dart translation of +page.svelte's orchestration, same semantics:
//
//   gradeMove(pre-move analysis lines) → backfillGrade(post-move analysis)
//
// One depth-22/3000ms MultiPV-5 analysis per reached position (the arbiter's
// `analysis` priority); the "pre" lines of a move are the "post" analysis of
// the previous one, cached by FEN. Bot searches run at `botMove` priority
// and preempt analysis, so replies stay snappy.

import 'dart:async';
import 'dart:math';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../brain/bot_api.dart';
import '../brain/chess_api.dart';
import '../brain/grading_api.dart';
import '../brain/types.dart';
import '../db/app_db.dart';
import '../engine/arbiter.dart';
import 'lines_tree_model.dart';
import 'practice_controller.dart';
import 'redo_stack.dart';
import 'settings_store.dart';

/// How long archiving a finished game waits for in-flight grading.
///
/// Must stay comfortably ABOVE [kAnalysisMovetimeMs]: a grade pipeline awaits
/// the analysis of the position after its move, so the slowest grade cannot
/// land sooner than the slowest analysis. Set below it, and finishing a game
/// during a deep search would archive it without its closing labels — silently,
/// since the wait times out rather than failing.
const int kSaveGradeWaitSeconds = 16;

class MoveRecord {
  final int ply; // 1-based, like the web
  final String san;
  final String uci;
  final String color; // 'w' | 'b' — who moved
  final String fenBefore;
  final String fenAfter;
  MoveGrade? grade;

  MoveRecord({
    required this.ply,
    required this.san,
    required this.uci,
    required this.color,
    required this.fenBefore,
    required this.fenAfter,
  });
}

class GameController extends ChangeNotifier {
  final SearchArbiter _arbiter;
  final BotApi _bot;
  final GradingApi _grading;
  final SettingsStore _settings;
  final AppDb? _db;
  final PracticeController? _practice;
  ChessApi? _chess;

  Position position = Chess.initial;
  Move? lastMove;
  final List<MoveRecord> moves = [];
  bool botThinking = false;
  String gameSeed = _newSeed();
  Persona? persona;
  bool _saved = false;

  // analysis cache: fen → future of its MultiPV-5 deep lines
  final Map<String, Future<List<EngineMove>?>> _analysis = {};
  // the deepest streamed snapshot per fen — grading falls back to these when
  // an analysis was cancelled because the board moved on
  final Map<String, List<EngineMove>> _partials = {};
  // grade pipelines still in flight — save waits for them (bounded)
  final Set<Future<void>> _pendingGrades = {};
  int _gen = 0;

  GameController(this._arbiter, this._bot, this._grading, this._settings,
      [this._db, this._practice, ChessApi? chessApi]) {
    _chess = chessApi;
    if (chessApi != null) linesTree = LinesTreeModel(chessApi);
    persona = _bot.personaById(_settings.personaId) ?? _bot.personas().first;
    _settings.addListener(_onSettings);
    _analysisFor(position.fen);
    _maybeBotTurn();
  }

  static String _newSeed() => 'm${Random().nextInt(1 << 30)}';

  String get playerColor => _settings.playerColor;
  bool get botEnabled => _settings.botEnabled;
  List<Persona> get rosterPersonas => _bot.personas();
  bool get isPlayerTurn =>
      !botEnabled || (position.turn == Side.white ? 'w' : 'b') == playerColor;
  bool get gameOver => position.isGameOver;

  String get statusLine {
    if (position.isCheckmate) {
      final winner = position.turn == Side.white ? 'Black' : 'White';
      return 'Checkmate — $winner wins';
    }
    if (position.isStalemate) return 'Stalemate';
    if (position.isInsufficientMaterial) return 'Draw — insufficient material';
    if (!botEnabled) {
      return 'Analysis — ${position.turn == Side.white ? "White" : "Black"} to move';
    }
    // a dead engine used to show the boot-error screen; boot no longer waits
    // for it, so without this the symptom is a board whose bot never moves
    if (_arbiter.engineError != null) return 'Engine unavailable — no analysis';
    if (botThinking) return '${persona?.name ?? "Bot"} is thinking…';
    return isPlayerTurn ? 'Your move' : '${persona?.name ?? "Bot"} to move';
  }

  /// The grade shown in the strip/insight card: the player's latest move —
  /// or, on the analysis board, simply the latest move of either side.
  MoveGrade? get lastPlayerGrade {
    for (var i = moves.length - 1; i >= 0; i--) {
      if (!botEnabled || moves[i].color == playerColor) return moves[i].grade;
    }
    return null;
  }

  String _settingsSig() =>
      '${_settings.personaId}|${_settings.playerColor}|${_settings.botEnabled}';
  late String _lastSettingsSig = _settingsSig();

  void _onSettings() {
    final sig = _settingsSig();
    if (sig == _lastSettingsSig) {
      // Only the overlay switches need a fresh probe. Colour pickers and
      // opacity sliders notify on every drag frame, and re-probing there
      // queued dozens of engine searches ahead of the position's analysis.
      final overlaySig = '${_settings.showThreats}|${_settings.blind}';
      if (overlaySig != _lastOverlaySig) {
        _lastOverlaySig = overlaySig;
        _probeThreat();
      }
      notifyListeners();
      return;
    }
    _lastSettingsSig = sig;
    persona = _bot.personaById(_settings.personaId) ?? persona;
    newGame();
  }

  // ---- game actions ----

  void newGame() {
    _browsePly = null;
    _redoStack.clear();
    _gen++;
    _arbiter.bumpGeneration();
    position = Chess.initial;
    lastMove = null;
    moves.clear();
    botThinking = false;
    _saved = false;
    gameSeed = _newSeed();
    _analysis.clear();
    _partials.clear();
    _controlCache.clear(); // per-fen maps would accrete for the process life
    _threat = null;
    _analysisFor(position.fen);
    _syncTree(); // playedSans is empty → the model wipes itself
    _probeThreat();
    notifyListeners();
    _maybeBotTurn();
  }

  /// Moves taken off by undo, in game order, so redo can put them back
  /// exactly as they were — including their grades, which cost engine time
  /// to earn. Any new move discards them (see _apply).
  final RedoStack _redoStack = RedoStack();

  bool get canUndo =>
      !botThinking &&
      (botEnabled
          ? moves.any((m) => m.color == playerColor)
          : moves.isNotEmpty);
  bool get canRedo => _redoStack.isNotEmpty && !botThinking;

  /// Undo the last player move (and the bot reply on top of it);
  /// on the analysis board, one ply at a time.
  void undo() {
    _browsePly = null;
    if (moves.isEmpty || botThinking) return;
    // in a bot game there must be a player move to take back: undoing the
    // bot's lone opening move would leave the bot on turn with input dead
    if (botEnabled && !moves.any((m) => m.color == playerColor)) return;
    _gen++;
    _arbiter.bumpGeneration();
    final undone = <MoveRecord>[];
    if (botEnabled) {
      while (moves.isNotEmpty && moves.last.color != playerColor) {
        undone.add(moves.removeLast());
      }
      if (moves.isNotEmpty) undone.add(moves.removeLast());
    } else {
      undone.add(moves.removeLast());
    }
    // prepended: this batch is OLDER than anything a previous undo stored
    _redoStack.pushUndone(undone);
    final fen = moves.isEmpty ? Chess.initial.fen : moves.last.fenAfter;
    position = Chess.fromSetup(Setup.parseFen(fen));
    lastMove =
        moves.isEmpty ? null : NormalMove.fromUci(moves.last.uci);
    _saved = false; // a re-finished game is a new game to archive
    _threat = null;
    _analysisFor(position.fen);
    _syncTree();
    _probeThreat();
    notifyListeners();
    _maybeBotTurn(); // safety: never leave the bot on turn (no-op otherwise)
  }

  /// Put back what undo took off. Replays the stored moves rather than
  /// re-deriving them, so the grades and explanations come back intact
  /// instead of being recomputed — or lost.
  void redo() {
    _browsePly = null;
    if (_redoStack.isEmpty || botThinking) return;
    _gen++;
    _arbiter.bumpGeneration();
    // one undo's worth: the player move and the bot's reply that sat on it
    moves.addAll(_redoStack.takeBatch(
        botEnabled: botEnabled, playerColor: playerColor));
    position = Chess.fromSetup(Setup.parseFen(moves.last.fenAfter));
    lastMove = NormalMove.fromUci(moves.last.uci);
    _threat = null;
    _analysisFor(position.fen);
    _syncTree();
    _probeThreat();
    notifyListeners();
  }

  /// The human plays a move (already validated by the board).
  void playerMove(NormalMove move, String san) {
    if (!isPlayerTurn || botThinking || gameOver) return;
    _apply(move, san);
    _maybeBotTurn();
  }

  /// Play a uci directly (tree/lines tap) — same rules as a board move.
  void playUci(String uci) {
    if (!isPlayerTurn || botThinking || gameOver) return;
    final move = NormalMove.fromUci(uci);
    if (!position.isLegal(move)) return;
    final (_, san) = position.makeSan(move);
    playerMove(move, san);
  }

  // ---- internals ----

  void _apply(NormalMove move, String san) {
    stopPreview();
    // a new move makes the undone future unreachable — without this, redo
    // after a divergent move replayed a stale record onto the wrong position
    _redoStack.clear();
    final fenBefore = position.fen;
    position = position.playUnchecked(move);
    lastMove = move;
    final record = MoveRecord(
      ply: moves.length + 1,
      san: san,
      uci: move.uci,
      color: position.turn == Side.white ? 'b' : 'w',
      fenBefore: fenBefore,
      fenAfter: position.fen,
    );
    moves.add(record);
    _syncTree(); // extend the played path (and prune the old anchor's churn)
    notifyListeners();
    // the board moved on: older analyses wrap up at depth 12 and yield the
    // engine — only the current position gets the full budget (web semantic;
    // without this a fast game builds a 3s-per-ply backlog)
    _arbiter.cancelAnalyses(exceptFen: position.fen);
    // post-analysis = next move's pre-lines; streamed partials backfill this
    // move's grade the moment the child search passes depth 10 (web parity —
    // the label shouldn't wait out the full 3s budget)
    final gen = _gen;
    _analysisFor(position.fen,
        onUpdate: (lines) => _earlyBackfill(record, lines, gen));
    _probeThreat();
    late final Future<void> pipeline;
    pipeline = _gradePipeline(record, _gen)
      ..whenComplete(() => _pendingGrades.remove(pipeline));
    _pendingGrades.add(pipeline);
    if (gameOver) _saveGame();
  }

  void _earlyBackfill(MoveRecord record, List<EngineMove> lines, int gen) {
    if (gen != _gen || lines.isEmpty || lines.first.depth < 10) return;
    final grade = record.grade;
    if (grade == null || grade.backfilled) return;
    record.grade = _grading.backfillGrade(grade, lines);
    notifyListeners();
  }

  /// Debug/self-test only: archive the game regardless of game-over state.
  Future<void> debugForceSave() => _saveGame();

  String get _result {
    if (position.isCheckmate) {
      return position.turn == Side.white ? '0-1' : '1-0';
    }
    if (position.isGameOver) return '1/2-1/2';
    return '*';
  }

  /// Archive the finished game — the web's saveCurrentGame, same StoredGame
  /// shape (JSON-compatible with the IndexedDB store for future import).
  Future<void> _saveGame() async {
    final db = _db;
    if (db == null || moves.isEmpty || _saved) return;
    _saved = true;
    // Snapshot the finished game BEFORE the wait below. The wait can run for
    // seconds, and an undo during it would otherwise archive a truncated game
    // with a result that no longer matches. The records themselves are safe to
    // hold: grading fills them in place (which is what we are waiting for) and
    // undo only removes them from the list.
    final played = List<MoveRecord>.of(moves);
    final p = botEnabled ? persona : null;
    final result = _result;
    final botName = p == null ? 'Analysis' : '${p.name} (${p.elo})';
    final youAreWhite = playerColor == 'w';

    // let in-flight grading land so the archive gets labels (bounded — the
    // terminal move's backfill may never come: a mate position has no lines)
    if (_pendingGrades.isNotEmpty) {
      await Future.wait(_pendingGrades.toList())
          .timeout(const Duration(seconds: kSaveGradeWaitSeconds),
              onTimeout: () => []);
    }

    final stored = played.map(_storedMoveOf).toList();

    final record = {
      'id': 'g-${DateTime.now().millisecondsSinceEpoch}-${played.length}',
      'endedAt': DateTime.now().toIso8601String(),
      'result': result,
      'pgn': _pgn(played, result, botName, youAreWhite),
      'botElo': p == null ? null : p.elo + 240, // internal scale (SCALE_OFFSET)
      if (p != null) 'botPersona': p.id,
      'botColor': p == null ? null : (playerColor == 'w' ? 'b' : 'w'),
      'moveCount': played.length,
      'whiteAccuracy': _bridgeAccuracy(stored, 'w'),
      'blackAccuracy': _bridgeAccuracy(stored, 'b'),
      'labelCounts': {
        'w': _grading.labelCounts(stored, 'w'),
        'b': _grading.labelCounts(stored, 'b'),
      },
      'labelVersion': 1,
      'moves': stored,
    };
    await db.saveGame(record);
  }

  double? _bridgeAccuracy(List<Map<String, dynamic>> stored, String color) =>
      _grading.gameAccuracy(stored, color);

  String _pgn(List<MoveRecord> played, String result, String botName,
      bool youAreWhite) {
    final white = youAreWhite ? 'You' : botName;
    final black = youAreWhite ? botName : 'You';
    final date =
        DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '.');
    final sb = StringBuffer()
      ..writeln('[White "$white"]')
      ..writeln('[Black "$black"]')
      ..writeln('[Date "$date"]')
      ..writeln('[Result "$result"]')
      ..writeln();
    for (var i = 0; i < played.length; i++) {
      if (i.isEven) sb.write('${i ~/ 2 + 1}. ');
      sb.write('${played[i].san} ');
    }
    sb.write(result);
    return sb.toString();
  }

  Future<void> _maybeBotTurn() async {
    if (!botEnabled || isPlayerTurn || gameOver || botThinking) return;
    final p = persona;
    if (p == null) return;
    botThinking = true;
    notifyListeners();
    final gen = _gen;
    // let the analysis of the player's move reach depth 10 before the bot's
    // reply search preempts it — the player's grade label lands in <1s and
    // the bot pausing a beat before answering reads human anyway
    final graded = position.fen;
    final sprintStart = DateTime.now();
    while (gen == _gen &&
        (_partials[graded]?.firstOrNull?.depth ?? 0) < 10 &&
        DateTime.now().difference(sprintStart).inMilliseconds < 1500) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (gen != _gen) {
      botThinking = false;
      notifyListeners();
      return;
    }
    try {
      final uci = await _pickBotMove(p);
      if (gen != _gen || uci == null) return;
      final move = NormalMove.fromUci(uci);
      if (!position.isLegal(move)) return;
      final san = _sanOf(position, move);
      _apply(move, san);
    } catch (e, st) {
      // Every call site here is fire-and-forget and the app installs no
      // zone guard, so without this an exception — a bridge StateError, a
      // dead engine — becomes an unhandled async error and leaves the board
      // silently dead: bot on turn, nothing thinking, input refused. Contained
      // here it is at least logged, and undo still recovers (it hands the turn
      // back, so this method returns early rather than retrying the failure).
      debugPrint('[bot] move selection failed: $e\n$st');
    } finally {
      if (gen == _gen) {
        botThinking = false;
        notifyListeners();
      }
    }
  }

  Future<String?> _pickBotMove(Persona p) async {
    final fen = position.fen;
    if (p.family == 'square') {
      final label = p.shapedLabel!;
      final lines = await _arbiter.search(
        fen: fen,
        depth: _bot.shapedSearchDepth(label),
        multiPv: kBotMultiPv,
        priority: SearchPriority.botMove,
      );
      if (lines == null || lines.isEmpty) return null;
      final lastTo =
          lastMove is NormalMove ? (lastMove as NormalMove).uci.substring(2, 4) : null;
      final pick = _bot.shapedMove(
            lines: lines,
            label: label,
            seed: gameSeed,
            fen: fen,
            lastMoveTo: lastTo,
          ) ??
          lines.first.uci;
      return _bot.avoidRepetition(pick, _fenHistory(), lines);
    }
    if (p.family == 'horizon') {
      // no engine search at all — js-chess-engine runs inside the JS runtime
      // that is already loaded, and answers in ~2-5ms. avoidRepetition gets
      // the app's own analysis lines (what repetition.ts documents wanting):
      // this branch is synchronous throughout, so they describe THIS position,
      // and an empty list degrades to returning the move unchanged.
      final uci = _bot.horizonMove(fen, p.jsceLevel ?? 1);
      if (uci != null) {
        return _bot.avoidRepetition(uci, _fenHistory(), currentLines);
      }
      debugPrint('[bot] horizon had no move; falling back to the engine');
    }
    // Fish, and the fallback for anything that could not answer for itself.
    // internalElo rather than numericElo: only fish carries numericElo, and a
    // family without an implementation here should play at its own rating
    // rather than crash on a null.
    //
    // This IS the "different opponent wearing the persona's name" that
    // roster_picker refuses to offer, and the two are complementary rather
    // than contradictory: the picker gates unimplemented families so a player
    // can never CHOOSE one, and this is the safety net for an id that arrives
    // some other way — a stored personaId from an older build, or from the
    // web, where the roster is larger. A stand-in beats the alternative here,
    // which used to be `p.numericElo!` throwing and wedging the bot's turn.
    //
    // It is not free, though: on the web the substitution is surfaced, because
    // grading a game against the rating you THINK you played corrupts the
    // player-rating fit. Flutter does not fit a rating yet; when it does, this
    // is the branch that has to tell it.
    final internalElo = p.numericElo ?? _bot.internalElo(p);
    final spec = _bot.botSpec(internalElo);
    switch (spec['kind'] as String) {
      case 'sampler':
        final lines = await _arbiter.search(
          fen: fen,
          depth: (spec['depth'] as num).toInt(),
          multiPv: 24,
          priority: SearchPriority.botMove,
        );
        if (lines == null || lines.isEmpty) return null;
        final pick = _bot.fishMove(
              lines: lines,
              internalElo: internalElo,
              alpha: (spec['alpha'] as num?)?.toDouble(),
            ) ??
            lines.first.uci;
        return _bot.avoidRepetition(pick, _fenHistory(), lines);
      case 'skill':
        final lines = await _arbiter.search(
          fen: fen,
          depth: (spec['depth'] as num).toInt(),
          multiPv: 1,
          extraOptions: [
            ['Skill Level', '${spec['level']}'],
          ],
          priority: SearchPriority.botMove,
        );
        return lines?.isNotEmpty == true ? lines!.first.uci : null;
      default: // ucielo
        final lines = await _arbiter.search(
          fen: fen,
          depth: 0,
          multiPv: 1,
          movetimeMs: (spec['movetimeMs'] as num).toInt(),
          extraOptions: [
            ['UCI_LimitStrength', 'true'],
            ['UCI_Elo', '${spec['elo']}'],
          ],
          priority: SearchPriority.botMove,
        );
        return lines?.isNotEmpty == true ? lines!.first.uci : null;
    }
  }

  /// The engine's live view of the current position (deepest streamed
  /// snapshot) — feeds the Lines pane as the search deepens.
  List<EngineMove> get currentLines => _partials[position.fen] ?? const [];

  bool get blind => _settings.blind;

  /// What the panes may show: nothing forward-looking in blind mode during
  /// a live bot game (web: visibleLines).
  List<EngineMove> get visibleLines =>
      blind && botEnabled ? const [] : currentLines;

  // ---- overlays: opponent threat (null-move probe) + square control ----

  Map<String, dynamic>? _threat; // {fen, uci, san, gain} — fen-gated
  final Map<String, Map<String, String>> _controlCache = {};

  /// Top engine moves for the board's green arrows (web: top-3, fading).
  List<String> get engineArrowUcis {
    if (!_settings.showArrows || blind) return const [];
    return [for (final l in currentLines.take(_settings.arrowCount)) l.uci];
  }

  /// The live threat, when it is fresh and wanted — the move the opponent
  /// would play with a free move, and what it nets them.
  Map<String, dynamic>? get threat {
    if (!_settings.showThreats || blind) return null;
    final t = _threat;
    return t != null && t['fen'] == position.fen ? t : null;
  }

  /// The threat arrow's uci.
  String? get threatUci => threat?['uci'] as String?;

  /// The threat in algebraic notation, e.g. 'Be6'.
  String? get threatSan => threat?['san'] as String?;

  /// What the threat nets them, in pawns. NULL MEANS MATE: the brain reports
  /// Infinity there and JSON has no way to carry it across the bridge.
  double? get threatGain => (threat?['gain'] as num?)?.toDouble();

  /// Current squares of the pieces the threat wins (the mated king for a
  /// mate): attacked by the threat move THIS INSTANT, and lost even under
  /// best defense in the line. A forked queen that escapes is neither.
  List<String> get threatTargets =>
      ((threat?['targets'] as List?) ?? const []).cast<String>();

  // the green mirror: memoised per (fen, top line) — the judge is a pure
  // bridge call, cheap but not free, and this getter runs on every rebuild
  Map<String, dynamic>? _winCache;
  String? _winKey;

  /// What the side to move's OWN top line wins — judged by the same rules as
  /// the threat (attacked after ply 1, falls in the window, no even trades).
  /// Costs no engine time: the line is the live analysis already streaming.
  Map<String, dynamic>? get tacticalWin {
    if (!_settings.showThreats || blind) return null;
    // in a bot game, "your line" only exists on YOUR turn — during the bot's
    // think the streamed lines are ITS tactics, and green rings for them
    // would invert the overlay's meaning (your own king ringed "win")
    if (botEnabled && !isPlayerTurn) return null;
    final chess = _chess;
    if (chess == null) return null;
    final lines = currentLines;
    if (lines.isEmpty) return null;
    // mate is load-bearing: an unchanged pv can convert cp→mate as the
    // search deepens, and the judgment flips with it
    final key = '${position.fen}|${lines.first.mate}|${lines.first.pv.join(' ')}';
    if (_winKey != key) {
      _winKey = key;
      _winCache = chess.judgeTacticalWin(position.fen, {
        'pv': lines.first.pv,
        'mate': lines.first.mate,
      });
    }
    return _winCache;
  }

  /// Current squares of the pieces YOUR top line wins (the enemy king for a
  /// mate) — drawn as green rings in the engine-arrow grammar.
  List<String> get winTargets =>
      ((tacticalWin?['targets'] as List?) ?? const []).cast<String>();

  /// Square-control tint for the current position, when wanted.
  Map<String, String>? get controlMap {
    if (!_settings.showControl || blind) return null;
    final chess = _chess;
    if (chess == null) return null;
    return _controlCache.putIfAbsent(
        position.fen, () => chess.controlSquares(position.fen));
  }

  String? _lastOverlaySig;
  String? _probeInFlightFen; // one probe per position, never a queue of them

  Future<void> _probeThreat() async {
    final chess = _chess;
    if (chess == null || !_settings.showThreats || blind) return;
    final fen = position.fen;
    if (_probeInFlightFen == fen) return;
    final probe = chess.threatProbeFen(fen);
    if (probe == null) {
      _threat = null;
      return;
    }
    final gen = _gen;
    _probeInFlightFen = fen;
    List<EngineMove>? lines;
    try {
      lines = await _arbiter.search(
        fen: probe,
        ownerFen: fen, // stale when the BOARD moves on, not the probe position
        depth: 14,
        multiPv: 1,
        movetimeMs: 500,
        priority: SearchPriority.threatProbe,
      );
    } catch (_) {
      lines = null; // an engine error must not wedge the in-flight flag
    } finally {
      if (_probeInFlightFen == fen) _probeInFlightFen = null;
    }
    if (gen != _gen || lines == null || lines.isEmpty) return;
    _threat = chess.judgeThreat(fen, {
      'pv': lines.first.pv,
      'mate': lines.first.mate,
    });
    if (position.fen == fen) notifyListeners();
  }

  // ---- view-only navigation ----
  //
  // Browsing and flipping never touch the game: the moves list, the engine
  // and the grading pipeline all carry on against the live position. Only
  // what the board draws changes.

  /// Plies into the game, or null when following the live position.
  /// 0 is the starting position, k is the position after moves[k-1].
  int? _browsePly;
  bool _flipped = false;

  bool get browsing => _browsePly != null;
  bool get flipped => _flipped;

  String? get browseFen {
    final p = _browsePly;
    if (p == null) return null;
    return p == 0 ? Chess.initial.fen : moves[p - 1].fenAfter;
  }

  NormalMove? get browseLastMove {
    final p = _browsePly;
    if (p == null || p == 0) return null;
    return NormalMove.fromUci(moves[p - 1].uci);
  }

  /// Where the cursor sits, for a move list to highlight.
  int get browsePly => _browsePly ?? moves.length;

  void toggleFlip() {
    _flipped = !_flipped;
    notifyListeners();
  }

  /// Steps the cursor; stepping past the last move returns to live.
  void browseBy(int delta) {
    if (moves.isEmpty) return;
    final next = (browsePly + delta).clamp(0, moves.length);
    _browsePly = next == moves.length ? null : next;
    notifyListeners();
  }

  void browseTo(int ply) {
    if (moves.isEmpty) return;
    final next = ply.clamp(0, moves.length);
    _browsePly = next == moves.length ? null : next;
    notifyListeners();
  }

  /// Back to the live position — also the escape hatch from a preview.
  void browseLive() {
    if (previewing) stopPreview();
    if (_browsePly == null) return;
    _browsePly = null;
    notifyListeners();
  }

  /// The game-long exploration map (null until wired with a ChessApi).
  LinesTreeModel? linesTree;

  void _syncTree() {
    linesTree?.ingest(
      lines: currentLines,
      fen: position.fen,
      playedSans: moves.map((m) => m.san).toList(),
      height: 300,
    );
  }

  Future<List<EngineMove>?> _analysisFor(String fen,
      {void Function(List<EngineMove>)? onUpdate}) {
    return _analysis.putIfAbsent(
        fen,
        () => _arbiter.analysis(fen, onUpdate: (lines) {
              _partials[fen] = lines;
              if (fen == position.fen) {
                _syncTree();
                notifyListeners();
              }
              onUpdate?.call(lines);
            }));
  }

  /// White-POV win chance per graded ply — the chart's data.
  List<({int ply, String san, double wc, String? label})> get chartPoints => [
        for (final m in moves)
          if (m.grade != null)
            (
              ply: m.ply,
              san: m.san,
              wc: _grading.whitePovWinChance(
                  m.color, m.grade!.evalPawns, m.grade!.mate),
              label: m.grade!.label,
            )
      ];

  // ---- line preview: animate an explanation's line on the main board ----

  List<String> _previewFens = [];
  List<NormalMove?> _previewMoves = [];
  int _previewIndex = 0;
  Timer? _previewTimer;

  bool get previewing => _previewTimer != null;
  String? get previewFen =>
      previewing ? _previewFens[_previewIndex] : null;
  NormalMove? get previewLastMove =>
      previewing ? _previewMoves[_previewIndex] : null;

  /// Plays [ucis] out from [baseFen] on the board, one move per beat,
  /// then returns to the live position. Tap again to stop early.
  void startPreview(String baseFen, List<String> ucis) {
    _browsePly = null; // the board prefers browseFen; an unseen preview is a dead key
    stopPreview();
    Position pos;
    try {
      pos = Chess.fromSetup(Setup.parseFen(baseFen));
    } catch (_) {
      return;
    }
    final fens = <String>[baseFen];
    final lastMoves = <NormalMove?>[null];
    for (final uci in ucis) {
      final m = NormalMove.fromUci(uci);
      if (!pos.isLegal(m)) break;
      pos = pos.playUnchecked(m);
      fens.add(pos.fen);
      lastMoves.add(m);
    }
    if (fens.length < 2) return;
    _previewFens = fens;
    _previewMoves = lastMoves;
    _previewIndex = 0;
    _previewTimer = Timer.periodic(const Duration(milliseconds: 850), (t) {
      if (_previewIndex >= _previewFens.length - 1) {
        // linger on the final position for a beat, then come home
        t.cancel();
        _previewTimer = Timer(const Duration(milliseconds: 1200), stopPreview);
        return;
      }
      _previewIndex++;
      notifyListeners();
    });
    notifyListeners();
  }

  void stopPreview() {
    if (_previewTimer == null) return;
    _previewTimer?.cancel();
    _previewTimer = null;
    notifyListeners();
  }

  Future<void> _gradePipeline(MoveRecord record, int gen) async {
    final t0 = DateTime.now();
    void log(String msg) => debugPrint(
        'grade[${record.ply} ${record.san}] +${DateTime.now().difference(t0).inMilliseconds}ms $msg');
    // pre-lines: the completed (or cancelled-with-partials) analysis of the
    // position the move was played from, falling back to streamed partials
    var pre = await _analysisFor(record.fenBefore);
    final preFromFuture = pre != null && pre.isNotEmpty;
    if (pre == null || pre.isEmpty) pre = _partials[record.fenBefore];
    log('pre: ${preFromFuture ? "future" : "partials"} '
        'depth=${pre?.firstOrNull?.depth} lines=${pre?.length}');
    if (gen != _gen || pre == null || pre.isEmpty) {
      log('ABORT: no pre-lines');
      return;
    }
    var grade = _grading.gradeMove(
      ply: record.ply,
      fenBefore: record.fenBefore,
      san: record.san,
      uci: record.uci,
      color: record.color,
      preLines: pre,
    );
    record.grade = grade;
    notifyListeners();
    log('graded (rank=${grade.rank})');
    // the child search may already have streamed past depth 10 while we
    // waited on the pre-lines — backfill from the snapshot immediately
    final snap = _partials[record.fenAfter];
    if (snap != null) _earlyBackfill(record, snap, gen);
    if (record.grade?.backfilled == true) log('early backfill from snapshot');

    var child = await _analysisFor(record.fenAfter);
    final childFromFuture = child != null && child.isNotEmpty;
    if (child == null || child.isEmpty) child = _partials[record.fenAfter];
    log('child: ${childFromFuture ? "future" : "partials"} '
        'depth=${child?.firstOrNull?.depth}');
    if (gen != _gen ||
        child == null ||
        child.isEmpty ||
        child.first.depth < 10) {
      log('ABORT: no usable child (label=${record.grade?.label})');
      return;
    }
    record.grade = _grading.backfillGrade(record.grade ?? grade, child);
    notifyListeners();
    log('backfilled label=${record.grade?.label}');

    // auto-collect big mistakes as practice puzzles (web maybeCollect)
    final practice = _practice;
    if (practice != null) {
      final prevUci =
          record.ply >= 2 ? moves[record.ply - 2].uci : null;
      await practice.maybeCollect(_storedMoveOf(record),
          setupUci: prevUci);
    }
  }

  Map<String, dynamic> _storedMoveOf(MoveRecord m) {
    final g = m.grade;
    final wcDrop = g == null
        ? 0.0
        : (_grading.winChance(g.bestEval, g.bestMate) -
                _grading.winChance(g.evalPawns, g.mate))
            .clamp(0.0, 100.0);
    return {
      'ply': m.ply,
      'san': m.san,
      'uci': m.uci,
      'color': m.color,
      'fenBefore': m.fenBefore,
      'fenAfter': m.fenAfter,
      'evalPawns': g?.evalPawns,
      'mate': g?.mate,
      'pctBest': g?.pctBest,
      'wcDrop': wcDrop,
      'depth': g?.depth ?? 0,
      if (g?.label != null) 'label': g!.label,
      if (g != null) 'bestSan': g.bestSan,
      if (g != null) 'bestUci': g.bestUci,
      if (g?.explanation != null) 'explanation': g!.explanation!.raw,
    };
  }

  List<String> _fenHistory() =>
      [Chess.initial.fen, ...moves.map((m) => m.fenAfter)];

  String _sanOf(Position pos, Move move) {
    final (_, san) = pos.makeSan(move);
    return san;
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    super.dispose();
  }
}
