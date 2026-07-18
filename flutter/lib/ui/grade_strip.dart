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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF262421),
      child: content,
    );
  }
}
