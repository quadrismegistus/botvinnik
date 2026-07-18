// The live game: position, bot reply loop, and the grading pipeline —
// the Dart translation of +page.svelte's orchestration, same semantics:
//
//   gradeMove(pre-move analysis lines) → backfillGrade(post-move analysis)
//
// One depth-22/3000ms MultiPV-5 analysis per reached position (the arbiter's
// `analysis` priority); the "pre" lines of a move are the "post" analysis of
// the previous one, cached by FEN. Bot searches run at `botMove` priority
// and preempt analysis, so replies stay snappy.

import 'dart:math';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../brain/bot_api.dart';
import '../brain/grading_api.dart';
import '../brain/types.dart';
import '../engine/arbiter.dart';
import 'settings_store.dart';

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

  Position position = Chess.initial;
  Move? lastMove;
  final List<MoveRecord> moves = [];
  bool botThinking = false;
  String gameSeed = _newSeed();
  Persona? persona;

  // analysis cache: fen → future of its MultiPV-5 deep lines
  final Map<String, Future<List<EngineMove>?>> _analysis = {};
  int _gen = 0;

  GameController(this._arbiter, this._bot, this._grading, this._settings) {
    persona = _bot.personaById(_settings.personaId) ?? _bot.personas().first;
    _settings.addListener(_onSettings);
    _analysisFor(position.fen);
    _maybeBotTurn();
  }

  static String _newSeed() => 'm${Random().nextInt(1 << 30)}';

  String get playerColor => _settings.playerColor;
  List<Persona> get rosterPersonas => _bot.personas();
  bool get isPlayerTurn =>
      (position.turn == Side.white ? 'w' : 'b') == playerColor;
  bool get gameOver => position.isGameOver;

  String get statusLine {
    if (position.isCheckmate) {
      final winner = position.turn == Side.white ? 'Black' : 'White';
      return 'Checkmate — $winner wins';
    }
    if (position.isStalemate) return 'Stalemate';
    if (position.isInsufficientMaterial) return 'Draw — insufficient material';
    if (botThinking) return '${persona?.name ?? "Bot"} is thinking…';
    return isPlayerTurn ? 'Your move' : '${persona?.name ?? "Bot"} to move';
  }

  MoveGrade? get lastPlayerGrade {
    for (var i = moves.length - 1; i >= 0; i--) {
      if (moves[i].color == playerColor) return moves[i].grade;
    }
    return null;
  }

  void _onSettings() {
    final p = _bot.personaById(_settings.personaId);
    if (p != null && p.id != persona?.id) {
      persona = p;
      newGame();
    } else {
      notifyListeners();
    }
  }

  // ---- game actions ----

  void newGame() {
    _gen++;
    _arbiter.bumpGeneration();
    position = Chess.initial;
    lastMove = null;
    moves.clear();
    botThinking = false;
    gameSeed = _newSeed();
    _analysis.clear();
    _analysisFor(position.fen);
    notifyListeners();
    _maybeBotTurn();
  }

  /// Undo the last player move (and the bot reply on top of it).
  void undo() {
    if (moves.isEmpty || botThinking) return;
    _gen++;
    _arbiter.bumpGeneration();
    while (moves.isNotEmpty && moves.last.color != playerColor) {
      moves.removeLast();
    }
    if (moves.isNotEmpty) moves.removeLast();
    final fen = moves.isEmpty ? Chess.initial.fen : moves.last.fenAfter;
    position = Chess.fromSetup(Setup.parseFen(fen));
    lastMove =
        moves.isEmpty ? null : NormalMove.fromUci(moves.last.uci);
    _analysisFor(position.fen);
    notifyListeners();
  }

  /// The human plays a move (already validated by the board).
  void playerMove(NormalMove move, String san) {
    if (!isPlayerTurn || botThinking || gameOver) return;
    _apply(move, san);
    _maybeBotTurn();
  }

  // ---- internals ----

  void _apply(NormalMove move, String san) {
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
    notifyListeners();
    _analysisFor(position.fen); // post-analysis = next move's pre-lines
    _gradePipeline(record, _gen);
  }

  Future<void> _maybeBotTurn() async {
    if (isPlayerTurn || gameOver || botThinking) return;
    final p = persona;
    if (p == null) return;
    botThinking = true;
    notifyListeners();
    final gen = _gen;
    try {
      final uci = await _pickBotMove(p);
      if (gen != _gen || uci == null) return;
      final move = NormalMove.fromUci(uci);
      if (!position.isLegal(move)) return;
      final san = _sanOf(position, move);
      _apply(move, san);
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
    // fish: the numeric recipe
    final spec = _bot.botSpec(p.numericElo!);
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
              internalElo: p.numericElo!,
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

  Future<List<EngineMove>?> _analysisFor(String fen) {
    return _analysis.putIfAbsent(fen, () => _arbiter.analysis(fen));
  }

  Future<void> _gradePipeline(MoveRecord record, int gen) async {
    final pre = await _analysisFor(record.fenBefore);
    if (gen != _gen || pre == null || pre.isEmpty) return;
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

    final child = await _analysisFor(record.fenAfter);
    if (gen != _gen || child == null || child.isEmpty) return;
    grade = _grading.backfillGrade(grade, child);
    record.grade = grade;
    notifyListeners();
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
