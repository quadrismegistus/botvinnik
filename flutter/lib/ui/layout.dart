// Layout arithmetic, kept out of the widgets so it can be tested directly.
// The board is square, which makes it the thing that overflows: on a phone
// height is plentiful and full width is right, but a desktop window can be
// narrow AND short at the same time.

import 'dart:math' as math;

/// Below this the panel column has no room and the phone layout is used.
const double kWideBreakpoint = 720;

/// The grade strip's height when it carries BOTH the move's verdict and a
/// threat line. Sizing for one line is what pushed the threat explanation
/// below the fold, which looks exactly like the feature not working.
const double kGradeStrip = 66; // two lines plus margin — measured ~56

/// Grade strip, view bar, and the least panel worth leaving on screen.
const double kNarrowChrome = kGradeStrip + 46 + 96;

/// Never shrink the board past this; below it nothing is usable anyway and
/// the desktop minimum window size keeps us clear of it.
const double kMinBoard = 200;

/// Practice: the prompt strip (two lines) plus the hint/retry action row.
const double kPracticeChrome = 56 + 48;

/// Review: the verdict strip and the scrub bar, plus enough move list to be
/// worth showing — the list is Expanded, so without a reserve the board would
/// eat it entirely on a short window.
const double kReviewChrome = kGradeStrip + 52 + 96;

/// The board's size when it sits at the top of a single column with [chrome]
/// pixels of fixed furniture beneath it: the full width, unless that would
/// push the furniture off the bottom.
///
/// Every stacked layout goes through here. Three call sites each deciding
/// this independently is what left Practice and Review overflowing by ~900px
/// on a desktop window while Play was fine.
double stackedBoardSize(double width, double height, double chrome) =>
    math.min(width, math.max(kMinBoard, height - chrome));

/// The board's size in the phone layout: the full width unless that would
/// push the rest of the column off the bottom.
double narrowBoardSize(double width, double height) =>
    stackedBoardSize(width, height, kNarrowChrome);

/// The board's size in the wide layout: its share of the width, capped so a
/// window dragged short does not overflow.
double wideBoardSize(double width, double height, double split) => math.min(
      math.max(240.0, width * split),
      math.max(120.0, height - kGradeStrip),
    );
