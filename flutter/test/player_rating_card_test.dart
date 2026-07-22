// What the game-over recap actually draws, at phone width, in the font the
// app bundles.
//
// A clean analyzer and a green unit suite say nothing about layout, and this
// card has the two shapes that go wrong: a large number beside a delta chip on
// one line, and two paragraphs of explanation on the empty state. Both are
// pumped at 375px with the real Roboto loaded from assets/fonts, the pattern
// review_summary_test.dart established — the default test font is a
// fixed-width placeholder and would size every one of these lines wrong.
//
// The store underneath is the real one over the real bundle (see
// support/node_brain.dart), so what is rendered here is a rating the brain
// actually returned rather than a number a stub was told to produce.
//
//   cd flutter && flutter test test/player_rating_card_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/rating_api.dart';
import 'package:botvinnik_mobile/stores/player_rating_store.dart';
import 'package:botvinnik_mobile/ui/player_rating_card.dart';

import 'support/fake_db.dart';
import 'support/node_brain.dart';

/// The narrow phone the app is laid out against elsewhere (see layout_test).
const Size _phone = Size(375, 812);

Map<String, dynamic> _game({
  required String id,
  required String result,
  String? persona = 'squarefish-1200',
  bool fallback = false,
  int undos = 0,
  bool rated = true,
}) =>
    {
      'id': id,
      'endedAt': '2026-07-20T10:00:00.000',
      'result': result,
      'pgn': '1. e4 e5 *',
      'botPersona': ?persona,
      if (fallback) 'botFallback': true,
      if (undos > 0) 'botUndos': undos,
      // Rated by default since #168: the gate, without which the fit is empty
      // and every assertion below is about an empty card. See the note on the
      // same helper in player_rating_test.dart.
      if (persona != null && rated) 'rated': true,
      if (persona != null) 'botHintsUsed': false,
      'botColor': 'b',
      'moveCount': 2,
      'moves': const [],
    };

/// Six mixed results across four Squares: enough information for the fit to
/// come back under the confidence floor, so the number is actually printed.
List<Map<String, dynamic>> _mixed() => [
      _game(id: 'm5', result: '1-0'),
      _game(id: 'm4', result: '0-1', persona: 'squarefish-1400'),
      _game(id: 'm3', result: '1/2-1/2'),
      _game(id: 'm2', result: '1-0', persona: 'squarefish-1100'),
      _game(id: 'm1', result: '0-1'),
      _game(id: 'm0', result: '1-0', persona: 'squarefish-1000'),
    ];

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

/// Pumps the card exactly as the recap does — inside the scrolling panel
/// column, at the width the phone layout gives it.
Future<PlayerRatingStore> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> newestFirst,
) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final store = PlayerRatingStore(
      FakeDb(newestFirst.reversed.toList()), RatingApi(NodeBrainBridge()));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Roboto'),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChangeNotifierProvider<PlayerRatingStore>.value(
              value: store,
              child: const PlayerRatingCard(),
            ),
          ],
        ),
      ),
    ),
  ));
  // the fit is async (the archive read) — one pump to run it, one to draw it
  await tester.pumpAndSettle();
  return store;
}

/// Every Text on screen, joined — cheaper to assert against than a dozen
/// separate finders when what matters is the sentence.
String _text(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  testWidgets('prints the rating, the sample size and the error bar',
      (tester) async {
    final store = await _pump(tester, _mixed());
    final rating = store.rating!;

    expect(find.text('YOUR RATING'), findsOneWidget);
    expect(find.text('${rating.elo}'), findsOneWidget,
        reason: 'the number on screen is the one the brain returned');
    expect(_text(tester), contains('from 6 rated games'));
    expect(_text(tester), contains('give or take ${rating.se}'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty archive offers no number at all', (tester) async {
    await _pump(tester, []);
    expect(_text(tester), contains('No rated games yet'));
    // The explanation names the MODE first. Since #168 a player can have
    // finished twenty clean games and still be here, and copy that only listed
    // the refusals would send them looking for a fault in games that had none.
    expect(_text(tester), contains('Rated game'));
    expect(_text(tester), contains('takeback'));
    expect(_text(tester), contains('substituted'));
    expect(find.textContaining('give or take'), findsNothing);
  });

  testWidgets('one game shows progress, never a four-digit figure',
      (tester) async {
    final store = await _pump(tester, [_game(id: 'a', result: '1-0')]);
    expect(store.rating, isNotNull, reason: 'the fit exists');
    expect(_text(tester), contains('Not enough rated games yet'));
    expect(_text(tester), contains('1 game counts so far'));
    expect(find.text('${store.rating!.elo}'), findsNothing,
        reason: 'a number this uncertain reads as a measurement and is not one');
  });

  testWidgets('a refused game says so, and shows no change', (tester) async {
    await _pump(tester, [_game(id: 'undone', result: '1-0', undos: 2), ..._mixed()]);
    expect(_text(tester),
        contains('This game did not count: you took 2 moves back.'));
    expect(_text(tester), contains('from 6 rated games'),
        reason: 'the refused game is not in the sample either');
  });

  testWidgets('a counted game shows which way the number moved',
      (tester) async {
    // A loss to a weaker bot on top of the mixed run: the estimate falls, so
    // the arrow points down and the amount is the size of the fall.
    final store = await _pump(
        tester, [_game(id: 'new', result: '0-1', persona: 'squarefish-1000'), ..._mixed()]);
    expect(store.delta, isNotNull);
    expect(store.delta, lessThan(0));
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.text('${store.delta!.abs()}'), findsOneWidget);
  });

  testWidgets('while the finished game is still being archived, it says so',
      (tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = FakeDb(_mixed().reversed.toList());
    final store = PlayerRatingStore(db, RatingApi(NodeBrainBridge()),
        pollInterval: const Duration(milliseconds: 20),
        pollDeadline: const Duration(milliseconds: 200));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Roboto'),
      home: Scaffold(
        body: ChangeNotifierProvider<PlayerRatingStore>.value(
          value: store,
          // what main.dart's recap builds
          child: const PlayerRatingCard(afterGame: true),
        ),
      ),
    ));

    await tester.pump();
    await tester.pump();
    expect(_text(tester), contains('Adding this game...'),
        reason: 'the record has not landed yet, and the number on screen is '
            'the one from before the game — the card has to admit that');
    expect(_text(tester), contains('from 6 rated games'));

    await db.saveGame(_game(id: 'late', result: '1-0'));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();

    expect(_text(tester), isNot(contains('Adding this game...')));
    expect(_text(tester), contains('from 7 rated games'),
        reason: 'the game the recap is about is now in the fit');
  });

  testWidgets('a first rated game being scored does not claim "no rated games"',
      (tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Empty archive: this IS the player's first rated game, still being scored.
    // After a checkmate that window is ~16s, so the empty-state CTA must not
    // assert "you have none" over the top of "Adding this game...".
    final db = FakeDb([]);
    final store = PlayerRatingStore(db, RatingApi(NodeBrainBridge()),
        pollInterval: const Duration(milliseconds: 20),
        pollDeadline: const Duration(milliseconds: 400));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Roboto'),
      home: Scaffold(
        body: ChangeNotifierProvider<PlayerRatingStore>.value(
          value: store,
          child: const PlayerRatingCard(afterGame: true),
        ),
      ),
    ));

    await tester.pump();
    await tester.pump();
    expect(_text(tester), contains('Adding this game...'));
    expect(_text(tester), isNot(contains('No rated games yet')),
        reason: 'the how-to-get-a-rating CTA must not verdict "none" on a game '
            'that is still being scored');

    await db.saveGame(_game(id: 'first', result: '1-0'));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();

    expect(_text(tester), isNot(contains('Adding this game...')));
    expect(_text(tester), contains('1 game counts so far'),
        reason: 'the first rated game landed and counts');
  });

  test('main.dart wires the card up', () {
    // The card reads its store from the tree in initState, so a missing
    // provider is a crash at game over and nothing else — no analyzer
    // complaint, no failing widget test, because every test here supplies its
    // own. Same shape and same reason as provider_parity_test.dart.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('PlayerRatingStore('),
        reason: 'nothing provides the store the card reads');
    expect(main, contains('PlayerRatingCard('),
        reason: 'the card is built nowhere, so the rating is unreachable');
  });

  testWidgets('nothing overflows at 375px, in any state', (tester) async {
    for (final archive in [
      <Map<String, dynamic>>[],
      [_game(id: 'a', result: '1-0')],
      _mixed(),
      [_game(id: 'stood-in', result: '1-0', fallback: true), ..._mixed()],
      [_game(id: 'w', result: '1-0', persona: 'squarefish-600'), ..._mixed()],
    ]) {
      await _pump(tester, archive);
      // A RenderFlex overflow is reported as an exception rather than a failed
      // assertion, so it is invisible to every finder above.
      expect(tester.takeException(), isNull,
          reason: 'archive of ${archive.length} overflowed');
      expect(
          tester.getSize(find.byType(PlayerRatingCard)).width, lessThanOrEqualTo(375));
    }
  });
}
