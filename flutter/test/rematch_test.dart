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
///
/// The arbiter is stocked so the bot can actually MOVE. The file comment used
/// to argue the fixture had to keep the human on the move after a rematch,
/// because `_maybeBotTurn`'s opening wait spins on wall-clock time that
/// `tester.pump` cannot advance — true of a bare fake, but `streamPartials`
/// exists precisely to exit that loop at depth 10, and four other test files
/// already use it for this. Since rematch now carries the starting FEN
/// forward, the swap genuinely does hand the bot the first move here, and the
/// fixture has to survive that rather than be arranged around it.
/// [squareBotPersona] rather than [testBotPersona]: only the former carries
/// the `shapedLabel` that lets a bot turn reach a move at all.
Future<(GameController, SettingsStore, FakeArbiter)> _game(
    {bool rated = false, TimeControl? timeControl, bool refuseBlunders = false}) async {
  final settings = await loadSettings(); // both null: analysis, nobody to move for
  final arbiter = FakeArbiter(
      analysisLines: kFakeLines,
      streamPartials: true,
      searchLines: kFakeLines);
  final game = GameController(arbiter,
      FakeBot({kSquareBotId: squareBotPersona}), FakeGrading(), settings);
  settings.setPlayers(white: kSquareBotId, black: null);
  game.newGame(
      fromFen: _mateIn1BlackMates,
      rated: rated,
      timeControl: timeControl,
      refuseBlunders: refuseBlunders);
  return (game, settings, arbiter);
}

/// Two live Timers can outlast one of these tests: a rated clock's ticker
/// (periodic — see clock_lifecycle_test's own `_windDown`, the same fix) and
/// the bot turn a rematch now starts, since carrying the FEN forward means the
/// swap really does hand the bot the first move. Taking both sides off the
/// board and starting a fresh game bumps the generation, which is what makes
/// the in-flight turn stand down.
Future<void> _windDown(
    WidgetTester tester, GameController g, SettingsStore s) async {
  // Let an in-flight bot turn run to its end first: bumping the generation
  // under it makes it BAIL, but the 50ms poll it is sitting in is already
  // scheduled and stays pending either way.
  await tester.pump(const Duration(milliseconds: 200));
  s.setPlayers(white: null, black: null);
  g.newGame();
  await tester.pump(const Duration(milliseconds: 200));
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

  group('canRematch waits for the finished game to be finalised', () {
    testWidgets('the button is off while a grade is still in flight',
        (tester) async {
      // newGame bumps the generation, which makes an in-flight _gradePipeline
      // return before the backfilled label and before the practice-collect
      // guard — so a fast tap threw away the grade AND the puzzle for the move
      // that ended the game. Rematch is the first one-tap path sitting under
      // the result, which is what turns that race from rare into normal.
      final settings = await loadSettings();
      // An analysis that never resolves: the pipeline for the mating move
      // stays pending, exactly as a real one does for a beat after the game.
      final arbiter = FakeArbiter(searchLines: kFakeLines);
      final game = GameController(arbiter,
          FakeBot({kSquareBotId: squareBotPersona}), FakeGrading(), settings);
      settings.setPlayers(white: kSquareBotId, black: null);
      game.newGame(fromFen: _mateIn1BlackMates);

      game.playUci('a8a1'); // Ra1#
      await tester.pump(const Duration(milliseconds: 50));

      expect(game.gameOver, isTrue, reason: 'precondition');
      expect(game.canRematch, isFalse,
          reason: 'the game is over but not yet finished with');

      await _windDown(tester, game, settings);
    });

    testWidgets('and on once the grades have drained', (tester) async {
      final (g, settings, _) = await _game();
      g.playUci('a8a1');
      await tester.pump(const Duration(milliseconds: 200));

      expect(g.canRematch, isTrue,
          reason: 'nothing left in flight — the recap is done with the game');

      await _windDown(tester, g, settings);
    });
  });

  group('rematch()', () {
    testWidgets(
        'swaps the sides and starts one fresh game, not a double reset (#133)',
        (tester) async {
      final (g, settings, arbiter) = await _game(refuseBlunders: true);
      g.playUci('a8a1'); // Ra1#
      await tester.pump(const Duration(milliseconds: 50));
      expect(g.gameOver, isTrue, reason: 'precondition');

      final resetsBefore = arbiter.bumpGenerations;
      g.rematch();

      expect(settings.blackPersonaId, kSquareBotId,
          reason: 'the bot takes the side the human just played');
      expect(settings.whitePersonaId, isNull,
          reason: 'the human takes the side the bot just played');
      expect(g.gameOver, isFalse, reason: 'a fresh game is under way');
      expect(g.moves, isEmpty, reason: 'and the bot has not moved yet either');
      // Fixture has it ON, so this can actually fail: with the fixture at its
      // default the assertion held whatever rematch() did, and a rematch that
      // carried the flag left all six tests green.
      expect(g.refuseBlunders, isFalse,
          reason: 'a per-attempt toggle (#167), not a property of the match '
              'being continued — it is never carried');
      expect(arbiter.bumpGenerations - resetsBefore, 1,
          reason: 'exactly one reset — the New Game sheet\'s own documented '
              'sequence, not the double reset #133 was about');

      await _windDown(tester, g, settings);
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

    testWidgets('a rated rematch re-asserts the rated PRESET, not just the flag',
        (tester) async {
      // The sheet turns blind on and the three overlays off for a rated game,
      // and deliberately does not restore them at game over. So the natural
      // move after a rated game — turning blind off to read the analysis of
      // what you just played — leaves the settings exactly wrong. Without the
      // preset, the rematch is rated but `_assisted` is true, the FIRST human
      // move sets botHintsUsed, and playerElo drops the game: a game that says
      // rated, shows nothing, and cannot count.
      final tc = TimeControl.parse('5+0');
      final (g, settings, _) = await _game(rated: true, timeControl: tc);
      g.playUci('a8a1'); // Ra1#
      await tester.pump(const Duration(milliseconds: 50));

      settings.blind = false; // the player looks at the game they just lost
      settings.showArrows = true;
      expect(g.blind, isFalse, reason: 'precondition');

      g.rematch();

      expect(g.rated, isTrue);
      expect(g.blind, isTrue, reason: 'the preset came back with the flag');
      expect(settings.showArrows, isFalse);
      expect(settings.showThreats, isFalse);
      expect(settings.showControl, isFalse);

      await _windDown(tester, g, settings);
    });

    testWidgets('a casual rematch leaves the overlay settings alone',
        (tester) async {
      // The preset belongs to rated play; a casual rematch has no business
      // blinding a board the player deliberately turned the help on for.
      final (g, settings, _) = await _game();
      settings.blind = false;
      settings.showArrows = true;
      g.playUci('a8a1');
      await tester.pump(const Duration(milliseconds: 50));

      g.rematch();

      expect(g.blind, isFalse);
      expect(settings.showArrows, isTrue);

      await _windDown(tester, g, settings);
    });

    testWidgets('the starting position carries, so a FEN game rematches from it',
        (tester) async {
      // "Same opponent, same terms" has to include the position the game was
      // played from — a rematch that silently reverts a pasted FEN to the
      // standard start is a different game.
      final (g, settings, _) = await _game();
      g.playUci('a8a1');
      await tester.pump(const Duration(milliseconds: 50));

      g.rematch();

      expect(g.position.fen, _mateIn1BlackMates,
          reason: 'not the standard start');
      await _windDown(tester, g, settings);
    });

    testWidgets('a casual game\'s rematch stays casual, with no clock',
        (tester) async {
      final (g, settings, _) = await _game(); // rated defaults to false
      g.playUci('a8a1'); // Ra1#
      await tester.pump(const Duration(milliseconds: 50));
      expect(g.gameOver, isTrue, reason: 'precondition');

      g.rematch();

      expect(g.rated, isFalse);
      expect(g.clock, isNull,
          reason: 'newGame only ever builds a clock for a rated game — '
              'nothing here to carry regardless of what the last one had');

      await _windDown(tester, g, settings);
    });
  });
}
