// The whole-game summary at the head of Review: both sides' accuracy, and a
// count of each label ordered by the brain's LABEL_ORDER (#140).
//
// Pumps the real [ReviewBody] over a real [ReviewController] (with a stub
// database), so these assertions run through the widget the app builds rather
// than a lookalike. The label order is INJECTED through the GradingApi stub
// and deliberately permuted: a hand-written order in the widget would satisfy
// every other test in this file and fail the ordering one.
//
//   cd flutter && flutter test test/review_summary_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/grading_api.dart';
import 'package:botvinnik_mobile/db/app_db.dart';
import 'package:botvinnik_mobile/stores/pgn_import.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/grade_strip.dart';
import 'package:botvinnik_mobile/ui/review_screen.dart';

import 'support/game_harness.dart';

/// The brain's LABEL_ORDER (brain/classifications.ts), best-first.
const _kLabelOrder = [
  'brilliant',
  'great',
  'best',
  'excellent',
  'good',
  'inaccuracy',
  'mistake',
  'miss',
  'blunder',
];

/// The brain's CLASS table, as it crosses the bridge. Glyphs matter: three of
/// them are drawn as Material icons rather than text (see [ClassTable]).
const _kClassRaw = {
  'brilliant': {'glyph': '‼', 'color': '#1baca6', 'noun': 'brilliant'},
  'great': {'glyph': '!', 'color': '#5b8bb0', 'noun': 'a great move'},
  'best': {'glyph': '★', 'color': '#81b64c', 'noun': 'the best move'},
  'excellent': {'glyph': '✔', 'color': '#81b64c', 'noun': 'excellent'},
  'good': {'glyph': '✓', 'color': '#95b776', 'noun': 'a good move'},
  'inaccuracy': {'glyph': '?!', 'color': '#f0c15c', 'noun': 'an inaccuracy'},
  'mistake': {'glyph': '?', 'color': '#e6912c', 'noun': 'a mistake'},
  'miss': {'glyph': '×', 'color': '#d9683a', 'noun': 'a miss'},
  'blunder': {'glyph': '??', 'color': '#ca3431', 'noun': 'a blunder'},
};

class _StubDb implements AppDb {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Only [labelOrder] is reached from the UI; everything else in GradingApi
/// runs at save time, well before a game is reviewed.
class _StubGrading implements GradingApi {
  final List<String> order;
  const _StubGrading(this.order);

  @override
  List<String> labelOrder() => order;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _kStartFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _kAfterE4 =
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
const _kAfterE5 =
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2';

/// Two plies, enough for the move list to have something to draw under the
/// summary. Grades are what a played game carries; an import has none.
List<Map<String, dynamic>> _moves({bool graded = true}) => [
      {
        'ply': 1,
        'san': 'e4',
        'uci': 'e2e4',
        'color': 'w',
        'fenBefore': _kStartFen,
        'fenAfter': _kAfterE4,
        if (graded) 'label': 'best',
        if (graded) 'bestSan': 'e4',
        if (graded) 'bestUci': 'e2e4',
      },
      {
        'ply': 2,
        'san': 'e5',
        'uci': 'e7e5',
        'color': 'b',
        'fenBefore': _kAfterE4,
        'fenAfter': _kAfterE5,
        if (graded) 'label': 'inaccuracy',
        if (graded) 'bestSan': 'c5',
        if (graded) 'bestUci': 'c7c5',
      },
    ];

/// A played game: the bot was Black, so White is the player.
Map<String, dynamic> _played({
  Object? whiteAccuracy = 84.2,
  Object? blackAccuracy = 71.9,
  Map<String, dynamic>? counts,
  Object? botColor = 'b',
}) =>
    {
      'id': 'g-1',
      'endedAt': '2026-07-20T10:11:00.000',
      'result': '1-0',
      'botColor': botColor,
      'botPersona': 'squarefish-1200',
      'moveCount': 2,
      'whiteAccuracy': whiteAccuracy,
      'blackAccuracy': blackAccuracy,
      'labelCounts': ?counts, // absent, as in a record saved before it existed
      'moves': _moves(),
    };

/// What [gameFromPgn] writes: no accuracy, no labelCounts, no botColor.
Map<String, dynamic> _imported() => {
      'id': 'import-1',
      'endedAt': '2026-07-20T10:11:00.000',
      'result': '1-0',
      'moveCount': 2,
      kImportedKey: true,
      'white': 'Kasparov, G.',
      'black': 'Topalov, V.',
      'moves': _moves(graded: false),
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

Future<ReviewController> _pumpReview(
  WidgetTester tester,
  Map<String, dynamic> game, {
  List<String> order = _kLabelOrder,
}) async {
  final settings = await loadSettings();
  final review = ReviewController(_StubDb())..open(game);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ClassTable>.value(value: const ClassTable(_kClassRaw)),
      Provider<GradingApi>.value(value: _StubGrading(order)),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<ReviewController>.value(value: review),
    ],
    child: const MaterialApp(home: Scaffold(body: ReviewBody())),
  ));
  await tester.pump();
  return review;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  testWidgets('shows both sides\' accuracy, attributed to you and the bot',
      (tester) async {
    await _pumpReview(
        tester,
        _played(counts: {
          'w': {'best': 12, 'blunder': 1},
          'b': {'inaccuracy': 3},
        }));

    expect(find.text('White (you)'), findsOneWidget,
        reason: 'botColor is b, so White is the player');
    expect(find.text('Black (bot)'), findsOneWidget);
    expect(find.text('84%'), findsOneWidget);
    expect(find.text('72%'), findsOneWidget, reason: '71.9 rounds to 72');
  });

  testWidgets('a game with no bot attributes neither side', (tester) async {
    await _pumpReview(
        tester,
        _played(botColor: null, counts: {
          'w': {'best': 12},
          'b': {'best': 9},
        }));

    expect(find.text('White'), findsOneWidget);
    expect(find.text('Black'), findsOneWidget);
    expect(find.textContaining('(you)'), findsNothing);
    expect(find.textContaining('(bot)'), findsNothing);
  });

  testWidgets('label counts follow the brain\'s LABEL_ORDER', (tester) async {
    // Every label present on one side or the other, so the whole order is
    // under test rather than the two labels a game happens to contain.
    await _pumpReview(
      tester,
      _played(counts: {
        'w': {for (final l in _kLabelOrder) l: 1},
        'b': {for (final l in _kLabelOrder) l: 0},
      }),
      // PERMUTED: reversed, so any order the widget invents for itself —
      // CLASS declaration order, the counts map's own key order, alphabetical
      // — disagrees with what it is told.
      order: _kLabelOrder.reversed.toList(),
    );

    double y(String label) => tester.getTopLeft(find.text(label)).dy;
    final rendered = [
      for (final l in _kLabelOrder.reversed) (l, y(_capitalised(l))),
    ];
    for (var i = 1; i < rendered.length; i++) {
      expect(rendered[i].$2, greaterThan(rendered[i - 1].$2),
          reason: '${rendered[i].$1} should be drawn below ${rendered[i - 1].$1}');
    }
  });

  testWidgets('an imported game shows no summary and no nulls', (tester) async {
    await _pumpReview(tester, _imported());

    expect(tester.takeException(), isNull);
    expect(find.textContaining('null'), findsNothing);
    expect(find.text('Accuracy'), findsNothing,
        reason: 'an import carries no grades at all — an empty grid is noise');
  });

  testWidgets('an older record without labelCounts still shows accuracy',
      (tester) async {
    await _pumpReview(tester, _played()); // no labelCounts key at all

    expect(tester.takeException(), isNull);
    expect(find.text('84%'), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets('a side with no graded moves shows a dash, not null',
      (tester) async {
    // gameAccuracy returns null for a side with no graded moves, and the
    // record stores that null.
    await _pumpReview(
        tester,
        _played(blackAccuracy: null, counts: {
          'w': {'best': 2},
          'b': <String, dynamic>{},
        }));

    expect(find.text('84%'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);
  });

  // A RenderFlex overflow is a runtime error: neither the analyzer nor a green
  // suite says anything about it. Roboto is loaded above because the default
  // test font is Ahem, whose uniform square glyphs are not a measurement of
  // anything a player sees.
  for (final width in [375.0, 320.0]) {
    testWidgets('the summary does not overflow at ${width.toInt()}px',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpReview(
          tester,
          _played(counts: {
            // the widest realistic grid: every label, two-digit counts
            'w': {for (final l in _kLabelOrder) l: 24},
            'b': {for (final l in _kLabelOrder) l: 17},
          }));

      expect(find.text('Inaccuracy'), findsOneWidget,
          reason: 'the grid must be on screen, or this proves nothing');
      expect(tester.takeException(), isNull,
          reason: 'the summary overflowed at ${width.toInt()}px');
    });
  }
}

String _capitalised(String label) =>
    label[0].toUpperCase() + label.substring(1);
