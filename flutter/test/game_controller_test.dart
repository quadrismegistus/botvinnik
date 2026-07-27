// GameController: the FEN gate behind the New Game sheet, and the state
// machine (undo, redo, browse, start-from-FEN) that undo/browse/FEN bugs live
// in. The state-machine tests run against fake engine deps — see
// support/game_harness.dart.
//
//   cd flutter && flutter test test/game_controller_test.dart

import 'package:dartchess/dartchess.dart' show Chess;
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/engine/arbiter.dart'
    show SearchPriority, kRefusalCheckDepth;
import 'package:botvinnik_mobile/brain/chess_api.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart' show CollectOutcome;
import 'package:botvinnik_mobile/stores/settings_store.dart';

import 'support/fake_db.dart';
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
          FakeBot({kTestBotId: testBotPersona}),
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

  group('refusal mode (#167)', () {
    // FakeGrading's default winChance is a constant 0, so _wcDrop is always
    // 0 too — fine for "was collection attempted", useless for refusal,
    // which needs a real number to compare against a threshold. gradeMove's
    // hardcoded grade never sets evalPawns, and backfillGrade does not add
    // it either, so evalPawns stays null through every attempt in this
    // harness: reading that as "bad" and a non-null bestEval as "good" gives
    // every attempted move here a reliable, large win-chance drop.
    double winChanceOf(double? eval, int? mate) =>
        eval == null ? 20 : 80; // drop = 60

    // The refutation must come from the AFTER-position search, never from the
    // pre-move lines the best move is read off. Giving the two fakes different
    // pvs is what makes those distinguishable: with both `d2d4`, swapping the
    // refutation for `grade.bestUci` — exactly the leak this feature must not
    // have — passed every assertion.
    final childLines = [
      EngineMove(pv: ['h7h5'], score: -0.9, mate: null, depth: 10, multipv: 1),
    ];

    Future<(GameController, FakePractice)> newRefusalGame(
        {bool rated = false, ChessApi? chess}) async {
      final settings = await loadSettings(black: kTestBotId);
      final practice = FakePractice();
      final game = GameController(
          FakeArbiter(analysisLines: kFakeLines, searchLines: childLines),
          FakeBot({kTestBotId: testBotPersona}),
          FakeGrading(winChanceOf: winChanceOf),
          settings,
          null,
          practice,
          chess);
      game.newGame(refuseBlunders: true, rated: rated);
      return (game, practice);
    }

    test('a bad move is refused, not played, and still collected', () async {
      final (game, practice) = await newRefusalGame();
      game.playUci('e2e4');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(game.moves, isEmpty, reason: 'refused — never committed');
      expect(game.refusedMoves, 1);
      expect(game.refusalMessage, contains('try again'));
      expect(practice.collected, hasLength(1),
          reason: 'still queued as a puzzle even though it was never played');
      expect(practice.collected.single['san'], 'e4');
      game.dispose();
    });

    // #231. The message renders in exactly one widget — the Insights card —
    // and a rated game has no panels, so refusing was completely silent in the
    // mode where it is arguably most useful. Two halves: WHAT IT COST, said
    // everywhere, and WHY, said only where help is not being withheld.
    test('the message names what the move cost', () async {
      final (game, _) = await newRefusalGame();
      game.playUci('e2e4');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // The harness is rigged for a 60-point drop (see winChanceOf above).
      expect(game.refusalDrop, closeTo(60, 0.5));
      expect(game.refusalMessage, contains('60%'),
          reason: 'refusing without saying how bad is the least useful half');
      game.dispose();
    });

    test('and says so in a RATED game too, where there are no panels',
        () async {
      final (game, _) = await newRefusalGame(rated: true);
      game.playUci('e2e4');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(game.refusedMoves, 1, reason: 'precondition: really refused');
      expect(game.refusalMessage, contains('60%'));
      game.dispose();
    });

    test('but never what to play instead while help is withheld', () async {
      // Rated forces blind on, and blind exists so the engine cannot advise.
      // The cost is a judgement about the move you chose; the refutation is
      // engine analysis of the position, which is the line rated must not
      // cross.
      final (game, _) = await newRefusalGame(rated: true, chess: _RefuteChess());
      game.playUci('e2e4');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(game.refusedMoves, 1, reason: 'precondition: really refused');
      expect(game.refusalRefutationUci, isNull);
      expect(game.refusalRefutationSan, isNull);
      game.dispose();
    });

    test('and does say it in a casual, non-blind game', () async {
      // The other half — so the assertion above fails for the reason claimed
      // rather than because nothing ever populates it.
      final (game, _) = await newRefusalGame(chess: _RefuteChess());
      game.playUci('e2e4');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(game.refusedMoves, 1, reason: 'precondition: really refused');
      expect(game.refusalRefutationUci, 'h7h5',
          reason: "the after-position search's reply, i.e. what it runs into");
      expect(game.refusalRefutationUci, isNot(kFakeLines.first.pv.first),
          reason: 'NEVER the best move — that is what practice withholds too');
      expect(game.refusalRefutationSan, 'SAN(h7h5)');
      game.dispose();
    });

    test('and not in a rated game even with blind turned back OFF', () async {
      // The half the previous two could not separate. `newGame(rated: true)`
      // applies the rated preset, which forces blind ON — so hidingHelp is
      // already true and `!_rated` never gets a chance to matter. Deleting it
      // left all 812 tests green while the commit claimed the mutation died.
      //
      // The separating state is reachable: the app-bar eye button writes
      // settings.blind unconditionally and is not disabled during a rated
      // game, so a player can turn blind off mid-rated-game. Rated must still
      // withhold the refutation there — being rated is the reason, not the
      // blindfold.
      // Built inline rather than through newRefusalGame, because this test
      // needs to keep hold of the SettingsStore to flip the switch.
      final settings = await loadSettings(black: kTestBotId);
      final game = GameController(
          FakeArbiter(analysisLines: kFakeLines, searchLines: childLines),
          FakeBot({kTestBotId: testBotPersona}),
          FakeGrading(winChanceOf: winChanceOf),
          settings,
          null,
          FakePractice(),
          _RefuteChess());
      game.newGame(refuseBlunders: true, rated: true);
      settings.blind = false;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(game.hidingHelp, isFalse,
          reason: 'precondition: the blind clause can no longer carry this');
      expect(game.rated, isTrue);

      game.playUci('e2e4');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(game.refusedMoves, 1, reason: 'precondition: really refused');
      expect(game.refusalRefutationUci, isNull);
      game.dispose();
    });

    // The check crosses the JS bridge and the arbiter on every await, and this
    // method is fire-and-forget with no zone guard. Before the catch, a throw
    // skipped _apply and the `finally` then cleared pendingFen on the way out:
    // the piece snapped home with no message and nothing counted, which is
    // indistinguishable from a misclick — and with a dead engine EVERY move
    // vanished, while the same dead engine with refusal mode off still let the
    // game be played.
    group('a failed check fails OPEN', () {
      Future<GameController> throwing({required bool refuse}) async {
        final settings = await loadSettings(black: kTestBotId);
        final game = GameController(
            FakeArbiter(analysisLines: kFakeLines, searchLines: childLines),
            FakeBot({kTestBotId: testBotPersona}),
            _ThrowingGrading(winChanceOf: winChanceOf),
            settings);
        game.newGame(refuseBlunders: refuse);
        return game;
      }

      test('a throwing bridge lets the move through', () async {
        final game = await throwing(refuse: true);
        game.playUci('e2e4');
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(game.moves.map((m) => m.san), ['e4'],
            reason: 'the move must not vanish');
        expect(game.pendingFen, isNull, reason: 'and must not stay hovering');
        expect(game.refusalMessage, isNull);
        expect(game.refusedMoves, 0, reason: 'nothing was actually refused');
        game.dispose();
      });

      test('but a throw AFTER the refusal must not undo it', () async {
        // The other side of the guard, and the one a blanket catch gets
        // wrong. The refusal path awaits a database write — maybeCollect —
        // AFTER the message is on screen and the board has snapped back. A
        // catch that failed open there would apply the very move it had just
        // refused, under its own "that costs 60%" message.
        final settings = await loadSettings(black: kTestBotId);
        final game = GameController(
            FakeArbiter(analysisLines: kFakeLines, searchLines: childLines),
            FakeBot({kTestBotId: testBotPersona}),
            FakeGrading(winChanceOf: winChanceOf),
            settings,
            null,
            _ThrowingPractice());
        game.newGame(refuseBlunders: true);

        game.playUci('e2e4');
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(game.moves, isEmpty,
            reason: 'the refused move must stay refused');
        expect(game.refusedMoves, 1);
        expect(game.refusalMessage, contains('60%'),
            reason: 'and the message it was refused with must stand');
        game.dispose();
      });

      test('and a throw that lands after the game moved on applies nothing',
          () async {
        // The generation guard the SUCCESS path has had all along (`if (gen !=
        // _gen) return`) and the catch was missing. Reachable exactly in the
        // scenario that makes the catch necessary: a dead bridge means moves
        // keep failing, which is what makes a player start a new game in the
        // middle of a check. The stale move then landed in the FRESH game —
        // and _maybeBotTurn was called on it, so the bot answered it.
        final settings = await loadSettings(black: kTestBotId);
        final game = GameController(
            _ThrowingSearchArbiter(),
            FakeBot({kTestBotId: testBotPersona}),
            FakeGrading(winChanceOf: winChanceOf),
            settings);
        game.newGame(refuseBlunders: true);

        game.playUci('e2e4');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        game.newGame(refuseBlunders: true); // bumps the generation mid-check
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(game.moves, isEmpty,
            reason: 'a move from the abandoned game landed in the new one');
        expect(game.position.fen, Chess.initial.fen);
        game.dispose();
      });

      test('which is what the same throw does with refusal mode off', () async {
        // The control, and the comparison that makes the bug a bug: without
        // refusal mode the identical failure costs only the grade.
        final game = await throwing(refuse: false);
        game.playUci('e2e4');
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(game.moves.map((m) => m.san), ['e4']);
        game.dispose();
      });
    });

    // #213 split one number into two: the practice bar and the refusal bar.
    // They had been the same field, set by a control labelled "Practice
    // mistakes losing at least" that said nothing about rated games — so
    // lowering your practice bar made refusal reject far more.
    //
    // Tested through the CONTROLLER, not the store. A store-level test that
    // the two fields are independent passes happily while game_controller
    // still reads the wrong one, which is exactly what a mutation showed.
    group('refusal reads its OWN bar (#213)', () {
      Future<GameController> refusalGame(
          {required int practice, required int refuse}) async {
        final settings = await loadSettings(black: kTestBotId);
        settings.collectThreshold = practice;
        settings.refuseThreshold = refuse;
        final game = GameController(
            FakeArbiter(analysisLines: kFakeLines, searchLines: childLines),
            FakeBot({kTestBotId: testBotPersona}),
            FakeGrading(winChanceOf: winChanceOf), // rigged for a 60-pt drop
            settings,
            null,
            FakePractice());
        game.newGame(refuseBlunders: true);
        return game;
      }

      test('refuses on the refusal bar even with the practice bar above it',
          () async {
        final game = await refusalGame(practice: 90, refuse: 10);
        game.playUci('e2e4');
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(game.refusedMoves, 1,
            reason: 'a 60-point drop clears the 10% refusal bar');
        expect(game.moves, isEmpty);
        game.dispose();
      });

      test('and lets a move through when only the PRACTICE bar is below it',
          () async {
        // The other direction, and the one that makes the pair a claim about
        // WHICH field is read rather than about thresholds in general.
        final game = await refusalGame(practice: 10, refuse: 90);
        game.playUci('e2e4');
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(game.refusedMoves, 0,
            reason: 'a 60-point drop does not clear the 90% refusal bar');
        expect(game.moves.map((m) => m.san), ['e4']);
        game.dispose();
      });
    });

    test('relents on the 4th attempt at the same position', () async {
      final (game, practice) = await newRefusalGame();
      for (var i = 0; i < GameController.kMaxRefusalAttempts; i++) {
        game.playUci('e2e4');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(game.moves, isEmpty, reason: 'attempt ${i + 1} refused');
      }
      expect(game.refusedMoves, GameController.kMaxRefusalAttempts);

      game.playUci('e2e4'); // the 4th attempt at this position
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(game.moves, hasLength(1), reason: 'relented — now committed');
      expect(game.moves.single.san, 'e4');
      expect(game.refusedMoves, GameController.kMaxRefusalAttempts,
          reason: 'the relented-through move is not itself a refusal');
      // 3 refusal-time collects, plus the ordinary POST-commit collect
      // _gradePipeline runs for every move once it lands — the relented-
      // through move is still a real blunder in this harness (its eval
      // reads exactly as "bad" as the three that were refused), and it
      // should still reach the practice queue like any played blunder does.
      expect(
          practice.collected, hasLength(GameController.kMaxRefusalAttempts + 1));
      game.dispose();
    });

    test('browsing away clears a stale refusal message (review follow-up)',
        () async {
      // A refusal message describes one specific attempted move — it must
      // not keep showing next to an unrelated position after the player
      // browses elsewhere and back. browseBy needs SOME move history to
      // step through; what it is doesn't matter to what's under test here
      // (refusalMessage's clearing behavior), so append one directly rather
      // than threading a realistic bot reply through the fake arbiter.
      final (game, _) = await newRefusalGame();
      game.moves.add(MoveRecord(
        ply: 1,
        san: 'd4',
        uci: 'd2d4',
        color: 'w',
        fenBefore: game.position.fen,
        fenAfter: game.position.fen,
      ));

      game.playUci('e2e4'); // refused: never commits, sets refusalMessage
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(game.refusalMessage, isNotNull);

      game.browseBy(-1);
      expect(game.refusalMessage, isNull, reason: 'browsing away clears it');

      game.browseLive();
      expect(game.refusalMessage, isNull,
          reason: 'returning to live does not resurrect it');
      game.dispose();
    });

    test('refusedMoves persists on the saved game record', () async {
      final db = FakeDb();
      final settings = await loadSettings(black: kTestBotId);
      final game = GameController(
          FakeArbiter(analysisLines: kFakeLines, streamPartials: true),
          FakeBot({kTestBotId: testBotPersona}),
          SavingGrading(winChanceOf: winChanceOf),
          settings,
          db);
      game.newGame(refuseBlunders: true);

      for (var i = 0; i < GameController.kMaxRefusalAttempts; i++) {
        game.playUci('e2e4');
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      game.playUci('e2e4'); // relent — commits
      await Future<void>.delayed(const Duration(milliseconds: 150));

      await game.debugForceSave();
      expect(game.lastSavedGame?['refusedMoves'],
          GameController.kMaxRefusalAttempts);
      game.dispose();
    });

    // ---- latency (#167 follow-up: "a serious lag before it appears") ----
    //
    // The check ran entirely at `analysis` priority: it awaited the live
    // position's depth-22 analysis to COMPLETION for pre-lines, then queued
    // the candidate search behind that same still-running analysis, because
    // equal priority never preempts. Two multi-second waits, in series,
    // before the piece moved at all.

    test('the candidate search preempts, and stays shallow', () async {
      final arbiter = FakeArbiter(analysisLines: kFakeLines);
      final settings = await loadSettings(black: kTestBotId);
      final game = GameController(
          arbiter,
          FakeBot({kTestBotId: testBotPersona}),
          FakeGrading(winChanceOf: winChanceOf),
          settings,
          null,
          FakePractice());
      game.newGame(refuseBlunders: true);

      game.playUci('e2e4');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final check = arbiter.searchRequests
          .where((r) => r.priority == SearchPriority.refusalCheck);
      expect(check, hasLength(1),
          reason: 'an `analysis`-priority request would queue behind the '
              'live position analysis instead of preempting it');
      expect(check.single.depth, kRefusalCheckDepth);
      expect(check.single.multiPv, 1,
          reason: 'backfillGrade reads the multipv-1 line and nothing else');
      game.dispose();
    });

    test('does not wait out an analysis that has already streamed usable lines',
        () async {
      // The live position's analysis streams depth-15 partials and then keeps
      // thinking for far longer than any player would wait. Reading the
      // partials answers now; awaiting the future does not answer at all.
      final settings = await loadSettings(black: kTestBotId);
      final practice = FakePractice();
      final game = GameController(
          FakeArbiter(
            analysisLines: kFakeLines,
            streamPartials: true,
            analysisDelay: const Duration(seconds: 30),
          ),
          FakeBot({kTestBotId: testBotPersona}),
          FakeGrading(winChanceOf: winChanceOf),
          settings,
          null,
          practice);
      game.newGame(refuseBlunders: true);

      game.playUci('e2e4');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(game.refusedMoves, 1,
          reason: 'decided from streamed partials, not the finished search');
      expect(game.moves, isEmpty);
      game.dispose();
    });

    test('the board shows the attempted move while the check runs', () async {
      final settings = await loadSettings(black: kTestBotId);
      final game = GameController(
          // the refusal check resolves from analysisLines, so searchDelay is
          // the length of the check itself here
          FakeArbiter(
              analysisLines: kFakeLines,
              searchDelay: const Duration(milliseconds: 100)),
          FakeBot({kTestBotId: testBotPersona}),
          FakeGrading(winChanceOf: winChanceOf),
          settings,
          null,
          FakePractice());
      game.newGame(refuseBlunders: true);
      final before = game.position.fen;

      game.playUci('e2e4');
      expect(game.pendingFen, isNot(before),
          reason: 'the piece lands where it was dropped, in the same frame — '
              'an unchanged board reads as a move the app ate');
      expect(game.pendingMove?.uci, 'e2e4');
      expect(game.position.fen, before, reason: 'shown, not committed');

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(game.pendingFen, isNull, reason: 'refused — the board snaps back');
      expect(game.position.fen, before);
      expect(game.refusalMessage, isNotNull);
      game.dispose();
    });

    test('a pending board view never outlives its check', () async {
      // Every gen-bumping path clears it; undo is the one that can land while
      // a check is genuinely in flight (the search here never resolves).
      final settings = await loadSettings(black: kTestBotId);
      final game = GameController(
          FakeArbiter(
              analysisLines: kFakeLines,
              searchDelay: const Duration(seconds: 30)),
          FakeBot({kTestBotId: testBotPersona}),
          FakeGrading(winChanceOf: winChanceOf),
          settings,
          null,
          FakePractice());
      game.newGame(refuseBlunders: true);
      game.moves.add(MoveRecord(
        ply: 1,
        san: 'd4',
        uci: 'd2d4',
        color: 'w',
        fenBefore: game.position.fen,
        fenAfter: game.position.fen,
      ));

      game.playUci('e2e4');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(game.pendingFen, isNotNull, reason: 'check still in flight');

      game.undo();
      expect(game.pendingFen, isNull);
      game.browseBy(-1);
      expect(game.pendingFen, isNull);
      game.newGame(refuseBlunders: true);
      expect(game.pendingFen, isNull);
      game.dispose();
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
          FakeBot({kTestBotId: testBotPersona}), FakeGrading(), settings);
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
          FakeBot({
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
          FakeBot({
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

  group('an opponent change is not itself a new game (#133)', () {
    // The New Game sheet is the only caller that changes players, and its very
    // next line starts the game with the FEN _onSettings cannot know. So the
    // settings listener must NOT reset on its own: doing so bumped the
    // generation twice per change and wiped to the standard start before the
    // sheet redid it with the FEN. Counting resets is what tells this apart
    // from the board merely ending up cleared — the exact measurement in #133.
    //
    // The eager `_lastSettingsSig` (assigned in the constructor, not by a late
    // initializer) is the other half: it made the FIRST change detectable at
    // all. The swallow used to hide it, which is why the old code's first
    // change reset once and every later one reset twice.
    testWidgets('each opponent change resets exactly once through the sheet '
        'sequence — the first as well as the rest', (tester) async {
      final arbiter = _CountingArbiter();
      final settings = await loadSettings(); // both null: analysis
      final game = GameController(
          arbiter,
          FakeBot({
            kTestBotId: testBotPersona,
            kSquareBotId: squareBotPersona,
          }),
          FakeGrading(),
          settings);

      // The sheet's real sequence: assign the players, then start the game.
      int resetsFor(void Function() change) {
        final before = arbiter.resets;
        change();
        game.newGame();
        return arbiter.resets - before;
      }

      // The FIRST change. With newGame() gone from _onSettings the listener
      // adds nothing, so only the sheet's own reset counts.
      expect(
          resetsFor(() => settings.setPlayers(white: null, black: kTestBotId)),
          1,
          reason: 'only the sheet resets, not the settings listener');

      // The SECOND change — the one that was TWO before the fix. _onSettings
      // detected it and called newGame() of its own, on top of the sheet's.
      expect(
          resetsFor(() => settings.setPlayers(white: null, black: kSquareBotId)),
          1,
          reason: 'the listener no longer piggybacks a reset on the change');

      settings.setPlayers(white: null, black: null);
      game.newGame();
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}

/// A [FakeArbiter] that counts board resets. newGame() calls bumpGeneration()
/// exactly once, so the tally is the number of resets — which is what tells a
/// redundant reset apart from a board that merely ended up cleared (#133).
class _CountingArbiter extends FakeArbiter {
  int resets = 0;
  @override
  void bumpGeneration() => resets++;
}

/// Names the refutation move so a test can tell it from the best move.
/// The CHILD search fails, after a delay.
///
/// The one throw site that survives [_computeGrade]'s own `gen != _gen` guard:
/// analysis resolves normally, the generation check passes, and the refusal
/// check's own search then throws — which is where a real dead engine reports
/// itself, since that search is the only thing refusal mode asks for that the
/// position's analysis has not already answered.
class _ThrowingSearchArbiter extends FakeArbiter {
  _ThrowingSearchArbiter() : super(analysisLines: kFakeLines);

  @override
  Future<List<EngineMove>?> search({
    required String fen,
    String? ownerFen,
    required int depth,
    required int multiPv,
    int? movetimeMs,
    List<List<String>> extraOptions = const [],
    required SearchPriority priority,
    void Function(List<EngineMove>)? onUpdate,
  }) =>
      Future<List<EngineMove>?>.delayed(const Duration(milliseconds: 80),
          () => throw StateError('the engine died mid-search'));
}

/// Collection fails, AFTER the refusal has already been decided and painted.
/// The database is the one dependency in [_maybeRefuse] that is touched past
/// the point of no return.
class _ThrowingPractice extends FakePractice {
  @override
  Future<CollectOutcome> maybeCollect(Map<String, dynamic> storedMove,
          {String? setupUci, int minDepth = 8}) async =>
      throw StateError('the practice store is unwritable');
}

/// A grading facade whose bridge is dead. `gradeMove` is the first call
/// `_maybeRefuse` makes across it, so this is the earliest and commonest shape
/// of the failure — a bridge StateError, exactly what `_maybeBotTurn` has
/// caught since it was written.
class _ThrowingGrading extends FakeGrading {
  _ThrowingGrading({super.winChanceOf});

  @override
  MoveGrade gradeMove({
    required int ply,
    required String fenBefore,
    required String san,
    required String uci,
    required String color,
    required List<EngineMove> preLines,
  }) =>
      throw StateError('brain.gradeMove failed: the bridge is dead');
}

class _RefuteChess implements ChessApi {
  @override
  String san(String fen, String uci) => 'SAN($uci)';

  /// Wiring a ChessApi also builds the lines tree, which calls this on every
  /// ingest; a noSuchMethod null throws a type error and takes the whole
  /// refusal flow down before it can set anything.
  @override
  List<Map<String, dynamic>> sanSteps(String fen, List<String> ucis) => [
        for (var i = 0; i < ucis.length; i++)
          {'san': ucis[i], 'uci': ucis[i], 'color': i.isEven ? 'w' : 'b', 'piece': 'p'}
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
