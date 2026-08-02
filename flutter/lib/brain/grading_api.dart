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

  /// How often a side played the engine's own first choice: {played, total},
  /// or null when nothing could be counted (an import nobody analysed, or a
  /// game of nothing but forced moves). Derived from the stored moves rather
  /// than saved on the record, so it is available for the whole archive and
  /// not only for games played after it existed.
  ({int played, int total})? engineCorrelation(
      List<Map<String, dynamic>> storedMoves, String color) {
    final r = _bridge.call('engineCorrelation', args: [storedMoves, color]);
    if (r is! Map) return null;
    // `is num`, not `as num?`: a cast throws on anything else, and this call is
    // made from a widget build method, where a throw is a red screen rather
    // than a missing row.
    final played = r['played'];
    final total = r['total'];
    if (played is! num || total is! num) return null;
    return (played: played.toInt(), total: total.toInt());
  }

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
