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
}
