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

/// One clock face's height at its default 26px digits: the line box plus its
/// symmetric padding. A layout that hangs a clock over the board must reserve
/// this the way it reserves [kPlayerPlate], or the clock pushes the board's
/// bottom edge off the screen.
///
/// Measured rather than assumed: clock_display_test.dart pumps the real
/// [ClockFace] with the real Roboto and asserts this number, so a style change
/// that grows the face reddens a test instead of eating board height.
const double kClockFace = 39;

/// A clock face is never narrower than this, so the pair does not jump about
/// as `12:34` becomes `9:59` becomes `0:09.4`.
const double kClockMinWidth = 96;

/// Practice: the prompt strip (two lines) plus the hint/retry action row.
const double kPracticeChrome = 56 + 48;

/// Review's verdict strip at its tallest WITHOUT a mini-board: the move, its
/// label, and an explanation wrapping to two lines at 320pt.
///
/// Measured (72) plus a small margin, not borrowed. This used to be
/// [kGradeStrip], which is 66 and was measured for the Play tab's grade strip —
/// a widget that no longer exists, and never had prose wrapping at a phone's
/// narrowest width. Six pixels of under-reservation cost the move list ten, and
/// on a 320x480 viewport ten was the difference between 46 and the 56 floor.
const double kReviewVerdict = 76;

/// Review's fixed furniture: the verdict strip and the scrub bar.
const double kReviewFixed = kReviewVerdict + 52;

/// The move-comparison mini-board in Review's verdict strip (#233): the
/// [MovePreview] board plus the gap above it.
///
/// Added to [kReviewFixed] only for a game that carries grades. An import has
/// no best move to compare anything against, so its strip stays one line and
/// reserving for a board it will never draw would cost it board height for
/// nothing. That predicate is a property of the GAME, not of the ply, so it
/// cannot change under a scrub — which is what keeps the board a fixed size
/// while the strip's own height varies with what each move has to show.
///
/// Measured rather than assumed, as [kClockFace] is: review_preview_test.dart
/// pumps the real strip with the real Roboto and asserts the height fits, so a
/// style change that grows the preview reddens a test instead of quietly
/// eating the move list.
///
/// 120, not the 112 first shipped: the tallest real strip is the one at 320pt
/// carrying an explanation, where the prose wraps to two lines. 112 was
/// measured without any prose at 390pt, which is the easy case.
const double kMovePreview = 120;

/// The least move list worth calling a move list: two rows plus their padding.
///
/// Smaller than [kPaneReserve], and deliberately — that reserve exists to keep
/// a GLANCE of a scrollable pane on screen on a desktop window, and layout.dart
/// already declines to spend it on a phone. This is the harder floor: below it
/// the Review tab is a board and a verdict with no game attached.
const double kMinMoveList = 56;

/// Whether Review should put the board BESIDE the move list rather than above.
///
/// Wider than [kWideBreakpoint] has always meant yes. The addition is LANDSCAPE
/// (#239): a 568x320 phone on its side stacked a 202px board over a verdict
/// strip and a scrub bar and had nothing left — the move list came out at 8px,
/// and because the list is `Expanded` it absorbed that silently rather than
/// overflowing. A board with no game beside it.
///
/// `width > height` is load-bearing and not a proxy for "small". A narrow
/// PORTRAIT viewport that is also cramped (320x480) must keep stacking: laid
/// out side by side at 320pt the board takes 240 and the list gets 80, which is
/// not a move list. Landscape is the case where the width exists and the height
/// does not, which is exactly when the Row helps. Portrait-and-cramped is
/// handled instead by [reviewStackedBoard] reserving list height.
bool reviewSideBySide(double width, double height) {
  if (width >= kWideBreakpoint) return true;
  if (width <= height) return false;
  final board = panedBoardSize(width, height, kReviewFixed);
  return height - board - kReviewFixed < kMinMoveList;
}

/// Review's board when it IS stacked, reserving room for a usable move list.
///
/// [panedBoardSize] deliberately declines to hold back [kPaneReserve] on a
/// phone — there the reserve costs board width the screen plainly has, to
/// protect a glance at content one flick away. Review is the exception: its
/// pane is not a glance, it is the game, and a phone short enough for the board
/// to be height-limited (320x480) was otherwise left 42px of it. So a phone
/// reserves the smaller [kMinMoveList] instead of nothing, and anything wider
/// keeps the [kPaneReserve] it already had — not both, which would double-count
/// and shrink the desktop board for no reason.
double reviewStackedBoard(double width, double height, double fixed) =>
    stackedBoardSize(width, height,
        fixed + (width < kPhoneWidth ? kMinMoveList : kPaneReserve));

/// Whether Review can afford the move-comparison mini-board here (#233).
///
/// The reservation alone was not enough, and the way it failed is worth
/// keeping. [kMovePreview] comes out of the BOARD only where the board is
/// height-limited. On a phone the board is width-limited, so the strip growing
/// took its 120px out of the move list instead — and the list is `Expanded`,
/// which absorbs it silently and clamps at zero rather than overflowing. On a
/// 320x568 phone, a graded move carrying an explanation left the list **8px
/// tall**: a board, a verdict, and no game. The test that was supposed to
/// cover this asserted the board had not moved, which was true and beside the
/// point.
///
/// So the mini-board is the thing that yields. It is the luxury of the three —
/// the board, the verdict and the list are all load-bearing — and the strip
/// already has a fallback for the case where it cannot draw one, the "best:
/// d4" sentence a promotion falls back to.
///
/// A property of the VIEWPORT, not of the ply, so it cannot change under a
/// scrub. The board's sizing and the strip's content must be fed the SAME
/// answer, or the two disagree about who is paying for the height and the
/// difference comes out of the move list — which is the bug itself, one level
/// down.
bool reviewShowsPreview(double width, double height) {
  // Side by side the board costs the column no height at all, so the only
  // question is whether the strip and a usable list both fit.
  if (reviewSideBySide(width, height)) {
    return height - kReviewFixed - kMovePreview >= kMinMoveList;
  }
  // Stacked, the mini-board must cost NOTHING — neither the list its floor
  // (which [reviewStackedBoard] now protects) nor the board any size. Stated
  // as a comparison rather than an arithmetic threshold because that is the
  // actual rule: draw it if and only if it is free.
  //
  // It is the luxury of the four. The board, the verdict and the list are all
  // load-bearing, and the strip already has a fallback for when it cannot draw
  // a comparison — the "best: d4" sentence a promotion gets. On a 320x568 SE
  // the preview would cost 46px of board; on a 620x520 window it would drive
  // the board to kMinBoard. Both take the sentence instead.
  return reviewStackedBoard(width, height, kReviewFixed + kMovePreview) ==
      reviewStackedBoard(width, height, kReviewFixed);
}


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
