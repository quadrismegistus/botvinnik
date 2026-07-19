// The one-line verdict under the board: last player move, its glyph + noun
// (colored per the brain's CLASS table), and % of best. The web app's
// grade-strip, phone-sized.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';

/// The brain's CLASS table {label: {glyph, color, noun}}, provided at boot.
class ClassTable {
  final Map<String, dynamic> raw;
  const ClassTable(this.raw);

  String glyph(String label) => (raw[label]?['glyph'] as String?) ?? '';
  String noun(String label) => (raw[label]?['noun'] as String?) ?? label;
  Color color(String label) {
    final hex = raw[label]?['color'] as String?;
    if (hex == null || !hex.startsWith('#')) return Colors.white70;
    final v = int.parse(hex.substring(1), radix: 16);
    return Color(0xFF000000 | v);
  }
}

class GradeStrip extends StatelessWidget {
  const GradeStrip({super.key});

  /// Says what the red arrow is actually threatening. The app already worked
  /// this out to decide whether to draw the arrow at all — it just used to
  /// throw the answer away, leaving a warning with no explanation.
  Widget? _threatLine(GameController game) {
    // the board hides its overlays while browsing/previewing — a strip line
    // asserting a live threat under a historical position would contradict it
    if (game.browsing || game.previewing) return null;
    final san = game.threatSan;
    if (san == null) return null;
    final gain = game.threatGain;
    // null gain means mate: the brain reports Infinity and JSON cannot carry it
    final cost = gain == null
        ? 'mates'
        : 'costs ${gain.abs().toStringAsFixed(gain.abs() >= 10 ? 0 : 1)}';
    return Row(
      children: [
        const Icon(Icons.warning_amber_rounded,
            size: 13, color: Color(0xFFC62828)),
        const SizedBox(width: 5),
        Text('threat: $san',
            style: const TextStyle(
                color: Color(0xFFE0908E),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Text(cost,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final table = context.read<ClassTable>();
    final grade = game.lastPlayerGrade;

    Widget content;
    if (grade == null) {
      content = Text(
        game.moves.isEmpty
            ? 'your moves are graded as you play'
            : 'grading…',
        style: const TextStyle(color: Colors.white38, fontSize: 13),
      );
    } else {
      final label = grade.label;
      content = Row(
        children: [
          Text(grade.san,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(width: 8),
          if (label != null)
            Text('${table.glyph(label)} ${table.noun(label)}',
                style: TextStyle(
                    color: table.color(label),
                    fontWeight: FontWeight.w600,
                    fontSize: 14))
          else
            const Text('grading…',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          const Spacer(),
          if (grade.pctBest != null)
            Text('${grade.pctBest!.round()}% of best',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      );
    }

    final threat = _threatLine(game);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF262421),
      child: threat == null
          ? content
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [content, const SizedBox(height: 4), threat],
            ),
    );
  }
}
