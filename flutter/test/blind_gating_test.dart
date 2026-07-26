// One predicate for "is this board withholding help" (#148).
//
// It used to be derived in six places with three different answers — the Book
// and Lines panes said `blind && botEnabled && !gameOver`, the tree pane said
// `blind && botEnabled`, and the board overlays said `blind` alone. The
// visible result was that turning blind on at the ANALYSIS board blanked the
// board while the Lines pane beside it went on listing the engine's moves
// with evaluations: the app hid and showed the same information at once, a
// few hundred pixels apart.
//
// These tests are about the two clauses that were missing from the overlays,
// and about the one place that must NOT follow them — see `_assisted`.
//
//   cd flutter && flutter test test/blind_gating_test.dart

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';

import 'support/game_harness.dart';

/// White king boxed in by its own pawns, Black rook on a8: Ra1# is mate.
const _mateIn1BlackMates = 'r3k3/8/8/8/8/8/5PPP/6K1 b - - 0 1';

Future<(GameController, SettingsStore)> _gameAndSettings(
    {required bool bot, bool blind = true}) async {
  final settings = await loadSettings(white: bot ? kSquareBotId : null);
  settings.blind = blind;
  final game = GameController(
      FakeArbiter(
          analysisLines: kFakeLines,
          streamPartials: true,
          searchLines: kFakeLines),
      const FakeBot({kSquareBotId: squareBotPersona}),
      FakeGrading(),
      settings);
  game.newGame(fromFen: _mateIn1BlackMates);
  return (game, settings);
}

Future<GameController> _game({required bool bot, bool blind = true}) async =>
    (await _gameAndSettings(bot: bot, blind: blind)).$1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('blind works on the analysis board too', () {
    // #148 was first resolved the other way — `hidingHelp` required
    // `botEnabled`, on the reading that there is nobody to keep a secret from
    // when both sides are you. That made the switch INERT on the analysis
    // board while leaving its toggle and its "no engine help" tooltip sitting
    // over a board covered in engine arrows. Blind mode's real use there is
    // not secrecy but self-testing: guess the move before letting the engine
    // tell you.
    test('hidingHelp follows the switch with no opponent on the board', () async {
      final game = await _game(bot: false);
      expect(game.blind, isTrue, reason: 'the switch really is on');
      expect(game.hidingHelp, isTrue);
      game.dispose();
    });

    test('and the BOARD hides, not just the panes', () async {
      // This assertion is the point of this file. Every earlier version of
      // it probed `visibleLines`, which is the PANE predicate — so reverting
      // all five board-overlay call sites to their old `blind` left the suite
      // green, and the one thing #148 changed had no test at all.
      // engineArrowUcis is the one board overlay this harness can reach:
      // `threat`, `tacticalWin` and `controlMap` all short-circuit on a null
      // ChessApi, which the harness does not wire, so asserting them null
      // here would pass whatever the predicate said. They share the call
      // site pattern; only this one is actually pinned.
      final game = await _game(bot: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(game.currentLines, isNotEmpty,
          reason: 'precondition: the engine really did stream something to hide');

      expect(game.engineArrowUcis, isEmpty, reason: 'green arrows');
      expect(game.visibleLines, isEmpty, reason: 'and the panes agree');
      game.dispose();
    });

    test('with the switch off, all of it comes back', () async {
      // The other half: the assertions above must be failing for the reason
      // claimed, not because this harness never produces overlays.
      final game = await _game(bot: false, blind: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(game.hidingHelp, isFalse);
      expect(game.engineArrowUcis, isNotEmpty);
      expect(game.visibleLines, isNotEmpty);
      game.dispose();
    });
  });

  group('the veil lifts when the game ends', () {
    test('hidden while the game is on', () async {
      final game = await _game(bot: true);
      expect(game.hidingHelp, isTrue);
      expect(game.visibleLines, isEmpty);
      game.dispose();
    });

    test('and lifted the moment it is over', () async {
      // The SETTING stays sticky — the New Game sheet relies on that — but
      // the EFFECT lapses: there is nothing left to protect, and reading what
      // just happened is the point of the recap. This is also what stops
      // anyone needing to touch the switch after a rated game, which is the
      // trap #212's rematch had to defend against.
      final game = await _game(bot: true);
      game.playUci('a8a1'); // Ra1#
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(game.gameOver, isTrue, reason: 'precondition');
      expect(game.blind, isTrue, reason: 'the switch is untouched');
      expect(game.hidingHelp, isFalse, reason: 'but the veil is up');
      game.dispose();
    });
  });

  group('a rated game borrows the overlay switches and gives them back', () {
    // Rated mode suppresses blind/arrows/threats/control by writing the real
    // settings, because those are what the board reads. Nothing put them back,
    // so ONE rated game silently disabled the engine arrows, threat glyphs and
    // square tint everywhere — Review and the analysis board included — and
    // left the next casual game blind.
    Future<(GameController, SettingsStore)> ratedGame({bool blind = false}) async {
      final settings = await loadSettings(white: kSquareBotId);
      settings.blind = blind;
      settings.showArrows = true;
      settings.showThreats = true;
      settings.showControl = true;
      final game = GameController(
          FakeArbiter(analysisLines: kFakeLines, streamPartials: true,
              searchLines: kFakeLines),
          const FakeBot({kSquareBotId: squareBotPersona}),
          FakeGrading(), settings);
      game.newGame(fromFen: _mateIn1BlackMates, rated: true);
      return (game, settings);
    }

    test('they go off while it is on', () async {
      final (game, settings) = await ratedGame();
      expect(settings.blind, isTrue);
      expect(settings.showArrows, isFalse);
      expect(settings.showThreats, isFalse);
      expect(settings.showControl, isFalse);
      expect(game.hidingHelp, isTrue);
      game.dispose();
    });

    test('and come back when the game ends', () async {
      final (game, settings) = await ratedGame();
      game.playerMove(NormalMove.fromUci('a8a1'), 'Ra1#'); // mate
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(game.gameOver, isTrue, reason: 'precondition');
      expect(settings.blind, isFalse, reason: 'as the player had it');
      expect(settings.showArrows, isTrue);
      expect(settings.showThreats, isTrue);
      expect(settings.showControl, isTrue);
      game.dispose();
    });

    test('a player who had blind ON keeps it on afterwards', () async {
      // Restoring means restoring, not forcing off.
      final (game, settings) = await ratedGame(blind: true);
      game.playerMove(NormalMove.fromUci('a8a1'), 'Ra1#');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(settings.blind, isTrue);
      game.dispose();
    });

    test('a rematch does not snapshot the SUPPRESSED switches', () async {
      // #212's rematch re-applies the preset onto a board that is already
      // suppressed. Without the guard on the snapshot, that overwrites the
      // player's values with blind-on/overlays-off — and hands THOSE back at
      // the end, so the switches are stranded exactly as before, one game
      // later.
      final (game, settings) = await ratedGame();
      game.newGame(fromFen: _mateIn1BlackMates, rated: true); // as rematch does
      game.playerMove(NormalMove.fromUci('a8a1'), 'Ra1#');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(settings.blind, isFalse, reason: 'the values from BEFORE the first');
      expect(settings.showArrows, isTrue);
      game.dispose();
    });

    test('the switches survive the app being killed mid-game', () async {
      // The snapshot is on DISK, not in a field. A field is lost to the one
      // teardown it cannot see — the process going away — and then blind
      // stays on with three overlays off forever, the original bug through a
      // different door. So this reloads the SettingsStore itself from the
      // same prefs rather than reusing the instance: reusing it would pass
      // just as well with an in-memory field, and I checked that it does.
      final (game, settings) = await ratedGame();
      expect(settings.showArrows, isFalse, reason: 'precondition');
      game.dispose();

      final relaunched = await SettingsStore.load(); // cold start, same prefs
      expect(relaunched.showArrows, isFalse,
          reason: 'precondition: the suppression persisted, as settings do');
      final revived = GameController(
          FakeArbiter(analysisLines: kFakeLines),
          const FakeBot({kSquareBotId: squareBotPersona}),
          FakeGrading(),
          relaunched);
      revived.newGame(); // the player comes back and starts a casual game
      expect(relaunched.blind, isFalse);
      expect(relaunched.showArrows, isTrue);
      expect(relaunched.showThreats, isTrue);
      expect(relaunched.showControl, isTrue);
      revived.dispose();
    });

    test('starting a casual game hands them back too', () async {
      // Abandoning a rated game mid-way for a casual one must not strand the
      // switches either.
      final (game, settings) = await ratedGame();
      expect(settings.showArrows, isFalse, reason: 'precondition');
      game.newGame();
      expect(settings.showArrows, isTrue);
      expect(settings.blind, isFalse);
      game.dispose();
    });
  });

  test('the veil lifting does not retroactively clean or taint a game', () async {
    // What this DOES pin: a game played entirely blind stays clean even
    // though hidingHelp goes false the instant it ends. That guards the
    // obvious wrong turn — deriving botHintsUsed from the effect at save
    // time, rather than sampling the setting per move.
    //
    // What it does NOT pin, and cannot: whether `_assisted` reads `blind` or
    // `hidingHelp`. Those are equivalent at the only call site — playerMove
    // returns early on gameOver, so `!gameOver` is always true there, and the
    // call site already guards botEnabled. Swapping one for the other leaves
    // this file green, and I checked. The distinction is kept for clarity,
    // and becomes real only if something reads `_assisted` from a path a
    // finished game can reach.
    // playerMove, NOT playUci: playUci is a machine handing you a move (a
    // tree or book tap) and marks hints used unconditionally, deliberately
    // bypassing _assisted. Only a move the human found themselves exercises
    // the predicate under test.
    final game = await _game(bot: true);
    game.playerMove(NormalMove.fromUci('a8a1'), 'Ra1#');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(game.hidingHelp, isFalse, reason: 'the veil lifted, as designed');
    expect(game.botHintsUsed, isFalse,
        reason: 'and that must not retroactively mark the game as assisted');
    game.dispose();
  });

  test('turning the switch off mid-game still taints the game', () async {
    // The other half of the same distinction, and the one that protects the
    // rating: help taken DURING play counts, sampled at every human move.
    final (game, settings) = await _gameAndSettings(bot: true, blind: true);
    settings.blind = false; // the player peeks
    game.playerMove(NormalMove.fromUci('a8a1'), 'Ra1#'); // see above
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(game.botHintsUsed, isTrue);
    game.dispose();
  });
}
