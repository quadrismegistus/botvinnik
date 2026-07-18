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

  /// The CLASS table (glyph/color/noun per label), fetched once.
  Map<String, dynamic> classTable() =>
      (_bridge.call('CLASS', isProperty: true) as Map).cast<String, dynamic>();
}
