// Layout arithmetic, kept out of the widgets so it can be tested directly.
// The board is square, which makes it the thing that overflows: on a phone
// height is plentiful and full width is right, but a desktop window can be
// narrow AND short at the same time.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Below this the panel column has no room and the phone layout is used.
const double kWideBreakpoint = 720;

/// The grade strip's height when it carries BOTH the move's verdict and a
/// threat line. Sizing for one line is what pushed the threat explanation
/// below the fold, which looks exactly like the feature not working.
const double kGradeStrip = 66; // two lines plus margin — measured ~56

/// Extra room held back so some of a scrollable pane stays on screen.
///
/// Worth its width on a desktop window, where the pane is the point of the
/// layout. Not worth it on a phone — see [kPhoneWidth].
const double kPaneReserve = 96;

/// Grade strip, view bar, and the least panel worth leaving on screen.
const double kNarrowChrome = kPhoneChrome + kPaneReserve;

/// Below this width a viewport is a PHONE, not a small desktop window.
///
/// The distinction is real and the gap is comfortable: the macOS minimum
/// window is 560 wide, and every phone in portrait is under 500. It matters
/// because the two want opposite things from the same Column — see
/// [kPhoneChrome].
const double kPhoneWidth = 500;

/// Play's only fixed furniture now: the view bar (the panel tabs). The grade
/// strip that used to sit under the board is gone — its move verdict already
/// lived in the Insights card, so it moved there (with the threat and the
/// engine-loading bar) and the board took back its ~66px of height.
///
/// [kNarrowChrome] also reserves 96px so some panel stays on screen. On a
/// desktop window that is worth having; on a phone it is not — `_panel()` is a
/// SingleChildScrollView, so the reserve would only protect a glance at
/// content one flick away, at the cost of board width the screen plainly has.
const double kPhoneChrome = 46;

/// One player plate (name + captured material) above the board and one below.
/// Fixed furniture in the Play layout, so their height must be reserved or the
/// board pushes them — and everything under them — off the bottom. Kept close
/// to the content it holds (a name row / a 16px capture tray) so the plate sits
/// flush against the board rather than floating a gap above it.
const double kPlayerPlate = 24;

/// Never shrink the board past this; below it nothing is usable anyway and
/// the desktop minimum window size keeps us clear of it.
const double kMinBoard = 200;

/// Practice: the prompt strip (two lines) plus the hint/retry action row.
const double kPracticeChrome = 56 + 48;

/// Review's fixed furniture: the verdict strip and the scrub bar.
const double kReviewFixed = kGradeStrip + 52;

/// Review, plus enough move list to be worth showing — the list is Expanded,
/// so without a reserve the board would eat it entirely on a short window.
const double kReviewChrome = kReviewFixed + kPaneReserve;

/// The board's size when it sits at the top of a single column with [chrome]
/// pixels of fixed furniture beneath it: the full width, unless that would
/// push the furniture off the bottom.
///
/// Every stacked layout goes through here. Three call sites each deciding
/// this independently is what left Practice and Review overflowing by ~900px
/// on a desktop window while Play was fine.
double stackedBoardSize(double width, double height, double chrome) =>
    math.min(width, math.max(kMinBoard, height - chrome));

/// The board's size in the stacked Play layout: the full width unless that
/// would push the rest of the column off the bottom.
///
/// A phone and a narrow desktop window reach this by different routes and
/// want different answers. A phone is tall, so the full width fits with room
/// left over and the board should simply take it. A desktop window can be
/// narrow AND short at once — that is what [stackedBoardSize] exists for, and
/// where holding back space for the panel is worth the width.
double narrowBoardSize(double width, double height) =>
    panedBoardSize(width, height - 2 * kPlayerPlate, kPhoneChrome);

/// The board's size in a stacked layout with a SCROLLABLE pane beneath it.
///
/// [fixed] is furniture that must always fit. On anything wider than a phone
/// a further [kPaneReserve] is held back so some of the pane stays visible;
/// on a phone it is not, because there the reserve costs board width that the
/// screen plainly has, to protect a glance at content one flick away.
///
/// Both Play and Review go through here. Each deciding it independently is
/// the mistake this file already made once — that is what left Practice and
/// Review overflowing by ~900px while Play was fine.
double panedBoardSize(double width, double height, double fixed) =>
    stackedBoardSize(
        width, height, width < kPhoneWidth ? fixed : fixed + kPaneReserve);

/// The board's size in the wide layout: its share of the width, capped so a
/// window dragged short does not overflow.
double wideBoardSize(double width, double height, double split) => math.min(
      math.max(240.0, width * split),
      math.max(120.0, height - 2 * kPlayerPlate),
    );

/// Room for the macOS traffic lights, which float over the app's own chrome.
///
/// The window is `fullSizeContentView` with a transparent titlebar (see
/// macos/Runner/MainFlutterWindow.swift), so the Flutter view owns the whole
/// window and the close/minimise/zoom buttons sit on top of whatever is at the
/// top-left. They occupy x 9-69 (measured against the live window; these are
/// points, so it is scale-invariant), and 78 clears them with a margin.
///
/// Zero everywhere else — no other platform draws anything over the app.
double get macTitlebarInset =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS ? 78.0 : 0.0;

/// Re-lay an [AppBar] so nothing it draws lands under the traffic lights.
///
/// Every AppBar in the app must go through this, not just the shell's. A
/// pushed route builds its own bar with an IMPLIED back button, and an implied
/// leading is the case to watch: it is null on the AppBar, so a wrapper that
/// only pads `bar.leading` insets the title and leaves the back arrow under the
/// close button. Clicking it closes the window — AppKit wins the hit test and
/// Flutter never sees the tap. That shipped in the About screen's legal viewer.
///
/// Returns [bar] untouched off macOS, where the inset is 0.
AppBar insetAppBar(BuildContext context, AppBar bar) {
  final inset = macTitlebarInset;
  if (inset == 0) return bar;
  // Resolve the implied back button into a real one so it can be padded.
  final leading = bar.leading ??
      (bar.automaticallyImplyLeading && Navigator.of(context).canPop()
          ? const BackButton()
          : null);
  return AppBar(
    leading: leading == null
        ? null
        : Padding(padding: EdgeInsets.only(left: inset), child: leading),
    leadingWidth: leading == null ? null : inset + 56,
    // already resolved above; letting Material imply a second one would put it
    // straight back under the buttons
    automaticallyImplyLeading: false,
    titleSpacing: leading == null ? inset : bar.titleSpacing,
    title: bar.title,
    actions: bar.actions,
    bottom: bar.bottom,
    // carried through rather than dropped: a future bar that styles itself
    // would otherwise lose that styling on macOS only, which is the hardest
    // kind of bug to notice
    backgroundColor: bar.backgroundColor,
    foregroundColor: bar.foregroundColor,
    elevation: bar.elevation,
    shape: bar.shape,
    flexibleSpace: bar.flexibleSpace,
    centerTitle: bar.centerTitle,
    toolbarHeight: bar.toolbarHeight,
    systemOverlayStyle: bar.systemOverlayStyle,
    iconTheme: bar.iconTheme,
  );
}
