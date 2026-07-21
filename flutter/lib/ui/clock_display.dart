// The clock as it is drawn: one face per side, and a pair of them.
//
// Three states have to be legible from across a table, without reading the
// numbers: which clock is RUNNING, whether either side is in trouble, and
// whether a flag has fallen. So the running face inverts — light block, dark
// digits, the way every playing site and every physical clock does it — rather
// than carrying a marker the eye has to find. Low time takes the whole face
// red, which is the same trick again.
//
// No glyphs. A clock is exactly where one would creep in (an hourglass, a
// play triangle, an infinity for no limit), and none of the three bundled
// Roboto faces contains any of them: drawing one on web fetches a Noto face
// from fonts.gstatic.com. Digits, a colon and a full stop only.
//
// The rebuild is scoped to the digits. A [ChessClock] notifies ten times a
// second; a `context.watch` here would rebuild everything from the nearest
// build boundary up to ten times a second while the engine is searching, on
// the one screen (#169) whose whole point is that the board is as large as it
// will go. The [ListenableBuilder] below is the only thing that reruns.

import 'package:flutter/material.dart';

import '../stores/chess_clock.dart';
import 'layout.dart';

/// Idle: reads as furniture, at the same weight as the rest of the chrome.
const Color _kIdleFill = Color(0xFF262421);
const Color _kIdleText = Colors.white70;

/// Running: inverted, so the eye finds it without looking for it.
const Color _kRunFill = Color(0xFFE8E6E1);
const Color _kRunText = Color(0xFF1B1A17);

/// Low, and running — the app's red (see kThreatArrowRed / games_list).
const Color _kLowFill = Color(0xFFCA3431);
const Color _kLowText = Color(0xFFFFFFFF);

/// Low, but not this side's move. Loud enough to see, quiet enough not to
/// compete with the running face.
const Color _kLowIdleText = Color(0xFFE0908E);

/// When a clock starts drawing itself as low.
///
/// A tenth of the initial time, floored at 5s and capped at 30s. A judgement,
/// not a measurement: a fixed 30s would be half a bullet game and a twentieth
/// of a classical one. Increment is deliberately ignored — a side under 20
/// seconds in a 3+2 is in as much trouble as one under 20 seconds in a 3+0,
/// because the increment only arrives if they move in time.
Duration lowTimeThreshold(TimeControl control) {
  final tenth = control.initial ~/ 10;
  if (tenth < const Duration(seconds: 5)) return const Duration(seconds: 5);
  if (tenth > const Duration(seconds: 30)) return const Duration(seconds: 30);
  return tenth;
}

/// One side's clock.
class ClockFace extends StatelessWidget {
  final ChessClock clock;
  final ClockSide side;

  /// Text size for the digits. The default is [kClockFace]'s measurement;
  /// change it and the face grows, so the layout constant no longer holds.
  final double fontSize;

  const ClockFace({
    super.key,
    required this.clock,
    required this.side,
    this.fontSize = 26,
  });

  @override
  Widget build(BuildContext context) {
    final low = lowTimeThreshold(clock.control);
    return ListenableBuilder(
      listenable: clock,
      builder: (context, _) {
        final left = clock.remaining(side);
        final isRunning = clock.running == side;
        final isLow = left <= low;
        final fill = isLow && isRunning
            ? _kLowFill
            : (isRunning ? _kRunFill : _kIdleFill);
        final ink = isLow
            ? (isRunning ? _kLowText : _kLowIdleText)
            : (isRunning ? _kRunText : _kIdleText);
        return Container(
          key: ValueKey('clock-${side.char}'),
          constraints: const BoxConstraints(minWidth: kClockMinWidth),
          padding: EdgeInsets.symmetric(
              horizontal: fontSize * 0.5, vertical: fontSize * 0.25),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4),
          ),
          // No `alignment:` — a Container that aligns its child expands to
          // fill the box it is given, which in a Row is the whole height.
          // [kClockFace] is only a number if the face wraps its digits, and
          // the minWidth below reaches the Text directly, so TextAlign.center
          // does the centring the alignment would have.
          child: Text(
            formatClock(left),
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              color: ink,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              height: 1.0,
              // Without this the digits are free to change width as they
              // change value, and a counting-down clock jitters.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

/// Both clocks side by side, opponent first.
///
/// [perspective] is the side the player has, so their own clock sits on the
/// right — the hand that presses it. A caller with room above and below the
/// board can place two [ClockFace]s instead and skip this.
class ClockPair extends StatelessWidget {
  final ChessClock clock;
  final ClockSide perspective;
  final double fontSize;

  const ClockPair({
    super.key,
    required this.clock,
    this.perspective = ClockSide.white,
    this.fontSize = 26,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClockFace(
              clock: clock, side: perspective.opponent, fontSize: fontSize),
          const SizedBox(width: 12),
          ClockFace(clock: clock, side: perspective, fontSize: fontSize),
        ],
      );
}
