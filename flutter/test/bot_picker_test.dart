// The family-first "Pick a bot" modal: it lists ELO families as one row that
// opens a strength slider, lists distinct opponents (Maia's nets) directly, and
// whichever way you go it returns one of the roster's own persona ids.
//
//   cd flutter && flutter test test/bot_picker_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/ui/bot_picker.dart';

import 'support/game_harness.dart';

Persona _p(String id, String name, int elo, String family) => Persona(
    {'id': id, 'name': name, 'elo': elo, 'family': family, 'blurb': 'blurb'});

final _roster = <String, Persona>{
  'squarefish-1000': _p('squarefish-1000', 'Squarefish 1000', 1000, 'squarefish'),
  'squarefish-1300': _p('squarefish-1300', 'Squarefish 1300', 1300, 'squarefish'),
  'squarefish-1600': _p('squarefish-1600', 'Squarefish 1600', 1600, 'squarefish'),
  'squarefish-1900': _p('squarefish-1900', 'Squarefish 1900', 1900, 'squarefish'),
  'maia-1500': _p('maia-1500', 'Maia V', 1500, 'maia'),
  'maia-1900': _p('maia-1900', 'Maia IX', 1900, 'maia'),
};

/// Pumps a launcher that opens the modal, and returns a getter for its result.
Future<String? Function()> _open(WidgetTester tester, GameController game) async {
  String? result;
  var done = false;
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider<GameController>.value(
      value: game,
      child: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await pickBotFamily(ctx);
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => done ? result : null;
}

void main() {
  testWidgets('lists ELO families as one row and variants directly',
      (tester) async {
    final settings = await loadSettings();
    final game =
        GameController(FakeArbiter(), FakeBot(_roster), FakeGrading(), settings);
    addTearDown(game.dispose);
    await _open(tester, game);

    expect(find.text('Pick a bot'), findsOneWidget);
    // the ELO family, one row
    expect(find.text('Squarefish'), findsOneWidget);
    // the nets, listed directly (title is "<name>  ·  <elo>")
    expect(find.textContaining('Maia V'), findsOneWidget);
    expect(find.textContaining('Maia IX'), findsOneWidget);
    // and there is no bare "Maia" family row — Maia is not a slider
    expect(find.text('Maia'), findsNothing);
    expect(find.text('Browse all…'), findsOneWidget);
  });

  testWidgets('an ELO family opens a slider and returns the chosen persona',
      (tester) async {
    final settings = await loadSettings();
    final game =
        GameController(FakeArbiter(), FakeBot(_roster), FakeGrading(), settings);
    addTearDown(game.dispose);
    final result = await _open(tester, game);

    await tester.tap(find.text('Squarefish'));
    await tester.pumpAndSettle();

    // the strength sub-page
    expect(find.byType(Slider), findsOneWidget);
    // defaulted to the median step (index 2 of four): Squarefish 1600
    expect(find.text('Play Squarefish 1600'), findsOneWidget);

    await tester.tap(find.text('Play Squarefish 1600'));
    await tester.pumpAndSettle();
    expect(result(), 'squarefish-1600');
  });

  testWidgets('a variant row returns that persona directly', (tester) async {
    final settings = await loadSettings();
    final game =
        GameController(FakeArbiter(), FakeBot(_roster), FakeGrading(), settings);
    addTearDown(game.dispose);
    final result = await _open(tester, game);

    await tester.tap(find.textContaining('Maia IX'));
    await tester.pumpAndSettle();
    expect(result(), 'maia-1900');
  });
}
