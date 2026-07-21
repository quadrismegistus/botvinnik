// The clock's arithmetic, driven by a hand-stepped time source.
//
// Every clock here is built with `tick: null`, so it has no Timer at all: the
// test advances [_Fake] by an exact amount and calls poll() where a running
// clock would have. That is the point of injecting the source. `tester.pump`
// advances Dart's timers but NOT a Stopwatch, which reads the real monotonic
// clock — a clock built on a bare Stopwatch is simply frozen under test, which
// is the shape that already bit the bot turn's opening wait.
//
//   cd flutter && flutter test test/chess_clock_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/chess_clock.dart';

/// A monotonic source the test moves by hand.
class _Fake {
  Duration now = Duration.zero;
  void advance(Duration d) => now += d;
  Duration call() => now;
}

const _w = ClockSide.white;
const _b = ClockSide.black;

/// A clock with no ticker, plus the source that drives it.
(ChessClock, _Fake) _clock(String notation,
    {void Function(ClockSide)? onFlag}) {
  final fake = _Fake();
  final clock = ChessClock(
    TimeControl.parse(notation),
    source: fake.call,
    tick: null,
    onFlag: onFlag,
  );
  return (clock, fake);
}

void main() {
  group('TimeControl', () {
    test('parses the standard notations', () {
      expect(TimeControl.parse('5+0'),
          const TimeControl(Duration(minutes: 5), Duration.zero));
      expect(TimeControl.parse('3+2'),
          const TimeControl(Duration(minutes: 3), Duration(seconds: 2)));
      expect(TimeControl.parse('15+10'),
          const TimeControl(Duration(minutes: 15), Duration(seconds: 10)));
    });

    test('accepts a bare initial, spaces, and half minutes', () {
      expect(TimeControl.parse('10'),
          const TimeControl(Duration(minutes: 10), Duration.zero));
      expect(TimeControl.parse(' 3 + 2 '),
          const TimeControl(Duration(minutes: 3), Duration(seconds: 2)));
      expect(TimeControl.parse('0.5+0'),
          const TimeControl(Duration(seconds: 30), Duration.zero));
      // increment without initial time is a real (if brutal) control
      expect(TimeControl.parse('0+1'),
          const TimeControl(Duration.zero, Duration(seconds: 1)));
    });

    test('rejects what is not a time control', () {
      for (final bad in ['', 'blitz', '5+', '+2', '5+2+1', '-5+0', '5 2']) {
        expect(TimeControl.tryParse(bad), isNull, reason: 'accepted "$bad"');
      }
      // no time and no increment is not a game, however well-formed
      expect(TimeControl.tryParse('0+0'), isNull);
    });

    test('notation round-trips', () {
      for (final s in ['1+0', '3+2', '5+0', '15+10', '30+0', '0.5+0', '0+1']) {
        expect(TimeControl.parse(s).notation, s);
      }
      expect(kTimeControlPresets.map((c) => c.notation).toList(), [
        '1+0',
        '2+1',
        '3+0',
        '3+2',
        '5+0',
        '5+3',
        '10+0',
        '15+10',
        '30+0',
      ]);
    });
  });

  group('running and switching', () {
    test('starts both sides on the initial time, neither running', () {
      final (c, _) = _clock('5+0');
      expect(c.remaining(_w), const Duration(minutes: 5));
      expect(c.remaining(_b), const Duration(minutes: 5));
      expect(c.running, isNull);
      expect(c.flagged, isNull);
    });

    test('only the running side loses time', () {
      final (c, t) = _clock('5+0');
      c.start(_w);
      t.advance(const Duration(seconds: 20));
      expect(c.remaining(_w), const Duration(minutes: 4, seconds: 40));
      expect(c.remaining(_b), const Duration(minutes: 5),
          reason: "the side not on move must not be charged");
      expect(c.running, _w);
    });

    test('a press hands the clock over and freezes the mover', () {
      final (c, t) = _clock('5+0');
      c.start(_w);
      t.advance(const Duration(seconds: 20));
      c.press(_w);
      t.advance(const Duration(seconds: 7));

      expect(c.running, _b);
      expect(c.remaining(_w), const Duration(minutes: 4, seconds: 40),
          reason: 'white stopped being charged at the press');
      expect(c.remaining(_b), const Duration(minutes: 4, seconds: 53));
    });
  });

  group('increment', () {
    test('lands on the mover, not the opponent', () {
      final (c, t) = _clock('3+2');
      c.start(_w);
      t.advance(const Duration(seconds: 10));
      c.press(_w);

      expect(c.remaining(_w), const Duration(minutes: 2, seconds: 52),
          reason: '3:00 - 0:10 + 0:02');
      expect(c.remaining(_b), const Duration(minutes: 3),
          reason: "black has not moved and must not be incremented");
    });

    test('is applied after the thinking time, on every move including the '
        'first', () {
      final (c, t) = _clock('3+2');
      c.start(_w);
      // Four full moves, each side spending exactly one second per move.
      for (var i = 0; i < 4; i++) {
        t.advance(const Duration(seconds: 1));
        c.press(_w);
        t.advance(const Duration(seconds: 1));
        c.press(_b);
      }
      // 4 × (-1s +2s) each way
      expect(c.remaining(_w), const Duration(minutes: 3, seconds: 4));
      expect(c.remaining(_b), const Duration(minutes: 3, seconds: 4));
    });

    test('a mover who is already through zero flags instead of incrementing',
        () {
      ClockSide? flagged;
      final (c, t) = _clock('3+2', onFlag: (s) => flagged = s);
      c.start(_w);
      t.advance(const Duration(minutes: 3, milliseconds: 1));
      c.press(_w);

      expect(flagged, _w);
      expect(c.flagged, _w);
      expect(c.remaining(_w), Duration.zero,
          reason: 'the increment must not resurrect a flagged clock');
      expect(c.running, isNull);
    });
  });

  group('the flag', () {
    test('falls at exactly zero, and not a microsecond before', () {
      ClockSide? flagged;
      final (c, t) = _clock('1+0', onFlag: (s) => flagged = s);
      c.start(_b);

      t.advance(
          const Duration(seconds: 59, milliseconds: 999, microseconds: 999));
      c.poll();
      expect(c.flagged, isNull, reason: '1µs left is not out of time');
      expect(c.remaining(_b), const Duration(microseconds: 1));

      t.advance(const Duration(microseconds: 1));
      c.poll();
      expect(flagged, _b);
      expect(c.remaining(_b), Duration.zero);
      expect(c.running, isNull, reason: 'nothing runs after a flag');
    });

    test('reports the side that ran out, not the side to move next', () {
      final (c, t) = _clock('1+0');
      c.start(_w);
      t.advance(const Duration(seconds: 10));
      c.press(_w); // black to move
      t.advance(const Duration(minutes: 2));
      c.poll();

      expect(c.flagged, _b);
      expect(c.remaining(_w), const Duration(seconds: 50),
          reason: "white's clock is untouched by black's flag");
    });

    test('fires onFlag once, however often it is polled', () {
      var calls = 0;
      final (c, t) = _clock('1+0', onFlag: (_) => calls++);
      c.start(_w);
      t.advance(const Duration(minutes: 2));
      for (var i = 0; i < 5; i++) {
        c.poll();
      }
      expect(calls, 1);
    });

    test('a flagged clock is inert', () {
      final (c, t) = _clock('1+0');
      c.start(_w);
      t.advance(const Duration(minutes: 2));
      c.poll();

      c.press(_b);
      c.start(_b);
      c.resume();
      t.advance(const Duration(minutes: 5));
      expect(c.running, isNull);
      expect(c.flagged, _w);
      expect(c.remaining(_b), const Duration(minutes: 1),
          reason: 'black never got the move, so black never spent time');
    });

    test('is not detected without a poll, but the number is still right', () {
      // The Timer only drives repaints. A caller that never ticks still reads
      // a correct remaining time; it just has not noticed the flag yet.
      final (c, t) = _clock('1+0');
      c.start(_w);
      t.advance(const Duration(minutes: 5));
      expect(c.remaining(_w), Duration.zero);
      expect(c.flagged, isNull);
      c.poll();
      expect(c.flagged, _w);
    });
  });

  group('pause, stop and reset', () {
    test('a pause costs the mover nothing', () {
      final (c, t) = _clock('5+0');
      c.start(_w);
      t.advance(const Duration(seconds: 30));
      c.pause();
      t.advance(const Duration(hours: 1));

      expect(c.remaining(_w), const Duration(minutes: 4, seconds: 30));
      expect(c.running, isNull, reason: 'nothing runs while paused');
      expect(c.toMove, _w, reason: 'but white is still to move');

      c.resume();
      t.advance(const Duration(seconds: 30));
      expect(c.remaining(_w), const Duration(minutes: 4));
    });

    test('stop banks the running side and leaves the readings alone', () {
      final (c, t) = _clock('5+0');
      c.start(_w);
      t.advance(const Duration(seconds: 30));
      c.stop();
      t.advance(const Duration(minutes: 10));

      expect(c.remaining(_w), const Duration(minutes: 4, seconds: 30));
      expect(c.running, isNull);
      expect(c.flagged, isNull);
    });

    test('reset returns a fresh pair of clocks', () {
      final (c, t) = _clock('5+0');
      c.start(_w);
      t.advance(const Duration(minutes: 6));
      c.poll();
      expect(c.flagged, _w);

      c.reset();
      expect(c.flagged, isNull);
      expect(c.remaining(_w), const Duration(minutes: 5));
      expect(c.remaining(_b), const Duration(minutes: 5));
      c.start(_b);
      t.advance(const Duration(seconds: 5));
      expect(c.remaining(_b), const Duration(minutes: 4, seconds: 55));
    });
  });

  group('drift', () {
    test('a 15-minute game read 90,000 times is exact to the microsecond', () {
      // The defect this exists for: subtracting the tick interval on every
      // tick. Timers fire late, so the subtraction is right and the elapsed
      // time is not — and the error only ever accumulates in one direction.
      // Here the source advances in ragged steps that are NOT multiples of any
      // tick interval, so a tick-counting implementation cannot get it right
      // by accident.
      final (c, t) = _clock('15+10');
      c.start(_w);

      var elapsed = Duration.zero;
      for (var i = 0; i < 90000; i++) {
        final step = Duration(microseconds: 9000 + (i % 7) * 137);
        t.advance(step);
        elapsed += step;
        c.poll();
        // Read on every step: a derived clock is unmoved by being observed.
        expect(c.remaining(_w), const Duration(minutes: 15) - elapsed);
      }
      expect(elapsed.inSeconds, greaterThan(800), reason: 'a real game long');
      expect(c.remaining(_w), const Duration(minutes: 15) - elapsed);
      expect(c.flagged, isNull);
    });

    test('300 moves of switching lose nothing between the two clocks', () {
      // Every press is a chance to drop or double-count the fraction of a
      // second between the last read and the handover.
      final (c, t) = _clock('15+10');
      c.start(_w);
      var white = Duration.zero;
      var black = Duration.zero;
      for (var i = 0; i < 300; i++) {
        final spent = Duration(milliseconds: 1234 + i);
        t.advance(spent);
        c.poll();
        if (i.isEven) {
          white += spent;
          c.press(_w);
        } else {
          black += spent;
          c.press(_b);
        }
      }
      const inc = Duration(seconds: 10);
      expect(c.remaining(_w),
          const Duration(minutes: 15) - white + inc * 150);
      expect(c.remaining(_b),
          const Duration(minutes: 15) - black + inc * 150);
    });
  });

  group('formatClock', () {
    test('floors the seconds and shows tenths under ten', () {
      expect(formatClock(const Duration(minutes: 5)), '5:00');
      expect(formatClock(const Duration(minutes: 4, seconds: 59)), '4:59');
      expect(
          formatClock(
              const Duration(minutes: 4, seconds: 59, milliseconds: 999)),
          '4:59',
          reason: 'floored, as every playing site floors it');
      expect(formatClock(const Duration(seconds: 10)), '0:10');
      expect(formatClock(const Duration(seconds: 9, milliseconds: 900)),
          '0:09.9');
      expect(formatClock(const Duration(milliseconds: 400)), '0:00.4');
      expect(formatClock(Duration.zero), '0:00.0');
      expect(formatClock(const Duration(minutes: 12, seconds: 34)), '12:34');
    });

    test('grows an hours field rather than counting to 90 minutes', () {
      expect(formatClock(const Duration(hours: 1, minutes: 5)), '1:05:00');
      expect(formatClock(const Duration(minutes: 59, seconds: 59)), '59:59');
    });
  });
  group('an out-of-turn press', () {
    test('does not refund the running side its elapsed time', () {
      // The bug: press(black) while White was running fell through to the
      // re-origin, discarding White's elapsed time — and `mover.opponent` put
      // White straight back on move, 30s richer. A double press, or a bot-reply
      // path racing the human's, is exactly that shape.
      final (c, t) = _clock('5+0');
      c.start(_w);
      t.advance(const Duration(seconds: 30));

      c.press(_b); // not the mover
      expect(c.remaining(_w), const Duration(minutes: 4, seconds: 30),
          reason: 'the 30s stands');
      expect(c.toMove, _w, reason: 'and it is still White to move');
    });

    test('does not hand the move over', () {
      final (c, t) = _clock('5+0');
      c.start(_w);
      t.advance(const Duration(seconds: 10));
      c.press(_b);
      c.press(_w); // the real move
      expect(c.toMove, _b);
      expect(c.remaining(_w), const Duration(minutes: 4, seconds: 50));
    });
  });

}
