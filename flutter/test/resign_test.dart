// Resigning (#163).
//
// The reason this is not cosmetic: results are derived from the POSITION
// (`_result` reads isCheckmate/isGameOver), so a game you walk away from
// archives as '*', and brain/playerElo.ts drops '*' as abandoned. Players
// resign the games they are losing — so with no resign button, every game a
// player would have conceded was invisible to their rating, which read high,
// and more so against stronger opponents.
//
//   cd flutter && flutter test test/resign_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/game_controller.dart';

import 'support/fake_db.dart';
import 'support/game_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(GameController, FakeDb)> game({String? black = kTestBotId}) async {
    final settings = await loadSettings(black: black);
    final db = FakeDb();
    final g = GameController(
        FakeArbiter(analysisLines: kFakeLines, streamPartials: true),
        const FakeBot({kTestBotId: testBotPersona}),
        SavingGrading(),
        settings,
        db);
    return (g, db);
  }

  testWidgets('a resigned game archives as a loss, not as abandoned',
      (tester) async {
    final (g, db) = await game();
    g.playUci('e2e4');
    await tester.pump(const Duration(milliseconds: 50));

    g.resign();
    await tester.pump(const Duration(seconds: 1));

    expect(g.resigned, isTrue);
    expect(g.gameOver, isTrue, reason: 'play stops, though the board is legal');
    expect(db.saved, hasLength(1), reason: 'it archives itself; no move follows');
    // The human is White here, so a resignation is 0-1. '*' is the bug: it is
    // what walking away produces, and playerElo drops it.
    expect(db.saved.single['result'], '0-1');
    expect(db.saved.single['result'], isNot('*'));
  });

  testWidgets('the board is still legal — that is the point', (tester) async {
    final (g, _) = await game();
    g.playUci('e2e4');
    await tester.pump(const Duration(milliseconds: 50));
    expect(g.position.isGameOver, isFalse, reason: 'precondition');

    g.resign();
    await tester.pump(const Duration(milliseconds: 50));

    // A position-derived result cannot express this, which is why _result
    // checks _resigned FIRST.
    expect(g.position.isGameOver, isFalse);
    expect(g.gameOver, isTrue);
    expect(g.statusLine, contains('resigned'));
  });

  testWidgets('the analysis board cannot be resigned', (tester) async {
    // Nobody to concede to. The button is absent rather than disabled there,
    // and the controller refuses regardless of what the UI does.
    final (g, db) = await game(black: null);
    g.playUci('e2e4');
    await tester.pump(const Duration(milliseconds: 50));

    g.resign();
    await tester.pump(const Duration(milliseconds: 50));

    expect(g.resigned, isFalse);
    expect(db.saved, isEmpty);
  });

  testWidgets('a new game clears it', (tester) async {
    final (g, _) = await game();
    g.playUci('e2e4');
    await tester.pump(const Duration(milliseconds: 50));
    g.resign();
    await tester.pump(const Duration(milliseconds: 50));
    expect(g.resigned, isTrue);

    g.newGame();
    expect(g.resigned, isFalse);
    expect(g.gameOver, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('resigning before playing anything does nothing', (tester) async {
    // There is no game to concede yet, and archiving an empty one would put a
    // move-less loss on the record.
    final (g, db) = await game();
    g.resign();
    await tester.pump(const Duration(milliseconds: 50));
    expect(g.resigned, isFalse);
    expect(db.saved, isEmpty);
  });

  testWidgets('the finished game is exposed for review (#198)', (tester) async {
    // The game-over recap opens the just-archived record straight into review,
    // so the controller has to hand it back — and it must be the SAME record
    // that landed in the archive, not a fresh read.
    final (g, db) = await game();
    g.playUci('e2e4');
    await tester.pump(const Duration(milliseconds: 50));
    expect(g.lastSavedGame, isNull, reason: 'nothing archived until it ends');

    g.resign();
    await tester.pump(const Duration(seconds: 1));

    expect(g.lastSavedGame, isNotNull);
    expect(g.lastSavedGame!['id'], db.saved.single['id']);
    expect(g.lastSavedGame!['result'], '0-1');

    // A new game clears it, so a stale record can't be reopened as "this game".
    g.newGame();
    expect(g.lastSavedGame, isNull);
    await tester.pump(const Duration(milliseconds: 200));
  });
}
