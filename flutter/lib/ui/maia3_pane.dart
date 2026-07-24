// The moves-by-rating panel (#221): for the position on the board, how often
// real players at each rating pick each candidate move — Maia-3's answer to
// "is your move normal for your level?". One line per move across the ELO
// ladder (600..2600), labelled at the right edge.
//
// This is a HUMAN panel, not an engine one: the curves are predicted human
// popularity, and the WDL behind them is "outcome given human play", never
// objective eval. It still shows candidate moves, so blind mode gates it
// exactly like Lines/Tree/Book.
//
// The idea and the batched-ladder architecture credit flawchess; the
// implementation (including the label spreading) is our own — their repo is
// AGPL and stays unread here.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/maia3_api.dart';
import '../stores/game_controller.dart';
import '../stores/maia3_store.dart';

/// Prospective: curves for the position on the board now — "what might I
/// play?". Retrospective: curves for the position BEFORE the last move
/// actually played — "was what I just played normal?" — with that move
/// pinned on the chart even if it isn't in the top-5 by peak popularity.
enum Maia3Mode { prospective, retrospective }

class Maia3Pane extends StatefulWidget {
  const Maia3Pane({super.key});

  @override
  State<Maia3Pane> createState() => _Maia3PaneState();
}

class _Maia3PaneState extends State<Maia3Pane> {
  String? _asked;
  Maia3Mode _mode = Maia3Mode.prospective;

  @override
  void initState() {
    super.initState();
    // Opening the panel is the moment to pay the ~6MB download, so the first
    // position's curves come up in the pause between opening and looking.
    if (Maia3Store.supported) context.read<Maia3Store>().warmUp();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final store = context.watch<Maia3Store>();

    if (!Maia3Store.supported) {
      return const _Note(
          'Maia needs more memory than this browser allows. '
          'The chart works in the desktop app and on desktop browsers.');
    }
    if (game.blind && game.botEnabled && !game.gameOver) {
      return const _Note('Blind mode — no move help until the game ends.');
    }

    final lastPlayed = _lastPlayerMove(game);
    final retro = _mode == Maia3Mode.retrospective;
    final fen = retro ? lastPlayed?.fenBefore : game.displayFen;

    if (fen != null && _asked != fen) {
      _asked = fen;
      // Post-frame: setPosition notifies synchronously and this is build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) store.setPosition(fen);
      });
    }

    final curves = fen != null ? store.curves : null;
    final children = <Widget>[
      _ModeToggle(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
      if (retro && lastPlayed == null)
        const _Note('Play a move to see it here.')
      else ...[
        if (curves != null && store.shownFen != null)
          Maia3ChartCanvas(
            curves: curves,
            stale: store.shownFen != fen,
            playedSan: retro ? lastPlayed?.san : null,
          ),
        if (store.failed)
          const _Note('Maia couldn’t answer — it will try again '
              'on the next move.')
        else if (curves == null)
          _Note(_pendingLine(store)),
        if (curves != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
            child: Text(
              // failed suppresses "Asking…": the note above already says it
              // gave up, and saying both at once reads as a contradiction
              (store.loading || store.shownFen != fen) && !store.failed
                  ? 'Asking Maia…'
                  : retro
                      ? 'How the move you played compares, by rating · Maia-3'
                      : 'How often humans play each move, by rating · Maia-3',
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ),
      ],
    ];
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  /// The most recent move belonging to the human, at or before the browse
  /// cursor — same "whose move counts" rule as [GameController.lastPlayerGrade]
  /// (skip the bot's replies; show every move in bot-vs-bot or no-bot games),
  /// but bounded by [GameController.browsePly] so browsing history moves the
  /// answer too, not just live play. Without this, playing a move against an
  /// auto-replying bot would immediately reattribute "Played" to the BOT'S
  /// reply — the position one ply later — rather than the human's move.
  MoveRecord? _lastPlayerMove(GameController game) {
    for (var i = game.browsePly - 1; i >= 0; i--) {
      final m = game.moves[i];
      if (!game.botEnabled || game.botBothSides || m.color == game.playerColor) {
        return m;
      }
    }
    return null;
  }

  String _pendingLine(Maia3Store store) {
    final p = store.progress;
    if (p != null && p.phase == 'fetching' && p.total > 0) {
      final pct = (p.received / p.total * 100).clamp(0, 100).round();
      return 'Downloading Maia-3… $pct%';
    }
    if (p != null && p.phase == 'starting') return 'Starting Maia-3…';
    return 'Asking Maia…';
  }
}

/// Two-way switch between prospective ("Now") and retrospective ("Played")
/// chart data — see [Maia3Mode].
class _ModeToggle extends StatelessWidget {
  final Maia3Mode mode;
  final ValueChanged<Maia3Mode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment('Now', Maia3Mode.prospective),
          const SizedBox(width: 4),
          _segment('Played', Maia3Mode.retrospective),
        ],
      ),
    );
  }

  Widget _segment(String label, Maia3Mode value) {
    final active = mode == value;
    // The visual pill stays small (it sits in a dense chart header), but the
    // tappable area is padded out to a real touch target — ~19px of pill
    // alone is a mis-tap risk on a phone.
    return GestureDetector(
      onTap: () => onChanged(value),
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: active ? Colors.white12 : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: active ? Colors.white24 : Colors.white10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: active ? Colors.white70 : Colors.white30,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(14),
        child: Text(text,
            style: const TextStyle(color: Colors.white38, fontSize: 13)),
      );
}

/// The chart on its own: popularity (0..100%) against rating (600..2600),
/// one polyline per shown move, SAN labels spread apart at the right edge.
/// Hovering (or, on touch, dragging a finger across it) drops a scrubber
/// line pinned to the nearest ELO rung, highlighting that rung's top move.
class Maia3ChartCanvas extends StatefulWidget {
  final Maia3MoveCurves curves;

  /// True while these curves belong to a position the board has already left
  /// — drawn dimmed rather than blanked, so browsing doesn't flicker.
  final bool stale;

  /// In retrospective mode, the SAN of the move actually played from this
  /// position — pinned on the chart (forced into the drawn set, styled
  /// distinctly) even if it isn't among the top-5 by peak popularity.
  final String? playedSan;

  const Maia3ChartCanvas({
    super.key,
    required this.curves,
    this.stale = false,
    this.playedSan,
  });

  @override
  State<Maia3ChartCanvas> createState() => _Maia3ChartCanvasState();
}

class _Maia3ChartCanvasState extends State<Maia3ChartCanvas> {
  int? _hoverElo;

  void _updateHover(Offset local, Size size) {
    final elo = Maia3ChartPainter.eloAtX(widget.curves, size, local.dx);
    if (elo != _hoverElo) setState(() => _hoverElo = elo);
  }

  void _clearHover() {
    if (_hoverElo != null) setState(() => _hoverElo = null);
  }

  @override
  void didUpdateWidget(covariant Maia3ChartCanvas old) {
    super.didUpdateWidget(old);
    // A new position's curves invalidate whatever rung was under the cursor.
    if (old.curves != widget.curves) _hoverElo = null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: SizedBox(
        height: 160,
        child: Opacity(
          opacity: widget.stale ? 0.45 : 1,
          child: LayoutBuilder(builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return MouseRegion(
              onExit: (_) => _clearHover(),
              child: Listener(
                onPointerHover: (e) => _updateHover(e.localPosition, size),
                onPointerDown: (e) => _updateHover(e.localPosition, size),
                onPointerMove: (e) => _updateHover(e.localPosition, size),
                onPointerUp: (_) => _clearHover(),
                onPointerCancel: (_) => _clearHover(),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: Maia3ChartPainter(
                    widget.curves,
                    playedSan: widget.playedSan,
                    hoverElo: _hoverElo,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

const double _kGutterL = 26; // y-axis labels
const double _kGutterR = 46; // move labels
const double _kGutterB = 14; // x-axis labels

/// Up to this many moves are drawn: the ones with the highest peak
/// popularity anywhere on the ladder. More is spaghetti.
const int _kMaxMoves = 5;

/// Chesscom-ish categorical palette, distinct on the dark panel.
const List<Color> _kLineColors = [
  Color(0xFF81B64C), // green
  Color(0xFF5AA3D8), // blue
  Color(0xFFE2B93B), // yellow
  Color(0xFFD4674A), // red-orange
  Color(0xFFB08CD6), // violet
];

class Maia3ChartPainter extends CustomPainter {
  final Maia3MoveCurves curves;

  /// See [Maia3ChartCanvas.playedSan].
  final String? playedSan;

  /// The ELO rung under the cursor, or null when nothing is being hovered.
  final int? hoverElo;

  Maia3ChartPainter(this.curves, {this.playedSan, this.hoverElo});

  /// The moves worth a line, ordered by peak popularity so the palette's
  /// strongest colors go to the strongest moves. [forceInclude] — the played
  /// move in retrospective mode — is guaranteed a line even if it never
  /// peaks in the top 5, bumping the weakest pick to make room.
  @visibleForTesting
  static List<String> pickMoves(Maia3MoveCurves curves,
      {String? forceInclude}) {
    final peak = <String, double>{};
    for (final rung in curves.perElo) {
      rung.moveProbabilities.forEach((san, p) {
        if (p > (peak[san] ?? -1)) peak[san] = p;
      });
    }
    final sans = peak.keys.toList()
      ..sort((a, b) => peak[b]!.compareTo(peak[a]!));
    final picked = sans.take(_kMaxMoves).toList();
    if (forceInclude != null &&
        peak.containsKey(forceInclude) &&
        !picked.contains(forceInclude)) {
      if (picked.length >= _kMaxMoves) picked.removeLast();
      picked.add(forceInclude);
    }
    return picked;
  }

  /// The ELO rung nearest horizontal position [dx] in a chart painted at
  /// [size], or null if there's nothing to snap to (no rungs, no width).
  @visibleForTesting
  static int? eloAtX(Maia3MoveCurves curves, Size size, double dx) {
    final rungs = curves.perElo;
    if (rungs.isEmpty) return null;
    final plotW = size.width - _kGutterL - _kGutterR;
    if (plotW <= 0) return null;
    final eloLo = rungs.first.elo.toDouble();
    final eloHi = rungs.last.elo.toDouble();
    final eloSpan = (eloHi - eloLo).clamp(1, double.infinity);
    final frac = ((dx - _kGutterL) / plotW).clamp(0.0, 1.0);
    final target = eloLo + frac * eloSpan;
    var best = rungs.first.elo;
    var bestDist = (rungs.first.elo - target).abs();
    for (final r in rungs) {
      final dist = (r.elo - target).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = r.elo;
      }
    }
    return best;
  }

  /// Spreads label centers at least [minGap] apart inside [lo]..[hi],
  /// preserving order — the flawchess-style de-collision, written from the
  /// same column-separation idea LinesTreeModel already uses.
  @visibleForTesting
  static List<double> spreadLabels(
      List<double> desired, double minGap, double lo, double hi) {
    final ys = List<double>.from(desired);
    for (var i = 1; i < ys.length; i++) {
      if (ys[i] - ys[i - 1] < minGap) ys[i] = ys[i - 1] + minGap;
    }
    final overflow = ys.isEmpty ? 0.0 : ys.last - hi;
    if (overflow > 0) {
      for (var i = 0; i < ys.length; i++) {
        ys[i] -= overflow;
      }
      for (var i = ys.length - 2; i >= 0; i--) {
        if (ys[i + 1] - ys[i] < minGap) ys[i] = ys[i + 1] - minGap;
      }
    }
    return [for (final y in ys) y.clamp(lo, hi)];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rungs = curves.perElo;
    if (rungs.isEmpty) return;
    final plotW = size.width - _kGutterL - _kGutterR;
    final plotH = size.height - _kGutterB;
    final eloLo = rungs.first.elo.toDouble();
    final eloHi = rungs.last.elo.toDouble();
    final eloSpan = (eloHi - eloLo).clamp(1, double.infinity);

    double xFor(num elo) => _kGutterL + plotW * (elo - eloLo) / eloSpan;
    double yFor(double p) => plotH * (1 - p);

    // y axis: 100 / 50 / 0
    for (final (frac, text) in [(0.0, '100%'), (0.5, '50%'), (1.0, '0%')]) {
      final y = plotH * frac;
      canvas.drawLine(
        Offset(_kGutterL, y),
        Offset(size.width - _kGutterR, y),
        Paint()
          ..color = frac == 0.5 ? Colors.white12 : Colors.white10
          ..strokeWidth = 1,
      );
      _text(canvas, text, Offset(0, y - 5), align: null);
    }

    // x axis: endpoints and midpoint — stepping 500 from 600 gave 1100/2100,
    // which read as odd tick values rather than a rating scale
    for (final elo in {eloLo, (eloLo + eloHi) / 2, eloHi}) {
      _text(canvas, elo.round().toString(), Offset(xFor(elo), plotH + 2),
          align: 'center');
    }

    // the lines
    final sans = pickMoves(curves, forceInclude: playedSan);
    final endYs = <double>[];
    for (var m = 0; m < sans.length; m++) {
      final san = sans[m];
      final color = _kLineColors[m % _kLineColors.length];
      final isPlayed = san == playedSan;
      final path = Path();
      var started = false;
      var lastY = 0.0;
      for (final rung in rungs) {
        final p = rung.moveProbabilities[san] ?? 0;
        final o = Offset(xFor(rung.elo), yFor(p));
        if (!started) {
          path.moveTo(o.dx, o.dy);
          started = true;
        } else {
          path.lineTo(o.dx, o.dy);
        }
        lastY = o.dy;
      }
      // The played move gets a white halo underneath so it reads as
      // "the" line even when its own color is faint against the others.
      if (isPlayed) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeJoin = StrokeJoin.round,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPlayed ? 2.4 : 1.8
          ..strokeJoin = StrokeJoin.round,
      );
      endYs.add(lastY);
    }

    // labels at the right edge, spread apart, with a short leader when a
    // label had to move off its line
    final order = List<int>.generate(sans.length, (i) => i)
      ..sort((a, b) => endYs[a].compareTo(endYs[b]));
    final spread = spreadLabels(
        [for (final i in order) endYs[i]], 12, 5, plotH - 5);
    for (var k = 0; k < order.length; k++) {
      final i = order[k];
      final color = _kLineColors[i % _kLineColors.length];
      final labelY = spread[k];
      final endX = size.width - _kGutterR;
      if ((labelY - endYs[i]).abs() > 1) {
        canvas.drawLine(
          Offset(endX, endYs[i]),
          Offset(endX + 4, labelY),
          Paint()
            ..color = color.withValues(alpha: 0.5)
            ..strokeWidth = 1,
        );
      }
      final labelAt = Offset(endX + 6, labelY - 6);
      if (sans[i] == playedSan) {
        // A small filled swatch marks the played move's label — the halo on
        // its line already sets it apart, this carries that to the legend.
        canvas.drawCircle(labelAt.translate(-4, 5), 2.5, Paint()..color = color);
        _text(canvas, sans[i], labelAt.translate(4, 0), color: color);
      } else {
        _text(canvas, sans[i], labelAt, color: color);
      }
    }

    // scrubber: a vertical line pinned to the hovered rung, with a
    // highlighted dot on its top (argmax) move and that move's read-out.
    if (hoverElo != null) {
      Maia3RungCurve? hoverRung;
      for (final r in rungs) {
        if (r.elo == hoverElo) {
          hoverRung = r;
          break;
        }
      }
      if (hoverRung != null) {
        final x = xFor(hoverElo!);
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, plotH),
          Paint()
            ..color = Colors.white30
            ..strokeWidth = 1,
        );
        _text(canvas, hoverElo.toString(), Offset(x, plotH + 2),
            align: 'center', color: Colors.white70);

        String? topSan;
        var topP = -1.0;
        for (final san in sans) {
          final p = hoverRung.moveProbabilities[san] ?? 0;
          if (p > topP) {
            topP = p;
            topSan = san;
          }
        }
        for (var m = 0; m < sans.length; m++) {
          final san = sans[m];
          final color = _kLineColors[m % _kLineColors.length];
          final p = hoverRung.moveProbabilities[san] ?? 0;
          final y = yFor(p);
          final isTop = san == topSan;
          canvas.drawCircle(
              Offset(x, y), isTop ? 4.5 : 2, Paint()..color = isTop ? Colors.white : color);
          if (isTop) {
            canvas.drawCircle(
                Offset(x, y),
                4.5,
                Paint()
                  ..color = color
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.5);
          }
        }
        if (topSan != null) {
          final topY = yFor(topP).clamp(14.0, plotH - 4);
          final atRight = x > plotW * 0.6 + _kGutterL;
          final label = '$topSan ${(topP * 100).round()}%';
          final tp = TextPainter(
            text: TextSpan(
                text: label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600)),
            textDirection: TextDirection.ltr,
          )..layout();
          final labelX = atRight ? x - 6 - tp.width : x + 6;
          tp.paint(canvas, Offset(labelX, topY - 14));
        }
      }
    }
  }

  void _text(Canvas canvas, String s, Offset at,
      {String? align, Color? color}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: color ?? Colors.white24,
              fontSize: 9,
              fontWeight: color != null ? FontWeight.w600 : null)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas, align == 'center' ? at.translate(-tp.width / 2, 0) : at);
  }

  @override
  bool shouldRepaint(Maia3ChartPainter old) =>
      old.curves != curves ||
      old.playedSan != playedSan ||
      old.hoverElo != hoverElo;
}
