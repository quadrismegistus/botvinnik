// Layout arithmetic, kept out of the widgets so it can be tested directly.
// The board is square, which makes it the thing that overflows: on a phone
// height is plentiful and full width is right, but a desktop window can be
// narrow AND short at the same time.

import 'dart:math' as math;

/// Below this the panel column has no room and the phone layout is used.
const double kWideBreakpoint = 720;

/// Grade strip, view bar, and the least panel worth leaving on screen.
const double kNarrowChrome = 28 + 46 + 96;

/// Never shrink the board past this; below it nothing is usable anyway and
/// the desktop minimum window size keeps us clear of it.
const double kMinBoard = 200;

/// The board's size in the phone layout: the full width unless that would
/// push the rest of the column off the bottom.
double narrowBoardSize(double width, double height) =>
    math.min(width, math.max(kMinBoard, height - kNarrowChrome));

/// The board's size in the wide layout: its share of the width, capped so a
/// window dragged short does not overflow.
double wideBoardSize(double width, double height, double split) => math.min(
      math.max(240.0, width * split),
      math.max(120.0, height - 56),
    );
