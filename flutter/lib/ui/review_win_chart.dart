// The win-chance chart in review: the same curve as live play, but fed from a
// stored game's evals and driven by the review cursor. The ply you are on is
// ringed, and tapping a point jumps the board there.
//
// The evals are read straight off the stored moves — the same numbers grading
// wrote at save time — and turned into White-POV win chance by the brain's own
// `whitePovWinChance`, so this curve matches the one the live chart drew as the
// game was played. The per-move bridge calls run once per opened game (memoised
// on its id), not on every scrub.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/grading_api.dart';
import '../stores/review_controller.dart';
import 'grade_strip.dart';
import 'win_chart.dart';

class ReviewWinChart extends StatefulWidget {
  const ReviewWinChart({super.key});

  @override
  State<ReviewWinChart> createState() => _ReviewWinChartState();
}

class _ReviewWinChartState extends State<ReviewWinChart> {
  String? _gameId; // the game the cached points belong to
  List<WinPoint> _points = const [];

  /// Whether any ply carries an eval to plot. Checked before touching
  /// [GradingApi] so an ungraded game — a raw import, or a record from before
  /// grading — needs no grading provider at all, just an empty chart.
  static bool _hasEvals(List<Map<String, dynamic>> moves) =>
      moves.any((m) => m['evalPawns'] != null || m['mate'] != null);

  List<WinPoint> _compute(ReviewController review, GradingApi grading) {
    final out = <WinPoint>[];
    for (final m in review.moves) {
      final evalPawns = (m['evalPawns'] as num?)?.toDouble();
      final mate = (m['mate'] as num?)?.toInt();
      // An ungraded ply (a raw import, or a record from before grading) has no
      // eval to plot — skip it rather than draw it at 50%.
      if (evalPawns == null && mate == null) continue;
      out.add((
        ply: (m['ply'] as num).toInt(),
        san: m['san'] as String,
        wc: grading.whitePovWinChance(m['color'] as String, evalPawns, mate),
        label: m['label'] as String?,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final review = context.watch<ReviewController>();
    final table = context.read<ClassTable>();
    final id = review.current?['id'] as String?;
    if (id == null) return const SizedBox();
    if (id != _gameId) {
      _gameId = id;
      _points = _hasEvals(review.moves)
          ? _compute(review, context.read<GradingApi>())
          : const [];
    }
    // Under two graded plies there is no curve to draw — an ungraded import,
    // or a game one move long. Say nothing rather than show an empty axis.
    if (_points.length < 2) return const SizedBox();

    // The point sitting at the current cursor ply, if any. cursor 0 (the start
    // position) and any ungraded ply have no dot, so nothing is ringed there.
    var selected = -1;
    for (var i = 0; i < _points.length; i++) {
      if (_points[i].ply == review.cursor) {
        selected = i;
        break;
      }
    }

    return WinChartCanvas(
      points: _points,
      table: table,
      selected: selected < 0 ? null : selected,
      onPick: (i) => review.goto(_points[i].ply),
    );
  }
}
