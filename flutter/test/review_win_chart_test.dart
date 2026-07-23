// The win-chance chart in review (#195): it draws from the stored evals, hides
// itself on a game that was never graded, and seeks the board when tapped.
//
// The win-chance math itself is the brain's; here it comes through the
// harness's FakeGrading (a flat 50%), which is enough — these assertions are
// about WHEN the chart shows and what a tap does, not the shape of the curve.
//
//   cd flutter && flutter test test/review_win_chart_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/grading_api.dart';
import 'package:botvinnik_mobile/db/app_db.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/ui/grade_strip.dart';
import 'package:botvinnik_mobile/ui/review_win_chart.dart';
import 'package:botvinnik_mobile/ui/win_chart.dart';

import 'support/game_harness.dart';

const _kClassRaw = {
  'best': {'glyph': '★', 'color': '#81b64c', 'noun': 'the best move'},
  'good': {'glyph': '✓', 'color': '#95b776', 'noun': 'a good move'},
  'inaccuracy': {'glyph': '?!', 'color': '#f0c15c', 'noun': 'an inaccuracy'},
  'blunder': {'glyph': '??', 'color': '#ca3431', 'noun': 'a blunder'},
};
const _kOrder = ['best', 'good', 'inaccuracy', 'blunder'];

class _StubDb implements AppDb {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// The chart never reads the FENs — it plots ply against eval — so placeholders
// are fine here; only ply/san/color/evalPawns matter.
Map<String, dynamic> _move(int ply, String color, num? evalPawns,
        {String label = 'best'}) =>
    {
      'ply': ply,
      'san': ply.isOdd ? 'Nf3' : 'Nc6',
      'uci': ply.isOdd ? 'g1f3' : 'b8c6',
      'color': color,
      'fenBefore': 'fen$ply-before',
      'fenAfter': 'fen$ply-after',
      'evalPawns': ?evalPawns, // omitted when null — an ungraded ply
      'label': label,
    };

/// A graded game: every ply carries an eval, so the chart draws five points.
Map<String, dynamic> _gradedGame() => {
      'id': 'g-graded',
      'moves': [
        _move(1, 'w', 0.3),
        _move(2, 'b', 0.2, label: 'good'),
        _move(3, 'w', 0.9, label: 'inaccuracy'),
        _move(4, 'b', -1.4, label: 'blunder'),
        _move(5, 'w', 0.5),
      ],
    };

/// An import: moves, but no evals on any ply.
Map<String, dynamic> _ungradedGame() => {
      'id': 'g-import',
      'moves': [
        _move(1, 'w', null),
        _move(2, 'b', null, label: 'good'),
        _move(3, 'w', null),
        _move(4, 'b', null, label: 'good'),
      ],
    };

Future<ReviewController> _pump(
    WidgetTester tester, Map<String, dynamic> game) async {
  final review = ReviewController(_StubDb())..open(game);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ClassTable>.value(
          value: ClassTable(_kClassRaw, labelOrder: _kOrder)),
      Provider<GradingApi>.value(value: FakeGrading()),
      ChangeNotifierProvider<ReviewController>.value(value: review),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 340, child: ReviewWinChart())),
      ),
    ),
  ));
  await tester.pump();
  return review;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a graded game draws the chart', (tester) async {
    await _pump(tester, _gradedGame());
    expect(find.byType(WinChartCanvas), findsOneWidget);
  });

  testWidgets('an ungraded import draws nothing — no empty axis', (tester) async {
    await _pump(tester, _ungradedGame());
    expect(find.byType(WinChartCanvas), findsNothing);
  });

  testWidgets('a single graded ply is not enough for a curve', (tester) async {
    await _pump(tester, {
      'id': 'g-one',
      'moves': [_move(1, 'w', 0.3)],
    });
    expect(find.byType(WinChartCanvas), findsNothing);
  });

  testWidgets('tapping the chart seeks the review cursor', (tester) async {
    final review = await _pump(tester, _gradedGame());
    expect(review.cursor, 0, reason: 'opens at the start position');

    await tester.tap(find.byType(WinChartCanvas));
    await tester.pump();

    // A tap lands on the nearest graded ply and moves the board there — the
    // exact ply depends on where centre falls, but it must be a real one and
    // never the start.
    expect(review.cursor, isNot(0));
    expect([1, 2, 3, 4, 5], contains(review.cursor));
  });
}
