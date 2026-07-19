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

  /// Icon stand-ins for the three glyphs no bundled font contains.
  ///
  /// The brain ships `★` best, `✔` excellent, `✓` good (classifications.ts).
  /// None is in Roboto, so drawing them made Flutter web fetch a Noto face
  /// from fonts.gstatic.com — on the verdict line under the board, i.e. on
  /// every graded move. That is a third-party request, and unservable on a
  /// cold offline start.
  ///
  /// The other six (`‼ ! ?! ? × ??`) are Roboto-covered and stay as text.
  /// Substituting on THIS side rather than in classifications.ts leaves the
  /// Svelte app's rendering alone, where browser fallback fonts have them.
  static const Map<String, IconData> _iconGlyphs = {
    'best': Icons.star,
    'excellent': Icons.done_all,
    'good': Icons.check,
  };

  /// The label's mark, as an inline span: an icon where Roboto has no glyph,
  /// plain text otherwise. Callers use `Text.rich` so the noun beside it keeps
  /// the normal font.
  InlineSpan glyphSpan(String label, {double size = 13, Color? color}) {
    final icon = _iconGlyphs[label];
    if (icon == null) return TextSpan(text: glyph(label));
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Icon(icon, size: size, color: color ?? this.color(label)),
    );
  }

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
            Text.rich(
                TextSpan(children: [
                  table.glyphSpan(label, size: 14),
                  TextSpan(text: ' ${table.noun(label)}'),
                ]),
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
