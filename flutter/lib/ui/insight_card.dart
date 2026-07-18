// The insight card: the latest graded player move with its label chip,
// win-chance context, and the brain's explanation prose — the web
// InsightsPanel's core card, phone-sized.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/types.dart';
import '../stores/game_controller.dart';
import 'grade_strip.dart';

class InsightCard extends StatelessWidget {
  const InsightCard({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final table = context.read<ClassTable>();
    final grade = game.lastPlayerGrade;

    if (grade == null) {
      return const _CardShell(
        child: Text(
          'Play a move — its grade and what the engine thinks appear here.',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    final label = grade.label;
    final expl = grade.explanation;
    // the line to narrate on the board: the explanation's evidence line
    // (played move + refutation) when there is one, else the best move's pv
    final evidence = expl?.evidence;
    final previewBase = evidence?['fen'] as String? ?? grade.fenBefore;
    final previewUcis = evidence != null
        ? (evidence['ucis'] as List).cast<String>()
        : grade.bestPv;
    final canPreview = previewUcis.isNotEmpty;

    final children = <Widget>[
      Row(
        children: [
          Text(grade.san,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(width: 8),
          if (label != null) _labelChip(label, table),
          const Spacer(),
          if (grade.pctBest != null)
            Text('${grade.pctBest!.round()}%',
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          if (canPreview) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () => game.previewing
                  ? game.stopPreview()
                  : game.startPreview(previewBase, previewUcis),
              borderRadius: BorderRadius.circular(14),
              child: Icon(
                game.previewing
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline,
                size: 22,
                color: game.previewing
                    ? const Color(0xFF81B64C)
                    : Colors.white54,
              ),
            ),
          ],
        ],
      ),
    ];

    if (!grade.isBest) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Best was ${grade.bestSan}',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ));
    }

    final prose = _prose(grade, expl);
    if (prose != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(prose,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.35)),
      ));
    }

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  String? _prose(MoveGrade grade, Explanation? expl) {
    if (expl == null) return null;
    final parts = <String>[
      if (expl.playedIssue != null) expl.playedIssue!,
      if (expl.playedPoint != null) expl.playedPoint!,
      if (expl.bestPoint != null) expl.bestPoint!,
      if (expl.lineStory != null) expl.lineStory!,
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  Widget _labelChip(String label, ClassTable table) {
    final color = table.color(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${table.glyph(label)} ${table.noun(label)}',
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF262421),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
