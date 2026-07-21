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
  double? split,
}) async {
  final settings = await loadSettings();
  if (split != null) settings.split = split;
  final review = ReviewController(_StubDb())..open(game);
  await tester.pumpWidget(MultiProvider(
    providers: [
      // LABEL_ORDER now rides on the ClassTable snapshot rather than being
      // read through GradingApi on every rebuild, so the order under test is
      // injected here.
      Provider<ClassTable>.value(
          value: ClassTable(_kClassRaw, labelOrder: order)),
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

    // The numbers must be UNDER THEIR OWN HEADINGS. Asserting only that both
    // percentages exist somewhere passes just as happily when the two cells
    // are swapped, which is the mutation this test is named for.
    expect(_columnUnder(tester, 'White (you)'), '84%');
    expect(_columnUnder(tester, 'Black (bot)'), '72%',
        reason: '71.9 rounds to 72');
  });

  testWidgets('the bot playing White is attributed the other way round',
      (tester) async {
    // The untested direction. With only botColor 'b' fixtured, a build that
    // simply always calls White "you" ships green — and every player who took
    // Black reads their own moves as the bot's.
    await _pumpReview(tester, _played(botColor: 'w'));
    expect(find.text('Black (you)'), findsOneWidget);
    expect(find.text('White (bot)'), findsOneWidget);
  });

  testWidgets('each label row shows the right count per side', (tester) async {
    // Nothing asserted a single count value: the grid could render all zeroes,
    // or swap its two columns, with the suite green.
    await _pumpReview(
        tester,
        _played(counts: {
          'w': {'blunder': 3, 'best': 7},
          'b': {'blunder': 1, 'best': 9},
        }));

    expect(_countsInRow(tester, 'blunder'), ['3', '1']);
    expect(_countsInRow(tester, 'best'), ['7', '9']);
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

    double y(String label) =>
        tester.getTopLeft(find.byKey(ValueKey('summary-row-$label'))).dy;
    final rendered = [for (final l in _kLabelOrder.reversed) (l, y(l))];
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
  // Widths BELOW kWideBreakpoint (720) take the phone branch, where the list is
  // full width. The wide branch splits the width with the board, so the pane
  // can be a fraction of it — and with the splitter at kMaxSplit that pane is
  // narrower than any phone. Testing only 375/320 could never fail there.
  for (final (width, split) in [
    (375.0, null),
    (320.0, null),
    (720.0, kMaxSplit),
    (800.0, kMaxSplit),
    (880.0, kMaxSplit),
  ]) {
    final where = split == null ? 'narrow' : 'wide, split $split';
    testWidgets('the summary does not overflow at ${width.toInt()}px ($where)',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpReview(
          tester,
          split: split,
          _played(counts: {
            // the widest realistic grid: every label, two-digit counts
            'w': {for (final l in _kLabelOrder) l: 24},
            'b': {for (final l in _kLabelOrder) l: 17},
          }));

      expect(find.byKey(const ValueKey('summary-row-inaccuracy')),
          findsOneWidget,
          reason: 'the grid must be on screen, or this proves nothing');
      expect(tester.takeException(), isNull,
          reason: 'the summary overflowed at ${width.toInt()}px');
    });
  }
}


/// The text of the cell sitting directly below [heading] — i.e. in its column,
/// not merely somewhere in the tree.
String _columnUnder(WidgetTester tester, String heading) {
  // Right edges, not centres: the cell is a Column with
  // crossAxisAlignment.end, so heading and value are shrink-wrapped to
  // different widths and share only their right edge.
  final x = tester.getBottomRight(find.text(heading)).dx;
  for (final e in tester.widgetList<Text>(find.byType(Text))) {
    final f = find.byWidget(e);
    final data = e.data;
    if (data == null || !data.endsWith('%') && data != '—') continue;
    if ((tester.getBottomRight(f).dx - x).abs() < 1.0) return data;
  }
  return '<none aligned>';
}

/// The two count cells on [label]'s row, left to right.
List<String> _countsInRow(WidgetTester tester, String label) {
  final row = find.byKey(ValueKey('summary-row-$label'));
  final cells = <(double, String)>[];
  for (final e
      in tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))) {
    final data = e.data;
    if (data == null || int.tryParse(data) == null) continue;
    cells.add((tester.getCenter(find.byWidget(e)).dx, data));
  }
  cells.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final c in cells) c.$2];
}
