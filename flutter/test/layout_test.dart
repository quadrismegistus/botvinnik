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
          // A phone only guarantees the FIXED furniture fits — the strip and
          // the view bar. It deliberately does not hold back panel space; see
          // kPhoneChrome.
          final chrome = w < kPhoneWidth ? kPhoneChrome : kNarrowChrome;
          expect(narrowBoardSize(w, h) + chrome, lessThanOrEqualTo(h),
              reason: 'overflowed at ${w}x$h');
          expect(narrowBoardSize(w, h), lessThanOrEqualTo(w),
              reason: 'wider than the window at ${w}x$h');
        }
      }
    });

    test('a phone spends its width on the board, not a hidden pane reserve', () {
      // The case that prompted this: reported on botvinnik.app 2026-07-19 as
      // "the board is small even at best case", with a visible margin down
      // both sides. Measured off that screenshot — a 393pt-wide viewport whose
      // body is ~556pt after the app bar and the bottom nav — the old reserve
      // gave 348 and left 45pt of width unused. The phone rule spends that
      // width on the board; only the two player plates, which are real fixed
      // furniture, take their 2*kPlayerPlate of HEIGHT — so on that same short
      // body the board is 388, not the full 393, and never the 348 it was.
      expect(narrowBoardSize(393, 556), 388);
      expect(narrowBoardSize(393, 556),
          greaterThan(stackedBoardSize(393, 556, kNarrowChrome)));
      // and every phone in portrait, not just that one: the board beats the
      // pane-reserve alternative it replaced (or ties it, when both hit the
      // width cap), and board + plates + furniture still fit with no scroll.
      for (final (w, h) in [(320.0, 480.0), (375.0, 540.0), (390.0, 556.0),
                            (393.0, 556.0), (430.0, 640.0)]) {
        expect(narrowBoardSize(w, h),
            greaterThanOrEqualTo(stackedBoardSize(w, h, kNarrowChrome)),
            reason: 'the pane reserve crept back in at ${w}x$h');
        expect(narrowBoardSize(w, h) + 2 * kPlayerPlate + kPhoneChrome,
            lessThanOrEqualTo(h),
            reason: 'the column overflowed at ${w}x$h');
      }
    });

    test('a narrow DESKTOP window is unaffected — it still holds panel space',
        () {
      // The macOS minimum is 560 wide, comfortably above kPhoneWidth, so the
      // window that motivated the original cap keeps the old behaviour: the
      // pane reserve, plus the same plate reserve every Play layout now holds.
      expect(narrowBoardSize(560, 620),
          stackedBoardSize(560, 620 - 2 * kPlayerPlate, kNarrowChrome));
      expect(narrowBoardSize(560, 620) + 2 * kPlayerPlate + kNarrowChrome,
          lessThanOrEqualTo(620));
    });

    test('never shrinks past the floor, absurd as the window may be', () {
      expect(narrowBoardSize(320, 100), kMinBoard);
    });
  });

  group('stacked layouts other than Play', () {
    // Practice and Review sized the board to the full width with no height
    // cap, so on a desktop window a square board was as tall as the window
    // was wide. Reported 2026-07-19: 945px and 871px of overflow, with the
    // action row and the scrub bar pushed off the bottom.
    test('the reported window no longer overflows', () {
      const w = 2000.0, h = 1150.0; // the screenshots, near enough
      expect(stackedBoardSize(w, h, kPracticeChrome) + kPracticeChrome,
          lessThanOrEqualTo(h));
      expect(stackedBoardSize(w, h, kReviewChrome) + kReviewChrome,
          lessThanOrEqualTo(h));
      // and the board is no longer wider than the window is tall
      expect(stackedBoardSize(w, h, kPracticeChrome), lessThan(h));
    });

    test('Review gets the full width on a phone too, and Practice already did',
        () {
      // Play was the reported case, but Review held back the same 96px for its
      // move list and lost the same width. Practice never did — its chrome is
      // all fixed furniture — so it is here as the control: if this one ever
      // starts failing, the phone rule has been applied somewhere it should
      // not be.
      const w = 393.0, h = 556.0;
      expect(panedBoardSize(w, h, kReviewFixed), w);
      expect(stackedBoardSize(w, h, kPracticeChrome), w);
      // and the furniture still fits under each
      expect(panedBoardSize(w, h, kReviewFixed) + kReviewFixed,
          lessThanOrEqualTo(h));
    });

    test('every chrome reserve fits at every plausible size', () {
      for (final chrome in [kNarrowChrome, kPracticeChrome, kReviewChrome]) {
        for (var w = 320.0; w <= 2400; w += 71) {
          for (var h = 600.0; h <= 1600; h += 53) {
            final size = stackedBoardSize(w, h, chrome);
            expect(size + chrome, lessThanOrEqualTo(h),
                reason: 'chrome $chrome overflowed at ${w}x$h');
            expect(size, lessThanOrEqualTo(w),
                reason: 'chrome $chrome exceeded the width at ${w}x$h');
          }
        }
      }
    });

    test('narrowBoardSize is the same helper, with the chrome its width earns '
        'and the two plates reserved', () {
      for (var w = 320.0; w <= 800; w += 37) {
        for (var h = 600.0; h <= 1200; h += 41) {
          final chrome = w < kPhoneWidth ? kPhoneChrome : kNarrowChrome;
          expect(narrowBoardSize(w, h),
              stackedBoardSize(w, h - 2 * kPlayerPlate, chrome),
              reason: 'wrong chrome picked at ${w}x$h');
        }
      }
    });

    test('the phone threshold sits in the gap between the two, not on an edge',
        () {
      // 500 is a real gap, not a guess: phones in portrait top out around 430
      // and the macOS minimum window is 560. A threshold inside that gap means
      // neither case ever lands on the wrong side of it.
      expect(kPhoneWidth, greaterThan(440));
      expect(kPhoneWidth, lessThan(560));
      // and the two policies really do differ, or none of this matters
      expect(kPhoneChrome, lessThan(kNarrowChrome));
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
      expect(wideBoardSize(1400, 300, 0.58), lessThanOrEqualTo(300 - kGradeStrip));
    });

    test('leaves room for a two-line grade strip', () {
      // a one-line reserve put the threat explanation below the fold, which
      // reads as the feature simply not working
      for (var h = 700.0; h <= 1400; h += 53) {
        expect(wideBoardSize(1600, h, 0.58) + kGradeStrip, lessThanOrEqualTo(h),
            reason: 'no room for the strip at height $h');
      }
    });

    test('stays sane when the window is tiny', () {
      expect(wideBoardSize(800, 120, 0.58), greaterThan(0));
    });
  });
}
