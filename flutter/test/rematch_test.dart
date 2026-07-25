// The Rematch button (#212): one tap from the game-over recap into a fresh
// game against the same opponent, sides swapped, same time control if the
// game that just ended was rated.
//
// The fixture below always has the HUMAN deliver mate as BLACK (bot plays
// White). That is deliberate, not incidental: after a rematch swaps the
// sides, the human ends up White in the fresh game — and White moves first
// on a fresh board. Set it up the other way (human mates as White) and the
// rematch would hand the bot the opening move, waking _maybeBotTurn's
// analysis-depth spin (see game_harness.dart's own note on it): the fake
// arbiter here never streams partials, so that loop would spin on real
// Timers for up to 1.5s of wall-clock — `tester.pump` cannot fast-forward it,
// and a Timer still pending when the test ends fails the suite's leak check.
// Losing as White instead avoids the spin entirely rather than fighting it.
//
// The same reasoning applies to how the controller is BUILT, one level up:
// the constructor's own `_maybeBotTurn()` runs against the plain standard
// start, before `newGame(fromFen:)` below ever replaces the position — so the
// bot persona is assigned only AFTER construction (analysis to start, nobody
// to move for), and the custom FEN is what turns the game into a bot game at
// all. Assigning the bot through `loadSettings` instead, as most of this
// suite's other fixtures do, is exactly as safe for THEM because their bot
// plays Black and White (human) always moves first at the default start —
// it is specifically pairing "bot" with "moves first at the default start"
// that wakes the spin, and this file's whole point is a swap that puts the
// bot on each side in turn.
//
//   cd flutter && flutter test test/rematch_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/chess_clock.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';

import 'support/game_harness.dart';

/// White king boxed in by its own pawns on f2/g2/h2, Black rook on a8: Ra1# is
/// mate, along the rank the king has no escape from. The mirror image of
/// game_help_test's `_mateIn1`, with the colours that deliver it swapped —
/// see the file comment for why that mirroring is the point.
const _mateIn1BlackMates = 'r3k3/8/8/8/8/8/5PPP/6K1 b - - 0 1';

/// Bot plays White, human plays Black — see the file comment. No db: a
/// finished game with nowhere to archive to returns out of `_saveGame`
/// immediately, which is one less thing (grading waits, save timers) for
/// these tests to have to wind down.
Future<(GameController, SettingsStore, FakeArbiter)> _game(
    {bool rated = false, TimeControl? timeControl}) async {
  final settings = await loadSettings(); // both null: analysis, nobody to move for
  final arbiter = FakeArbiter(analysisLines: const []);
  final game = GameController(
      arbiter, const FakeBot({kTestBotId: testBotPersona}), FakeGrading(), settings);
  settings.setPlayers(white: kTestBotId, black: null);
  game.newGame(
      fromFen: _mateIn1BlackMates, rated: rated, timeControl: timeControl);
  return (game, settings, arbiter);
}

/// A live rated clock's ticker is a real periodic Timer; leaving one running
/// past a test's end fails the pending-timer invariant (see
/// clock_lifecycle_test's own `_windDown`, the same fix). Only the rated
/// rematch test needs this — every other test here either never rates a game
/// or ends on a casual one, which never gets a clock at all.
Future<void> _windDown(
    WidgetTester tester, GameController g, SettingsStore s) async {
  s.setPlayers(white: null, black: null);
  g.newGame();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('canRematch', () {
    testWidgets('is false while the game is still in progress', (tester) async {
      final (g, _, _) = await _game();
      expect(g.gameOver, isFalse, reason: 'precondition: nobody has moved yet');
      expect(g.canRematch, isFalse);
    });

    testWidgets('turns true once the mate actually lands', (tester) async {
      final (g, _, _) = await _game();

      g.playUci('a8a1'); // Ra1#
      await tester.pump(const Duration(milliseconds: 50));

      expect(g.gameOver, isTrue, reason: 'precondition: the mate landed');
      expect(g.canRematch, isTrue);
    });

    testWidgets('stays false in analysis — there is no opponent to rematch',
        (tester) async {
      final g = await makeGame(fromFen: _mateIn1BlackMates);

      g.playUci('a8a1'); // Ra1#
      await tester.pump(const Duration(milliseconds: 50));

      expect(g.gameOver, isTrue, reason: 'precondition: the mate landed');
      expect(g.botEnabled, isFalse, reason: 'precondition: analysis, no bot');
      expect(g.canRematch, isFalse);
    });
  });

  group('rematch()', () {
    testWidgets(
        'swaps the sides and starts one fresh game, not a double reset (#133)',
        (tester) async {
      final (g, settings, arbiter) = await _game();
      g.playUci('a8a1'); // Ra1#
      await tester.pump(const Duration(milliseconds: 50));
      expect(g.gameOver, isTrue, reason: 'precondition');

      final resetsBefore = arbiter.bumpGenerations;
      g.rematch();

      expect(settings.blackPersonaId, kTestBotId,
          reason: 'the bot takes the side the human just played');
      expect(settings.whitePersonaId, isNull,
          reason: 'the human takes the side the bot just played');
      expect(g.gameOver, isFalse, reason: 'a fresh game is under way');
      expect(g.moves, isEmpty);
      expect(g.refuseBlunders, isFalse,
          reason: 'a per-attempt toggle (#167), not a property of the match '
              'being continued — it is never carried');
      expect(arbiter.bumpGenerations - resetsBefore, 1,
          reason: 'exactly one reset — the New Game sheet\'s own documented '
              'sequence, not the double reset #133 was about');
    });

    testWidgets('carries the time control when the finished game was rated',
        (tester) async {
      final tc = TimeControl.parse('5+0');
      final (g, settings, _) = await _game(rated: true, timeControl: tc);
      expect(g.clock?.control, tc, reason: 'precondition: a real rated clock');

      g.playUci('a8a1'); // Ra1#
      await tester.pump(const Duration(milliseconds: 50));
      expect(g.gameOver, isTrue, reason: 'precondition');

      g.rematch();

      expect(g.rated, isTrue,
          reason: 'one explicit tap on the just-shown result continues under '
              'the same terms — see rematch()\'s own comment on why that is '
              'not the same thing as the sheet\'s sticky-checkbox worry');
      expect(g.clock?.control, tc);

      await _windDown(tester, g, settings);
    });

    testWidgets('a casual game\'s rematch stays casual, with no clock',
        (tester) async {
      final (g, _, _) = await _game(); // rated defaults to false
      g.playUci('a8a1'); // Ra1#
      await tester.pump(const Duration(milliseconds: 50));
      expect(g.gameOver, isTrue, reason: 'precondition');

      g.rematch();

      expect(g.rated, isFalse);
      expect(g.clock, isNull,
          reason: 'newGame only ever builds a clock for a rated game — '
              'nothing here to carry regardless of what the last one had');
    });
  });
}
