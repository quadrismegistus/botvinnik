// The plate's Row has to survive a narrow phone with a long persona name, a
// full captured-piece tray and the stand-in badge all at once.
//
// Loads the REAL bundled Roboto rather than testing under Ahem, whose glyphs
// are uniform squares and much wider than Roboto's — an Ahem measurement is not
// evidence about what a player sees.
//
//   cd flutter && flutter test test/player_plate_overflow_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/player_plate.dart';

import 'support/game_harness.dart';

/// The longest name on the roster (`brain/bots.ts`), on the family that has no
/// engine of its own — so the badge is showing at the same time.
const _kLongBotId = 'maia-s-1900';
const _longNameBot = Persona({
  'id': _kLongBotId,
  'name': 'Maia III (sampled)',
  'elo': 1440,
  'family': 'dala', // falls through to the stand-in, so the badge is visible
  'blurb': '',
});

/// White to move, d2d4 legal, and black is missing a rook, knight, bishop,
/// queen and one pawn — so White's tray shows five captured pieces.
const _fiveCaptures = '4kbnr/1ppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQk - 0 1';

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

/// Black has lost all eight pawns — the widest the tray realistically gets,
/// since captured pieces stack by role and pawns are the numerous one.
const _eightCaptures =
    'rnbqkbnr/8/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  testWidgets('a long name, five captures and the badge do not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(375, 800); // iPhone SE / mini class
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final settings = await loadSettings(white: _kLongBotId);
    final game = GameController(
        FakeArbiter(
            analysisLines: kFakeLines,
            streamPartials: true,
            searchLines: kFakeLines),
        const FakeBot({_kLongBotId: _longNameBot}),
        FakeGrading(),
        settings);
    game.newGame(fromFen: _fiveCaptures);
    await tester.pump(const Duration(seconds: 2));

    expect(game.stoodInFor(_kLongBotId), isTrue,
        reason: 'the badge must be showing, or this proves nothing');
    expect(PlayerPlate.materialFor(game.displayFen, 'w').captured.values
            .fold<int>(0, (a, b) => a + b),
        5,
        reason: 'five captured pieces, or the tray is not under pressure');

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<GameController>.value(value: game),
        ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PlayerPlate(side: 'w')),
      ),
    ));

    // A RenderFlex overflow is a runtime layout error, not a static one — the
    // analyzer and a green suite both say nothing about it.
    expect(tester.takeException(), isNull,
        reason: 'the plate overflowed at 375px');

    settings.setPlayers(white: null, black: null);
    game.newGame();
    await tester.pump(const Duration(milliseconds: 200));
  });

  // The extremes, so the fix is not tuned to the single case that was
  // measured: a wider tray, and a narrower phone than any current model.
  for (final (label, width, fen, captures) in [
    ('eight captures at 375', 375.0, _eightCaptures, 8),
    ('five captures at 320', 320.0, _fiveCaptures, 5),
    ('eight captures at 320', 320.0, _eightCaptures, 8),
  ]) {
    testWidgets('no overflow: $label', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final settings = await loadSettings(white: _kLongBotId);
      final game = GameController(
          FakeArbiter(
              analysisLines: kFakeLines,
              streamPartials: true,
              searchLines: kFakeLines),
          const FakeBot({_kLongBotId: _longNameBot}),
          FakeGrading(),
          settings);
      game.newGame(fromFen: fen);
      await tester.pump(const Duration(seconds: 2));

      expect(
          PlayerPlate.materialFor(game.displayFen, 'w')
              .captured
              .values
              .fold<int>(0, (a, b) => a + b),
          captures);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<GameController>.value(value: game),
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PlayerPlate(side: 'w')),
        ),
      ));
      expect(tester.takeException(), isNull, reason: '$label overflowed');

      settings.setPlayers(white: null, black: null);
      game.newGame();
      await tester.pump(const Duration(milliseconds: 200));
    });
  }
}
