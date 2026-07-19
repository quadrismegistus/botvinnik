// The key→action mapping. Worth pinning because the failure mode is silent:
// a binding that stops matching just does nothing, and a modifier that stops
// being ignored steals a system shortcut.
//
//   cd flutter && flutter test

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/ui/keyboard.dart';

KeyEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
      logicalKey: key,
      physicalKey: PhysicalKeyboardKey.keyA, // not consulted by the mapping
      timeStamp: Duration.zero,
    );

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

  test('every binding in the help sheet has a description', () {
    for (final mac in [true, false]) {
      final bindings = KeyboardControls.bindingsFor(mac: mac);
      expect(bindings, isNotEmpty);
      for (final (keys, what) in bindings) {
        expect(keys.trim(), isNotEmpty);
        expect(what.trim(), isNotEmpty);
      }
    }
    // the modifier glyphs differ by platform
    expect(KeyboardControls.bindingsFor(mac: true).last.$1, contains('Cmd'));
    expect(KeyboardControls.bindingsFor(mac: false).last.$1, contains('Ctrl'));
  });
}
