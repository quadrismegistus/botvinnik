// The clock stops while the app is not in front of the player (#234).
//
// DECIDED (Ryan, 2026-07-27): pause generously. "This is just a practice app."
// There is no opponent to wrong — the rating is the player's own estimate of
// themselves — and losing on time because a phone call arrived measures the
// phone call. So every lifecycle state that is not `resumed` pauses, including
// a mere window blur, rather than only a hard suspend.
//
// Two layers, tested separately, because they fail in different ways:
//
//   * the POLICY on GameController — what pausing does to a live game, a
//     finished one, and one with no clock at all.
//   * the BINDING in ClockLifecycle — that a lifecycle event reaches the
//     policy. Before #234, `ChessClock.pause`/`resume` had existed since the
//     file was written and had NO production caller at all; the whole feature
//     was a missing wire, so a test of the policy alone would have proved
//     nothing about the bug.
//
// Real time, not tester.pump: the clock derives from a monotonic Stopwatch and
// a fake clock does not move one (see flag_in_apply_test.dart).
//
//   cd flutter && flutter test test/clock_background_test.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/stores/chess_clock.dart';
import 'package:botvinnik_mobile/stores/clock_lifecycle.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';

import 'support/fake_db.dart';
import 'support/game_harness.dart';

/// Long enough that nothing flags by accident, short enough that a 60ms pause
/// is a large and unmistakable fraction of it.
const _control = TimeControl(Duration(milliseconds: 400), Duration.zero);

Future<GameController> _game({bool rated = true, TimeControl? tc}) async {
  final settings = await loadSettings();
  final g = GameController(
      FakeArbiter(analysisLines: kFakeLines, streamPartials: true),
      FakeBot(),
      SavingGrading(),
      settings,
      FakeDb());
  g.newGame(rated: rated, timeControl: rated ? (tc ?? _control) : null);
  return g;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the policy', () {
    test('a running clock freezes, and time does not pass while it is away',
        () async {
      final g = await _game();
      g.playUci('e2e4'); // starts the clock, hands to Black
      await Future<void>.delayed(const Duration(milliseconds: 20));

      g.pauseForBackground();
      final atPause = g.clock!.remaining(ClockSide.black);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(g.clock!.isPaused, isTrue);
      expect(g.clock!.remaining(ClockSide.black), atPause,
          reason: '120ms passed while the app was away and it cost the player');

      g.resumeFromBackground();
      expect(g.clock!.isPaused, isFalse);
      g.dispose();
    });

    test('and without the pause that same wait would have cost them',
        () async {
      // The control. Without it, a clock that had simply stopped for an
      // unrelated reason would satisfy the assertion above.
      final g = await _game();
      g.playUci('e2e4');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final before = g.clock!.remaining(ClockSide.black);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(g.clock!.remaining(ClockSide.black), lessThan(before - const Duration(milliseconds: 80)));
      g.dispose();
    });

    test('time already spent still counts — backgrounding rescues nothing',
        () async {
      // [ChessClock.pause] banks the running side first and falls the flag if
      // it had already run out. A player whose time expired while they were
      // reaching for the home button has still lost.
      final g = await _game(tc: const TimeControl(Duration(milliseconds: 40), Duration.zero));
      g.playUci('e2e4');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      g.pauseForBackground();

      expect(g.clock!.flagged, ClockSide.black,
          reason: 'the flag had already fallen before we paused');
      expect(g.clock!.isPaused, isFalse, reason: 'a fallen flag is not a pause');
      g.dispose();
    });

    test('a finished game is not resumed by coming back', () async {
      // Ended by MATE rather than resignation: resign() requires botEnabled
      // and this fixture is an analysis game, so it would have returned early
      // and the precondition would have been the thing under test.
      //
      // The line is the one flag_in_apply_test.dart uses, checked against
      // dartchess: back-rank mate with a spare a7 pawn to wait with.
      final g = await _game();
      g.newGame(
          fromFen: '6k1/p4ppp/8/8/8/8/5PPP/Q5K1 w - - 0 1',
          rated: true,
          timeControl: _control);
      g.playUci('a1b1');
      g.playUci('a7a6');
      g.playUci('b1b8'); // Qb8#
      expect(g.position.isCheckmate, isTrue, reason: 'the fixture really mates');
      expect(g.gameOver, isTrue, reason: 'precondition');

      g.pauseForBackground();
      g.resumeFromBackground();

      expect(g.clock!.running, isNull,
          reason: 'returning to a decided game must not restart its clock');
      g.dispose();
    });

    test('a casual game has no clock and neither call throws', () async {
      // The commonest case in the app by far: no time control at all.
      final g = await _game(rated: false);
      expect(g.clock, isNull, reason: 'precondition');

      g.pauseForBackground();
      g.resumeFromBackground();

      g.dispose();
    });
  });

  group('the binding', () {
    // The half that was actually missing. `pause`/`resume` existed and worked
    // and nothing called them.
    Future<GameController> pump(WidgetTester tester) async {
      final g = await _game();
      await tester.pumpWidget(ChangeNotifierProvider<GameController>.value(
        value: g,
        child: const ClockLifecycle(child: SizedBox()),
      ));
      return g;
    }

    testWidgets('every state that is not resumed pauses', (tester) async {
      for (final state in [
        AppLifecycleState.inactive, // a macOS window losing focus
        AppLifecycleState.hidden, // a hidden web tab
        AppLifecycleState.paused, // a backgrounded phone
      ]) {
        final g = await pump(tester);
        g.playUci('e2e4');

        tester.binding.handleAppLifecycleStateChanged(state);
        expect(g.clock!.isPaused, isTrue, reason: '$state did not pause');

        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        expect(g.clock!.isPaused, isFalse, reason: 'resumed did not unfreeze');

        g.dispose();
      }
    });

    testWidgets('a torn-down ClockLifecycle does not still pause',
        (tester) async {
      // This pins `removeObserver` in dispose, and it only does so because the
      // widget no longer ALSO carries a `mounted` check. With both, each
      // masked the other and neither could be shown to matter — deleting
      // either left this green. One mechanism, observable.
      final g = await pump(tester);
      g.playUci('e2e4');
      await tester.pumpWidget(const SizedBox());

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(g.clock!.isPaused, isFalse,
          reason: 'a removed ClockLifecycle must not still be listening');

      g.dispose();
    });
  });
}
