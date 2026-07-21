// The Insights card's two new pieces (#123): the win-chance drop the grade is
// computed from, and the miniature board showing the move played against the
// move the engine wanted.
//
// Pumps the REAL [InsightCard] over a REAL [GameController], so the number on
// screen is the one the controller computed rather than one a lookalike widget
// was handed. The grading fake's `winChance` is a straight line (50 + 10 per
// pawn) rather than the brain's logistic: every figure below is then exact and
// hand-checkable, and what is under test is the wiring, not lichess's curve.
//
//   cd flutter && flutter test test/insight_card_test.dart

import 'dart:io';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side, Square;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/engine/maia_progress.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/board_theme.dart';
import 'package:botvinnik_mobile/ui/grade_strip.dart';
import 'package:botvinnik_mobile/ui/insight_card.dart';

import 'support/game_harness.dart';

/// The brain's CLASS table, as it crosses the bridge (the three labels whose
/// glyphs are drawn as icons are in here for the same reason as in
/// review_summary_test: they are the ones that would fetch a font).
const _kClassRaw = {
  'brilliant': {'glyph': '‼', 'color': '#1baca6', 'noun': 'brilliant'},
  'best': {'glyph': '★', 'color': '#81b64c', 'noun': 'the best move'},
  'blunder': {'glyph': '??', 'color': '#ca3431', 'noun': 'a blunder'},
};

const _kStartFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// White to move, pawn on e7, e8 EMPTY (the black king is in the corner) — so
/// e7e8=Q and e7e8=N are both legal and the underpromotion case has a real
/// position under it rather than a FEN nobody checked.
const _kPromotionFen = '7k/4P3/8/8/8/8/8/4K3 w - - 0 1';

/// A grading stub whose numbers are chosen so every figure the card prints is
/// exact: best move worth +2.0 (→ 70%), the move played worth 0.0 (→ 50%), so
/// the drop is 20.0 — a blunder by the brain's own threshold.
///
/// [gradeMove] deliberately leaves `evalPawns` null, as the real one does for a
/// move outside the pre-move lines, and only [backfillGrade] fills it in. That
/// is the state the "nothing before backfill" test stands in.
class _Grading extends FakeGrading {
  @override
  MoveGrade gradeMove({
    required int ply,
    required String fenBefore,
    required String san,
    required String uci,
    required String color,
    required List<EngineMove> preLines,
  }) =>
      MoveGrade(gradeRaw(
        ply: ply,
        fenBefore: fenBefore,
        san: san,
        uci: uci,
        color: color,
        backfilled: false,
        evalPawns: null,
        label: null,
      ));

  @override
  MoveGrade backfillGrade(MoveGrade grade, List<EngineMove> childLines) =>
      MoveGrade({
        ...grade.raw,
        'backfilled': true,
        'evalPawns': 0.0,
        'label': 'blunder',
      });

  @override
  double winChance(double? evalPawns, int? mate) {
    if (mate != null) return mate > 0 ? 100 : 0;
    if (evalPawns == null) return 50; // what the brain does, and the hazard
    return (50 + evalPawns * 10).clamp(0.0, 100.0);
  }
}

/// Every field the card and [GameController.lastGradeWinChance] read. Written
/// out in full on purpose: `bestPv` and `isBest` are unconditional casts, so a
/// fixture missing one throws inside build() and the test that "passed" never
/// reached its assertion.
Map<String, dynamic> gradeRaw({
  int ply = 1,
  String fenBefore = _kStartFen,
  String san = 'e4',
  String uci = 'e2e4',
  String color = 'w',
  bool backfilled = true,
  double? evalPawns = 0.0,
  int? mate,
  double bestEval = 2.0,
  int? bestMate,
  String bestSan = 'd4',
  String bestUci = 'd2d4',
  bool isBest = false,
  String? label = 'blunder',
  double? pctBest = 41.0,
  Map<String, dynamic>? explanation,
}) =>
    {
      'ply': ply,
      'fenBefore': fenBefore,
      'san': san,
      'uci': uci,
      'color': color,
      'depth': 15,
      'rank': 3,
      'evalPawns': evalPawns,
      'mate': mate,
      'pctBest': pctBest,
      'isBest': isBest,
      'bestSan': bestSan,
      'bestUci': bestUci,
      'bestEval': bestEval,
      'bestMate': bestMate,
      'bestPv': const ['d2d4', 'd7d5'],
      'backfilled': backfilled,
      'label': label,
      'explanation': explanation,
    };

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

Future<GameController> _controller({
  String? white,
  String? black,
  FakePractice? practice,
  List<EngineMove>? analysisLines,
}) async {
  final settings = await loadSettings(white: white, black: black);
  return GameController(
    // streamPartials so a bot turn's opening wait can EXIT: it spins on a 50ms
    // timer until the analysis reaches depth 10 or 1500ms of wall clock pass,
    // and a widget test advances fake timers, not the clock. Without it the
    // timer is still pending when the tree is disposed, which is a failure.
    FakeArbiter(analysisLines: analysisLines, streamPartials: true),
    const FakeBot({kTestBotId: testBotPersona}),
    _Grading(),
    settings,
    null,
    practice,
  );
}

/// A controller with one played move whose grade is [raw] — the analysis board,
/// where `lastPlayerGrade` is simply the latest move, and where the grading
/// pipeline parks forever on a never-resolving analysis so it cannot overwrite
/// what the test injected.
Future<GameController> _withGrade(Map<String, dynamic> raw,
    {String fromFen = _kStartFen, String uci = 'e2e4'}) async {
  final game = await _controller();
  if (fromFen != _kStartFen) game.newGame(fromFen: fromFen);
  game.playUci(uci);
  game.moves.last.grade = MoveGrade(raw);
  return game;
}

Future<void> _pump(WidgetTester tester, GameController game,
    {double width = 375}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ClassTable>.value(value: const ClassTable(_kClassRaw)),
      ChangeNotifierProvider<SettingsStore>.value(value: await loadSettings()),
      ChangeNotifierProvider<GameController>.value(value: game),
    ],
    // A FRESH KEY every pump. Without it a second _pump in the same test is a
    // no-op: `const InsightCard()` compares equal to the one already mounted,
    // and Element.updateChild returns the existing element untouched — so a
    // test that injects a new grade and re-pumps would assert against the
    // first build's output and could not tell a gate from a dead branch.
    child: MaterialApp(home: Scaffold(body: InsightCard(key: UniqueKey()))),
  ));
  await tester.pump();
}

Set<Shape> _shapes(WidgetTester tester) =>
    tester.widget<StaticChessboard>(find.byType(StaticChessboard)).shapes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  group('the win-chance delta', () {
    testWidgets('the card prints the number practice collects on',
        (tester) async {
      // The whole point of the figure: it is the one that decides the label
      // AND the one that decides the puzzle. Driven through the real grading
      // pipeline, so the printed string and the collected value come from the
      // same run — a card computing its own drop would pass every other
      // assertion here.
      final practice = FakePractice();
      final game = await _controller(
          black: kTestBotId, // you are White: e2e4 is YOUR move in a real game
          practice: practice,
          analysisLines: kFakeLines);
      game.playUci('e2e4');
      await tester.pump(const Duration(milliseconds: 50));

      expect(practice.collected, hasLength(1),
          reason: 'the pipeline must have reached the collect guard, or this '
              'test is measuring nothing');
      final collected = practice.collected.single['wcDrop'] as double;
      expect(collected, 20.0);

      await _pump(tester, game);
      expect(find.textContaining('Win chance lost '
          '${collected.toStringAsFixed(1)}%'), findsOneWidget);
      // and the two figures it is the difference of
      expect(find.textContaining('70% to 50%'), findsOneWidget);
    });

    testWidgets('nothing is claimed before the grade is backfilled',
        (tester) async {
      // `gradeMove` leaves evalPawns null for a move outside the pre-move
      // lines, and winChance reads null as 50% — so an ungated card would
      // print "lost 20.0%" measured against an eval that does not exist yet,
      // for exactly the moves the number matters for.
      final game = await _withGrade(gradeRaw(
          backfilled: false, evalPawns: null, label: null, pctBest: null));
      await _pump(tester, game);

      expect(find.textContaining('e4'), findsWidgets,
          reason: 'the card must be showing the move, or nothing is on screen '
              'and every absence below is free');
      expect(find.textContaining('Win chance'), findsNothing);

      // the control: the SAME move once backfilled does print it, so the gate
      // is a gate and not a feature that never fires
      game.moves.last.grade = MoveGrade(gradeRaw());
      await _pump(tester, game);
      expect(find.textContaining('Win chance lost 20.0%'), findsOneWidget);
    });

    testWidgets('a move that gave nothing away says so', (tester) async {
      // The threshold is only legible if the small numbers are shown too.
      final game = await _withGrade(gradeRaw(
          evalPawns: 2.0, isBest: true, label: 'best', pctBest: 100.0));
      await _pump(tester, game);
      expect(find.textContaining('Win chance lost 0.0%'), findsOneWidget);
      expect(find.textContaining('70% to 70%'), findsOneWidget);
    });

    testWidgets('a mate the player walked into is 100 points, not a pawn count',
        (tester) async {
      // The mate branch of winChance, which carries no eval at all: -1 is
      // "mated next move", so the move played is worth 0% against a best move
      // worth 70%.
      final game =
          await _withGrade(gradeRaw(evalPawns: null, mate: -1, label: 'blunder'));
      await _pump(tester, game);
      expect(find.textContaining('Win chance lost 70.0%'), findsOneWidget);
      expect(find.textContaining('70% to 0%'), findsOneWidget);
    });
  });

  group('the played-vs-best board', () {
    testWidgets('draws the played move in red and the engine\'s in blue',
        (tester) async {
      final game = await _withGrade(gradeRaw());
      await _pump(tester, game);

      final board =
          tester.widget<StaticChessboard>(find.byType(StaticChessboard));
      expect(board.fen, _kStartFen,
          reason: 'the position the move was CHOSEN in, not the one it made');

      final arrows = _shapes(tester).whereType<Arrow>().toList();
      expect(arrows, hasLength(2), reason: 'two arrows, two facts');
      final played = arrows.firstWhere((a) => a.orig == Square.e2);
      final best = arrows.firstWhere((a) => a.orig == Square.d2);
      expect(played.dest, Square.e4);
      expect(best.dest, Square.d4);
      // #29's grammar: blue is the engine's move everywhere in this app, red
      // is the move that costs you. Swapping them is invisible to any
      // assertion that only counts arrows.
      expect(played.color, kThreatArrowRed.withValues(alpha: 0.85));
      expect(best.color, kEngineArrowBlue.withValues(alpha: 0.9));

      // and the legend that says which is which
      expect(find.text('Played e4'), findsOneWidget);
      expect(find.text('Best was d4'), findsOneWidget);
    });

    testWidgets('faces the side that moved', (tester) async {
      final game = await _withGrade(
          gradeRaw(ply: 2, san: 'e5', uci: 'e7e5', color: 'b'),
          uci: 'e2e4');
      // black's move: the board is drawn from black's side
      await _pump(tester, game);
      expect(
          tester
              .widget<StaticChessboard>(find.byType(StaticChessboard))
              .orientation,
          Side.black);
    });

    testWidgets('the best move gets no board — there is nothing to compare',
        (tester) async {
      final game = await _withGrade(
          gradeRaw(isBest: true, label: 'best', evalPawns: 2.0));
      await _pump(tester, game);
      expect(find.byType(StaticChessboard), findsNothing);
      expect(find.textContaining('Best was'), findsNothing);
    });

    testWidgets('a promotion differing only in the piece keeps the sentence',
        (tester) async {
      // e7e8q against e7e8n: the two arrows would be drawn on the identical
      // line and read as one move, and the difference — WHICH piece — is the
      // one thing a board cannot show. (chess.js orders promotions n,b,r,q,
      // so an underpromotion as the engine's choice is not exotic.)
      final game = await _withGrade(
        gradeRaw(
          fenBefore: _kPromotionFen,
          san: 'e8=Q',
          uci: 'e7e8q',
          bestSan: 'e8=N',
          bestUci: 'e7e8n',
        ),
        fromFen: _kPromotionFen,
        uci: 'e7e8q',
      );
      await _pump(tester, game);

      expect(find.byType(StaticChessboard), findsNothing);
      expect(find.text('Best was e8=N'), findsOneWidget,
          reason: 'the sentence is the only thing that can say which piece');
    });
  });

  group('what the card already did', () {
    testWidgets('a loading engine still wins over everything', (tester) async {
      final game = await _withGrade(gradeRaw());
      game.maiaProgress = const MaiaProgress('fetching', received: 1, total: 4);
      await _pump(tester, game);

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Win chance'), findsNothing);
      expect(find.byType(StaticChessboard), findsNothing);
    });

    testWidgets('no move yet: the prompt, and no numbers', (tester) async {
      final game = await _controller();
      await _pump(tester, game);

      expect(find.textContaining('Play a move'), findsOneWidget);
      expect(find.textContaining('Win chance'), findsNothing);
      expect(find.byType(StaticChessboard), findsNothing);
    });
  });

  group('layout', () {
    // A RenderFlex overflow is a runtime error: a clean analyzer and a green
    // suite say nothing about it. The widest realistic card — the longest SANs
    // this can show, the widest label chip, the delta line and four sentences
    // of prose, all at once — at the two narrowest widths that matter.
    //
    // NOT covered: the threat chip, which is fen-gated behind a private field
    // no test can set. It is unchanged by this work and sits below everything
    // here, in its own Row.
    final crowded = gradeRaw(
      san: 'Qxf7+',
      uci: 'd1f7',
      bestSan: 'Nxe6+',
      bestUci: 'g5e6',
      label: 'brilliant',
      pctBest: 100.0,
      explanation: const {
        'playedIssue': 'This drops the queen for a pawn.',
        'playedPoint': 'The king is forced into the open.',
        'bestPoint': 'The knight forks the king and the rook instead.',
        'lineStory': 'After Kxf7 Nxd8+ White is a whole rook up.',
        'evidence': {'fen': _kStartFen, 'ucis': ['d2d4', 'd7d5']},
      },
    );

    for (final width in [375.0, 320.0]) {
      testWidgets('the crowded card does not overflow at $width',
          (tester) async {
        final game = await _withGrade(crowded);
        await _pump(tester, game, width: width);

        // the pressure has to actually be on screen, or this proves nothing
        expect(find.byType(StaticChessboard), findsOneWidget);
        expect(find.textContaining('Win chance lost'), findsOneWidget);
        expect(find.text('Best was Nxe6+'), findsOneWidget);
        expect(find.textContaining('a whole rook up'), findsOneWidget);

        expect(tester.takeException(), isNull,
            reason: 'the insight card overflowed at ${width}px');
      });
    }
  });
  testWidgets('a move that gained shows no loss, and no negative drop',
      (tester) async {
    // The backfilled eval is DEEPER than the pre-move MultiPV best, so it
    // routinely lands above it — a played-best move then computes a negative
    // "loss". The drop is clamped at zero, but the endpoints print raw, which
    // read as "Win chance lost 0.0% · 70% to 74%": nothing lost, beside two
    // numbers that went up. Removing the clamp left all 335 tests green.
    final game = await _withGrade(gradeRaw(evalPawns: 2.4, isBest: true));
    final wc = game.lastGradeWinChance!;
    expect(wc.drop, 0.0, reason: 'clamped — a gain is not a loss');
    expect(wc.after, greaterThan(wc.before), reason: 'it really did gain');

    await _pump(tester, game);
    expect(find.textContaining('lost 0.0%'), findsNothing);
    expect(find.textContaining('held'), findsOneWidget);
  });

  testWidgets('the play button animates the BEST line, not the move played',
      (tester) async {
    // It used to play the explanation's evidence line, which explain.ts builds
    // from playedPv — your own mistake and its refutation. The card said "Best
    // was d4", drew d4 on the preview board, and then played e4. #164.
    final game = await _withGrade(gradeRaw(
      uci: 'e2e4',
      bestUci: 'd2d4',
      explanation: {
        'evidence': {'fen': _kStartFen, 'ucis': ['e2e4', 'e7e5']},
      },
    ));
    await _pump(tester, game);

    await tester.tap(find.byIcon(Icons.play_circle_outline).first);
    await tester.pump();

    expect(game.previewing, isTrue);
    expect(game.previewTag, 'move');

    // What the BOARD shows after the first step — the only public observable,
    // and the thing that was wrong. d4 gives a pawn on d4; e4 gives one on e4.
    await tester.pump(const Duration(milliseconds: 900));
    final shown = game.previewFen!;
    expect(shown.split(' ').first, contains('3P4'),
        reason: 'a pawn on d4 — the button beside "Best was d4" must show d4');
    expect(shown, isNot(contains('4P3')), reason: 'not the move played');

    game.stopPreview();
    await tester.pump(const Duration(milliseconds: 200));
  });

}
