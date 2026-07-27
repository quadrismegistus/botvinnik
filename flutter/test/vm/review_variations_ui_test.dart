// How variations PRINT in the review move list (#196 review follow-up).
//
// Three bugs lived here, all of them invisible to a controller test because the
// tree held the branch correctly the whole time — it was the list that could
// not find it:
//
//   * a variation hangs off the node BEFORE the move it replaces, and the list
//     indexed the carrier instead of the replaced move, so every branch printed
//     one row too early — an alternative to White's 2nd move above move 1;
//   * a branch off the START position is carried by the root, which no mainline
//     row looks at, so it rendered nowhere at all and (once you tapped back
//     onto the game) was reachable by no control;
//   * two branches replacing different moves printed as identical indented
//     rows in the same group, with nothing saying which move either departs
//     from.
//
//   cd flutter && flutter test test/review_variations_ui_test.dart

import 'dart:io' as io;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/db/app_db.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/grade_strip.dart';
import 'package:botvinnik_mobile/ui/review_screen.dart';

import '../support/game_harness.dart';

const _kClassRaw = {
  'best': {'glyph': '*', 'color': '#81b64c', 'noun': 'Best'},
};

class _StubDb implements AppDb {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// Roboto, so a Text that would otherwise measure zero-width actually lays out
/// (the same reason the other Review UI tests load it).
Future<void> _loadRoboto() async {
  // `as io` because dartchess exports its own `File` — the board file.
  final path = '${io.Directory.current.path}/fonts/Roboto-Regular.ttf';
  final file = io.File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader('Roboto')..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

/// 1. e4 e5 2. Nf3 — derived, so the fens are ones the app would really write.
Map<String, dynamic> _game() {
  Position pos = Chess.initial;
  final moves = <Map<String, dynamic>>[];
  var ply = 0;
  for (final uci in ['e2e4', 'e7e5', 'g1f3']) {
    final m = NormalMove.fromUci(uci);
    final before = pos.fen;
    final (_, san) = pos.makeSan(m);
    pos = pos.play(m);
    ply++;
    moves.add({
      'ply': ply,
      'san': san,
      'uci': uci,
      'color': ply.isOdd ? 'w' : 'b',
      'fenBefore': before,
      'fenAfter': pos.fen,
    });
  }
  return {'id': 'g-var-ui', 'botColor': 'b', 'moves': moves};
}

Future<ReviewBoardController> _pump(WidgetTester tester,
    {Size size = const Size(400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final settings = await loadSettings();
  final review = ReviewController(_StubDb());
  final board = fakeReviewBoard(review, settings);
  review.open(_game());

  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ClassTable>.value(
          value: ClassTable(_kClassRaw, labelOrder: const ['best'])),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<ReviewController>.value(value: review),
      ChangeNotifierProvider<ReviewBoardController>.value(value: board),
    ],
    child: const MaterialApp(home: Scaffold(body: ReviewBody())),
  ));
  await tester.pump();
  return board;
}

/// The y of the (first) widget whose text is exactly [text].
double _dy(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).first).dy;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadRoboto);

  testWidgets('a branch off the START position is printed', (tester) async {
    final board = await _pump(tester);
    board.gotoMainlinePly(0);
    board.playUci('d2d4'); // an alternative FIRST move
    await tester.pump();

    expect(find.text('d4'), findsOneWidget,
        reason: 'carried by the root, which no mainline row used to look at');
    expect(find.text('1.'), findsWidgets, reason: 'and it is numbered');
    board.dispose();
  });

  testWidgets('a branch prints BELOW the move it replaces', (tester) async {
    final board = await _pump(tester);
    board.gotoMainlinePly(2); // after 1.e4 e5 — an alternative to White's 2nd
    board.playUci('d2d4');
    await tester.pump();

    expect(find.text('d4'), findsOneWidget);
    expect(_dy(tester, 'd4'), greaterThan(_dy(tester, 'Nf3')),
        reason: 'it replaces Nf3, so it belongs under it — it used to print '
            'above move 1');
    board.dispose();
  });

  testWidgets('branches are numbered so two of them are distinguishable',
      (tester) async {
    final board = await _pump(tester);
    board.gotoMainlinePly(1);
    board.playUci('c7c5'); // 1...c5, an alternative to Black's 1st
    board.gotoMainlinePly(2);
    board.playUci('d2d4'); // 2.d4, an alternative to White's 2nd
    await tester.pump();

    expect(find.text('c5'), findsOneWidget);
    expect(find.text('d4'), findsOneWidget);
    // Book numbering: "1..." for a Black alternative, "2." for a White one.
    expect(find.text('1...'), findsOneWidget);
    expect(find.text('2.'), findsWidgets);
    board.dispose();
  });

  testWidgets('a move played past the end of the game prints as a variation',
      (tester) async {
    final board = await _pump(tester);
    board.gotoMainlinePly(3); // the last archived move
    board.playUci('b8c6');
    await tester.pump();

    expect(board.inVariation, isTrue);
    expect(find.text('Nc6'), findsOneWidget,
        reason: 'it used to join the mainline and print nowhere');
    board.dispose();
  });

  testWidgets('a variation OF a variation is printed and reachable',
      (tester) async {
    // It used to render nowhere — and since backing out of a branch forgets
    // the way onward, it was then reachable by no control at all: a line the
    // user had played, invisible and unreturnable.
    final board = await _pump(tester);
    board.gotoMainlinePly(1);
    board.playUci('c7c5'); // 1...c5, a branch
    board.playUci('g1f3'); // 2.Nf3 inside it
    board.stepBack();
    board.playUci('b1c3'); // 2.Nc3 — a branch OFF the branch
    await tester.pump();

    expect(board.tree!.current.san, 'Nc3', reason: 'the tree has it');
    expect(find.text('Nc3'), findsOneWidget, reason: 'and now so does the list');
    expect(find.text('Nf3'), findsWidgets);
    board.dispose();
  });

  testWidgets('a record whose rows cannot be drawn does not break the tab',
      (tester) async {
    // The board degrades to an empty position, but the move list reads the RAW
    // archive and cast it itself — so a malformed row threw inside a ListView
    // itemBuilder and took the whole pane with it.
    final settings = await loadSettings();
    final review = ReviewController(_StubDb());
    final board = fakeReviewBoard(review, settings);
    review.open({
      'id': 'bad',
      'moves': [
        {'ply': 1, 'san': 42, 'uci': 'e2e4', 'color': 'w'}, // san not a String
      ],
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ClassTable>.value(
            value: ClassTable(_kClassRaw, labelOrder: const ['best'])),
        ChangeNotifierProvider<SettingsStore>.value(value: settings),
        ChangeNotifierProvider<ReviewController>.value(value: review),
        ChangeNotifierProvider<ReviewBoardController>.value(value: board),
      ],
      child: const MaterialApp(home: Scaffold(body: ReviewBody())),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    board.dispose();
  });

  testWidgets('a moves field that is not a list does not strand the board',
      (tester) async {
    // BackupService.importJson validates only id and endedAt, and sync pulls
    // funnel through it. This used to throw above the guard, leaving the id on
    // the failed game while the board kept the previous one — permanently,
    // since re-opening then matched the id and returned early.
    final settings = await loadSettings();
    final review = ReviewController(_StubDb());
    final board = fakeReviewBoard(review, settings);

    review.open({'id': 'ok', 'moves': _game()['moves']});
    expect(board.tree!.mainline, hasLength(3), reason: 'a good game first');

    review.open({'id': 'broken', 'moves': 'not a list'});
    expect(board.tree!.mainline, isEmpty);
    expect(board.position.fen, Chess.initial.fen,
        reason: 'the previous game is not left on the board');
    expect(board.moves, isEmpty);
    board.dispose();
  });

  for (final w in [320.0, 375.0, 800.0]) {
    testWidgets('no overflow at ${w.toInt()}px with variations present',
        (tester) async {
      final board = await _pump(tester, size: Size(w, 900));
      board.gotoMainlinePly(1);
      board.playUci('c7c5');
      for (final uci in ['g1f3', 'b8c6', 'f1b5', 'a7a6', 'b5a4']) {
        board.playUci(uci); // a long branch, to make the row work for a living
      }
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'this pane has a history of RenderFlex overflow');
      board.dispose();
    });
  }
}
