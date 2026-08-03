// The "practise this game's mistakes" affordance in Review (#197): a button in
// the move-list header that hands this game's collected blunder positions to
// the Practice tab. Pumps the real [ReviewBody] over a real
// [PracticeController] (fake persistence), so the button's presence, its count,
// and the exact fens it hands on are all asserted through the widget the app
// builds.
//
//   cd flutter && flutter test test/review_practise_game_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/db/app_db.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/grade_strip.dart';
import 'package:botvinnik_mobile/ui/review_screen.dart';

import 'package:botvinnik_mobile/stores/game_controller.dart';

import '../support/game_harness.dart';
import '../support/practice_harness.dart';

const _kStartFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _kAfterE4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
const _kAfterE5 =
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2';
const _kAfterNf3 =
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
const _kAfterNc6 =
    'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';

const _kClassRaw = {
  'best': {'glyph': '★', 'color': '#81b64c', 'noun': 'the best move'},
  'inaccuracy': {'glyph': '?!', 'color': '#f0c15c', 'noun': 'an inaccuracy'},
  'blunder': {'glyph': '??', 'color': '#ca3431', 'noun': 'a blunder'},
};

class _StubDb implements AppDb {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Map<String, dynamic> _game() => {
      'id': 'g-1',
      'endedAt': '2026-07-20T10:11:00.000',
      'result': '1-0',
      'botColor': 'b',
      'moveCount': 4,
      'whiteAccuracy': 84.2,
      'blackAccuracy': 71.9,
      'moves': [
        {
          'ply': 1,
          'san': 'e4',
          'uci': 'e2e4',
          'color': 'w',
          'fenBefore': _kStartFen,
          'fenAfter': _kAfterE4,
          'label': 'best',
        },
        {
          'ply': 2,
          'san': 'e5',
          'uci': 'e7e5',
          'color': 'b',
          'fenBefore': _kAfterE4,
          'fenAfter': _kAfterE5,
          'label': 'blunder',
          'bestSan': 'c5',
          'bestUci': 'c7c5',
        },
        {
          'ply': 3,
          'san': 'Nf3',
          'uci': 'g1f3',
          'color': 'w',
          'fenBefore': _kAfterE5,
          'fenAfter': _kAfterNf3,
          'label': 'blunder',
          'bestSan': 'd4',
          'bestUci': 'd2d4',
        },
        {
          'ply': 4,
          'san': 'Nc6',
          'uci': 'b8c6',
          'color': 'b',
          'fenBefore': _kAfterNf3,
          'fenAfter': _kAfterNc6,
          'label': 'best',
        },
      ],
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

Future<Map<String, String>> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> collection,
  Map<String, dynamic>? game,
}) async {
  Map<String, String>? handed;
  final settings = await loadSettings();
  final review = ReviewController(_StubDb())..open(game ?? _game());
  final h = makePractice(collection);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ClassTable>.value(
          value: ClassTable(_kClassRaw, labelOrder: const [])),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<ReviewController>.value(value: review),
      ChangeNotifierProvider<ReviewBoardController>.value(
          value: fakeReviewBoard(review, settings)),
      ChangeNotifierProvider<PracticeController>.value(value: h.practice),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: ReviewBody(onPractiseGame: (fens) => handed = fens),
      ),
    ),
  ));
  await tester.pump();
  return handed ?? _sentinel;
}

// A private sentinel so "callback not yet fired" (null) is distinguishable
// from "fired with an empty map". _pump returns this when nothing was handed.
final Map<String, String> _sentinel = {'<not-fired>': ''};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadRoboto);

  testWidgets('offers the button, counting only this game\'s collected mistakes',
      (tester) async {
    // Two collected items: one on this game's blundered position, one from
    // some other game. Only the first should count.
    await _pump(tester, collection: [
      practiceItem(_kStartFen, playedUci: 'e2e4'), // your blunder here
      practiceItem('rnbqkbnr/ppp1pppp/8/3p4/8/8/PPPPPPPP/RNBQKBNR w KQkq d6 0 2'),
    ]);

    expect(find.text("Practise this game's mistake"), findsOneWidget,
        reason: 'exactly one of this game\'s positions is collected');
  });

  testWidgets('does not offer the bot\'s own blunders', (tester) async {
    // botColor is 'b', so every black ply is the bot's. A puzzle sitting on one
    // of those positions belongs to some OTHER game in which the player had
    // Black — an item's id is its fen, deduped across the whole collection —
    // and drilling it here is being asked to fix a move you never made (#285).
    final handed = await _pump(tester, collection: [
      practiceItem(_kAfterE4, playedUci: 'e7e5'), // the bot's ply, exactly
      practiceItem(_kAfterNf3, playedUci: 'b8c6'), // and the other one
    ]);

    expect(handed, _sentinel);
    expect(find.textContaining("Practise this game"), findsNothing,
        reason: 'both collected positions are the bot\'s');
  });

  testWidgets('does not offer another game\'s puzzle at a shared position',
      (tester) async {
    // The same position, a different move played there — so a different game's
    // mistake. Opening positions collide constantly.
    final handed = await _pump(tester, collection: [
      practiceItem(_kStartFen, playedUci: 'd2d4'), // you played e4 in THIS game
    ]);

    expect(handed, _sentinel);
    expect(find.textContaining("Practise this game"), findsNothing);
  });

  testWidgets('pluralises the count when the game has several mistakes',
      (tester) async {
    // Both of this game's move-before positions are collected.
    final handed = await _pump(tester, collection: [
      practiceItem(_kStartFen, playedUci: 'e2e4'),
      practiceItem(_kAfterE5, playedUci: 'g1f3'),
    ]);

    expect(handed, _sentinel, reason: 'nothing handed on until the tap');
    expect(find.text("Practise this game's 2 mistakes"), findsOneWidget);
  });

  testWidgets('tapping hands the game\'s move-before fens to the callback',
      (tester) async {
    Map<String, String>? handed;
    final settings = await loadSettings();
    final review = ReviewController(_StubDb())..open(_game());
    final h = makePractice([practiceItem(_kStartFen, playedUci: 'e2e4')]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ClassTable>.value(
            value: ClassTable(_kClassRaw, labelOrder: const [])),
        ChangeNotifierProvider<SettingsStore>.value(value: settings),
        ChangeNotifierProvider<ReviewController>.value(value: review),
      ChangeNotifierProvider<ReviewBoardController>.value(
          value: fakeReviewBoard(review, settings)),
        ChangeNotifierProvider<PracticeController>.value(value: h.practice),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ReviewBody(onPractiseGame: (fens) => handed = fens),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text("Practise this game's mistake"));
    await tester.pump();

    expect(handed, {_kStartFen: 'e2e4', _kAfterE5: 'g1f3'},
        reason: 'YOUR positions, each with the move you played there — the bot '
            'plies are not yours to drill, and the move is what tells this '
            "game's item apart from another game's at the same position");
  });

  testWidgets('no button when none of this game\'s positions are collected',
      (tester) async {
    final handed = await _pump(tester, collection: [
      practiceItem('rnbqkbnr/ppp1pppp/8/3p4/8/8/PPPPPPPP/RNBQKBNR w KQkq d6 0 2'),
    ]);
    expect(handed, _sentinel);
    expect(find.textContaining("Practise this game"), findsNothing,
        reason: 'an ungraded or already-curated game offers no dead button');
  });

  testWidgets('no button when the shell provides no target', (tester) async {
    // onPractiseGame null — e.g. a standalone board with no tab to jump to.
    final settings = await loadSettings();
    final review = ReviewController(_StubDb())..open(_game());
    final h = makePractice([practiceItem(_kStartFen, playedUci: 'e2e4')]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ClassTable>.value(
            value: ClassTable(_kClassRaw, labelOrder: const [])),
        ChangeNotifierProvider<SettingsStore>.value(value: settings),
        ChangeNotifierProvider<ReviewController>.value(value: review),
      ChangeNotifierProvider<ReviewBoardController>.value(
          value: fakeReviewBoard(review, settings)),
        ChangeNotifierProvider<PracticeController>.value(value: h.practice),
      ],
      child: const MaterialApp(home: Scaffold(body: ReviewBody())),
    ));
    await tester.pump();
    expect(find.textContaining("Practise this game"), findsNothing);
  });
}
