// Grading: gradeMove from the pre-move lines, backfillGrade from the
// post-move search (which also assigns the label and attaches the
// explanation once child depth ≥ 10 — web semantics, unchanged).

import 'js_bridge.dart';
import 'types.dart';

class GradingApi {
  final JsBridge _bridge;
  const GradingApi(this._bridge);

  MoveGrade gradeMove({
    required int ply,
    required String fenBefore,
    required String san,
    required String uci,
    required String color,
    required List<EngineMove> preLines,
  }) {
    final raw = _bridge.call('gradeMove', args: [
      ply, fenBefore, san, uci, color,
      preLines.map((l) => l.toJson()).toList(),
    ]);
    return MoveGrade((raw as Map).cast<String, dynamic>());
  }

  MoveGrade backfillGrade(MoveGrade grade, List<EngineMove> childLines) {
    final raw = _bridge.call('backfillGrade', args: [
      grade.raw,
      childLines.map((l) => l.toJson()).toList(),
    ]);
    return MoveGrade((raw as Map).cast<String, dynamic>());
  }

  double winChance(double? evalPawns, int? mate) =>
      (_bridge.call('winChance', args: [evalPawns, mate]) as num).toDouble();

  /// Win chance from White's perspective (evals are mover-perspective).
  double whitePovWinChance(String color, double? evalPawns, int? mate) =>
      (_bridge.call('whitePovWinChance', args: [color, evalPawns, mate]) as num)
          .toDouble();

  /// The CLASS table (glyph/color/noun per label), fetched once.
  Map<String, dynamic> classTable() =>
      (_bridge.call('CLASS', isProperty: true) as Map).cast<String, dynamic>();

  /// Chess.com-style accuracy over a game's StoredMove array (null when the
  /// side has no graded moves).
  double? gameAccuracy(List<Map<String, dynamic>> storedMoves, String color) =>
      (_bridge.call('gameAccuracy', args: [storedMoves, color]) as num?)
          ?.toDouble();

  /// {blunder: n, mistake: n, ...} for one side of a stored game.
  Map<String, dynamic> labelCounts(
          List<Map<String, dynamic>> storedMoves, String color) =>
      (_bridge.call('labelCounts', args: [storedMoves, color]) as Map)
          .cast<String, dynamic>();

  /// LABEL_ORDER: the brain's own ranking of the labels, brilliant first and
  /// blunder last. Anything that lists all nine — the review summary's count
  /// grid — orders by this rather than by a list of its own, which is how the
  /// UI and the brain's ranking drift apart.
  List<String> labelOrder() =>
      (_bridge.call('LABEL_ORDER', isProperty: true) as List).cast<String>();
}
