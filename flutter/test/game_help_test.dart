// What the archive needs to know about HOW a game was won: the takebacks the
// human used (`botUndos`) and whether the engine's hints were on the board
// (`botHintsUsed`). Both are declared in StoredGame and, until #144, written
// by nothing — so `playerElo.ts`, which drops any game carrying a takeback
// from the rating fit, never saw one to drop.
//
// The last group is the one that matters most: the save path snapshots the
// finished game BEFORE waiting for grading, and a new game started during that
// wait (which is what a player does after a checkmate) must not be able to
// rewrite what gets archived. botFallback shipped with exactly that bug two
// days ago; these two fields have the same shape.
//
//   cd flutter && flutter test test/game_help_test.dart

import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';

import 'support/fake_db.dart';
import 'support/game_harness.dart';

/// Black king boxed in by its own pawns, White rook on a1: 1.Ra8 is mate, and
/// 1.Ra7 is a legal quiet move from the same position. The mate matters because
/// the game then ends on the HUMAN's move — no bot reply is due, so nothing
/// parks in `botThinking` and undo is free to run.
const _mateIn1 = '6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1';

/// A practice controller whose collect NEVER returns, which parks the grading
/// pipeline at its last line and so holds `_pendingGrades` non-empty. That is
/// the only way to open the save path's grade-wait window from a test — the
/// real thing is an engine that has not answered yet.
///
/// A bare Completer, not a long `Future.delayed`: a delay is a TIMER, and a
/// timer still pending when a widget test ends fails the test for a reason
/// that has nothing to do with what it was checking.
class ParkingPractice implements PracticeController {
  @override
  Future<void> maybeCollect(Map<String, dynamic> storedMove,
          {String? setupUci, int minDepth = 8}) =>
      Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The harness's [FakeGrading] answers the whole-game calls out of
/// `noSuchMethod`, i.e. with null, which a non-nullable `labelCounts` rejects
/// — so it cannot reach the end of a save. These two are the difference
/// between a test that archives a game and one that dies in the accountancy.
class SavingGrading extends FakeGrading {
  @override
  double? gameAccuracy(List<Map<String, dynamic>> storedMoves, String color) =>
      null;

  @override
  Map<String, dynamic> labelCounts(
          List<Map<String, dynamic>> storedMoves, String color) =>
      const {'blunder': 0, 'mistake': 0, 'inaccuracy': 0};
}

/// A bot game with the human on White, starting from [_mateIn1].
///
/// [arbiter] and [practice] default to the never-resolving fakes, which keep
/// every async tail parked; the race test passes resolving ones.
Future<(GameController, SettingsStore, FakeDb)> _botGame({
  FakeArbiter? arbiter,
  PracticeController? practice,
}) async {
  final settings = await loadSettings(black: kTestBotId);
  final db = FakeDb();
  final game = GameController(
      arbiter ?? FakeArbiter(),
      const FakeBot({kTestBotId: testBotPersona}),
      SavingGrading(),
      settings,
      db,
      practice);
  game.newGame(fromFen: _mateIn1);
  return (game, settings, db);
}

void _mate(GameController g) =>
    g.playerMove(NormalMove.fromUci('a1a8'), 'Ra8#');
void _quiet(GameController g) =>
    g.playerMove(NormalMove.fromUci('a1a7'), 'Ra7');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('botUndos counts takebacks against the bot', () {
    test('one undo in a bot game is one takeback', () async {
      final (g, _, _) = await _botGame();
      _mate(g);
      expect(g.gameOver, isTrue,
          reason: 'the fixture must actually end the game, or the bot is on '
              'move and undo refuses for a reason this test is not about');
      expect(g.botUndos, 0);

      g.undo();
      expect(g.botUndos, 1);
    });

    test('an undo→redo round trip gives the takeback back', () async {
      // Nothing was changed and nothing was learned: the same moves go back on
      // the same board. Only a round trip can reach redo — a divergent move
      // clears the stack, which is the case below.
      final (g, _, _) = await _botGame();
      _mate(g);
      g.undo();
      g.redo();
      expect(g.botUndos, 0);
      expect(g.gameOver, isTrue, reason: 'redo put the mate back');
    });

    test('a takeback followed by a different move stands', () async {
      final (g, _, _) = await _botGame();
      _mate(g);
      g.undo();
      _quiet(g); // diverges — the mate is unreachable now
      expect(g.botUndos, 1);
    });

    test('an undo refused because the bot is thinking is not a takeback',
        () async {
      // undo() returns early on botThinking. Counting before that guard would
      // charge the player for a takeback that never happened — one tap on a
      // dead button per bot move.
      final (g, _, _) = await _botGame();
      _quiet(g); // the bot is now on move, and the fake search never resolves
      expect(g.botThinking, isTrue,
          reason: 'no parked bot turn — this test proves nothing');

      g.undo();
      expect(g.moves, hasLength(1), reason: 'the undo was refused');
      expect(g.botUndos, 0);
    });

    test('the analysis board counts nothing', () async {
      // Both sides human: there is no result to assist and nothing to rate.
      final g = await makeGame(fromFen: _mateIn1);
      _quiet(g);
      g.undo();
      expect(g.botUndos, 0);
    });

    test('a new game clears the count', () async {
      final (g, _, _) = await _botGame();
      _mate(g);
      g.undo();
      expect(g.botUndos, 1);
      g.newGame();
      expect(g.botUndos, 0);
    });
  });

  group('botHintsUsed records the help that was on the board', () {
    test('the overlays are on by default, so a plain move is helped', () async {
      final (g, s, _) = await _botGame();
      expect(s.showArrows || s.showThreats || s.showControl, isTrue,
          reason: 'a fixture with every overlay off would prove nothing');
      expect(g.botHintsUsed, isFalse, reason: 'no move played yet');

      _mate(g);
      expect(g.botHintsUsed, isTrue);
    });

    test('blind mode alone makes a move unhelped', () async {
      // blind suppresses all three overlays (engineArrowUcis, threat and
      // controlMap each gate on it) without touching their switches.
      final (g, s, _) = await _botGame();
      s.blind = true;
      _mate(g);
      expect(g.botHintsUsed, isFalse);
    });

    test('switching all three overlays off makes a move unhelped', () async {
      final (g, s, _) = await _botGame();
      s.showArrows = false;
      s.showThreats = false;
      s.showControl = false;
      expect(s.blind, isFalse, reason: 'this is the not-blind route to clean');
      _mate(g);
      expect(g.botHintsUsed, isFalse);
    });

    test('the flag is sampled per move, not read at the end', () async {
      // The switches are toggleable mid-game (they do not restart it), so help
      // taken on move 1 cannot be switched off on move 20.
      final (g, s, _) = await _botGame();
      _quiet(g); // overlays on
      expect(g.botHintsUsed, isTrue);
      s.blind = true;
      expect(g.botHintsUsed, isTrue,
          reason: 'going blind afterwards does not un-take the help');
    });

    test('playing the engine\'s own line counts even in blind mode', () async {
      // playUci is the tree/lines tap and the book tap: a machine handing you a
      // move. That is help whatever the overlay switches say.
      final (g, s, _) = await _botGame();
      s.blind = true;
      s.showArrows = false;
      s.showThreats = false;
      s.showControl = false;
      g.playUci('a1a8');
      expect(g.moves, hasLength(1), reason: 'the move must have been played');
      expect(g.botHintsUsed, isTrue);
    });

    test('an illegal tap plays nothing and takes no help', () async {
      final (g, _, _) = await _botGame();
      g.playUci('a1b8'); // not a rook move
      expect(g.moves, isEmpty);
      expect(g.botHintsUsed, isFalse);
    });

    test('the analysis board records nothing', () async {
      final g = await makeGame(fromFen: _mateIn1);
      _mate(g);
      expect(g.botHintsUsed, isFalse);
    });

    test('a new game clears the flag', () async {
      final (g, _, _) = await _botGame();
      _mate(g);
      expect(g.botHintsUsed, isTrue);
      g.newGame();
      expect(g.botHintsUsed, isFalse);
    });
  });

  group('the archived record', () {
    // An arbiter whose analysis RESOLVES EMPTY: the grade pipeline aborts at
    // "no pre-lines" instead of parking, so the save's grade wait is over
    // immediately and these tests need no clock. The race group below wants
    // the opposite and says so.
    FakeArbiter noLines() => FakeArbiter(analysisLines: const []);

    test('a clean win writes botHintsUsed FALSE and omits botUndos', () async {
      // The load-bearing asymmetry. ABSENT means "hints unknown" — which is
      // what every game archived before this shipped is — and the crown
      // refuses those the clean mark. Only an explicit false says "known
      // clean", so a clean game must write one.
      final (g, s, db) = await _botGame(arbiter: noLines());
      s.blind = true;
      _mate(g); // checkmate archives the game by itself
      await pumpEventQueue();

      final rec = db.saved.single;
      expect(rec['botHintsUsed'], isFalse);
      expect(rec.containsKey('botHintsUsed'), isTrue,
          reason: 'absent would mean unknown, not clean');
      expect(rec.containsKey('botUndos'), isFalse,
          reason: 'playerElo reads (botUndos ?? 0) > 0 — zero is absence');
      expect(rec['result'], '1-0');
      expect(rec['botColor'], 'b');
    });

    test('a helped win writes both fields', () async {
      final (g, _, db) = await _botGame(arbiter: noLines());
      _mate(g); // archived once, with the overlays on but no takeback yet
      g.undo();
      g.undo(); // refused: nothing left to take back
      _mate(g); // re-finished, so archived again
      await pumpEventQueue();

      expect(db.saved, hasLength(2), reason: 'a re-finished game archives anew');
      final rec = db.saved.last;
      expect(rec['botUndos'], 1, reason: 'the second undo was refused');
      expect(rec['botHintsUsed'], isTrue);
      expect(db.saved.first.containsKey('botUndos'), isFalse,
          reason: 'the first finish had no takeback behind it');
    });

    test('an analysis game writes neither field', () async {
      final settings = await loadSettings(); // both sides human
      final db = FakeDb();
      final game = GameController(
          noLines(), const FakeBot(), SavingGrading(), settings, db);
      game.newGame(fromFen: _mateIn1);
      _mate(game);
      game.undo();
      _mate(game);
      await pumpEventQueue();

      final rec = db.saved.last;
      expect(rec.containsKey('botUndos'), isFalse);
      expect(rec.containsKey('botHintsUsed'), isFalse,
          reason: 'there was no bot, so there is nothing to say about hints');
    });
  });

  group('a new game during the grade wait', () {
    testWidgets('cannot rewrite the help the finished game was won with',
        (tester) async {
      // THE test. After a checkmate the save is already running — it waits up
      // to 16s for in-flight grading — and the player starts the next game
      // straight away. Every field the record needs must therefore be
      // snapshotted BEFORE that wait. botFallback was not, and a substituted
      // game archived itself as clean (#117); botUndos and botHintsUsed have
      // precisely the same shape.
      //
      // The arbiter resolves so the pipeline reaches its last line; the
      // practice fake then parks it there, holding the window open.
      final (g, s, db) = await _botGame(
        arbiter: FakeArbiter(analysisLines: kFakeLines, streamPartials: true),
        practice: ParkingPractice(),
      );

      _quiet(g); // hints on the board, and the bot is now on move
      await tester.pump(); // its turn fails on the fixture persona and clears
      expect(g.botThinking, isFalse, reason: 'undo would be refused');
      g.undo();
      expect(g.botUndos, 1);
      expect(g.botHintsUsed, isTrue);

      _mate(g); // the game ends and _saveGame starts, parked on the wait
      expect(db.saved, isEmpty, reason: 'the save must still be in the wait');

      // what the player does next: a new game, while the old one is still
      // being written
      g.newGame();
      expect(g.botUndos, 0, reason: 'the live counters are the NEW game now');
      expect(g.botHintsUsed, isFalse);

      // the wait times out and the record lands
      await tester.pump(const Duration(seconds: kSaveGradeWaitSeconds + 1));

      final rec = db.saved.single;
      expect(rec['result'], '1-0', reason: 'the game that was archived');
      expect(rec['botUndos'], 1,
          reason: 'the takeback belonged to the game that just ended');
      expect(rec['botHintsUsed'], isTrue,
          reason: 'reading the live flag here would archive the fresh game\'s '
              'zeroed counters against the finished game\'s result');

      s.setPlayers(white: null, black: null);
      g.newGame();
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
