// The clock as it is drawn: the running face, the low face, the flagged face,
// and the cost of the ten repaints a second it asks for.
//
// The clocks here keep their real ticker, so `tester.pump(d)` fires it — but
// the ARITHMETIC comes from a hand-stepped source, because a Stopwatch reads
// the real monotonic clock and pump does not move it. [_advance] moves both,
// which is the only way this widget can be made to count under test.
//
// Roboto is loaded from the bundled faces: the default test font is Ahem,
// whose glyphs are uniform squares, so every measurement here — the face's
// height against kClockFace above all — would be a measurement of nothing.
//
//   cd flutter && flutter test test/clock_display_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/chess_clock.dart';
import 'package:botvinnik_mobile/ui/clock_display.dart';
import 'package:botvinnik_mobile/ui/layout.dart';

class _Fake {
  Duration now = Duration.zero;
  Duration call() => now;
}

const _w = ClockSide.white;
const _b = ClockSide.black;

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

/// Clocks built by this file, so [_clockWidgets] can stop their tickers
/// INSIDE the test body. `addTearDown` is too late: flutter_test checks for
/// pending timers before it runs teardowns, and a running clock has one.
final _live = <ChessClock>[];

/// [testWidgets], with every clock stopped before the invariant check.
void _clockWidgets(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      for (final c in _live) {
        c.dispose();
      }
      _live.clear();
    }
  });
}

/// Move wall time and the frame clock together.
Future<void> _advance(WidgetTester tester, _Fake t, Duration d) async {
  t.now += d;
  await tester.pump(d);
}

/// The pair, at phone width, over a clock whose ticker is real.
Future<(ChessClock, _Fake)> _pump(
  WidgetTester tester,
  String control, {
  double width = 375,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final fake = _Fake();
  final clock = ChessClock(TimeControl.parse(control), source: fake.call);
  _live.add(clock);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF161512),
      body: Center(child: ClockPair(clock: clock)),
    ),
  ));
  return (clock, fake);
}

Color _fill(WidgetTester tester, ClockSide side) {
  final box =
      tester.widget<Container>(find.byKey(ValueKey('clock-${side.char}')));
  return (box.decoration! as BoxDecoration).color!;
}

Text _digits(WidgetTester tester, ClockSide side) => tester.widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('clock-${side.char}')),
        matching: find.byType(Text),
      ),
    );

String _reading(WidgetTester tester, ClockSide side) =>
    _digits(tester, side).data!;

/// Red-dominant by a clear margin — the low-time signal, whether it is the
/// whole face or only the digits.
bool _isRed(Color c) => c.r > c.g + 0.2 && c.r > c.b + 0.2;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  _clockWidgets('both clocks start on the control, neither marked as running',
      (tester) async {
    await _pump(tester, '5+0');

    expect(_reading(tester, _w), '5:00');
    expect(_reading(tester, _b), '5:00');
    expect(_fill(tester, _w), _fill(tester, _b));
  });

  _clockWidgets('the running clock is a different colour from the idle one',
      (tester) async {
    final (clock, t) = await _pump(tester, '5+0');
    clock.start(_w);
    await _advance(tester, t, const Duration(seconds: 1));

    // At a glance: the running face inverts. Asserting only that the numbers
    // differ would pass over two identical grey boxes.
    expect(_fill(tester, _w), isNot(_fill(tester, _b)));
    expect(_fill(tester, _w).computeLuminance(),
        greaterThan(_fill(tester, _b).computeLuminance() + 0.5),
        reason: 'the running face should read as light against the dark one');
    expect(_digits(tester, _w).style!.color!.computeLuminance(),
        lessThan(_digits(tester, _b).style!.color!.computeLuminance()),
        reason: 'and its digits dark against the light fill');
  });

  _clockWidgets('the running clock counts down as the frames come',
      (tester) async {
    final (clock, t) = await _pump(tester, '5+0');
    clock.start(_w);

    await _advance(tester, t, const Duration(seconds: 1));
    expect(_reading(tester, _w), '4:59');
    await _advance(tester, t, const Duration(seconds: 59));
    expect(_reading(tester, _w), '4:00');
    expect(_reading(tester, _b), '5:00', reason: 'black has not moved');

    clock.press(_w);
    await _advance(tester, t, const Duration(seconds: 30));
    expect(_reading(tester, _w), '4:00', reason: 'frozen at the press');
    expect(_reading(tester, _b), '4:30');
  });

  _clockWidgets('a repaint does not cost a rebuild above the digits',
      (tester) async {
    // Ten notifications a second on the screen whose whole point is a
    // full-size board, while the engine searches.
    var outerBuilds = 0;
    final fake = _Fake();
    final clock = ChessClock(TimeControl.parse('5+0'), source: fake.call);
    _live.add(clock);

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        outerBuilds++;
        return Scaffold(body: Center(child: ClockPair(clock: clock)));
      }),
    ));
    clock.start(_w);
    expect(outerBuilds, 1);

    // A notification marks exactly one element dirty: the root of the subtree
    // that will rebuild. Measuring WHICH one is the point — outerBuilds alone
    // would stay at 1 however far up the clock's own tree the rebuild started.
    fake.now += const Duration(seconds: 1);
    clock.poll();
    final face = find.byType(ClockFace).first;
    final digits =
        find.descendant(of: face, matching: find.byType(ListenableBuilder));
    expect(digits, findsOneWidget,
        reason: 'the listener must sit INSIDE the face, not around it');
    expect(tester.element(digits).dirty, isTrue);
    expect(tester.element(face).dirty, isFalse,
        reason: 'the face itself does not rebuild');
    expect(tester.element(find.byType(ClockPair)).dirty, isFalse);

    for (var i = 0; i < 20; i++) {
      await _advance(tester, fake, const Duration(milliseconds: 100));
    }
    expect(_reading(tester, _w), '4:57', reason: 'it really did tick');
    expect(outerBuilds, 1, reason: 'and the screen around it was built once');
  });

  _clockWidgets('low time is distinct on the running clock and the idle one',
      (tester) async {
    final (clock, t) = await _pump(tester, '1+0');
    final idle = _fill(tester, _b);
    clock.start(_w);
    // 1+0's threshold is the 5s floor, so 4 seconds left is low.
    await _advance(tester, t, const Duration(seconds: 56));

    expect(_reading(tester, _w), '0:04.0');
    expect(_fill(tester, _w), isNot(idle), reason: 'the low face takes colour');
    expect(_isRed(_fill(tester, _w)), isTrue, reason: 'and the colour is red');

    // Now hand over: white is still low, but no longer running.
    clock.press(_w);
    await tester.pump();
    expect(_fill(tester, _w), idle, reason: 'not running, so not a red block');
    expect(_isRed(_digits(tester, _w).style!.color!), isTrue,
        reason: 'but the digits still say so');
    expect(_digits(tester, _w).style!.color,
        isNot(_digits(tester, _b).style!.color),
        reason: 'and say it differently from a side with time to spare');
  });

  _clockWidgets('a flag shows zero and stops', (tester) async {
    final (clock, t) = await _pump(tester, '1+0');
    clock.start(_b);
    await _advance(tester, t, const Duration(seconds: 61));

    expect(clock.flagged, _b);
    expect(_reading(tester, _b), '0:00.0');
    await _advance(tester, t, const Duration(seconds: 30));
    expect(_reading(tester, _b), '0:00.0', reason: 'it cannot go below zero');
    expect(_reading(tester, _w), '1:00');
  });

  _clockWidgets('the digits are tabular', (tester) async {
    // Asserted on the style rather than by measuring two readings: Roboto's
    // default figures are already uniform in width, so a width comparison
    // would pass with the feature deleted and prove nothing. What is actually
    // at stake is the fallback face, where they are not.
    await _pump(tester, '5+0');
    expect(_digits(tester, _w).style!.fontFeatures,
        contains(const FontFeature.tabularFigures()));
  });

  _clockWidgets('a face is kClockFace high and no narrower than kClockMinWidth',
      (tester) async {
    final (clock, t) = await _pump(tester, '5+0');
    final size = tester.getSize(find.byKey(const ValueKey('clock-w')));
    expect(size.height, kClockFace,
        reason: 'layout.dart reserves this; the face must actually be it');
    expect(size.width, greaterThanOrEqualTo(kClockMinWidth));

    // The reading that changes shape — tenths, and the widest hour — must not
    // change the height a layout has reserved.
    clock.start(_w);
    await _advance(tester, t, const Duration(minutes: 4, seconds: 55));
    expect(_reading(tester, _w), '0:05.0');
    expect(tester.getSize(find.byKey(const ValueKey('clock-w'))).height,
        kClockFace);
  });

  for (final width in [375.0, 320.0]) {
    _clockWidgets('the pair does not overflow at ${width.toInt()}px',
        (tester) async {
      // A RenderFlex overflow is a runtime error: neither the analyzer nor a
      // green suite says anything about it.
      final (clock, t) = await _pump(tester, '90+30', width: width);
      clock.start(_w); // the widest reading there is: 1:30:00
      await _advance(tester, t, const Duration(milliseconds: 100));

      expect(_reading(tester, _w), '1:29:59');
      expect(tester.takeException(), isNull,
          reason: 'the pair overflowed at ${width.toInt()}px');
      final pair = tester.getSize(find.byType(ClockPair));
      expect(pair.width, lessThanOrEqualTo(width));
    });
  }
}
