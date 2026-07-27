// A flag that falls INSIDE _apply, in the ≤100ms window before the ticker
// notices (#238).
//
// `_apply` presses the clock before it plays the move — deliberately, because
// the presser is the side whose turn it currently IS and `playUnchecked` flips
// that. But `ChessClock.press` calls `_fall` SYNCHRONOUSLY when the mover is
// already through zero, and `_fall` runs `onFlag`, which sets `_flagged`, bumps
// the generation and archives the game. All of that happens while the move that
// triggered it is still unplayed: `moves` has not got it, `position` has not
// advanced. So the archive is written one move short of the board the player is
// looking at, `_saved` is then true, and the `_saveGame()` at the bottom of
// `_apply` — which would have written the right thing — returns early.
//
// The board says Nf3. The archive says the game ended after e5.
//
// It matters beyond tidiness: `_result` and the move list feed
// brain/playerElo.ts, so a game archived a move short is a game rated on a
// position that never happened.
//
// REAL TIME, not tester.pump: the clock derives its remaining time from a
// monotonic Stopwatch (see chess_clock.dart's opening comment — the arithmetic
// never counts ticks), and a fake clock does not move a Stopwatch. The window
// is made deterministic instead of raced for: the ticker restarts on every
// press, so its first poll is 100ms after move one, and move two lands at 60ms.
//
//   cd flutter && flutter test test/flag_in_apply_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/chess_clock.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';

import 'support/fake_db.dart';
import 'support/game_harness.dart';

/// 40ms each, no increment: long enough that move one does not flag, short
/// enough that a 60ms pause runs it out.
const _blitz = TimeControl(Duration(milliseconds: 40), Duration.zero);

Future<(GameController, FakeDb)> _game() async {
  // Analysis mode — both sides human. The bug is about the clock and the
  // archive, and a bot turn would only add a timer to outlive the test.
  final settings = await loadSettings();
  final db = FakeDb();
  final g = GameController(
      FakeArbiter(analysisLines: kFakeLines, streamPartials: true),
      FakeBot(),
      SavingGrading(),
      settings,
      db);
  g.newGame(rated: true, timeControl: _blitz);
  return (g, db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a move that flags the clock is still in the archive', () async {
    final (g, db) = await _game();

    g.playUci('e2e4');
    g.playUci('e7e5');
    expect(g.gameOver, isFalse, reason: 'precondition: still running');

    // Past the 40ms on White's clock, but inside the 100ms before the ticker
    // would poll and flag independently of any move.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    g.playUci('g1f3');

    expect(g.gameOver, isTrue, reason: 'White flagged');
    expect(g.clock!.flagged, ClockSide.white);

    // The board took the move.
    expect(g.moves.map((m) => m.san), ['e4', 'e5', 'Nf3']);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(db.saved, hasLength(1), reason: 'the flag archives the game');
    final saved = db.saved.single;

    // THE BUG. Archived from a move list that did not yet contain the move
    // being played, so this was 2 and the pgn read `1. e4 e5 0-1`.
    expect(saved['moveCount'], 3,
        reason: 'the archive is short of the board it was written from');
    expect((saved['moves'] as List).map((m) => m['san']), ['e4', 'e5', 'Nf3']);

    g.dispose();
  });

  test('and the ordinary ticker flag is unchanged', () async {
    // The control, and the case that already worked: nobody is moving, the
    // ticker polls, the flag falls outside _apply entirely. A fix that moved
    // the press must not disturb this.
    final (g, db) = await _game();

    g.playUci('e2e4');
    g.playUci('e7e5');
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(g.gameOver, isTrue, reason: 'the ticker flagged White');
    expect(g.moves.map((m) => m.san), ['e4', 'e5']);
    expect(db.saved, hasLength(1));
    expect(db.saved.single['moveCount'], 2);

    g.dispose();
  });

  test('a move that delivers MATE stands as mate, not a loss on time',
      () async {
    // A consequence of pressing after the move rather than before, and the
    // reason it is the right way round. `onFlag` opens with `if (gameOver)
    // return`; pressed BEFORE the move, gameOver was still false, so a flag
    // arriving in the same instant overwrote a completed checkmate with a loss
    // on time. That is not the rule anywhere: a move completed before the flag
    // falls is a move, and mate ends the game.
    final settings = await loadSettings();
    final db = FakeDb();
    final g = GameController(
        FakeArbiter(analysisLines: kFakeLines, streamPartials: true),
        FakeBot(),
        SavingGrading(),
        settings,
        db);
    // A back-rank mate: black king g8 shut in by its own f7/g7/h7 pawns, with
    // a spare a7 pawn to make a waiting move. DERIVED, not described — the
    // line was checked against dartchess before it went in here, and
    // `isCheckmate` is asserted below, because this repo has been bitten by a
    // FEN whose comment and contents disagreed.
    g.newGame(
        fromFen: '6k1/p4ppp/8/8/8/8/5PPP/Q5K1 w - - 0 1',
        rated: true,
        timeControl: _blitz);

    // Two waiting moves FIRST, and they are the whole reason this test is not
    // vacuous. The clock does not start until the first move is applied, so
    // before then `press` finds nobody running and can never flag — the first
    // version of this mated on move one and passed identically with the bug
    // reintroduced.
    g.playUci('a1b1'); // Qb1 — starts White's clock, hands to Black
    g.playUci('a7a6'); // a6  — a waiting move that blocks nothing
    expect(g.gameOver, isFalse, reason: 'precondition: still running');

    // Now White is over time, and the MATING move is what presses.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    g.playUci('b1b8'); // Qb8#

    expect(g.position.isCheckmate, isTrue, reason: 'the fixture really mates');
    expect(g.gameOver, isTrue);

    // The CLOCK does flag — `_fall` sets its own `_flagged` before it calls
    // back, and that is not the controller's business to prevent. What
    // changed is whether the GAME records it: `onFlag` opens with `if
    // (gameOver) return`, and pressing after the move means checkmate is
    // already on the board when it runs.
    expect(g.statusLine, isNot(contains('ran out of time')),
        reason: 'a completed mate is not a loss on time');
    expect(g.statusLine.toLowerCase(), contains('checkmate'));

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(db.saved.single['result'], '1-0',
        reason: 'White mated; pressed before the move this archived 0-1');

    g.dispose();
  });

  test('the flagging move is not counted twice', () async {
    // The obvious wrong fix — press after playing, and let the flag path
    // archive whatever it finds — would archive the move; the risk on that
    // side is a duplicate, since _apply's own tail calls _saveGame() again
    // once gameOver is true.
    final (g, db) = await _game();

    g.playUci('e2e4');
    g.playUci('e7e5');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    g.playUci('g1f3');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(db.saved, hasLength(1), reason: 'archived once, not twice');
    final moves = (db.saved.single['moves'] as List).map((m) => m['san']);
    expect(moves.toList(), ['e4', 'e5', 'Nf3'],
        reason: 'and not with Nf3 repeated');

    g.dispose();
  });
}
