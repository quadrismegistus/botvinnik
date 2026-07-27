// The key→action mapping. Worth pinning because the failure mode is silent:
// a binding that stops matching just does nothing, and a modifier that stops
// being ignored steals a system shortcut.
//
//   cd flutter && flutter test

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/db/app_db.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/ui/keyboard.dart';

import 'support/game_harness.dart';
import 'support/practice_harness.dart';

KeyEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
      logicalKey: key,
      physicalKey: PhysicalKeyboardKey.keyA, // not consulted by the mapping
      timeStamp: Duration.zero,
    );

const _forkFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _pinFen = 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2';

class _StubDb implements AppDb {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// The real key layer over a real PracticeController, on the Practice tab.
///
/// The Practice bindings live in a private method of [KeyboardControls], so
/// unlike the Play mapping above they can only be reached by mounting the
/// widget and pressing keys at it. Two puzzles are loaded so that "n did not
/// advance" is a claim about the guard and not about a queue of one.
Future<({PracticeController practice, String served})> _practiceKeys(
    WidgetTester tester) async {
  final h = makePractice([practiceItem(_forkFen), practiceItem(_pinFen)]);
  h.practice.startSession();
  final settings = await loadSettings();
  final review = ReviewController(_StubDb());
  await tester.pumpWidget(MaterialApp(
    home: KeyboardControls(
      game: await makeGame(),
      review: review,
      reviewBoard: fakeReviewBoard(review, settings),
      practice: h.practice,
      settings: settings,
      currentTab: () => 1, // Practice
      child: const SizedBox.expand(),
    ),
  ));
  await tester.pump();
  return (practice: h.practice, served: h.practice.current!['id'] as String);
}

void main() {
  test('the navigation keys map to their actions', () {
    expect(boardActionFor(_down(LogicalKeyboardKey.arrowLeft)),
        BoardKeyAction.back);
    expect(boardActionFor(_down(LogicalKeyboardKey.arrowRight)),
        BoardKeyAction.forward);
    expect(boardActionFor(_down(LogicalKeyboardKey.keyF)), BoardKeyAction.flip);
    expect(boardActionFor(_down(LogicalKeyboardKey.space)),
        BoardKeyAction.preview);
  });

  test('start and live each have two keys', () {
    for (final key in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.home]) {
      expect(boardActionFor(_down(key)), BoardKeyAction.start);
    }
    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.escape,
    ]) {
      expect(boardActionFor(_down(key)), BoardKeyAction.live);
    }
  });

  test('holding an arrow scrubs — repeats count', () {
    final repeat = KeyRepeatEvent(
      logicalKey: LogicalKeyboardKey.arrowLeft,
      physicalKey: PhysicalKeyboardKey.arrowLeft,
      timeStamp: Duration.zero,
    );
    expect(boardActionFor(repeat), BoardKeyAction.back);
  });

  test('key up does nothing, so an action fires once per press', () {
    final up = KeyUpEvent(
      logicalKey: LogicalKeyboardKey.arrowLeft,
      physicalKey: PhysicalKeyboardKey.arrowLeft,
      timeStamp: Duration.zero,
    );
    expect(boardActionFor(up), isNull);
  });

  test('unbound keys are left alone', () {
    for (final key in [
      LogicalKeyboardKey.keyQ,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.tab,
    ]) {
      expect(boardActionFor(_down(key)), isNull);
    }
  });

  testWidgets('modifiers are ignored, so system shortcuts still work',
      (tester) async {
    // Cmd-F must reach the browser's find, not flip the board
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    expect(boardActionFor(_down(LogicalKeyboardKey.keyF)), isNull);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    // and with the modifier released it flips again
    expect(boardActionFor(_down(LogicalKeyboardKey.keyF)), BoardKeyAction.flip);
  });

  testWidgets('undo and redo take the platform-standard chords',
      (tester) async {
    // ⌘Z / ⇧⌘Z — the macOS standard
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    expect(boardActionFor(_down(LogicalKeyboardKey.keyZ)), BoardKeyAction.undo);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(boardActionFor(_down(LogicalKeyboardKey.keyZ)), BoardKeyAction.redo);
    // ⌘Y is NOT redo on a Mac
    expect(boardActionFor(_down(LogicalKeyboardKey.keyY)), isNull);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    // Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y — the Windows and Linux set
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(boardActionFor(_down(LogicalKeyboardKey.keyZ)), BoardKeyAction.undo);
    expect(boardActionFor(_down(LogicalKeyboardKey.keyY)), BoardKeyAction.redo);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('other command chords are left to the OS', (tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    for (final key in [
      LogicalKeyboardKey.keyR, // reload
      LogicalKeyboardKey.keyW, // close tab
      LogicalKeyboardKey.keyF, // find — must not flip the board
      LogicalKeyboardKey.arrowLeft, // history back
    ]) {
      expect(boardActionFor(_down(key)), isNull);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });

  group('n is the green button, never a bare skip (#214)', () {
    testWidgets('an unanswered puzzle survives it', (tester) async {
      // The reported bug, as a key press: reaching for r (retry), hitting the
      // n beside it, and the puzzle is gone with no answer ever shown.
      final t = await _practiceKeys(tester);
      expect(t.practice.solvedOrRevealed, isFalse,
          reason: 'precondition: nothing is answered yet');

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);

      expect(t.practice.current!['id'], t.served,
          reason: 'n must not advance past an unanswered puzzle');
      expect(t.practice.hintTier, 1,
          reason: 'it takes the first rung of the ladder instead');
    });

    testWidgets('and advances once the answer is up', (tester) async {
      final t = await _practiceKeys(tester);
      t.practice.reveal();
      expect(t.practice.primaryAction, PracticePrimary.next,
          reason: 'precondition: the button now says Next');

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);

      expect(t.practice.current!['id'], isNot(t.served));
    });

    testWidgets('r, the key it gets mistaken for, still retries',
        (tester) async {
      final t = await _practiceKeys(tester);
      t.practice.attempt = const AttemptOutcome(
          san: 'Nf3', uci: 'g1f3', pass: false, drop: 18, evalPawns: -1);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);

      expect(t.practice.attempt, isNull);
      expect(t.practice.current!['id'], t.served);
    });
  });

  test('every binding in the help sheet has a description', () {
    for (final mac in [true, false]) {
      final groups = KeyboardControls.bindingsByTab(mac: mac);
      expect(groups, isNotEmpty);
      for (final (tab, binds) in groups) {
        expect(tab.trim(), isNotEmpty);
        expect(binds, isNotEmpty, reason: '$tab has no bindings');
        for (final (keys, what) in binds) {
          expect(keys.trim(), isNotEmpty);
          expect(what.trim(), isNotEmpty);
        }
      }
    }
    // all three tabs with keys are documented
    final tabs =
        KeyboardControls.bindingsByTab(mac: true).map((g) => g.$1).toList();
    expect(tabs, containsAll(['Play', 'Practice', 'Review']));
    // the modifier glyphs differ by platform — undo/redo live in the Play group
    String playRedo(bool mac) => KeyboardControls.bindingsByTab(mac: mac)
        .firstWhere((g) => g.$1 == 'Play')
        .$2
        .last
        .$1;
    expect(playRedo(true), contains('Cmd'));
    expect(playRedo(false), contains('Ctrl'));
  });
}
