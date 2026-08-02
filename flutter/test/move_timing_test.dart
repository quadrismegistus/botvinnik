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

import 'package:botvinnik_mobile/stores/pgn_import.dart';

import 'support/game_harness.dart';
import 'support/memory_db.dart';

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
  test('a game built with no injected timer uses a running clock', () async {
    // The field initialiser is the only ThinkTimer that ships, and every other
    // test here replaces it. Frozen at zero, every move of every real game
    // would record 0ms with the suite green.
    final game = await makeGame();
    game.newGame(); // the field initialiser's timer, started by the real path
    final spin = Stopwatch()..start();
    while (spin.elapsedMilliseconds < 5) {/* burn a few real milliseconds */}
    game.playUci('e2e4');
    expect(game.moves.single.thinkMs, isNotNull);
    expect(game.moves.single.thinkMs, greaterThan(0));
    game.dispose();
  });

  test('the refusal check\'s own search is not the player thinking', () async {
    // refuse-blunders awaits an engine search of up to 2.5s BEFORE the move is
    // applied. Measured before the fix: an instant move recorded 412ms with
    // the check on and 0 with it off. The reading is taken when the human
    // commits, so time that passes during the check is not charged to them.
    final settings = await loadSettings(black: kTestBotId);
    final game = GameController(
        FakeArbiter(analysisLines: kFakeLines),
        FakeBot({kTestBotId: testBotPersona}),
        FakeGrading(),
        settings);
    game.newGame(refuseBlunders: true);
    var now = Duration.zero;
    game.thinkTimer = ThinkTimer(source: () => now)..restart();

    now += const Duration(seconds: 3); // the player thinking
    game.playUci('e2e4');
    now += const Duration(seconds: 90); // the check grinding away
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(game.moves, isNotEmpty, reason: 'precondition: the move went through');
    expect(game.moves.first.thinkMs, 3000,
        reason: 'three seconds of thinking, not ninety-three');

    // and the sample is consumed, not left to stamp every later move too
    game.newGame(refuseBlunders: false);
    now += const Duration(seconds: 7);
    game.playUci('e2e4');
    expect(game.moves.single.thinkMs, 7000,
        reason: 'its own time, not the reading the refusal check sampled');
    game.dispose();
  });

  group('the exported PGN', () {
    /// A game played with controlled time, archived, and its movetext read back.
    Future<String> pgnOf(List<int> seconds) async {
      final settings = await loadSettings();
      final db = MemoryDb();
      final game = GameController(
          FakeArbiter(), FakeBot(), SavingGrading(), settings, db);
      var now = Duration.zero;
      game.thinkTimer = ThinkTimer(source: () => now)..restart();
      const ucis = ['e2e4', 'e7e5', 'g1f3'];
      for (var i = 0; i < seconds.length; i++) {
        now += Duration(seconds: seconds[i]);
        game.playUci(ucis[i]);
      }
      await game.debugForceSave();
      game.dispose();
      return db.games.values.single['pgn'] as String;
    }

    test('writes %emt in SECONDS, at a precision that round-trips', () async {
      // the units are the trap: `ms.toStringAsFixed(1)` writes 9000.0 for a
      // nine-second think — two and a half hours — and this branch's own
      // reader believes it
      final pgn = await pgnOf([9, 11]);
      expect(pgn, contains('{[%emt 9.000]}'));
      expect(pgn, contains('{[%emt 11.000]}'));

      final back = gameFromPgn(pgn, now: DateTime.utc(2026, 8, 2))!;
      final moves = (back['moves'] as List).cast<Map<String, dynamic>>();
      expect(moves[0]['thinkMs'], 9000);
      expect(moves[1]['thinkMs'], 11000);
    });
  });

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
              // with the e3 en-passant field, as _storedMoveOf writes it
              'fenAfter':
                  'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
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

    test('a record written before this existed reads as unknown, not zero',
        () async {
      final game = await reviewBoard();
      final old = storedGame();
      (old['moves'] as List).first.remove('thinkMs');
      game.showReview(old);
      expect(game.moves.single.thinkMs, isNull,
          reason: 'absent is not zero — zero is a measurement');
      game.dispose();
    });

    test('a nonsense value in the archive is refused, not cast', () async {
      // the archive is the one input here we do not control: BackupService
      // validates only id and endedAt and writes the rest verbatim
      final game = await reviewBoard();
      final bad = storedGame();
      (bad['moves'] as List).first['thinkMs'] = 'quite a while';
      expect(() => game.showReview(bad), returnsNormally);
      expect(game.moves.single.thinkMs, isNull);
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
