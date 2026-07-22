// The family-first "Pick a bot" modal and its three second pages: an ELO slider
// (Squarefish, and now Maia), a distinct-members list (Retro), and a custom
// engine's UCI_Elo cap. Every path returns a roster persona id.
//
//   cd flutter && flutter test test/bot_picker_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/custom_engine.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/ui/bot_picker.dart';

import 'support/game_harness.dart';
import 'support/memory_db.dart';

Persona _p(String id, String name, int elo, String family) => Persona(
    {'id': id, 'name': name, 'elo': elo, 'family': family, 'blurb': 'blurb'});

final _roster = <String, Persona>{
  'squarefish-1000': _p('squarefish-1000', 'Squarefish 1000', 1000, 'squarefish'),
  'squarefish-1300': _p('squarefish-1300', 'Squarefish 1300', 1300, 'squarefish'),
  'squarefish-1600': _p('squarefish-1600', 'Squarefish 1600', 1600, 'squarefish'),
  'squarefish-1900': _p('squarefish-1900', 'Squarefish 1900', 1900, 'squarefish'),
  'maia-1500': _p('maia-1500', 'Maia V', 1500, 'maia'),
  'maia-1900': _p('maia-1900', 'Maia IX', 1900, 'maia'),
  'retro-turochamp': _p('retro-turochamp', 'Turochamp', 700, 'retro'),
  'retro-bernstein': _p('retro-bernstein', 'Bernstein', 900, 'retro'),
  'retro-sargon': _p('retro-sargon', 'Sargon', 1100, 'retro'),
};

Future<CustomEngineStore> _loaded(MemoryDb db) async {
  final s = CustomEngineStore(db);
  for (var i = 0; i < 100 && !s.isLoaded; i++) {
    await Future<void>.microtask(() {});
  }
  return s;
}

/// Opens the modal over a GameController (+ optional custom store), returns a
/// getter for its result.
Future<String? Function()> _open(WidgetTester tester,
    {CustomEngineStore? engines}) async {
  final settings = await loadSettings();
  final game = GameController(FakeArbiter(), FakeBot(_roster), FakeGrading(),
      settings, null, null, null, engines);
  addTearDown(game.dispose);

  String? result;
  var done = false;
  // Providers ABOVE MaterialApp, so a modal route (a sibling of home under the
  // Navigator) can read them — the real app's shape.
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<GameController>.value(value: game),
      if (engines != null)
        ChangeNotifierProvider<CustomEngineStore>.value(value: engines),
    ],
    child: MaterialApp(
      home: Scaffold(
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
  testWidgets('Maia and Retro are families now, not loose members', (tester) async {
    await _open(tester);

    expect(find.text('Squarefish'), findsOneWidget);
    expect(find.text('Maia'), findsOneWidget); // one row, a slider behind it
    expect(find.text('Retro'), findsOneWidget); // one row, a list behind it
    // the nets/engines are NOT on page one anymore
    expect(find.textContaining('Maia V'), findsNothing);
    expect(find.textContaining('Turochamp'), findsNothing);
  });

  testWidgets('Maia opens a slider and returns a net', (tester) async {
    final result = await _open(tester);
    await tester.tap(find.text('Maia'));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsOneWidget);
    // median of two nets (index 1): Maia IX
    expect(find.text('Play Maia IX'), findsOneWidget);
    await tester.tap(find.text('Play Maia IX'));
    await tester.pumpAndSettle();
    expect(result(), 'maia-1900');
  });

  testWidgets('Retro opens a second-page list, pick returns that engine',
      (tester) async {
    final result = await _open(tester);
    await tester.tap(find.text('Retro'));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNothing); // a list, not a dial
    expect(find.textContaining('Turochamp'), findsOneWidget);
    expect(find.textContaining('Bernstein'), findsOneWidget);
    await tester.tap(find.textContaining('Sargon'));
    await tester.pumpAndSettle();
    expect(result(), 'retro-sargon');
  });

  testWidgets('a custom engine gets a cap page that persists and selects',
      (tester) async {
    final db = MemoryDb([]);
    final engines = await _loaded(db);
    await engines.upsert(const CustomEngine(
        id: 'v', name: 'Viridithas', path: '/v', elo: 3000));
    final result = await _open(tester, engines: engines);

    await tester.tap(find.text('More engines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viridithas'));
    await tester.pumpAndSettle();
    expect(find.text('Cap strength'), findsOneWidget);

    await tester.tap(find.text('Cap strength')); // turn the cap on
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);

    await tester.tap(find.text('Play Viridithas'));
    await tester.pumpAndSettle();

    expect(result(), 'custom-v');
    expect(engines.byPersonaId('custom-v')!.limitElo, isTrue,
        reason: 'the cap was persisted');
  });

  testWidgets('page one collapses engines into "More engines", weakest-first',
      (tester) async {
    final db = MemoryDb([]);
    final engines = await _loaded(db);
    await engines.upsert(const CustomEngine(
        id: 'stormphrax', name: 'Stormphrax', path: '/s', elo: 3600));
    await engines.upsert(const CustomEngine(
        id: 'velvet', name: 'Velvet', path: '/v', elo: 3450));
    await _open(tester, engines: engines);

    // page one shows one row, not a loose row per engine
    expect(find.text('More engines'), findsOneWidget);
    expect(find.text('Velvet'), findsNothing);
    expect(find.text('Stormphrax'), findsNothing);

    await tester.tap(find.text('More engines'));
    await tester.pumpAndSettle();

    // both here now, and Velvet (dials to 1225) sits above Stormphrax (fixed
    // 3600) because it can be played weaker.
    expect(find.text('Velvet'), findsOneWidget);
    expect(find.text('Stormphrax'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Velvet')).dy,
        lessThan(tester.getTopLeft(find.text('Stormphrax')).dy),
        reason: 'lowest reachable rating first');
  });

  testWidgets('a catalogued capping engine (Velvet) dials over its real range',
      (tester) async {
    final db = MemoryDb([]);
    final engines = await _loaded(db);
    // id 'velvet' matches the catalog entry, which caps 1225–3000.
    await engines.upsert(const CustomEngine(
        id: 'velvet', name: 'Velvet', path: '/velvet', elo: 3450));
    final result = await _open(tester, engines: engines);

    await tester.tap(find.text('More engines'));
    await tester.pumpAndSettle();
    // On the list, the engine advertises its dial range — rounded to hundreds.
    expect(find.textContaining('Dials 1200'), findsOneWidget);
    await tester.tap(find.text('Velvet'));
    await tester.pumpAndSettle();
    // Honest copy names the range (rounded), not a generic "may be ignored".
    expect(find.textContaining('between 1200 and 3000'), findsOneWidget);

    await tester.tap(find.text('Cap strength')); // turn the cap on
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    // Whole-hundred bounds (1225 floor shows as 1200); steps of 100.
    expect(slider.min, 1200.0);
    expect(slider.max, 3000.0);
    expect(slider.divisions, ((3000 - 1200) / 100).round());

    await tester.tap(find.text('Play Velvet'));
    await tester.pumpAndSettle();
    expect(result(), 'custom-velvet');
    final saved = engines.byPersonaId('custom-velvet')!;
    expect(saved.limitElo, isTrue);
    // stored on the whole-hundred label; the engine's real floor is applied at
    // play time by clampElo, not here.
    expect(saved.elo % 100, 0, reason: 'the stored cap is a round hundred');
    expect(saved.elo, inInclusiveRange(1200, 3000));
  });

  testWidgets('a catalogued full-strength engine offers no cap, just the fact',
      (tester) async {
    final db = MemoryDb([]);
    final engines = await _loaded(db);
    // id 'viridithas' matches the catalog entry, which has NO UCI_Elo.
    await engines.upsert(const CustomEngine(
        id: 'viridithas', name: 'Viridithas', path: '/v', elo: 3500));
    final result = await _open(tester, engines: engines);

    await tester.tap(find.text('More engines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viridithas'));
    await tester.pumpAndSettle();
    // No lying slider, no toggle — an honest note instead.
    expect(find.text('Cap strength'), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.textContaining('no rating limiter'), findsOneWidget);

    await tester.tap(find.text('Play Viridithas'));
    await tester.pumpAndSettle();
    expect(result(), 'custom-viridithas');
    expect(engines.byPersonaId('custom-viridithas')!.limitElo, isFalse);
  });

  testWidgets('Rodent is one browsable family of styles, each dialable',
      (tester) async {
    final db = MemoryDb([]);
    final engines = await _loaded(db);
    await engines.upsert(
        const CustomEngine(id: 'rodent', name: 'Rodent IV', path: '/r'));
    final result = await _open(tester, engines: engines);

    // page one: one Rodent row, not dozens of loose styles.
    expect(find.text('Rodent IV'), findsOneWidget);
    expect(find.text('Tal'), findsNothing);

    await tester.tap(find.text('Rodent IV'));
    await tester.pumpAndSettle();
    // the styles, each shown with its character.
    expect(find.text('Tal'), findsOneWidget);
    expect(find.text('Petrosian'), findsOneWidget);

    await tester.tap(find.text('Tal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cap strength')); // dial the shared strength
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect((slider.min, slider.max), (800.0, 2800.0));

    await tester.tap(find.text('Play Tal'));
    await tester.pumpAndSettle();
    expect(result(), 'custom-rodent~tal',
        reason: 'the chosen style persona, not the base engine');
  });

  testWidgets('BrainLearn is a two-style family (Classic / MCTS), dialable',
      (tester) async {
    final db = MemoryDb([]);
    final engines = await _loaded(db);
    await engines.upsert(
        const CustomEngine(id: 'brainlearn', name: 'BrainLearn', path: '/b'));
    final result = await _open(tester, engines: engines);

    expect(find.text('BrainLearn'), findsOneWidget); // one row
    expect(find.text('MCTS'), findsNothing);

    await tester.tap(find.text('BrainLearn'));
    await tester.pumpAndSettle();
    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('MCTS'), findsOneWidget);

    await tester.tap(find.text('MCTS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cap strength'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect((slider.min, slider.max), (1300.0, 3200.0)); // rounded to hundreds

    await tester.tap(find.text('Play MCTS'));
    await tester.pumpAndSettle();
    expect(result(), 'custom-brainlearn~mcts');
    // the style sends a plain UCI option, not a file
    expect(engines.styleOptionFor('custom-brainlearn~mcts'), 'MCTS value true');
  });

  testWidgets('a long custom engine name does not overflow the cap page',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = MemoryDb([]);
    final engines = await _loaded(db);
    await engines.upsert(const CustomEngine(
        id: 'v',
        name: 'Stockfish 17 Development Build NNUE big-net long name',
        path: '/v',
        elo: 3000));
    await _open(tester, engines: engines);

    await tester.tap(find.text('More engines'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Stockfish 17 Development'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'the cap-page back bar must ellipsize a long name, not overflow');
  });
}
