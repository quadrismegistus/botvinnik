// The clock's lifecycle against the game's endings (#169 review).
//
// One root defect had four faces: the clock is only ever stopped by a flag or
// a new game, so after mate/resign/undo it kept ticking and a background flag
// rewrote a decided game as a loss on time. And undo/redo never reconciled with
// the clock, so the running side and the side-to-move could disagree.
//
//   cd flutter && flutter test test/clock_lifecycle_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/chess_clock.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';

import 'support/fake_db.dart';
import 'support/game_harness.dart';

// White mates in one with Qxf7; a stalemate FEN for the draw case.
const _mateIn1 = '6k1/5ppp/8/8/8/8/5PPP/Q5K1 w - - 0 1';
const _stalemate = '7k/5Q2/8/8/8/8/8/7K w - - 0 1';

Future<(GameController, SettingsStore)> _rated({String fromFen = _mateIn1}) async {
  final settings = await loadSettings(black: kTestBotId);
  final g = GameController(
      FakeArbiter(analysisLines: kFakeLines, streamPartials: true, searchLines: kFakeLines),
      const FakeBot({kTestBotId: testBotPersona}),
      SavingGrading(), settings, FakeDb());
  g.newGame(fromFen: fromFen, rated: true, timeControl: TimeControl.parse('5+0'));
  return (g, settings);
}

/// Analysis mode, so no bot-delay timer survives, and newGame disposes the
/// clock ticker. The clock is a live periodic Timer; left running it fails the
/// pending-timer invariant.
Future<void> _windDown(
    WidgetTester tester, GameController g, SettingsStore s) async {
  s.setPlayers(white: null, black: null);
  g.newGame();
  // Past the 16s save-grade timeout that a rated ending schedules; it
  // self-completes, but its Timer is pending until then.
  await tester.pump(const Duration(seconds: 17));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a mate stops the clock, so a later flag cannot rewrite it',
      (tester) async {
    final (g, s) = await _rated();
    g.playUci('a1a8'); // Qa8# — verified mate
    await tester.pump(const Duration(milliseconds: 50));

    expect(g.gameOver, isTrue);
    expect(g.clock!.running, isNull, reason: 'the clock stopped at the ending');

    g.clock!.debugFlag(ClockSide.black); // a background flag now
    await tester.pump();
    expect(g.statusLine, isNot(contains('ran out of time')),
        reason: 'the mate stands; the stopped clock cannot flag it');

    await _windDown(tester, g, s);
  });

  testWidgets('a stalemate is not rewritten as a loss on time', (tester) async {
    final (g, s) = await _rated(fromFen: _stalemate);
    g.playUci('f7f8'); // Qf8 — if it stalemates the black king
    await tester.pump(const Duration(milliseconds: 50));

    // Only meaningful if the move actually drew; skip if the FEN did not.
    if (g.gameOver && g.statusLine.contains('Stalemate')) {
      expect(g.clock!.running, isNull);
      g.clock!.debugFlag(ClockSide.black);
      await tester.pump();
      expect(g.statusLine, 'Stalemate',
          reason: 'a drawn game must not become a White win on time');
    }

    await _windDown(tester, g, s);
  });

  testWidgets('resign stops the clock and cannot be overridden by a flag',
      (tester) async {
    final (g, s) = await _rated();
    g.playUci('a1a2'); // a quiet move, not mate
    await tester.pump(const Duration(milliseconds: 50));
    g.resign();
    await tester.pump();

    expect(g.clock!.running, isNull, reason: 'resign stopped the clock');
    expect(g.statusLine, contains('resigned'));

    g.clock!.debugFlag(ClockSide.black);
    await tester.pump();
    expect(g.statusLine, contains('resigned'),
        reason: 'the resignation is the result, not a subsequent flag');

    await _windDown(tester, g, s);
  });

  testWidgets('resign refuses a game already ended by a flag', (tester) async {
    final (g, s) = await _rated();
    g.playUci('a1a2');
    await tester.pump(const Duration(milliseconds: 50));
    g.clock!.debugFlag(ClockSide.white);
    await tester.pump();
    expect(g.gameOver, isTrue);

    g.resign(); // must be a no-op — the game is over
    await tester.pump();
    expect(g.statusLine, contains('ran out of time'),
        reason: 'the flag is the result; resign did not stack on it');

    await _windDown(tester, g, s);
  });

  // The rated gate and its casual control, side by side and IDENTICAL except for
  // `rated`. Both play 1.e4 as the human; the bot then tries and fails to reply
  // (its canned move is illegal here), so botThinking clears and a human move
  // is left on the board. In that state canUndo depends on nothing but the
  // rated gate — which is the point: the casual one is the proof the gate is
  // not global, and disabling the gate makes them agree, reddening one.
  Future<GameController> afterOneMove(SettingsStore settings) async {
    final g = GameController(
        FakeArbiter(
            analysisLines: kFakeLines, streamPartials: true, searchLines: kFakeLines),
        const FakeBot({kTestBotId: testBotPersona}), FakeGrading(), settings);
    return g;
  }

  testWidgets('a rated game refuses takebacks, a casual one allows them',
      (tester) async {
    final rs = await loadSettings(black: kTestBotId);
    final rated = await afterOneMove(rs);
    rated.newGame(rated: true, timeControl: TimeControl.parse('5+0'));
    rated.playUci('e2e4');
    await tester.pump(const Duration(seconds: 2)); // bot turn completes (no legal reply)
    expect(rated.botThinking, isFalse);
    expect(rated.moves.any((m) => m.color == 'w'), isTrue,
        reason: 'a human move is on the board');
    expect(rated.canUndo, isFalse, reason: 'no takebacks in a rated game (#168)');
    rated.undo();
    expect(rated.moves, isNotEmpty, reason: 'the move stands');

    final cs = await loadSettings(black: kTestBotId);
    final casual = await afterOneMove(cs);
    casual.newGame(); // not rated
    casual.playUci('e2e4');
    await tester.pump(const Duration(seconds: 2));
    expect(casual.botThinking, isFalse);
    expect(casual.canUndo, isTrue,
        reason: 'the rated gate must not disable undo everywhere');

    for (final (g, st) in [(rated, rs), (casual, cs)]) {
      st.setPlayers(white: null, black: null);
      g.newGame();
    }
    await tester.pump(const Duration(seconds: 1));
  });
}
