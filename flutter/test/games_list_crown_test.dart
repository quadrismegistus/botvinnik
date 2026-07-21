// The archive's crown: a human win over a bot, and how clean it was.
//
// A result alone teaches you to farm easy wins, so the row says HOW the game
// was won — solid crown for clean, outline plus an itemised line for a win
// with help. The rule the Svelte archive drew and this must keep: an ABSENT
// `botHintsUsed` is "hints unknown", not clean. Every game archived before
// GameController started writing the field is in that state.
//
// The layout half loads the REAL bundled Roboto, because a green suite and a
// clean analyzer say nothing about whether a row fits on a phone.
//
//   cd flutter && flutter test test/games_list_crown_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/pgn_import.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/ui/games_list.dart';

import 'support/fake_db.dart';
import 'support/game_harness.dart';

/// A stored bot game. The human is White (`botColor: 'b'`), so '1-0' is a win
/// for the human and '0-1' a loss. [hints] is deliberately three-valued: null
/// means the record has no `botHintsUsed` at all.
Map<String, dynamic> storedGame({
  String result = '1-0',
  String botColor = 'b',
  int? undos,
  bool? hints = false,
  bool fallback = false,
  bool imported = false,
  String id = 'g-1',
}) =>
    {
      'id': id,
      'endedAt': '2026-07-21T10:30:00.000',
      'result': result,
      'botElo': 1740,
      'botPersona': 'squarefish-1500',
      'botColor': botColor,
      'moveCount': 42,
      'whiteAccuracy': 81.4,
      'blackAccuracy': 74.2,
      'labelCounts': {
        'w': {'blunder': 1, 'mistake': 2},
        'b': {'blunder': 0, 'mistake': 0},
      },
      'moves': const [],
      // `?` omits the key entirely when the value is null, which is the state
      // this fixture exists to reproduce: a record written before the field was
      'botUndos': ?undos,
      'botHintsUsed': ?hints,
      if (fallback) 'botFallback': true,
      if (imported) kImportedKey: true,
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

/// The archive tab, populated with [games], at [width] logical pixels.
Future<void> pumpArchive(WidgetTester tester, List<Map<String, dynamic>> games,
    {double width = 375}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final review = ReviewController(FakeDb(games));
  await review.loadGames();
  final game = await makeGame();

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<GameController>.value(value: game),
      ChangeNotifierProvider<ReviewController>.value(value: review),
    ],
    child: const MaterialApp(home: Scaffold(body: GamesListBody())),
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  group('winCrown', () {
    test('a clean win earns the solid crown', () {
      final c = winCrown(storedGame(hints: false))!;
      expect(c.clean, isTrue);
      expect(c.detail, 'Won clean — blind, no takebacks');
    });

    test('an ABSENT botHintsUsed is unknown, not clean', () {
      // The whole archive predates the field. Treating absent as false would
      // hand the solid crown to every old win on no evidence at all.
      final c = winCrown(storedGame(hints: null))!;
      expect(c.clean, isFalse);
      expect(c.detail, contains('hints unknown'));
    });

    test('takebacks, a stand-in and hints are itemised together', () {
      final c = winCrown(
          storedGame(undos: 3, hints: true, fallback: true))!;
      expect(c.clean, isFalse);
      expect(c.detail,
          'Won with help — 3 takebacks, engine stand-in, hint overlays');
    });

    test('one takeback is singular', () {
      expect(winCrown(storedGame(undos: 1))!.detail,
          'Won with help — 1 takeback');
    });

    test('a loss, a draw and the bot\'s own win earn nothing', () {
      expect(winCrown(storedGame(result: '0-1')), isNull);
      expect(winCrown(storedGame(result: '1/2-1/2')), isNull);
      // same result, the human on the other side: now it is the bot's win
      expect(winCrown(storedGame(result: '1-0', botColor: 'w')), isNull);
    });

    test('the human as Black wins with 0-1', () {
      expect(winCrown(storedGame(result: '0-1', botColor: 'w'))?.clean, isTrue);
    });

    test('analysis games and imports have no "you" to crown', () {
      final solo = storedGame()..['botElo'] = null;
      expect(winCrown(solo), isNull);
      expect(winCrown(storedGame(imported: true)), isNull);
    });
  });

  group('the archive row', () {
    testWidgets('a clean win draws the solid crown and says so',
        (tester) async {
      await pumpArchive(tester, [storedGame(hints: false)]);

      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events_outlined), findsNothing);
      expect(find.text('Won clean — blind, no takebacks'), findsOneWidget);
    });

    testWidgets('a helped win draws the outline and itemises the help',
        (tester) async {
      await pumpArchive(
          tester, [storedGame(undos: 2, hints: true, fallback: true)]);

      expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsNothing);
      expect(
          find.text(
              'Won with help — 2 takebacks, engine stand-in, hint overlays'),
          findsOneWidget);
    });

    testWidgets('a game from before the tracking gets the outline',
        (tester) async {
      await pumpArchive(tester, [storedGame(hints: null)]);

      expect(find.byIcon(Icons.emoji_events), findsNothing,
          reason: 'unknown must never look like clean');
      expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
    });

    testWidgets('a loss carries no crown and no extra line', (tester) async {
      await pumpArchive(tester, [storedGame(result: '0-1')]);

      expect(find.byIcon(Icons.emoji_events), findsNothing);
      expect(find.byIcon(Icons.emoji_events_outlined), findsNothing);
      expect(find.textContaining('Won'), findsNothing);
    });

    testWidgets('the crown is gold when clean and muted when helped',
        (tester) async {
      await pumpArchive(tester,
          [storedGame(hints: false, id: 'a'), storedGame(undos: 1, id: 'b')]);

      final clean =
          tester.widget<Icon>(find.byIcon(Icons.emoji_events));
      final helped =
          tester.widget<Icon>(find.byIcon(Icons.emoji_events_outlined));
      expect(clean.color, const Color(0xFFD4A017));
      expect(helped.color, isNot(const Color(0xFFD4A017)));
    });
  });

  // The worst row the crown can produce is three help items on top of the
  // existing date/moves/blunders line, on the narrowest phones. A RenderFlex
  // overflow is a runtime layout error: the analyzer and a green suite both say
  // nothing about it.
  for (final width in [375.0, 320.0]) {
    testWidgets('the longest helped row does not overflow at $width',
        (tester) async {
      await pumpArchive(
          tester,
          [
            storedGame(undos: 12, hints: true, fallback: true, id: 'a'),
            storedGame(hints: false, id: 'b'),
            storedGame(hints: null, id: 'c'),
            storedGame(result: '0-1', id: 'd'),
          ],
          width: width);

      final detail = find.text(
          'Won with help — 12 takebacks, engine stand-in, hint overlays');
      expect(detail, findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'the archive row overflowed at $width');

      // A ListTile positions its subtitle rather than flexing around it, so a
      // second line that does not fit paints OUTSIDE the tile — over the row
      // below — without any overflow error to catch. Only the geometry says so.
      // A ListTile grows to fit a wrapped subtitle — measured here: this row is
      // 68px tall at 375 and 84 at 320, where the help line takes two lines.
      // The guard is against that stopping being true (a fixed-height row would
      // paint the line over the one below with no overflow error to catch).
      // Its OWN tile: the list is newest-first, so the rows are not in the
      // order the games are declared above.
      final tile = tester.getRect(
          find.ancestor(of: detail, matching: find.byType(ListTile)));
      expect(tester.getRect(detail).bottom, lessThanOrEqualTo(tile.bottom),
          reason: 'the help line spilled out of its own row at $width');
    });
  }
  test('a bot-vs-bot game earns nobody a crown', () {
    // playerColor falls back to 'w' when both sides carry a persona, so such a
    // game archives with botColor 'b', a real botElo and botHintsUsed false —
    // which read as "the human played White, blind, and won". Nobody played it.
    expect(
        winCrown({
          'result': '1-0',
          'botElo': 1440,
          'botColor': 'b',
          'botHintsUsed': false,
          'botBothSides': true,
        }),
        isNull);
  });

}
