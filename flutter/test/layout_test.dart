// The board is square, so it is what overflows when a window is both narrow
// and short — which is exactly what a desktop window can be and a phone
// cannot. This is the arithmetic that got that wrong.
//
//   cd flutter && flutter test

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/ui/layout.dart';

void main() {
  group('phone layout', () {
    test('takes the full width when there is height to spare', () {
      // a real phone: tall relative to its width
      expect(narrowBoardSize(390, 844), 390);
      expect(narrowBoardSize(430, 932), 430);
    });

    test('caps the board when the window is short, so nothing overflows', () {
      // the macOS minimum window: 560 wide would leave nothing for the panel
      expect(narrowBoardSize(560, 620), lessThan(560));
      expect(narrowBoardSize(560, 620) + kNarrowChrome, lessThanOrEqualTo(620));
    });

    test('the column fits at every size down to the desktop minimum', () {
      for (var w = 320.0; w <= 719; w += 23) {
        for (var h = 620.0; h <= 1000; h += 37) {
          expect(narrowBoardSize(w, h) + kNarrowChrome, lessThanOrEqualTo(h),
              reason: 'overflowed at ${w}x$h');
          expect(narrowBoardSize(w, h), lessThanOrEqualTo(w),
              reason: 'wider than the window at ${w}x$h');
        }
      }
    });

    test('never shrinks past the floor, absurd as the window may be', () {
      expect(narrowBoardSize(320, 100), kMinBoard);
    });
  });

  group('wide layout', () {
    test('follows the split', () {
      expect(wideBoardSize(1400, 1000, 0.5), 700);
      expect(wideBoardSize(1400, 1000, 0.32), closeTo(448, 0.01));
    });

    test('is capped by height, so a short window does not overflow', () {
      // the floor applies to the WIDTH share only — flooring the height too
      // is the bug this guards
      expect(wideBoardSize(1400, 300, 0.58), lessThanOrEqualTo(300 - 56));
    });

    test('stays sane when the window is tiny', () {
      expect(wideBoardSize(800, 120, 0.58), greaterThan(0));
    });
  });
}
