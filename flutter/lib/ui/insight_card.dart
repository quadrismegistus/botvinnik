// The insight card: the latest graded player move with its label chip, the
// win chance it gave away, that move against the engine's on a miniature
// board, and the brain's explanation prose — the web InsightsPanel's core
// card, phone-sized.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Move, NormalMove, Side;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/types.dart';
import '../engine/maia_progress.dart';
import '../stores/game_controller.dart';
import '../stores/settings_store.dart';
import 'board_theme.dart';
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
            // tagged, because the threat chip has its own play button and both
            // share `previewing` — untagged, each would show STOP while the
            // other one was the line actually running
            InkWell(
              onTap: () => game.previewTag == 'move'
                  ? game.stopPreview()
                  : game.startPreview(previewBase, previewUcis, tag: 'move'),
              borderRadius: BorderRadius.circular(14),
              child: Icon(
                game.previewTag == 'move'
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline,
                size: 22,
                color: game.previewTag == 'move'
                    ? const Color(0xFF81B64C)
                    : Colors.white54,
              ),
            ),
          ],
        ],
      ),
    ];

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

    if (!grade.isBest) {
      final preview = _previewArrows(grade);
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: preview == null
            // no board to draw (see [_previewArrows]): the sentence it would
            // have replaced, unchanged
            ? Text(
                'Best was ${grade.bestSan}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              )
            : _MovePreview(
                fen: grade.fenBefore,
                played: preview.$1,
                best: preview.$2,
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

  /// The win-chance drop, with the two figures it is the difference of.
  ///
  /// One decimal on the loss and none on the endpoints, so "12.4%" and
  /// "71% to 59%" can differ by a tenth: the loss is the load-bearing figure
  /// (the label's thresholds are 5 / 10 / 20 and practice collects at 5), and
  /// rounding it to a whole number would put a move either side of a threshold
  /// it is not on. The endpoints are context and do not need the precision.
  Widget _winChanceLine(
      ({double before, double after, double drop}) wc, Color? tone) {
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'Win chance lost '),
        TextSpan(
          text: '${wc.drop.toStringAsFixed(1)}%',
          style: TextStyle(
              color: tone ?? Colors.white70, fontWeight: FontWeight.w700),
        ),
        TextSpan(text: ' · ${wc.before.round()}% to ${wc.after.round()}%'),
      ]),
      style: const TextStyle(color: Colors.white38, fontSize: 12),
    );
  }

  /// The two moves as board arrows, or null when a board cannot show the
  /// difference between them.
  ///
  /// Refuses two cases. A uci that will not parse — nothing to draw at all.
  /// And two moves with the same origin and destination, which happens on a
  /// promotion where only the piece chosen differs (e7e8q vs e7e8n): the two
  /// arrows would be drawn on the identical line and read as one, so the
  /// sentence naming the piece is the only thing that can say it.
  (NormalMove, NormalMove)? _previewArrows(MoveGrade grade) {
    final played = _normalMove(grade.uci);
    final best = _normalMove(grade.bestUci);
    if (played == null || best == null) return null;
    if (played.from == best.from && played.to == best.to) return null;
    return (played, best);
  }

  NormalMove? _normalMove(String uci) {
    if (uci.length < 4) return null;
    final move = Move.parse(uci);
    // Arrow asserts orig != dest, and a drop move has no origin square at all.
    // Neither can come out of the engine, and both are an assertion failure —
    // i.e. a red screen — rather than a missing arrow if one ever does.
    return move is NormalMove && move.from != move.to ? move : null;
  }

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
    final gain = game.threatGain;
    // null gain is mate: the brain reports Infinity, which JSON cannot carry
    final cost = gain == null
        ? 'mate'
        : 'costs ${gain.abs().toStringAsFixed(gain.abs() >= 10 ? 0 : 1)}';
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
          const Spacer(),
          // play the line the threat is judged on, so "costs 1.0" becomes
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

/// "Best was Nc6" as a picture: the position the move was chosen in, with the
/// move played and the move the engine wanted drawn on it.
///
/// The colours are #29's board grammar rather than the issue's red/green,
/// because that grammar is already on the board six inches above this one:
/// BLUE is the engine's move everywhere in this app (green is taken — it is
/// the control overlay's "your squares"), and RED is the move that costs you.
/// Two arrows, two facts, and nothing else on the squares.
///
/// It shows only what the card's own sentence already says, so it needs no
/// blind-mode gate that the sentence does not have.
class _MovePreview extends StatelessWidget {
  final String fen;
  final NormalMove played;
  final NormalMove best;
  final String playedSan;
  final String bestSan;
  final Side orientation;

  const _MovePreview({
    required this.fen,
    required this.played,
    required this.best,
    required this.playedSan,
    required this.bestSan,
    required this.orientation,
  });

  /// Small enough to leave the legend room at 320pt (the card is ~276pt wide
  /// there), big enough for a piece to be recognisable at 13pt a square.
  static const double _size = 104;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaticChessboard(
          size: _size,
          orientation: orientation,
          fen: fen,
          settings: staticBoardSettingsFor(settings),
          shapes: {
            // Fixed opacity, not the user's arrow/threat sliders. Those exist
            // so the live overlays do not drown a position being played; here
            // the arrows are the entire content, and a slider left low would
            // leave a board with nothing on it.
            Arrow(
                color: kThreatArrowRed.withValues(alpha: 0.85),
                orig: played.from,
                dest: played.to),
            Arrow(
                color: kEngineArrowBlue.withValues(alpha: 0.9),
                orig: best.from,
                dest: best.to),
          },
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _key(kThreatArrowRed, 'Played $playedSan'),
              const SizedBox(height: 6),
              _key(kEngineArrowBlue, 'Best was $bestSan'),
            ],
          ),
        ),
      ],
    );
  }

  /// A legend row. The swatch is a drawn box rather than a glyph: a coloured
  /// bullet would be a codepoint, and an uncovered codepoint is a font fetch.
  Widget _key(Color color, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      );
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
