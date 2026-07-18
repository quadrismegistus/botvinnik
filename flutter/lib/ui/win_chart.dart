// The win-chance chart: White's win probability over the game, one dot per
// graded ply, colored by the move's label. A thin 50% midline anchors the
// eye; the area under the curve is tinted toward the leading side.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';
import 'grade_strip.dart';

class WinChart extends StatelessWidget {
  const WinChart({super.key});

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: SizedBox(
        height: 140,
        child: CustomPaint(
          size: Size.infinite,
          painter: _ChartPainter(points, table),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<({int ply, String san, double wc, String? label})> points;
  final ClassTable table;
  _ChartPainter(this.points, this.table);

  @override
  void paint(Canvas canvas, Size size) {
    final maxPly = points.last.ply.toDouble();
    Offset toXy(({int ply, String san, double wc, String? label}) p) => Offset(
          size.width * (p.ply - 1) / (maxPly - 1).clamp(1, double.infinity),
          size.height * (1 - p.wc / 100),
        );

    // 50% midline
    final mid = size.height / 2;
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = Colors.white12
        ..strokeWidth = 1,
    );

    // area fill down to the midline
    final path = Path()..moveTo(toXy(points.first).dx, toXy(points.first).dy);
    for (final p in points.skip(1)) {
      final o = toXy(p);
      path.lineTo(o.dx, o.dy);
    }
    final fill = Path.from(path)
      ..lineTo(toXy(points.last).dx, mid)
      ..lineTo(toXy(points.first).dx, mid)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = const Color(0x2281B64C),
    );

    // the line itself
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // dots, colored by label (only notable ones get size)
    for (final p in points) {
      final o = toXy(p);
      final label = p.label;
      final notable = label != null &&
          const {'blunder', 'mistake', 'miss', 'inaccuracy', 'brilliant', 'great'}
              .contains(label);
      canvas.drawCircle(
        o,
        notable ? 4 : 2,
        Paint()
          ..color = label != null ? table.color(label) : Colors.white38,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points.length != points.length ||
      (points.isNotEmpty &&
          old.points.isNotEmpty &&
          (old.points.last.wc != points.last.wc ||
              old.points.last.label != points.last.label));
}
