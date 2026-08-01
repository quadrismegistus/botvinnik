import 'chess_clock.dart' show ElapsedSource;

/// How long the side to move has spent on the move it is about to play.
///
/// Deliberately independent of [ChessClock]. A clock exists only in a rated
/// game with a time control (`game_controller.dart`, `_clock = rated &&
/// timeControl != null ? ... : null`), which is a minority of games — and "how
/// long did that take" is worth knowing in all of them. It is also the axis a
/// fixed dashboard cannot ask about: a player can be tactically sound and fall
/// apart under thirty seconds, and nothing in the archive could see that.
///
/// Three things it deliberately does NOT do:
///
///   * It does not know about the clock's increment, or banked time, or flags.
///     It measures wall time in front of a position, which is the question.
///   * It does not keep counting while the app is in the background — see
///     [pause]. Otherwise a game resumed the next morning records an eight-hour
///     think, and the number that was meant to find time trouble finds only
///     that somebody closed a laptop.
///   * It does not guess. After a takeback the elapsed time no longer belongs
///     to any one decision, so [discard] makes the next reading null rather
///     than a number nobody can interpret.
class ThinkTimer {
  ThinkTimer({ElapsedSource? source}) : _now = source ?? _defaultSource();

  static ElapsedSource _defaultSource() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  final ElapsedSource _now;

  /// When the current turn began, or null when nothing is being timed.
  Duration? _origin;

  /// Time already counted for this turn, from before the last [pause].
  Duration _banked = Duration.zero;
  bool _paused = false;

  /// True while a turn is being timed (whether or not it is paused).
  bool get isRunning => _origin != null;

  /// A new turn begins. Any part-timed turn is abandoned.
  void restart() {
    _banked = Duration.zero;
    _paused = false;
    _origin = _now();
  }

  /// Stop counting: the app went to the background, or the window lost focus.
  /// Time already spent still counts, exactly as [ChessClock.pause] banks it.
  void pause() {
    if (_origin == null || _paused) return;
    _banked += _now() - _origin!;
    _paused = true;
  }

  void resume() {
    if (_origin == null || !_paused) return;
    _origin = _now();
    _paused = false;
  }

  /// The elapsed time so far, without stopping. For a reading taken before the
  /// move is applied (the practice collector runs there).
  Duration? peek() {
    final origin = _origin;
    if (origin == null) return null;
    return _paused ? _banked : _banked + (_now() - origin);
  }

  /// The elapsed time for the turn just ended, and stop timing. Null when
  /// nothing was being timed, or when [discard] declared the reading unusable.
  Duration? take() {
    final origin = _origin;
    if (origin == null) return null;
    final spent = _paused ? _banked : _banked + (_now() - origin);
    _origin = null;
    _banked = Duration.zero;
    _paused = false;
    return spent;
  }

  /// Throw away the current reading without producing a number: a takeback, a
  /// redo, or a game loaded mid-way. The next [take] returns null.
  void discard() {
    _origin = null;
    _banked = Duration.zero;
    _paused = false;
  }
}
