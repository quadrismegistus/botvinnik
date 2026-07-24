// The insight card: the latest graded player move with its label chip, the
// win chance it gave away, that move against the engine's on a miniature
// board, and the brain's explanation prose — the web InsightsPanel's core
// card, phone-sized.

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/types.dart';
import '../engine/maia_progress.dart';
import '../stores/game_controller.dart';
import '../stores/practice_controller.dart';
import 'board_theme.dart';
import 'grade_strip.dart';
import 'move_preview.dart';

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

    // Refusal mode (#167) just rejected an attempted move — this overrides
    // whatever the card would otherwise show (the LAST committed move's
    // grade, or the empty placeholder) rather than living inside either
    // branch below: a refusal can happen at any point in the game, not only
    // when there is no grade yet to display.
    final refusal = game.refusalMessage;
    if (refusal != null) {
      return _CardShell(
        child: Text(refusal,
            style: TextStyle(color: table.color('blunder'), fontSize: 13)),
      );
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
    // Two lines you can watch on the board, two buttons — not one that silently
    // means different things (#164). The card says "Best was Nc6" and draws it,
    // so the obvious control has to BE "show me Nc6"; that is the BEST line
    // (`grade.bestPv`, from the pre-move position). The other line is the one
    // the explanation is built on — the move you PLAYED and its refutation
    // (`evidence['ucis']`, which explain.ts builds from playedPv) — worth
    // watching too, but only as its own labelled control, never as the default.
    //
    // Each appears only when its line exists: a good move has no refutation to
    // show (evidence null), and a move with no better alternative has an empty
    // bestPv. They carry distinct `previewTag`s so they coordinate with the
    // threat chip's own play control through `previewing` — an untagged pair
    // would each show STOP while the other was the line actually running.
    final evidence = expl?.evidence;
    final bestPv = grade.bestPv;
    final evidenceUcis = evidence != null
        ? (evidence['ucis'] as List).cast<String>()
        : const <String>[];

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
        ],
      ),
    ];

    // The two play controls, on their own line so a label can sit beside each
    // arrow — the header row has no room, and two bare arrows there would be
    // exactly the "which one is this?" the single button already was. Wrapped,
    // so at 320pt the second button drops to a new line rather than overflowing.
    // Colours echo the preview board's grammar (#29): BLUE is the engine's move
    // everywhere in this app, RED is the move that cost you.
    final controls = <Widget>[
      if (bestPv.isNotEmpty)
        _lineButton(game,
            tag: 'best',
            label: 'Best line',
            base: grade.fenBefore,
            ucis: bestPv,
            accent: kEngineArrowBlue),
      if (evidenceUcis.isNotEmpty)
        _lineButton(game,
            tag: 'played',
            label: 'Your move',
            base: evidence!['fen'] as String? ?? grade.fenBefore,
            ucis: evidenceUcis,
            accent: kThreatArrowRed),
    ];
    if (controls.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 6, runSpacing: 4, children: controls),
      ));
    }

    // The evidence for the chip. The label IS this number thresholded, and the
    // same number decides whether the move becomes a practice puzzle — so
    // withholding it left the card asserting a verdict and keeping its
    // reasons. Absent until the grade is backfilled; see [lastGradeWinChance].
    final wc = game.lastGradeWinChance;
    if (wc != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: _winChanceLine(wc, label == null ? null : table.color(label)),
      ));
    }

    // Directly under that number, the verdict it decides: whether the move just
    // became a practice puzzle. Pairing the two is what makes the collect
    // threshold legible — you watch a loss cross it and the line appears,
    // rather than discovering the puzzle later with no memory of the position.
    final collected = game.lastGradeCollectOutcome;
    if (collected != null) {
      final line = _practiceLine(collected);
      if (line != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: line,
        ));
      }
    }

    if (!grade.isBest) {
      final arrows = MovePreview.arrowsFor(grade.uci, grade.bestUci);
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: arrows == null
            // no board to draw (see [MovePreview.arrowsFor]): the sentence it
            // would have replaced, unchanged
            ? Text(
                'Best was ${grade.bestSan}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              )
            : MovePreview(
                fen: grade.fenBefore,
                played: arrows.$1,
                best: arrows.$2,
                playedSan: grade.san,
                bestSan: grade.bestSan,
                // the mover's own side. In an ordinary game against a bot that
                // is the player's, so it agrees with the board above unless
                // they have flipped it by hand.
                orientation: grade.color == 'w' ? Side.white : Side.black,
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

  /// One of the header's play controls: an arrow-plus-label that animates [ucis]
  /// from [base] on the live board, toggling to STOP while it is the running
  /// line. [tag] keeps it and the threat chip from both claiming STOP; [accent]
  /// is the resting colour, green while active (the app's playback colour).
  Widget _lineButton(
    GameController game, {
    required String tag,
    required String label,
    required String base,
    required List<String> ucis,
    required Color accent,
  }) {
    final active = game.previewTag == tag;
    final color = active ? const Color(0xFF81B64C) : accent;
    return InkWell(
      onTap: () =>
          active ? game.stopPreview() : game.startPreview(base, ucis, tag: tag),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  /// The win-chance drop, with the two figures it is the difference of.
  ///
  /// One decimal on the loss and none on the endpoints, so "12.4%" and
  /// "71% to 59%" can differ by a tenth: the loss is the load-bearing figure
  /// (the label's thresholds are 5 / 10 / 20 and practice collects at 5), and
  /// rounding it to a whole number would put a move either side of a threshold
  /// it is not on. The endpoints are context and do not need the precision.
  Widget _winChanceLine(
      ({double before, double after, double drop}) wc, Color? tone) {
    // A move that LOST nothing does not say "lost 0.0%". The drop is clamped at
    // zero, but the endpoints are printed raw — and the deeper backfill eval
    // routinely lands above the pre-move best, so the played-best case read
    // "Win chance lost 0.0% · 70% to 74%": a loss of nothing beside two numbers
    // that went up. Say what happened instead.
    final gained = wc.after > wc.before;
    return Text.rich(
      TextSpan(children: [
        if (wc.drop <= 0 && gained) ...[
          const TextSpan(text: 'Win chance held · '),
          TextSpan(
            text: '${wc.before.round()}% to ${wc.after.round()}%',
            style: TextStyle(
                color: tone ?? Colors.white70, fontWeight: FontWeight.w700),
          ),
        ] else ...[
          const TextSpan(text: 'Win chance lost '),
          TextSpan(
            text: '${wc.drop.toStringAsFixed(1)}%',
            style: TextStyle(
                color: tone ?? Colors.white70, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' · ${wc.before.round()}% to ${wc.after.round()}%'),
        ],
      ]),
      style: const TextStyle(color: Colors.white38, fontSize: 12),
    );
  }

  /// The practice verdict as one small line, carrying the Practice tab's own
  /// glyph so the connection to where the puzzle went is visual, not just
  /// worded. [CollectOutcome.notEligible] draws nothing — a move that gave away
  /// too little to drill needs no note; its absence from the collection is the
  /// default, and saying "not added" under every accurate move is noise.
  Widget? _practiceLine(CollectOutcome outcome) {
    switch (outcome) {
      case CollectOutcome.added:
        return _practiceRow(
          'Added to practice',
          const Color(0xFF8AA9C4), // a calm slate, not the engine/threat hues
          Icons.fitness_center,
        );
      case CollectOutcome.duplicate:
        return _practiceRow(
          'Already in your practice queue',
          Colors.white38,
          Icons.fitness_center_outlined,
        );
      case CollectOutcome.notEligible:
        return null;
    }
  }

  Widget _practiceRow(String text, Color color, IconData icon) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 7),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );

  /// What the board's red arrow is threatening, as a chip — the board already
  /// worked this out to decide whether to draw the arrow, so this only names
  /// it. Hidden while browsing or previewing, where the live overlays are off
  /// and a warning about the current position would contradict what is shown.
  Widget? _threat(GameController game) {
    // Hidden while browsing, or while the OTHER preview runs: a live-threat
    // claim under a historical position contradicts what the board is showing.
    // Its OWN preview is the exception — that line IS the threat, and the chip
    // carries the stop button, so hiding it there would strand the playback.
    if (game.browsing) return null;
    if (game.previewing && game.previewTag != 'threat') return null;
    final san = game.threatSan;
    if (san == null) return null;
    // Verbal first: the brain names what the free move DOES (a fork, a capture,
    // a mate) by pointing the move explainers at the null-move probe. That
    // sentence already carries the SAN and the point, so it replaces the bare
    // "Threat: Be6 costs 1.0" outright rather than sitting beside it. Only a
    // victimless gain, which names no piece, falls through to the number.
    final prose = game.threatProse;
    final Widget headline;
    if (prose != null) {
      headline = Expanded(
        child: Text(prose,
            style: const TextStyle(
                color: Color(0xFFE0908E),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3)),
      );
    } else {
      final gain = game.threatGain;
      // null gain is mate: the brain reports Infinity, which JSON cannot carry
      final cost = gain == null
          ? 'mate'
          : 'costs ${gain.abs().toStringAsFixed(gain.abs() >= 10 ? 0 : 1)}';
      headline = Expanded(
        child: Row(
          children: [
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Threat: '),
                  TextSpan(
                      text: san,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFFE0908E),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(cost,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      );
    }
    final line = game.threatLine;
    final base = game.threatProbeFen;
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
          headline,
          const SizedBox(width: 8),
          // play the line the threat is judged on, so the words become
          // something you can watch rather than a claim you have to take
          if (line.isNotEmpty && base != null)
            InkWell(
              onTap: () => game.previewTag == 'threat'
                  ? game.stopPreview()
                  : game.startPreview(base, line, tag: 'threat'),
              borderRadius: BorderRadius.circular(14),
              child: Icon(
                game.previewTag == 'threat'
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline,
                size: 20,
                color: game.previewTag == 'threat'
                    ? const Color(0xFF81B64C)
                    : const Color(0xFFE0908E),
              ),
            ),
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
