// Drag a piece on the REVIEW board and prove a variation appears (#194/#196).
//
// The one layer none of the unit tests reach. `review_board_test.dart` calls
// `board.playUci(...)`, which is the controller's own door — it cannot tell you
// that a human dragging a piece reaches it. Between the two sits BoardPane's
// `playerSide` (review takes input at all), chessground's hit-testing (the
// pointer lands on the square you meant), its gesture recogniser (a drag is
// recognised rather than cancelled as a tap) and BoardPane's `onMove` (the
// move is legal and reaches `playerMove`). Every one of those has been wrong at
// some point in this feature's short life; the first version of review mode
// refused input entirely and the tests were perfectly green.
//
//   cd flutter && flutter test integration_test/review_branch_test.dart -d macos
//
// macOS ONLY, for now. `-d chrome` is rejected outright by Flutter 3.44.6 —
// "Web devices are not supported for integration tests yet" — so the web route
// is `flutter drive` + a separate chromedriver process, which is not set up
// here (no test_driver/, no chromedriver) and carries flutter/flutter#150358:
// on web it can report "All tests passed" with exit code 0 while tests
// actually failed in the browser. Not worth adopting for a green signal you
// cannot trust. Nothing in this file is web-specific, so it should port when
// that lands.
//
// What running it natively still buys, and it is the whole point: WidgetTester
// gestures do not go through any platform's input stack. They synthesise
// PointerEvents into Flutter's own gesture pipeline and hit-test against its
// render tree — the same pipeline the CanvasKit web build uses. So this covers
// the layer that "the UI is one canvas element" makes untestable from outside,
// and it does it without a browser at all.
//
// WHY COORDINATES, THEN. chessground 10.1.1 paints squares and pieces with a
// CustomPainter (`PiecesPainter`) — there is no per-square or per-piece widget,
// so `find.byKey(Key('e2'))` cannot work and no amount of instrumentation on
// our side would change that. What it DOES give us is
// `SizedBox.square(key: ValueKey('board-container'))` at exactly the board's
// size. So the coordinates here are derived from that widget's real rect at run
// time, not hardcoded pixels: the board can move, resize or reflow and the
// arithmetic still lands on the right square. That is the difference between
// this and the brittle CDP-over-canvas approach it replaces.

import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:botvinnik_mobile/brain/bot_api.dart';
import 'package:botvinnik_mobile/brain/grading_api.dart';
import 'package:botvinnik_mobile/brain/js_bridge.dart';
import 'package:botvinnik_mobile/db/app_db.dart';
import 'package:botvinnik_mobile/engine/arbiter.dart';
import 'package:botvinnik_mobile/engine/search_engine.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/board_pane.dart';

/// Where a square's centre is on screen.
///
/// chessground's own geometry, replicated over the board container's measured
/// rect: files left-to-right and ranks bottom-to-top when White is at the
/// bottom, which is the orientation an archived game from White's side opens
/// in. Squares are `size / 8`, and the centre is half a square in from the
/// corner — aiming at a corner is how a rounding error puts the pointer on the
/// neighbouring square.
Offset squareCentre(Rect board, String square) {
  final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0); // 0..7
  final rank = square.codeUnitAt(1) - '1'.codeUnitAt(0); // 0..7
  final s = board.width / 8;
  return Offset(
    board.left + (file + 0.5) * s,
    board.top + (7 - rank + 0.5) * s,
  );
}

class _StubDb implements AppDb {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// 1. e4 e5, archived — enough to have a played line to depart from, and its
/// fens are DERIVED rather than typed (dartchess normalises an en-passant
/// square no capture can reach, so a hand-written one is a fen this app never
/// writes and the board would not match it).
Map<String, dynamic> archivedGame() {
  final moves = <Map<String, dynamic>>[];
  Position pos = Chess.initial;
  var ply = 0;
  for (final uci in ['e2e4', 'e7e5']) {
    final move = NormalMove.fromUci(uci);
    final before = pos.fen;
    final (_, san) = pos.makeSan(move);
    pos = pos.play(move);
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
  return {'id': 'g-branch-test', 'botColor': 'b', 'moves': moves};
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late JsBridge bridge;
  setUpAll(() async => bridge = await JsBridge.load());

  testWidgets('dragging a piece on the review board branches the game',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final review = ReviewController(_StubDb());
    final board = ReviewBoardController(
      // No engine: its searches never resolve, so the overlays stay idle and
      // this test is about input reaching the controller, nothing else.
      SearchArbiter(Completer<UciSearcher>().future),
      BotApi(bridge),
      GradingApi(bridge),
      settings,
      review,
    );
    review.open(archivedGame());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
          ChangeNotifierProvider<GameController>.value(value: board),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 400, height: 400, child: BoardPane()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Precondition: the board is showing the start of the archived game, and
    // the game is the game.
    expect(board.position.fen, Chess.initial.fen);
    expect(board.inVariation, isFalse);
    expect(board.tree!.mainline.map((n) => n.san), ['e4', 'e5']);

    final rect = tester.getRect(find.byKey(const ValueKey('board-container')));

    // 1. d4 — a legal first move that is NOT what was played, so it must
    // create a variation rather than walk the game.
    final from = squareCentre(rect, 'd2');
    final to = squareCentre(rect, 'd4');

    // A real drag, in steps. chessground needs the pointer to travel past
    // _kDragDistanceThreshold (3 logical pixels) before it treats the gesture
    // as a drag at all, and a single jump from origin to destination is the
    // shape most likely to be read as a tap-and-cancel instead.
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(board.inVariation, isTrue,
        reason: 'the drag reached playerMove and branched');
    expect(board.tree!.current.san, 'd4');
    expect(board.position.fen,
        Chess.initial.play(NormalMove.fromUci('d2d4')).fen);

    // The archived game is untouched and still reachable — the whole promise
    // of a variation.
    expect(board.tree!.mainline.map((n) => n.san), ['e4', 'e5']);
    expect(board.tree!.root.variations.map((n) => n.san), ['d4']);

    board.gotoMainlinePly(2);
    expect(board.inVariation, isFalse);
    expect(board.tree!.current.san, 'e5');

    board.dispose();
  });
}
