// Wall time in front of a position (#267), with a clock the test controls.
//
//   cd flutter && flutter test test/think_timer_test.dart

import 'package:botvinnik_mobile/stores/think_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Duration now;
  late ThinkTimer t;

  setUp(() {
    now = Duration.zero;
    t = ThinkTimer(source: () => now);
  });

  void advance(int seconds) => now += Duration(seconds: seconds);

  test('measures the time between the turn starting and the move', () {
    t.restart();
    advance(7);
    expect(t.take(), const Duration(seconds: 7));
  });

  test('reads nothing before a turn has begun', () {
    expect(t.take(), isNull);
  });

  test('reads nothing twice for one turn', () {
    t.restart();
    advance(3);
    expect(t.take(), const Duration(seconds: 3));
    advance(5);
    expect(t.take(), isNull, reason: 'the turn already ended');
  });

  test('does not count the time the app spent in the background', () {
    t.restart();
    advance(4);
    t.pause();
    advance(3600); // overnight
    t.resume();
    advance(6);
    expect(t.take(), const Duration(seconds: 10),
        reason: 'four before, six after, and nothing in between');
  });

  test('banks the time already spent when it pauses', () {
    // the half-measure this guards: dropping the pre-pause span and reporting
    // only what came after
    t.restart();
    advance(30);
    t.pause();
    t.resume();
    expect(t.take(), const Duration(seconds: 30));
  });

  test('a pause with nothing running changes nothing', () {
    t.pause();
    t.resume();
    expect(t.take(), isNull);
    t.restart();
    advance(2);
    expect(t.take(), const Duration(seconds: 2));
  });

  test('resume without a pause does not restart the count', () {
    t.restart();
    advance(5);
    t.resume(); // spurious — no pause preceded it
    advance(5);
    expect(t.take(), const Duration(seconds: 10),
        reason: 'a stray resume must not discard the first five seconds');
  });

  test('take while paused reports what was banked', () {
    t.restart();
    advance(9);
    t.pause();
    advance(1000);
    expect(t.take(), const Duration(seconds: 9));
  });

  test('discard refuses to report a number rather than reporting a wrong one', () {
    t.restart();
    advance(12);
    t.discard();
    expect(t.take(), isNull);
  });

  test('a discarded turn does not poison the next one', () {
    t.restart();
    advance(12);
    t.discard();
    expect(t.take(), isNull);
    t.restart();
    advance(4);
    expect(t.take(), const Duration(seconds: 4),
        reason: 'the twelve seconds must not carry over');
  });

  test('restart abandons a turn already in progress', () {
    t.restart();
    advance(20);
    t.restart();
    advance(3);
    expect(t.take(), const Duration(seconds: 3));
  });

  test('restart clears time banked by an earlier pause', () {
    // restart is reached from newGame, which can happen with the app paused
    t.restart();
    advance(40);
    t.pause();
    t.restart();
    advance(2);
    expect(t.take(), const Duration(seconds: 2),
        reason: 'the banked forty seconds belong to the abandoned turn');
  });

  test('peek reads without ending the turn', () {
    t.restart();
    advance(6);
    expect(t.peek(), const Duration(seconds: 6));
    advance(4);
    expect(t.peek(), const Duration(seconds: 10), reason: 'still counting');
    expect(t.take(), const Duration(seconds: 10));
    expect(t.peek(), isNull, reason: 'and now the turn is over');
  });

  test('isRunning tracks whether anything is being timed', () {
    expect(t.isRunning, isFalse);
    t.restart();
    expect(t.isRunning, isTrue);
    t.pause();
    expect(t.isRunning, isTrue, reason: 'paused is still a turn in progress');
    t.take();
    expect(t.isRunning, isFalse);
  });
}
