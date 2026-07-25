// The win-chance chart in review (#195): it draws from the stored evals, hides
// itself on a game that was never graded, and seeks the board when tapped.
//
// The win-chance math itself is the brain's; here it comes through the
// harness's FakeGrading (a flat 50%), which is enough — these assertions are
// about WHEN the chart shows and what a tap does, not the shape of the curve.
//
//   cd flutter && flutter test test/review_win_chart_test.dart

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/grading_api.dart';
import 'package:botvinnik_mobile/db/app_db.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
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

// REAL positions, played out rather than typed. The chart itself only plots
// ply against eval and never looks at a FEN — but the review BOARD loads the
// same record and puts its positions on a board (#194/#196), so placeholder
// strings here stopped being harmless the moment the two shared a fixture.
//
// 1. e4 e5 2. Nf3 Nc6 3. Bb5 — five plies, which is what the chart tests want.
final _kLine = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5'];
final _kSans = ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'];

/// fen before / fen after, per ply, derived by playing [_kLine].
final List<({String before, String after})> _kFens = () {
  final out = <({String before, String after})>[];
  Position pos = Chess.initial;
  for (final uci in _kLine) {
    final before = pos.fen;
    pos = pos.play(NormalMove.fromUci(uci));
    out.add((before: before, after: pos.fen));
  }
  return out;
}();

Map<String, dynamic> _move(int ply, String color, num? evalPawns,
        {String label = 'best'}) =>
    {
      'ply': ply,
      'san': _kSans[ply - 1],
      'uci': _kLine[ply - 1],
      'color': color,
      'fenBefore': _kFens[ply - 1].before,
      'fenAfter': _kFens[ply - 1].after,
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

/// The chart reads the cursor off the BOARD now (#196), so a chart test needs
/// one in the tree — the archive no longer has a cursor of its own.
Future<ReviewBoardController> _pump(
    WidgetTester tester, Map<String, dynamic> game) async {
  final settings = await loadSettings();
  final review = ReviewController(_StubDb());
  final board = fakeReviewBoard(review, settings);
  review.open(game);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ClassTable>.value(
          value: ClassTable(_kClassRaw, labelOrder: _kOrder)),
      Provider<GradingApi>.value(value: FakeGrading()),
      ChangeNotifierProvider<ReviewController>.value(value: review),
      ChangeNotifierProvider<ReviewBoardController>.value(value: board),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 340, child: ReviewWinChart())),
      ),
    ),
  ));
  await tester.pump();
  return board;
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
    final board = await _pump(tester, _gradedGame());
    expect(board.reviewAnchorPly, 0, reason: 'opens at the start position');

    await tester.tap(find.byType(WinChartCanvas));
    await tester.pump();

    // A tap lands on the nearest graded ply and moves the board there — the
    // exact ply depends on where centre falls, but it must be a real one and
    // never the start.
    expect(board.reviewAnchorPly, isNot(0));
    expect([1, 2, 3, 4, 5], contains(board.reviewAnchorPly));
  });
}
