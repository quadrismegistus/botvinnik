// The undo/redo regression Ryan hit live: two consecutive undos, then redo,
// teleported the board — undo appended batches while redo consumed from the
// front, so redo replayed the NEWEST moves onto the OLDEST position. The
// stack must hand batches back in game order no matter how many undos ran.
// (The other half of the bug — a new move must clear the stack — is one line
// in GameController._apply, which needs the live bridge and isn't unit-
// testable here.)

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/game_controller.dart' show MoveRecord;
import 'package:botvinnik_mobile/stores/redo_stack.dart';

MoveRecord rec(int ply, String color) => MoveRecord(
      ply: ply,
      san: 'm$ply',
      uci: 'a1a2',
      color: color,
      fenBefore: 'fen${ply - 1}',
      fenAfter: 'fen$ply',
    );

void main() {
  test('two undos then redos replay in game order (analysis board)', () {
    final stack = RedoStack();
    // undo pops newest first: first undo stores m4, second stores m3
    stack.pushUndone([rec(4, 'b')]);
    stack.pushUndone([rec(3, 'w')]);
    final first = stack.takeBatch(botEnabled: false, playerColor: 'w');
    final second = stack.takeBatch(botEnabled: false, playerColor: 'w');
    expect(first.map((m) => m.ply), [3]); // the OLDER move comes back first
    expect(second.map((m) => m.ply), [4]);
    expect(stack.isEmpty, isTrue);
  });

  test('bot pairs come back whole and in game order', () {
    final stack = RedoStack();
    // moves were p1(w) b1(b) p2(w) b2(b); undo pops newest-first per pair
    stack.pushUndone([rec(4, 'b'), rec(3, 'w')]);
    stack.pushUndone([rec(2, 'b'), rec(1, 'w')]);
    final first = stack.takeBatch(botEnabled: true, playerColor: 'w');
    final second = stack.takeBatch(botEnabled: true, playerColor: 'w');
    expect(first.map((m) => m.ply), [1, 2]); // player move plus its bot reply
    expect(second.map((m) => m.ply), [3, 4]);
  });

  test('takeBatch on an empty stack is a no-op', () {
    final stack = RedoStack();
    expect(stack.takeBatch(botEnabled: true, playerColor: 'w'), isEmpty);
  });

  test('clear discards the stored future', () {
    final stack = RedoStack();
    stack.pushUndone([rec(1, 'w')]);
    stack.clear();
    expect(stack.isEmpty, isTrue);
  });
}
