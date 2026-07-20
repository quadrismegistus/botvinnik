// The insight card: the latest graded player move with its label chip,
// win-chance context, and the brain's explanation prose — the web
// InsightsPanel's core card, phone-sized.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/types.dart';
import '../engine/maia_progress.dart';
import '../stores/game_controller.dart';
import 'grade_strip.dart';

class InsightCard extends StatelessWidget {
  const InsightCard({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final table = context.read<ClassTable>();

    // Loading wins: a heavy engine (Maia/retro/Garbo) is still compiling, and
    // until it does there is nothing to grade or play. This used to be the one
    // always-visible slot under the board; that strip is gone (the board took
    // its height), so the card is the slot now.
    final loading = game.maiaProgress;
    if (loading != null) {
      return _CardShell(
          child: _loadingLine(loading, game.persona?.name ?? 'Maia'));
    }

    final grade = game.lastPlayerGrade;
    final threat = _threat(game);

    if (grade == null) {
      return _CardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Play a move — its grade and what the engine thinks appear here.',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
            if (threat != null) ...[const SizedBox(height: 10), threat],
          ],
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

    if (threat != null) {
      children.add(Padding(padding: const EdgeInsets.only(top: 10), child: threat));
    }

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// What the board's red arrow is threatening, as a chip — the board already
  /// worked this out to decide whether to draw the arrow, so this only names
  /// it. Hidden while browsing or previewing, where the live overlays are off
  /// and a warning about the current position would contradict what is shown.
  Widget? _threat(GameController game) {
    if (game.browsing || game.previewing) return null;
    final san = game.threatSan;
    if (san == null) return null;
    final gain = game.threatGain;
    // null gain is mate: the brain reports Infinity, which JSON cannot carry
    final cost = gain == null
        ? 'mate'
        : 'costs ${gain.abs().toStringAsFixed(gain.abs() >= 10 ? 0 : 1)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1FC62828),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 15, color: Color(0xFFE0908E)),
          const SizedBox(width: 8),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Threat: '),
              TextSpan(
                  text: san,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            style: const TextStyle(
                color: Color(0xFFE0908E),
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(cost,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  /// What a Maia is doing before it can play: a determinate bar while its
  /// weights download, an indeterminate one while the WebAssembly compiles.
  /// Compiling ~13MB is the longest single part of the wait and reports
  /// nothing, so a bar that fills and stops would look more broken than none.
  Widget _loadingLine(MaiaProgress p, String name) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(p.describe(name),
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: p.fraction, // null → indeterminate, which is honest
              minHeight: 3,
              backgroundColor: const Color(0xFF3a3733),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFFb06f8a)),
            ),
          ),
          const SizedBox(height: 4),
          Text(p.reassurance,
              style: const TextStyle(color: Colors.white30, fontSize: 10.5)),
        ],
      );

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
      child: Text.rich(
        TextSpan(children: [
          table.glyphSpan(label, size: 12, color: color),
          TextSpan(text: ' ${table.noun(label)}'),
        ]),
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
