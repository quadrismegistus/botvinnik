// The Lines pane's search-progress header (#95).
//
// It used to read 'depth 14' and nothing else, which is a number with nothing
// to be a number of — the target is 22 and no player has any way to know that.
// Two claims are made now, and they can fail independently:
//
//  1. the fraction and the bar are measured against the REAL budget
//     ([kAnalysisDepth]), not a number typed into the pane;
//  2. a search that STOPS SHORT of the budget — which is the ordinary case,
//     since analysis also ends on the movetime backstop and on the board
//     moving on — says so, instead of leaving a bar parked at 86% for the
//     rest of the position's life.
//
// (2) is the whole design decision, and it rests on a signal that depth cannot
// supply: whether the arbiter's future has resolved. So the controller side of
// it is tested here too, and specifically that it is NOT derivable from the
// lines — the first test has partials in hand and is still unsettled.
//
//   cd flutter && flutter test test/lines_pane_progress_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/chess_api.dart';
import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/engine/arbiter.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/ui/lines_pane.dart';

import 'support/game_harness.dart';

/// Exactly half the budget, so a pane measuring against some other target
/// draws a visibly different bar rather than one a rounding tolerance hides.
final _kHalfDepth = kAnalysisDepth ~/ 2;

final List<EngineMove> _kLines = [
  EngineMove(
      pv: const ['e2e4'],
      score: 0.3,
      mate: null,
      depth: _kHalfDepth,
      multipv: 1),
];

/// An analysis that streams its lines and then never ends — a search still
/// thinking. [FakeArbiter.analysisDelay] models the same thing with a timer,
/// which a widget test then has to be careful never to outlive; a future that
/// simply never completes has nothing to outlive.
class _StillThinkingArbiter extends FakeArbiter {
  _StillThinkingArbiter() : super(analysisLines: _kLines, streamPartials: true);

  @override
  Future<List<EngineMove>?> analysis(String fen,
      {void Function(List<EngineMove>)? onUpdate}) {
    onUpdate?.call(_kLines);
    return Completer<List<EngineMove>?>().future;
  }
}

/// An analysis that resolves with NULL — the engine declined, or the position
/// is terminal and there is nothing to search.
///
/// The distinction that makes this worth a fixture: `_analysisFor` EVICTS the
/// memo on a null so the position can be analysed afresh, which means the
/// search has not finished, it has not happened. Marking such a fen settled
/// parks a full bar on a search that never ran.
class _DeclinedArbiter extends FakeArbiter {
  _DeclinedArbiter() : super(analysisLines: _kLines, streamPartials: true);

  @override
  Future<List<EngineMove>?> analysis(String fen,
      {void Function(List<EngineMove>)? onUpdate}) {
    onUpdate?.call(_kLines); // partials arrive, then the search yields nothing
    return Future<List<EngineMove>?>.value(null);
  }
}

const _kPaneWidth = 300.0;

/// The pane's own horizontal padding, which the bar sits inside.
const _kTrackWidth = _kPaneWidth - 28;

/// A pane over [arbiter]. The gap between "has streamed lines" and "has
/// finished" is the entire subject of this file: before it the search is
/// running, after it the search is over at whatever depth it managed — which
/// for a real search is usually short of the target.
Future<GameController> _pump(WidgetTester tester,
    {required SearchArbiter arbiter}) async {
  final settings = await loadSettings(); // both human: analysis mode, no bot
  final game =
      GameController(arbiter, FakeBot(), FakeGrading(), settings);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<GameController>.value(value: game),
      Provider<ChessApi>.value(value: FakeChess()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: _kPaneWidth, child: const LinesPane()),
        ),
      ),
    ),
  ));
  await tester.pump();
  return game;
}

double _fillWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(kAnalysisProgressFillKey)).width;

Color _fillColor(WidgetTester tester) => (tester
        .widget<DecoratedBox>(find.byKey(kAnalysisProgressFillKey))
        .decoration as BoxDecoration)
    .color!;

/// A pane whose search has already resolved. Second half of the pair the
/// widget tests are built on — see [_StillThinkingArbiter] for the first.
Future<GameController> _pumpSettled(WidgetTester tester) async {
  final game = await _pump(tester,
      arbiter: FakeArbiter(
          analysisLines: _kLines,
          streamPartials: true,
          analysisDelay: const Duration(milliseconds: 50)));
  await tester.pump(const Duration(milliseconds: 100));
  return game;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a running search reads as a fraction of the real budget',
      (tester) async {
    final game = await _pump(tester, arbiter: _StillThinkingArbiter());

    expect(game.currentLines, isNotEmpty,
        reason: 'nothing streamed — the pane is in its empty state and this '
            'test proves nothing');
    expect(game.analysisSettled, isFalse,
        reason: 'the search resolved early — the running state is not under '
            'test here');

    expect(find.text('depth $_kHalfDepth / $kAnalysisDepth'), findsOneWidget);
    // and the bar agrees with the words. Half the budget, half the track — a
    // pane measuring against anything but kAnalysisDepth lands elsewhere.
    expect(_fillWidth(tester), closeTo(_kTrackWidth / 2, 0.5));
  });

  // THE case the feature exists for. A search that has ended at depth 11 will
  // never reach 22, so a bar frozen at half is a promise the app cannot keep;
  // the bar reports completion, and the number alone reports depth.
  testWidgets('a search that ends below the budget says final, and fills',
      (tester) async {
    final game = await _pumpSettled(tester);

    expect(game.analysisSettled, isTrue,
        reason: 'the search never resolved — the settled state is not on '
            'screen and the assertions below would be about the running one');
    // the depth really is short of the target: this is the stopped-early case,
    // not a search that got there
    expect(game.currentLines.first.depth, lessThan(kAnalysisDepth));

    expect(find.text('depth $_kHalfDepth · final'), findsOneWidget);
    expect(find.text('depth $_kHalfDepth / $kAnalysisDepth'), findsNothing);
    expect(_fillWidth(tester), closeTo(_kTrackWidth, 0.5),
        reason: 'a finished search left its bar part-full, which reads as a '
            'search still running');
  });

  // Filling the bar is what makes the settled state honest, and it is also
  // what makes it the widest mark in the pane — so it has to get quieter as it
  // gets bigger, or finishing a search would draw the eye to the one thing
  // that has stopped having anything to say.
  testWidgets('the bar recedes once it is full', (tester) async {
    await _pump(tester, arbiter: _StillThinkingArbiter());
    final running = _fillColor(tester);
    await _pumpSettled(tester);
    final settled = _fillColor(tester);

    expect(_fillWidth(tester), greaterThan(_kTrackWidth / 2),
        reason: 'the settled bar did not grow — there is nothing to quieten');
    expect(settled.a, lessThan(running.a));
  });

  testWidgets('a search that resolved NULL is not settled', (tester) async {
    // The case the production comment argues for and nothing checked — found
    // by mutating `else if (lines != null)` to `else if (true)`, which left
    // the whole file green. A null resolution evicts the memo so the position
    // is searched again; calling that "final" fills the bar for a search that
    // has not run.
    final game = await _pump(tester, arbiter: _DeclinedArbiter());
    await tester.pump(const Duration(milliseconds: 50));

    expect(game.currentLines, isNotEmpty,
        reason: 'precondition: partials did arrive, so the pane is drawn');
    expect(game.analysisSettled, isFalse);
    expect(find.textContaining('final'), findsNothing);
    expect(_fillWidth(tester), closeTo(_kTrackWidth / 2, 0.5),
        reason: 'still the running fraction, not a full bar');
  });

  testWidgets('a search deeper than the budget does not overflow the track',
      (tester) async {
    // The clamp. Stockfish's last info line can report past the depth it was
    // asked for, and a fraction above 1 in a FractionallySizedBox paints
    // outside its parent. Found by deleting `.clamp(0.0, 1.0)`, which nothing
    // else noticed.
    final deep = [
      EngineMove(
          pv: const ['e2e4'],
          score: 0.3,
          mate: null,
          depth: kAnalysisDepth + 8,
          multipv: 1),
    ];
    final settings = await loadSettings();
    final game = GameController(
        FakeArbiter(analysisLines: deep, streamPartials: true),
        FakeBot(),
        FakeGrading(),
        settings);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<GameController>.value(value: game),
        Provider<ChessApi>.value(value: FakeChess()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: _kPaneWidth, child: const LinesPane()),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(_fillWidth(tester), lessThanOrEqualTo(_kTrackWidth + 0.5));
    expect(tester.takeException(), isNull);
    game.dispose();
  });

  testWidgets('the empty state is untouched — no header, no bar',
      (tester) async {
    final settings = await loadSettings();
    // the default fake never resolves and never streams: no lines at all
    final game = GameController(
        FakeArbiter(), FakeBot(), FakeGrading(), settings);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<GameController>.value(value: game),
        Provider<ChessApi>.value(value: FakeChess()),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: _kPaneWidth, child: LinesPane()),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Analyzing…'), findsOneWidget);
    expect(find.byKey(kAnalysisProgressFillKey), findsNothing,
        reason: 'a progress bar over no lines at all is progress toward '
            'nothing');
  });

  group('analysisSettled', () {
    test('is not derivable from the lines — partials arrive long before it',
        () async {
      final settings = await loadSettings();
      final game = GameController(
          FakeArbiter(
              analysisLines: _kLines,
              streamPartials: true,
              analysisDelay: const Duration(milliseconds: 40)),
          FakeBot(),
          FakeGrading(),
          settings);

      expect(game.currentLines, isNotEmpty);
      expect(game.analysisSettled, isFalse,
          reason: 'streamed partials are not a finished search');

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(game.analysisSettled, isTrue);
    });

    test('a new game starts unsettled, even on the same position', () async {
      final settings = await loadSettings();
      final game = GameController(
          FakeArbiter(analysisLines: _kLines, streamPartials: true),
          FakeBot(),
          FakeGrading(),
          settings);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(game.analysisSettled, isTrue);

      // Same fen as before, so nothing but the clearing of the record can make
      // this false — and without it the pane would open a fresh game claiming
      // its first search was already over.
      game.newGame();
      expect(game.analysisSettled, isFalse);
    });
  });
}
