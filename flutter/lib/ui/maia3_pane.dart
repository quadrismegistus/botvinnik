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

class Maia3Pane extends StatefulWidget {
  const Maia3Pane({super.key});

  @override
  State<Maia3Pane> createState() => _Maia3PaneState();
}

class _Maia3PaneState extends State<Maia3Pane> {
  String? _asked;

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

    final fen = game.displayFen;
    if (_asked != fen) {
      _asked = fen;
      // Post-frame: setPosition notifies synchronously and this is build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) store.setPosition(fen);
      });
    }

    final curves = store.curves;
    final children = <Widget>[
      if (curves != null && store.shownFen != null)
        Maia3ChartCanvas(curves: curves, stale: store.shownFen != fen),
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
                : 'How often humans play each move, by rating · Maia-3',
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ),
    ];
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
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
class Maia3ChartCanvas extends StatelessWidget {
  final Maia3MoveCurves curves;

  /// True while these curves belong to a position the board has already left
  /// — drawn dimmed rather than blanked, so browsing doesn't flicker.
  final bool stale;

  const Maia3ChartCanvas({super.key, required this.curves, this.stale = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: SizedBox(
        height: 160,
        child: Opacity(
          opacity: stale ? 0.45 : 1,
          child: CustomPaint(
            size: Size.infinite,
            painter: Maia3ChartPainter(curves),
          ),
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
  Maia3ChartPainter(this.curves);

  /// The moves worth a line, ordered by peak popularity so the palette's
  /// strongest colors go to the strongest moves.
  @visibleForTesting
  static List<String> pickMoves(Maia3MoveCurves curves) {
    final peak = <String, double>{};
    for (final rung in curves.perElo) {
      rung.moveProbabilities.forEach((san, p) {
        if (p > (peak[san] ?? -1)) peak[san] = p;
      });
    }
    final sans = peak.keys.toList()
      ..sort((a, b) => peak[b]!.compareTo(peak[a]!));
    return sans.take(_kMaxMoves).toList();
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
    final sans = pickMoves(curves);
    final endYs = <double>[];
    for (var m = 0; m < sans.length; m++) {
      final san = sans[m];
      final color = _kLineColors[m % _kLineColors.length];
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
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
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
      _text(canvas, sans[i], Offset(endX + 6, labelY - 6), color: color);
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
  bool shouldRepaint(Maia3ChartPainter old) => old.curves != curves;
}
