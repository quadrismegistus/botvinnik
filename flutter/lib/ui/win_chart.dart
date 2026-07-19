// The win-chance chart: White's win probability (0-100%) over the game, one
// dot per graded ply, colored by the move's label. Tap a point to read it.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';
import 'grade_strip.dart';

class WinChart extends StatefulWidget {
  const WinChart({super.key});

  @override
  State<WinChart> createState() => _WinChartState();
}

class _WinChartState extends State<WinChart> {
  int? _selected; // index into points

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final table = context.read<ClassTable>();
    final points = game.chartPoints;

    if (points.length < 2) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text('The chart draws as the game goes.',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }
    final sel =
        _selected != null && _selected! < points.length ? _selected : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: SizedBox(
            height: 140,
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onTapDown: (d) {
                  final w = constraints.maxWidth - _kGutter;
                  final maxPly = points.last.ply.toDouble();
                  var best = 0;
                  var bestDist = double.infinity;
                  for (var i = 0; i < points.length; i++) {
                    final x = _kGutter +
                        w *
                            (points[i].ply - 1) /
                            (maxPly - 1).clamp(1, double.infinity);
                    final dist = (x - d.localPosition.dx).abs();
                    if (dist < bestDist) {
                      bestDist = dist;
                      best = i;
                    }
                  }
                  setState(() => _selected = _selected == best ? null : best);
                },
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _ChartPainter(points, table, sel),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: sel == null
              ? const Text('White win chance · tap a point',
                  style: TextStyle(color: Colors.white24, fontSize: 11))
              : _readout(points[sel], table),
        ),
      ],
    );
  }

  Widget _readout(
      ({int ply, String san, double wc, String? label}) p, ClassTable table) {
    final moveNo = '${(p.ply + 1) ~/ 2}${p.ply.isOdd ? '.' : '…'}';
    final label = p.label;
    return Row(children: [
      Text('$moveNo ${p.san}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      if (label != null) ...[
        const SizedBox(width: 6),
        Text.rich(
            TextSpan(children: [
              table.glyphSpan(label, size: 12),
              TextSpan(text: ' ${table.noun(label)}'),
            ]),
            style: TextStyle(color: table.color(label), fontSize: 12)),
      ],
      const Spacer(),
      Text('${p.wc.toStringAsFixed(0)}% for White',
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }
}

const double _kGutter = 26; // room for the y-axis labels

class _ChartPainter extends CustomPainter {
  final List<({int ply, String san, double wc, String? label})> points;
  final ClassTable table;
  final int? selected;
  _ChartPainter(this.points, this.table, this.selected);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - _kGutter;
    final maxPly = points.last.ply.toDouble();
    Offset toXy(({int ply, String san, double wc, String? label}) p) => Offset(
          _kGutter +
              w * (p.ply - 1) / (maxPly - 1).clamp(1, double.infinity),
          size.height * (1 - p.wc / 100),
        );

    // y axis: 100 / 50 / 0
    for (final (frac, text) in [(0.0, '100%'), (0.5, '50%'), (1.0, '0%')]) {
      final y = size.height * frac;
      canvas.drawLine(
        Offset(_kGutter, y),
        Offset(size.width, y),
        Paint()
          ..color = frac == 0.5 ? Colors.white12 : Colors.white10
          ..strokeWidth = 1,
      );
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: const TextStyle(color: Colors.white24, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(0,
              (y - tp.height / 2).clamp(0, size.height - tp.height)));
    }

    // area fill down to the midline
    final mid = size.height / 2;
    final path = Path()..moveTo(toXy(points.first).dx, toXy(points.first).dy);
    for (final p in points.skip(1)) {
      final o = toXy(p);
      path.lineTo(o.dx, o.dy);
    }
    final fill = Path.from(path)
      ..lineTo(toXy(points.last).dx, mid)
      ..lineTo(toXy(points.first).dx, mid)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0x2281B64C));

    // the line
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // dots, colored by label; the selected point gets a ring
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final o = toXy(p);
      final label = p.label;
      final notable = label != null &&
          const {'blunder', 'mistake', 'miss', 'inaccuracy', 'brilliant', 'great'}
              .contains(label);
      canvas.drawCircle(
        o,
        notable ? 4 : 2,
        Paint()..color = label != null ? table.color(label) : Colors.white38,
      );
      if (i == selected) {
        canvas.drawCircle(
          o,
          7,
          Paint()
            ..color = Colors.white70
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points.length != points.length ||
      old.selected != selected ||
      (points.isNotEmpty &&
          old.points.isNotEmpty &&
          (old.points.last.wc != points.last.wc ||
              old.points.last.label != points.last.label));
}
