// Maia3Pane pumped for real (#221 review follow-up): the provider wiring,
// the post-frame setPosition handshake, and the blind gate. This exists
// because provider_parity_test only sees `*Api` reads — a Store the pane
// watches but main.dart forgot to provide would crash only on panel open,
// and only this test would notice first.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/maia3_api.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/maia3_store.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/maia3_pane.dart';

import 'support/game_harness.dart';

const _ladder = [600, 1600, 2600];

Maia3Store _fakeStore(List<String> analyzed) {
  final store = Maia3Store.test();
  store.debugLadder = _ladder;
  store.debugAnalyze = (fen, elos) async {
    analyzed.add(fen);
    return Maia3Raw(
      elos: elos,
      policyByElo: [for (final _ in elos) const [0.0]],
      wdlByElo: [for (final _ in elos) const [0.0, 0.0, 0.0]],
    );
  };
  store.debugDecode = (fen, _) => Maia3MoveCurves(
        perElo: [
          for (final e in _ladder) Maia3RungCurve(e, const {'e4': 0.4})
        ],
        wdlByElo: const [],
      );
  return store;
}

Future<(GameController, Maia3Store, List<String>)> _pump(
    WidgetTester tester,
    {bool blind = false}) async {
  final settings = await loadSettings();
  final game =
      GameController(FakeArbiter(), const FakeBot(), FakeGrading(), settings);
  if (blind) settings.blind = true;
  final analyzed = <String>[];
  final store = _fakeStore(analyzed);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<GameController>.value(value: game),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<Maia3Store>.value(value: store),
    ],
    child: const MaterialApp(home: Scaffold(body: Maia3Pane())),
  ));
  return (game, store, analyzed);
}

void main() {
  testWidgets('asks the store for the board position and draws the chart',
      (tester) async {
    final (game, _, analyzed) = await _pump(tester);
    // post-frame setPosition + the 250ms debounce + the async analyze
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(analyzed, [game.displayFen],
        reason: 'one request, for the shown position');
    expect(find.byType(Maia3ChartCanvas), findsOneWidget);
    expect(find.textContaining('by rating'), findsOneWidget);

    // and it settles: further frames must not re-ask (the build-loop class)
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(analyzed.length, 1);
    game.dispose();
  });

  testWidgets('blind mode with a bot hides the curves', (tester) async {
    final settings = await loadSettings(black: kTestBotId);
    final game = GameController(
        FakeArbiter(), const FakeBot(), FakeGrading(), settings);
    settings.blind = true;
    final analyzed = <String>[];
    final store = _fakeStore(analyzed);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<GameController>.value(value: game),
        ChangeNotifierProvider<SettingsStore>.value(value: settings),
        ChangeNotifierProvider<Maia3Store>.value(value: store),
      ],
      child: const MaterialApp(home: Scaffold(body: Maia3Pane())),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Blind mode'), findsOneWidget);
    expect(find.byType(Maia3ChartCanvas), findsNothing);
    expect(analyzed, isEmpty, reason: 'blind must not even ask');
    game.dispose();
  });

  testWidgets(
      'Played asks for the pre-move position and pins the played move',
      (tester) async {
    final settings = await loadSettings();
    final game = GameController(
        FakeArbiter(), const FakeBot(), FakeGrading(), settings);
    final fenBeforeMove = game.position.fen;
    game.playUci('e2e4');
    final analyzed = <String>[];
    final store = _fakeStore(analyzed);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<GameController>.value(value: game),
        ChangeNotifierProvider<SettingsStore>.value(value: settings),
        ChangeNotifierProvider<Maia3Store>.value(value: store),
      ],
      child: const MaterialApp(home: Scaffold(body: Maia3Pane())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(analyzed, [game.displayFen],
        reason: 'defaults to next (prospective)');

    await tester.tap(find.text('Played'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(analyzed.last, fenBeforeMove,
        reason: 'Played asks about the position before the played move');
    expect(find.byType(Maia3ChartCanvas), findsOneWidget);
    game.dispose();
  });

  testWidgets(
      'Played skips a bots auto-reply and pins the humans own move',
      (tester) async {
    final settings = await loadSettings(black: kTestBotId);
    final game = GameController(
        FakeArbiter(), const FakeBot(), FakeGrading(), settings);
    final fenBeforeHumanMove = game.position.fen;
    game.playUci('e2e4'); // the human (White) move
    final fenAfterHumanMove = game.position.fen;
    // The fake arbiter's search never resolves, so the bot never actually
    // replies here — append its move directly to simulate one having landed
    // before the panel asks. This is the exact shape that broke retro mode:
    // moves.last stops being the human's move the instant the bot moves.
    game.moves.add(MoveRecord(
      ply: 2,
      san: 'e5',
      uci: 'e7e5',
      color: 'b',
      fenBefore: fenAfterHumanMove,
      fenAfter: fenAfterHumanMove, // content unused by _lastPlayerMove
    ));
    final analyzed = <String>[];
    final store = _fakeStore(analyzed);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<GameController>.value(value: game),
        ChangeNotifierProvider<SettingsStore>.value(value: settings),
        ChangeNotifierProvider<Maia3Store>.value(value: store),
      ],
      child: const MaterialApp(home: Scaffold(body: Maia3Pane())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    await tester.tap(find.text('Played'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(analyzed.last, fenBeforeHumanMove,
        reason: 'Played must attribute to the human move (e4), not the '
            "bot's auto-reply (e5)");
    game.dispose();
  });

  testWidgets('Played with no move played yet shows a note, not a request',
      (tester) async {
    final (game, _, analyzed) = await _pump(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    analyzed.clear();

    await tester.tap(find.text('Played'));
    await tester.pump();

    expect(find.text('Play a move to see it here.'), findsOneWidget);
    expect(analyzed, isEmpty);
    game.dispose();
  });
}
