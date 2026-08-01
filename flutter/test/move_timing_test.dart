// A move remembers how long it took (#267).
//
// The archive has never known this, so "do I blunder in time trouble" was a
// question the app could not ask. The number comes from ThinkTimer rather than
// the chess clock, because a clock only exists in a rated game with a time
// control and this has to work in the casual games that are most of them.
//
//   cd flutter && flutter test test/move_timing_test.dart

import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/think_timer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A game whose sense of time the test controls completely.
  Future<(GameController, void Function(int))> timedGame() async {
    final game = await makeGame();
    var now = Duration.zero;
    game.thinkTimer = ThinkTimer(source: () => now)..restart();
    return (game, (int s) => now += Duration(seconds: s));
  }

  test('a played move carries the time spent in front of the position', () async {
    final (game, advance) = await timedGame();
    advance(9);
    game.playUci('e2e4');
    expect(game.moves.single.thinkMs, 9000);
    game.dispose();
  });

  test('the next side is timed from the move, not from its own reply', () async {
    // the bug this guards: restarting the timer when the move is played rather
    // than when the position appears would charge each side its opponent's time
    final (game, advance) = await timedGame();
    advance(4);
    game.playUci('e2e4');
    advance(11);
    game.playUci('e7e5');
    expect(game.moves[0].thinkMs, 4000);
    expect(game.moves[1].thinkMs, 11000,
        reason: 'eleven seconds since white moved, not fifteen since the start');
    game.dispose();
  });

  test('it survives the round trip through the archive', () async {
    final (game, advance) = await timedGame();
    advance(6);
    game.playUci('e2e4');
    final stored = game.debugStoredMoves();
    expect(stored.single['thinkMs'], 6000);
    game.dispose();
  });

  test('a move nobody timed stores no key at all', () async {
    // an archive written before this existed, and every imported game without
    // clock comments: absent, not zero, because zero is a measurement
    final game = await makeGame();
    game.thinkTimer = ThinkTimer(source: () => Duration.zero); // never restarted
    game.playUci('e2e4');
    expect(game.moves.single.thinkMs, isNull);
    expect(game.debugStoredMoves().single.containsKey('thinkMs'), isFalse);
    game.dispose();
  });

  test('backgrounding the app is not thinking', () async {
    final (game, advance) = await timedGame();
    advance(3);
    game.pauseForBackground();
    advance(7200); // two hours in a pocket
    game.resumeFromBackground();
    advance(2);
    game.playUci('e2e4');
    expect(game.moves.single.thinkMs, 5000);
    game.dispose();
  });

  test('after a takeback the next move reports nothing rather than a fiction',
      () async {
    // the position has already been seen, and the time in front of it no
    // longer belongs to one decision
    final (game, advance) = await timedGame();
    advance(5);
    game.playUci('e2e4');
    expect(game.moves.single.thinkMs, 5000, reason: 'precondition');
    game.undo();
    advance(30);
    game.playUci('d2d4');
    expect(game.moves.single.thinkMs, isNull);
    game.dispose();
  });

  test('and the move after THAT is timed again', () async {
    final (game, advance) = await timedGame();
    game.playUci('e2e4');
    game.undo();
    advance(30);
    game.playUci('d2d4'); // null, per the test above
    advance(8);
    game.playUci('e7e5');
    expect(game.moves[1].thinkMs, 8000,
        reason: 'the discarded thirty seconds must not carry over');
    game.dispose();
  });

  test('a redo also refuses to time the move that follows it', () async {
    // undo->redo puts the same moves back on the same board, so it costs the
    // game nothing — but the player has still seen what came next
    final (game, advance) = await timedGame();
    advance(5);
    game.playUci('e2e4');
    game.undo();
    game.redo();
    advance(9);
    game.playUci('e7e5');
    expect(game.moves[1].thinkMs, isNull);
    game.dispose();
  });

  // A review board never writes a variation into `moves` — the played line is
  // the record and a variation is explored on the board — so there is nothing
  // to time there, and no discard is needed on the load path.
  group('a game reopened in Review', () {
    /// The archive's shape, as `_storedMoveOf` writes it.
    Map<String, dynamic> storedGame() => {
          'id': 'g1',
          'endedAt': DateTime.utc(2026, 8, 1).toIso8601String(),
          'moves': [
            {
              'ply': 1,
              'san': 'e4',
              'uci': 'e2e4',
              'color': 'w',
              'fenBefore': kStandardStartFen,
              'fenAfter':
                  'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
              'thinkMs': 4200,
            },
          ],
        };

    Future<GameController> reviewBoard() async {
      final settings = await loadSettings();
      return GameController(FakeArbiter(), FakeBot(), FakeGrading(), settings,
          null, null, null, null, true);
    }

    test('carries the stored time back out of the archive', () async {
      final game = await reviewBoard();
      game.showReview(storedGame());
      expect(game.moves.single.thinkMs, 4200);
      game.dispose();
    });

  });

  test('a new game starts the count from the new game', () async {
    final (game, advance) = await timedGame();
    advance(100);
    game.newGame();
    advance(3);
    game.playUci('e2e4');
    expect(game.moves.single.thinkMs, 3000,
        reason: 'not 103 — the previous game is over');
    game.dispose();
  });
}
