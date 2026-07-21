// GameController: the FEN gate behind the New Game sheet, and the state
// machine (undo, redo, browse, start-from-FEN) that undo/browse/FEN bugs live
// in. The state-machine tests run against fake engine deps — see
// support/game_harness.dart.
//
//   cd flutter && flutter test test/game_controller_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';

import 'support/game_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isPlayableFen', () {
    test('accepts the standard start and a legal midgame position', () {
      expect(
          GameController.isPlayableFen(
              'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
          isTrue);
      // a bare K+P vs K endgame — unmistakably not the start
      expect(GameController.isPlayableFen('8/8/8/4k3/8/4K3/4P3/8 w - - 0 1'),
          isTrue);
    });

    test('trims surrounding whitespace off a pasted FEN', () {
      expect(
          GameController.isPlayableFen('  8/8/8/4k3/8/4K3/4P3/8 w - - 0 1\n'),
          isTrue);
    });

    test('rejects empty, garbage, and structurally broken input', () {
      expect(GameController.isPlayableFen(''), isFalse);
      expect(GameController.isPlayableFen('not a fen'), isFalse);
      // right shape, impossible board (nine files on a rank)
      expect(
          GameController.isPlayableFen(
              'rnbqkbnrx/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
          isFalse);
    });
  });

  // A K+P vs K endgame: three pieces, so a fall-back to the 32-piece standard
  // start is unmistakable. Kings on the back ranks so the e-pawn is free to
  // move (with the king on e3 it would be blocked — a legal FEN, illegal e2e4).
  const kpk = '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1';

  group('start from a FEN', () {
    test('newGame(fromFen:) loads the position, not the standard start',
        () async {
      final g = await makeGame(fromFen: kpk);
      expect(g.moves, isEmpty);
      expect(g.position.fen, isNot(kStandardStartFen));
    });

    test('undo after a move returns to the FEN, not the standard start',
        () async {
      final g = await makeGame(fromFen: kpk);
      final start = g.position.fen;
      g.playUci('e2e4');
      expect(g.moves, hasLength(1));
      g.undo();
      expect(g.moves, isEmpty);
      expect(g.position.fen, start);
      expect(g.position.fen, isNot(kStandardStartFen));
    });

    test('browse to the start shows the FEN, not the standard start', () async {
      final g = await makeGame(fromFen: kpk);
      final start = g.position.fen;
      g.playUci('e2e4');
      g.browseTo(0);
      expect(g.browseFen, start);
      expect(g.browseFen, isNot(kStandardStartFen));
    });
  });

  group('undo / redo / browse on a normal game', () {
    test('undo steps back one ply and redo replays it', () async {
      final g = await makeGame();
      final start = g.position.fen;
      g.playUci('e2e4');
      final after1 = g.position.fen;
      g.playUci('e7e5');
      final after2 = g.position.fen;

      g.undo();
      expect(g.position.fen, after1);
      g.undo();
      expect(g.position.fen, start);

      g.redo();
      expect(g.position.fen, after1);
      g.redo();
      expect(g.position.fen, after2);
    });

    test('browse to the start, then back to live', () async {
      final g = await makeGame();
      final start = g.position.fen;
      g.playUci('e2e4');

      g.browseTo(0);
      expect(g.browsing, isTrue);
      expect(g.browseFen, start);

      g.browseLive();
      expect(g.browsing, isFalse);
    });
  });

  group('preview tagging', () {
    // The Insights move line and the threat line share ONE preview slot.
    // Without a tag each button reads the shared `previewing` flag and both
    // show STOP while only one is actually running.
    test('starting one preview replaces the other and the tag follows',
        () async {
      final g = await makeGame();
      final start = g.position.fen;

      g.startPreview(start, ['e2e4', 'e7e5'], tag: 'move');
      expect(g.previewing, isTrue);
      expect(g.previewTag, 'move');

      // the threat line takes over the slot
      g.startPreview(start, ['d2d4'], tag: 'threat');
      expect(g.previewing, isTrue);
      expect(g.previewTag, 'threat');

      g.stopPreview();
      expect(g.previewing, isFalse);
      expect(g.previewTag, isNull); // nothing is playing, so nobody shows STOP
    });

    test('an illegal line never starts a preview, so no tag is left behind',
        () async {
      final g = await makeGame();
      g.startPreview(g.position.fen, ['e2e5'], tag: 'threat'); // not a legal move
      expect(g.previewing, isFalse);
      expect(g.previewTag, isNull);
    });
  });

  group('practice collection', () {
    // Practice drills YOUR blunders from real games. The analysis board is
    // exploration — both sides are you, its "mistakes" are deliberate, and
    // collecting them poisoned the practice queue. The guard is botEnabled.
    Future<FakePractice> playOneMove({String? white, String? black}) async {
      final settings = await loadSettings(white: white, black: black);
      final practice = FakePractice();
      final game = GameController(
          FakeArbiter(analysisLines: kFakeLines),
          const FakeBot({kTestBotId: testBotPersona}),
          FakeGrading(),
          settings,
          null,
          practice);
      game.playUci('e2e4');
      // let the grading pipeline run to the collect guard
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return practice;
    }

    test('a real game collects your blunder', () async {
      // you are White, a bot is Black — so e2e4 is YOUR move in a real game
      final practice = await playOneMove(black: kTestBotId);
      expect(practice.collected, hasLength(1));
      expect(practice.collected.single['san'], 'e4');
    });

    test('the analysis board collects nothing', () async {
      // both sides you: botEnabled is false, so nothing is collected
      final practice = await playOneMove();
      expect(practice.collected, isEmpty);
    });
  });

  group('bot turn generations', () {
    // A bot turn waits up to 1.5s before replying (so the player's grade lands
    // first), which is the window a new game can land in. The stale turn then
    // wakes to a bumped generation and must bail WITHOUT clearing botThinking —
    // by then the fresh turn owns that flag. Clearing it re-enabled re-entry
    // (a second concurrent bot search) and desynced undo/redo. Issue #87.
    testWidgets('a new game mid-turn does not clobber the fresh turn',
        (tester) async {
      // Bot plays White, so it is on move immediately and the controller
      // starts a bot turn in its constructor.
      final settings = await loadSettings(white: kTestBotId);
      final game = GameController(FakeArbiter(),
          const FakeBot({kTestBotId: testBotPersona}), FakeGrading(), settings);
      expect(game.botThinking, isTrue, reason: 'the bot turn should have begun');

      // a new game bumps the generation and starts a FRESH bot turn
      game.newGame();
      expect(game.botThinking, isTrue);

      // now the STALE turn wakes from its wait and sees the new generation
      await tester.pump(const Duration(milliseconds: 60));
      expect(game.botThinking, isTrue,
          reason: 'the stale bot turn clobbered the fresh one');

      // wind the bot down so no timer outlives the test
      settings.setPlayers(white: null, black: null);
      game.newGame();
      await tester.pump(const Duration(milliseconds: 120));
    });
  });

  group('the Stockfish stand-in is recorded', () {
    // When a persona's own engine cannot answer, the move comes from Stockfish
    // instead — the same board, the same name on the card, a different
    // opponent. Nothing about that fails, so nothing surfaces it; the flag is
    // the only way the UI, the saved game, and estimatePlayerElo can know.
    // Issue #117.
    // The controller starts a bot turn in its constructor, so the settings have
    // to come back out with it — winding the bot down at the end of each test
    // is what stops a timer outliving it.
    Future<(GameController, SettingsStore)> botTurn(
        {required Persona persona, required String id}) async {
      final settings = await loadSettings(white: id);
      final game = GameController(
          FakeArbiter(
              analysisLines: kFakeLines,
              streamPartials: true,
              searchLines: kFakeLines),
          FakeBot({id: persona}),
          FakeGrading(),
          settings);
      return (game, settings);
    }

    Future<void> windDown(
        WidgetTester tester, GameController game, SettingsStore s) async {
      s.setPlayers(white: null, black: null);
      game.newGame();
      await tester.pump(const Duration(milliseconds: 120));
    }

    testWidgets('a family with no engine of its own sets the flag',
        (tester) async {
      final (game, s) =
          await botTurn(persona: fallbackBotPersona, id: kFallbackBotId);
      await tester.pump(const Duration(seconds: 2));
      expect(game.botFallback, isTrue,
          reason: 'the move came from Stockfish, not the persona');

      await windDown(tester, game, s);
    });

    testWidgets('a fish bot reaches the same block and sets nothing',
        (tester) async {
      // The load-bearing half of the guard. Fish arrives at the very same line
      // as the dala persona above — the difference is that for fish this block
      // IS its engine, so it played itself and nothing was substituted.
      //
      // Without the family check, marking on arrival would flag every fish
      // game, estimatePlayerElo would drop them all, and the flag would mean
      // nothing. This is the test that fails if the guard is dropped; the
      // square case below only proves square never gets here at all.
      final (game, s) = await botTurn(persona: fishBotPersona, id: kFishBotId);
      await tester.pump(const Duration(seconds: 2));
      expect(game.botFallback, isFalse,
          reason: 'fish played itself — nothing stood in for it');

      await windDown(tester, game, s);
    });

    testWidgets('a square bot plays its own branch and never falls through',
        (tester) async {
      // Uses squareBotPersona, which carries a shapedLabel. With
      // testBotPersona this test was VACUOUS: `p.shapedLabel!` threw before the
      // square branch called anything, the catch-all swallowed it, and the test
      // passed even when square was rewritten to fall through to the stand-in
      // on failure — the exact regression it names. Found by review on #131.
      final (game, s) =
          await botTurn(persona: squareBotPersona, id: kSquareBotId);
      await tester.pump(const Duration(seconds: 2));
      expect(game.moves, isNotEmpty,
          reason: 'square must actually have played, or this proves nothing');
      expect(game.botFallback, isFalse);

      await windDown(tester, game, s);
    });

    testWidgets('bot vs bot badges only the persona that was stood in for',
        (tester) async {
      // The flag is a property of the game, but the CLAIM it corrects is per
      // side. White falls through to the stand-in; black is a square bot
      // playing its own branch. A per-game bool put the chip on both.
      final settings =
          await loadSettings(white: kFallbackBotId, black: kSquareBotId);
      final game = GameController(
          FakeArbiter(
              analysisLines: kFakeLines,
              streamPartials: true,
              searchLines: kFakeLines),
          const FakeBot({
            kFallbackBotId: fallbackBotPersona,
            kSquareBotId: squareBotPersona,
          }),
          FakeGrading(),
          settings);
      await tester.pump(const Duration(seconds: 2));

      expect(game.stoodInFor(kFallbackBotId), isTrue,
          reason: 'white had no engine of its own');
      expect(game.stoodInFor(kSquareBotId), isFalse,
          reason: 'black played itself and must not be accused');

      settings.setPlayers(white: null, black: null);
      game.newGame();
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('an abandoned turn does not flag the game that replaced it',
        (tester) async {
      // The reason the flag is committed by the CALLER rather than where the
      // stand-in is chosen. _pickBotMove awaits — maia, retro and garbo all
      // wait on an engine, and the stand-in itself waits on a search — and the
      // generation is only re-checked after it returns. Set the flag inside
      // and a turn abandoned by a new game resumes into the game that replaced
      // it.
      //
      // Found by review on PR #131. It was not hypothetical: the original
      // implementation set the flag on entry to the fallback block, and this
      // test reproduced a square bot's game being marked as substituted.
      final settings = await loadSettings(white: kFallbackBotId);
      final game = GameController(
          FakeArbiter(
              analysisLines: kFakeLines,
              streamPartials: true,
              searchLines: kFakeLines,
              // the window the new game lands in
              searchDelay: const Duration(milliseconds: 500)),
          const FakeBot({
            kFallbackBotId: fallbackBotPersona,
            kTestBotId: testBotPersona,
          }),
          FakeGrading(),
          settings);

      // game 1's turn is now parked awaiting the stand-in's search
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.botFallback, isFalse, reason: 'still in flight');

      // game 2 starts under it, against a bot that plays itself
      settings.setPlayers(white: kTestBotId, black: null);
      game.newGame();
      expect(game.botFallback, isFalse, reason: 'newGame cleared it');

      // game 1's abandoned turn now resumes and returns its stand-in move
      await tester.pump(const Duration(seconds: 1));
      expect(game.botFallback, isFalse,
          reason: 'game 2 is a square bot playing itself — the abandoned '
              'game-1 turn must not stamp it');

      settings.setPlayers(white: null, black: null);
      game.newGame();
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('a new game clears it', (tester) async {
      // Sticky for the GAME, not the session: a later game against a persona
      // whose engine works must not inherit this one's substitution.
      //
      // The players are cleared BEFORE newGame so the fresh game starts no bot
      // turn of its own — otherwise the same broken persona would substitute
      // again immediately (correctly), and the reset would be untestable
      // because the flag would never be observably false.
      final (game, s) =
          await botTurn(persona: fallbackBotPersona, id: kFallbackBotId);
      await tester.pump(const Duration(seconds: 2));
      expect(game.botFallback, isTrue);

      s.setPlayers(white: null, black: null);
      game.newGame();
      expect(game.botFallback, isFalse);
      await tester.pump(const Duration(milliseconds: 120));
    });
  });
}
