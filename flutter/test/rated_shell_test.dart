// The rated screen (#169): board, plates, clocks, nothing else.
//
// Blind already empties the panels of engine content. This is a different
// claim — that they are not RENDERED. A player should be able to tell at a
// glance that the game counts, and nothing on screen can leak an engine that
// is not drawn.
//
//   cd flutter && flutter test test/rated_shell_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/main.dart';
import 'package:botvinnik_mobile/stores/chess_clock.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/clock_display.dart';
import 'package:botvinnik_mobile/ui/grade_strip.dart';

import 'package:botvinnik_mobile/brain/rating_api.dart';
import 'package:botvinnik_mobile/stores/player_rating_store.dart';

import 'support/fake_db.dart';
import 'support/game_harness.dart';

/// Never answers, so the card stays in its loading state and the recap builds.
class _StubRating implements RatingApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<(GameController, SettingsStore)> _game() async {
  final settings = await loadSettings(black: kTestBotId);
  final g = GameController(FakeArbiter(), const FakeBot({kTestBotId: testBotPersona}),
      FakeGrading(), settings);
  return (g, settings);
}

Future<void> _pump(WidgetTester tester, GameController g, SettingsStore s,
    {double width = 900}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<GameController>.value(value: g),
      ChangeNotifierProvider<SettingsStore>.value(value: s),
      Provider<ClassTable>.value(value: const ClassTable({})),
      // The game-over recap draws the rating card, which reads this. Only the
      // fourth test reaches it — the rated shell renders no panel column at
      // all, which is the whole point of the first three.
      ChangeNotifierProvider<PlayerRatingStore>(
          create: (_) => PlayerRatingStore(FakeDb(), _StubRating(),
          // zero deadline: the post-game recap's refit otherwise leaves a
          // 400ms poll timer pending past the test.
          pollInterval: Duration.zero, pollDeadline: Duration.zero)),
    ],
    child: const MaterialApp(home: Scaffold(body: PlayTab())),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a rated game draws no panels at all', (tester) async {
    final (g, s) = await _game();
    g.newGame(rated: true, timeControl: TimeControl.parse('5+0'));
    await _pump(tester, g, s);

    // Not "the Insights card is empty" — it is not built. Blind gives the
    // first; only this screen gives the second.
    expect(find.byType(SingleChildScrollView), findsNothing,
        reason: 'no panel column at all — not merely an empty one');
    expect(find.textContaining('INSIGHTS'), findsNothing);
    expect(find.textContaining('TREE'), findsNothing);
    expect(find.byType(ClockFace), findsNWidgets(2),
        reason: 'one clock per side');

    g.newGame(); // wind the controller down
    await tester.pumpAndSettle();
  });

  testWidgets('a casual game still has them', (tester) async {
    // The control. Without it the test above passes on a screen that renders
    // nothing at all.
    final (g, s) = await _game();
    g.newGame();
    await _pump(tester, g, s);

    expect(find.byType(ClockFace), findsNothing);
    expect(find.byType(SingleChildScrollView), findsWidgets,
        reason: 'the casual layout is unchanged');

    await tester.pumpAndSettle();
  });

  testWidgets('a rated game with no clock still hides the panels',
      (tester) async {
    // The time control is a property of the game; what counts is the mode.
    final (g, s) = await _game();
    g.newGame(rated: true); // no timeControl
    await _pump(tester, g, s);

    expect(find.byType(ClockFace), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);

    g.newGame();
    await tester.pumpAndSettle();
  });

  testWidgets('the panels come back when the game ends', (tester) async {
    // The recap, the result and the rating change all live in the panel
    // column, so the screen has to hand back at gameOver rather than stranding
    // the player on a finished board.
    // Analysis mode: no bot turn, so no bot-delay timer to outlive the test —
    // the shell doesn't care who the opponent is, only that the game is rated.
    final (g, s) = await _game();
    s.setPlayers(white: null, black: null);
    g.newGame(rated: true, timeControl: TimeControl.parse('5+0'));
    await _pump(tester, g, s);
    expect(find.byType(SingleChildScrollView), findsNothing,
        reason: 'precondition');

    // End it the way a clocked game ends: a flag. This also exercises that
    // flag-fall makes gameOver true, which the controller's own tests cover
    // but the shell's hand-back depends on.
    g.clock!.debugFlag(ClockSide.black);
    await tester.pump();

    expect(g.gameOver, isTrue);
    // The clocks go with the shell, and the scrolling panel column — which the
    // shell does not have — is back, so the recap is reachable in-tab.
    expect(find.byType(ClockFace), findsNothing);
    expect(find.byType(SingleChildScrollView), findsWidgets,
        reason: 'the panel column is back');
    expect(g.statusLine, contains('ran out of time'));

    g.newGame();
    await tester.pumpAndSettle();
  });
}
