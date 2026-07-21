// The Book pane carries three columns it did not before — an eval chip, a
// confidence percentage, and the merged rows the engine contributes. Two
// things can go wrong that neither the analyzer nor a green suite would say
// anything about:
//
//  1. the pane can stop asking the brain for the engine's lines at all, and
//     still look right (a book-only table is what it used to be), so the
//     tests assert what the pane HANDED OVER, not only what it drew;
//  2. it can overflow. A RenderFlex overflow is a runtime error, and the pane
//     is at its narrowest not on a phone but in the WIDE layout — a 720pt
//     window at the maximum split leaves it 170pt, well under an iPhone SE.
//
// Loads the REAL bundled Roboto: the default test font is Ahem, whose glyphs
// are uniform squares much wider than Roboto's, so an Ahem measurement is not
// evidence about what a player sees.
//
//   cd flutter && flutter test test/book_pane_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/explorer_api.dart';
import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/book_store.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/book_pane.dart';
import 'package:botvinnik_mobile/ui/layout.dart';

import 'support/game_harness.dart';

/// Depth >= 10 so the controller keeps them, and three of them so the merge
/// has something to rank.
const _kLines = [
  EngineMove(pv: ['e2e4'], score: 0.35, mate: null, depth: 18, multipv: 1),
  EngineMove(pv: ['d2d4'], score: 0.30, mate: null, depth: 18, multipv: 2),
  EngineMove(pv: ['g1f3'], score: 0.20, mate: null, depth: 18, multipv: 3),
];

/// book.json's node shape: counts, and the moves played from the position.
const _kNode = {
  'white': 900000,
  'draws': 400000,
  'black': 900000,
  'moves': [
    {'uci': 'e2e4', 'san': 'e4', 'white': 400000, 'draws': 200000, 'black': 400000},
    {'uci': 'd2d4', 'san': 'd4', 'white': 300000, 'draws': 100000, 'black': 100000},
  ],
};

class _FakeBook extends BookStore {
  _FakeBook() {
    loaded = true;
    source = 'lichess db dump 2025-06, 1200-2200 blitz';
  }
  @override
  Future<void> ensureLoaded() async {}
  @override
  Map<String, dynamic>? node(String fen) => Map<String, dynamic>.from(_kNode);
  @override
  List<String>? openingFor(List<String> fens) => ['B00', "King's Pawn Game"];
}

/// Stands in for the brain — the arithmetic itself is proved in
/// brain/explorer.test.ts. What this fake is for is (a) recording what the
/// pane asked for, and (b) handing back the WIDEST plausible row, so the
/// layout assertions are made under pressure rather than on 'e4 / +0.3'.
class _FakeExplorer implements ExplorerApi {
  String? lastFen;
  List<EngineMove> lastLines = const [];
  Map<String, dynamic>? lastLichess;
  int calls = 0;

  static Map<String, dynamic> _stats(int games, double pct) => {
        'games': games,
        'pct': pct,
        'white': 44.4,
        'draws': 22.2,
        'black': 33.4,
      };

  /// A book row, a merged row, and an engine-only row — in the order the
  /// brain ranks them (by games, engine-only last).
  static final rows = <Map<String, dynamic>>[
    {
      'uci': 'e2e4',
      'san': 'e4',
      'engine': {'score': 0.35, 'mate': null, 'confidence': 100.0},
      'lichess': _stats(1200000, 60.0),
    },
    {
      'uci': 'd2d4',
      'san': 'd4',
      'lichess': _stats(500000, 25.0),
    },
    {
      // the widest a row realistically gets: the longest legal san, a losing
      // eval that needs its sign and two digits, and no book column at all
      'uci': 'a1d4',
      'san': 'Qa1xd4#',
      'engine': {'score': -12.9, 'mate': null, 'confidence': 0.4},
    },
  ];

  @override
  List<UnifiedMove> unifyMoves({
    required String fen,
    required List<EngineMove> lines,
    Map<String, dynamic>? lichess,
    Map<String, dynamic>? masters,
  }) {
    calls++;
    lastFen = fen;
    lastLines = lines;
    lastLichess = lichess;
    return [for (final r in rows) UnifiedMove(r)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

/// A pane at [width], with a controller whose analysis has already streamed in.
Future<(GameController, _FakeExplorer)> _pump(WidgetTester tester,
    {required double width}) async {
  final settings = await loadSettings(); // both human: analysis mode
  final game = GameController(
      FakeArbiter(analysisLines: _kLines, streamPartials: true),
      const FakeBot(),
      FakeGrading(),
      settings);
  await tester.pump(const Duration(seconds: 2));
  final explorer = _FakeExplorer();

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<GameController>.value(value: game),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<BookStore>(create: (_) => _FakeBook()),
      Provider<ExplorerApi>.value(value: explorer),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: const BookPane()),
        ),
      ),
    ),
  ));
  await tester.pump();
  return (game, explorer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  testWidgets('the engine reaches the book table — lines, fen and book node',
      (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (game, explorer) = await _pump(tester, width: 375);

    // The pane can only show an eval if it was given one to merge. Without
    // this the drawing assertions below would pass against a pane that had
    // quietly stopped asking the engine anything.
    expect(game.currentLines, isNotEmpty,
        reason: 'the analysis never streamed in — the test proves nothing');
    expect(explorer.calls, greaterThan(0));
    expect(explorer.lastLines.map((l) => l.uci), ['e2e4', 'd2d4', 'g1f3']);
    expect(explorer.lastFen, game.position.fen);
    // and the BOOK node reached it too, in the shape the brain wants
    expect(explorer.lastLichess?['total'], 2200000);
    expect((explorer.lastLichess?['moves'] as List).length, 2);
  });

  testWidgets('each row shows eval and confidence beside the book stats',
      (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, width: 375);

    // white to move, so the mover-POV score the brain reports is already
    // white-POV here
    expect(find.text('+0.3'), findsOneWidget); // 0.35 -> +0.3
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget); // the engine has all but ruled it out
    expect(find.text('-12.9'), findsOneWidget);
    expect(find.text('1.2M · 60%'), findsOneWidget);
    // the book-only row keeps its stats and says nothing about an eval it
    // does not have; the engine-only row is the mirror image
    expect(find.text('d4'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2)); // d4's eval, Qa1xd4#'s games
  });

  testWidgets('the pane does not overflow at 375pt', (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, width: 375);
    expect(find.text('Qa1xd4#'), findsOneWidget,
        reason: 'nothing was drawn — a clean takeException would mean nothing');
    expect(tester.takeException(), isNull,
        reason: 'the book table overflowed at 375pt');
  });

  testWidgets('nor in the wide layout, where it is narrower than any phone',
      (tester) async {
    // The real arithmetic, not a guessed width: a 720pt window (the wide
    // breakpoint) with the split dragged to its maximum leaves the pane
    // whatever the board and the split handle do not take.
    const window = kWideBreakpoint;
    final board = wideBoardSize(window, 800, kMaxSplit);
    const handle = 10.0; // _SplitHandle in main.dart
    final pane = window - board - handle;
    expect(pane, lessThan(375),
        reason: 'the wide pane is not under pressure — this test proves '
            'nothing beyond the 375pt one');

    tester.view.physicalSize = const Size(window, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, width: pane);
    expect(tester.takeException(), isNull,
        reason: 'the book table overflowed at ${pane}pt');
    // and it is still a table, not a collapsed one: every row is on screen
    expect(find.text('Qa1xd4#'), findsOneWidget);
  });
}
