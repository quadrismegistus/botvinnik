// The inline opponent picker: it must offer families, resolve a family tap to a
// concrete persona (the calibrated median), give an ELO family a slider and a
// variant family (Maia) a segmented pick — all without changing which persona
// ids the roster produces.
//
//   cd flutter && flutter test test/bot_picker_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/ui/bot_picker.dart';

import 'support/game_harness.dart';

Persona _p(String id, String name, int elo, String family) =>
    Persona({'id': id, 'name': name, 'elo': elo, 'family': family, 'blurb': ''});

Future<GameController> _game() async {
  final settings = await loadSettings(); // both null → analysis, no bot turn
  return GameController(FakeArbiter(), FakeBot(_roster), FakeGrading(), settings);
}

final _roster = <String, Persona>{
  'squarefish-1000': _p('squarefish-1000', 'Squarefish 1000', 1000, 'squarefish'),
  'squarefish-1300': _p('squarefish-1300', 'Squarefish 1300', 1300, 'squarefish'),
  'squarefish-1600': _p('squarefish-1600', 'Squarefish 1600', 1600, 'squarefish'),
  'squarefish-1900': _p('squarefish-1900', 'Squarefish 1900', 1900, 'squarefish'),
  'maia-1500': _p('maia-1500', 'Maia V', 1500, 'maia'),
  'maia-1900': _p('maia-1900', 'Maia IX', 1900, 'maia'),
};

/// Pumps the picker with a StatefulBuilder holding the selection, so a change
/// reflects back the way the real sheet drives it.
Future<ValueNotifier<String?>> _pump(
    WidgetTester tester, GameController game,
    {String? initial}) async {
  final sel = ValueNotifier<String?>(initial);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<String?>(
        valueListenable: sel,
        builder: (_, value, _) => BotPicker(
          label: 'White',
          game: game,
          selectedId: value,
          onChanged: (id) => sel.value = id,
          onBrowseAll: () {},
        ),
      ),
    ),
  ));
  await tester.pump();
  return sel;
}

void main() {
  testWidgets('offers families and You, and a family tap lands on a persona',
      (tester) async {
    final game = await _game();
    addTearDown(game.dispose);
    final sel = await _pump(tester, game);

    expect(find.text('You'), findsOneWidget);
    expect(find.text('Squarefish'), findsOneWidget);
    expect(find.text('Maia'), findsOneWidget);

    await tester.tap(find.text('Squarefish'));
    await tester.pump();
    // Median of the four squarefish steps (index 2): squarefish-1600.
    expect(sel.value, 'squarefish-1600');
  });

  testWidgets('an ELO family gets a slider; moving nothing keeps the pick',
      (tester) async {
    final game = await _game();
    addTearDown(game.dispose);
    await _pump(tester, game, initial: 'squarefish-1300');

    expect(find.byType(Slider), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.max, 3); // four steps → divisions 0..3
    expect(slider.value, 1); // 1300 is index 1
  });

  testWidgets('a variant family (Maia) gets a segmented pick, not a slider',
      (tester) async {
    final game = await _game();
    addTearDown(game.dispose);
    await _pump(tester, game, initial: 'maia-1500');

    expect(find.byType(Slider), findsNothing);
    // the nets, by name, as segmented choices
    expect(find.text('Maia V'), findsWidgets);
    expect(find.text('Maia IX'), findsWidgets);
  });
}
