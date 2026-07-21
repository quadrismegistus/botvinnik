// A chess clock: a time control, two banks of time, and at most one of them
// running. Machinery for #169's rated mode, which is the only place a clock
// makes sense — but nothing here knows about the game, the board or a bot. A
// flag is a FACT this exposes, not an action it takes: the caller decides what
// losing on time means.
//
// The one decision the whole file is built around: a clock that subtracts a
// fixed amount on every Timer tick accumulates error, because a Timer fires
// late — by whatever the frame, the engine search and the platform's scheduler
// happen to cost — and never early. Over a 15-minute game those late arrivals
// are the difference between the two clocks and the game.
//
// So the arithmetic never counts ticks. Each side's time is BANKED at discrete
// events (a press, a pause, a stop), and the running side's remaining time is
// DERIVED, on every read, from a monotonic origin. The Timer's only job is to
// ask for a repaint; delete it and the numbers are still right, they just stop
// being drawn.
//
// Backgrounding follows from that. A phone that locks mid-game keeps the game
// going — that is what a real clock does, and the fact that Timers stop firing
// in the background changes nothing about the numbers. The next [poll] after
// the app resumes reports the true remaining time and falls the flag if it
// fell while the screen was off. (Whether the monotonic source keeps advancing
// across a full device SUSPEND is platform-dependent and not measured here.
// A caller that needs that guarantee can inject a wall-clock source.)

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Monotonic elapsed time since some fixed origin.
///
/// Only differences between two reads are ever used, so the origin is
/// arbitrary — but it must never run backwards, which is exactly what
/// `DateTime.now()` does when the system clock is corrected, a timezone
/// changes, or NTP steps the machine. [Stopwatch] is the right source; this
/// is a function so a test can be one instead.
typedef ElapsedSource = Duration Function();

/// The default source: a [Stopwatch] started when the clock is built.
ElapsedSource _stopwatchSource() {
  final sw = Stopwatch()..start();
  return () => sw.elapsed;
}

/// Which clock. Kept as an enum rather than the `'w'`/`'b'` strings the rest
/// of the app passes around, because a clock indexed by an unvalidated string
/// has a silent third state; [fromChar] is the one place that conversion
/// happens.
enum ClockSide {
  white,
  black;

  static ClockSide fromChar(String c) =>
      c == 'w' ? ClockSide.white : ClockSide.black;

  String get char => this == ClockSide.white ? 'w' : 'b';

  ClockSide get opponent =>
      this == ClockSide.white ? ClockSide.black : ClockSide.white;
}

/// An initial time plus a Fischer increment, which is what every notation in
/// #169 describes: 5+0, 3+2, 15+10.
///
/// DELAY (Bronstein, and the US delay it is equivalent to) is deliberately out
/// of scope. It is not a variation on this arithmetic but a second timing
/// regime layered on it — a per-move countdown that must elapse before the
/// main clock starts, with its own start, its own reset on every press, and
/// its own interaction with a flag. That is a second state machine for a
/// control no one has asked for and no online site uses by default. The shape
/// here (a bank plus an origin) admits it later: delay would be a subtraction
/// applied to the derived elapsed, not a rewrite.
@immutable
class TimeControl {
  /// Each side's time on the clock at move one.
  final Duration initial;

  /// Added to a side's clock when that side completes a move.
  final Duration increment;

  const TimeControl(this.initial, this.increment);

  /// The standard notation's own units: minutes, plus seconds of increment.
  TimeControl.of(num minutes, [num incrementSeconds = 0])
      : initial = Duration(microseconds: (minutes * 60e6).round()),
        increment = Duration(microseconds: (incrementSeconds * 1e6).round());

  /// Parses `5+0`, `3+2`, `15+10` — and a bare `10`, which means `10+0`.
  ///
  /// Returns null for anything else, INCLUDING `0+0`: a control with neither
  /// time nor increment is not a game, and a clock built on it flags on the
  /// first read.
  static TimeControl? tryParse(String text) {
    final m = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(?:\+\s*(\d+(?:\.\d+)?)\s*)?$')
        .firstMatch(text);
    if (m == null) return null;
    final minutes = double.parse(m.group(1)!);
    final inc = m.group(2) == null ? 0.0 : double.parse(m.group(2)!);
    if (minutes <= 0 && inc <= 0) return null;
    return TimeControl.of(minutes, inc);
  }

  /// As [tryParse], but throws rather than returning null.
  factory TimeControl.parse(String text) =>
      tryParse(text) ?? (throw FormatException('not a time control', text));

  /// `5+0`, `3+2`, `0.5+0` — the inverse of [tryParse].
  ///
  /// Half-minute controls are written `0.5`, not the `½` lichess uses: that
  /// glyph is in none of the three bundled Roboto faces, so drawing it on web
  /// fetches a Noto face from fonts.gstatic.com.
  String get notation => '${_trim(initial.inMicroseconds / 60e6)}'
      '+${_trim(increment.inMicroseconds / 1e6)}';

  static String _trim(double v) {
    final whole = v.round();
    if ((v - whole).abs() < 1e-9) return '$whole';
    return v.toStringAsFixed(1);
  }

  @override
  String toString() => notation;

  @override
  bool operator ==(Object other) =>
      other is TimeControl &&
      other.initial == initial &&
      other.increment == increment;

  @override
  int get hashCode => Object.hash(initial, increment);
}

/// The controls a picker would offer, fastest first. Ordinary tournament
/// fare — nothing here is load-bearing, and a caller is free to build its own.
const List<TimeControl> kTimeControlPresets = [
  TimeControl(Duration(minutes: 1), Duration.zero),
  TimeControl(Duration(minutes: 2), Duration(seconds: 1)),
  TimeControl(Duration(minutes: 3), Duration.zero),
  TimeControl(Duration(minutes: 3), Duration(seconds: 2)),
  TimeControl(Duration(minutes: 5), Duration.zero),
  TimeControl(Duration(minutes: 5), Duration(seconds: 3)),
  TimeControl(Duration(minutes: 10), Duration.zero),
  TimeControl(Duration(minutes: 15), Duration(seconds: 10)),
  TimeControl(Duration(minutes: 30), Duration.zero),
];

/// Two clocks and the rules for moving between them.
///
/// A [ChangeNotifier] so a display can rebuild, but only a display should
/// listen: it notifies on every tick, and anything above the clock widget in
/// the tree would then rebuild ten times a second while an engine searches.
class ChessClock extends ChangeNotifier {
  final TimeControl control;

  /// How often the internal ticker asks listeners to repaint. Null runs no
  /// ticker at all and leaves [poll] to the caller — which is what the model
  /// tests do, and what a headless caller wants.
  ///
  /// The interval affects only how fresh a drawn number is, never the number.
  final Duration? tick;

  /// Called once, with the side that ran out, at the moment a flag falls.
  /// Deliberately a callback and not a rule: this class does not know that
  /// flagging loses the game, and #169's caller may want to check for
  /// insufficient material first.
  void Function(ClockSide side)? onFlag;

  final ElapsedSource _now;
  final Map<ClockSide, Duration> _banked;

  /// The side whose clock is counting down, or null before the first move and
  /// after [stop]. Non-null but frozen while [isPaused].
  ClockSide? _running;
  bool _paused = false;
  ClockSide? _flagged;

  /// The value of [_now] when [_running] last started counting. Every derived
  /// remaining time is measured from here, which is why nothing drifts.
  Duration _origin = Duration.zero;

  Timer? _timer;
  bool _disposed = false;

  ChessClock(
    this.control, {
    ElapsedSource? source,
    this.tick = const Duration(milliseconds: 100),
    this.onFlag,
  })  : _now = source ?? _stopwatchSource(),
        _banked = {
          ClockSide.white: control.initial,
          ClockSide.black: control.initial,
        };

  /// The side counting down right now, or null if nobody is.
  ClockSide? get running => _paused || _flagged != null ? null : _running;

  /// The side to move, whether or not the clock is currently counting for
  /// them — the side a [resume] would start.
  ClockSide? get toMove => _running;

  bool get isPaused => _paused;

  /// The side that ran out of time, once one has. Null otherwise; this is the
  /// result a caller acts on.
  ClockSide? get flagged => _flagged;

  bool get hasFlagged => _flagged != null;

  /// [side]'s remaining time, derived fresh on every read and never negative.
  Duration remaining(ClockSide side) {
    final left = _exact(side);
    return left.isNegative ? Duration.zero : left;
  }

  /// Remaining time, allowed to go negative — the overshoot between a flag
  /// falling and anything noticing.
  Duration _exact(ClockSide side) {
    final banked = _banked[side]!;
    if (side != _running || _paused || _flagged != null) return banked;
    return banked - (_now() - _origin);
  }

  /// Start the game with [side] to move. Does nothing once a flag has fallen.
  void start(ClockSide side) {
    if (_flagged != null) return;
    _running = side;
    _paused = false;
    _origin = _now();
    _restartTicker();
    _notify();
  }

  /// [mover] has completed a move: bank their time, add their increment, and
  /// hand the clock to the opponent.
  ///
  /// The increment lands on the MOVER's clock, after their thinking time has
  /// been taken off it — and not at all if they were already through zero when
  /// they pressed, which is a flag, not a move.
  ///
  /// Pressing before [start] simply hands over with no increment: no time was
  /// spent, so there is nothing to increment.
  ///
  /// Pressing OUT OF TURN is ignored entirely. It used to fall through to the
  /// re-origin below, which silently refunded the running side every second it
  /// had spent — 30s of White's time handed back, with White still to move,
  /// because `mover.opponent` put it straight back on White. A double press,
  /// or a bot-reply path racing the human's, is exactly the shape that takes.
  void press(ClockSide mover) {
    if (_flagged != null) return;
    if (_running != null && _running != mover) return;
    if (_running == mover) {
      // [_exact] reads the bank while paused, so a move made over a paused
      // clock costs nothing and still earns its increment.
      final left = _exact(mover);
      if (left <= Duration.zero) {
        _fall(mover);
        return;
      }
      _banked[mover] = left + control.increment;
    }
    _running = mover.opponent;
    _paused = false;
    _origin = _now();
    _restartTicker();
    _notify();
  }

  /// Freeze both clocks, keeping [toMove]. The time spent so far is banked, so
  /// a pause that lasts an hour costs the mover nothing.
  void pause() {
    if (_paused || _running == null || _flagged != null) return;
    if (_bankRunning()) return; // ran out while we were banking it
    _paused = true;
    _stopTicker();
    _notify();
  }

  /// Resume the side [pause] froze.
  void resume() {
    if (!_paused || _running == null || _flagged != null) return;
    _paused = false;
    _origin = _now();
    _restartTicker();
    _notify();
  }

  /// The game is over: bank the running side's time and leave both clocks
  /// showing what is left. Idempotent.
  void stop() {
    if (_running != null && !_paused && _flagged == null) _bankRunning();
    _running = null;
    _paused = false;
    _stopTicker();
    _notify();
  }

  /// Back to a fresh pair of clocks on the same control.
  void reset() {
    _banked[ClockSide.white] = control.initial;
    _banked[ClockSide.black] = control.initial;
    _running = null;
    _paused = false;
    _flagged = null;
    _origin = _now();
    _stopTicker();
    _notify();
  }

  /// Look at the running clock now: fall the flag if it has run out,
  /// otherwise ask listeners to repaint.
  ///
  /// The ticker calls this, and so should anything that has reason to believe
  /// wall time has passed unobserved — an app-resume handler, most obviously,
  /// since no Timer fires while the app is in the background.
  void poll() {
    final side = _running;
    if (side == null || _paused || _flagged != null) return;
    if (_exact(side) <= Duration.zero) {
      _fall(side);
      return;
    }
    _notify();
  }

  /// Move the running side's elapsed time out of the origin and into the
  /// bank. Returns true if doing so found them already through zero.
  bool _bankRunning() {
    final side = _running;
    if (side == null) return false;
    final left = _exact(side);
    if (left <= Duration.zero) {
      _fall(side);
      return true;
    }
    _banked[side] = left;
    return false;
  }

  /// Force a flag, for tests that need a clocked game to END without waiting
  /// out real time — the ticker reads a monotonic source `tester.pump` cannot
  /// advance.
  @visibleForTesting
  void debugFlag(ClockSide side) => _fall(side);

  void _fall(ClockSide side) {
    _banked[side] = Duration.zero;
    _flagged = side;
    _paused = false;
    _stopTicker();
    _notify();
    onFlag?.call(side);
  }

  void _restartTicker() {
    _stopTicker();
    final every = tick;
    if (every == null || _disposed) return;
    _timer = Timer.periodic(every, (_) => poll());
  }

  void _stopTicker() {
    _timer?.cancel();
    _timer = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    super.dispose();
  }
}

/// A clock reading: `5:00`, `12:34`, `1:05:00`, and tenths under ten seconds
/// where a tenth is the difference between having time and not.
///
/// Seconds are FLOORED, as every playing site's clock floors them: a 5+0 game
/// reads 5:00 for an instant and 4:59 for most of the first minute. `0:00.0`
/// therefore means out of time, not nearly out.
String formatClock(Duration d) {
  final t = d.isNegative ? Duration.zero : d;
  if (t.inHours > 0) {
    final m = (t.inMinutes % 60).toString().padLeft(2, '0');
    final s = (t.inSeconds % 60).toString().padLeft(2, '0');
    return '${t.inHours}:$m:$s';
  }
  final m = t.inMinutes;
  final s = (t.inSeconds % 60).toString().padLeft(2, '0');
  if (t.inSeconds >= 10) return '$m:$s';
  final tenths = (t.inMilliseconds ~/ 100) % 10;
  return '$m:$s.$tenths';
}
