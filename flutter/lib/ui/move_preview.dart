// "Best was Nc6" as a picture: the position a move was chosen in, with the move
// PLAYED and the move the engine WANTED drawn on it. Shared by the Insight card
// (a graded game move) and Practice (a solved/revealed puzzle) — both want the
// same two-arrow comparison, so it lives here rather than in either panel.
//
// The colours are #29's board grammar, not the naive red/green: BLUE is the
// engine's move everywhere in this app (green is taken — it is the control
// overlay's "your squares"), and RED is the move that cost you. Two arrows, two
// facts, and nothing else on the squares — so it needs no blind-mode gate that
// the caller's own sentence does not already have.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Move, NormalMove, Side;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/settings_store.dart';
import 'board_theme.dart';

class MovePreview extends StatelessWidget {
  final String fen;
  final NormalMove played;
  final NormalMove best;
  final String playedSan;
  final String bestSan;
  final Side orientation;
  /// The label under the red arrow. "Played Nf3" in a game, "You played Nf3" in
  /// practice — the caller owns the voice.
  final String playedLabel;

  const MovePreview({
    super.key,
    required this.fen,
    required this.played,
    required this.best,
    required this.playedSan,
    required this.bestSan,
    required this.orientation,
    this.playedLabel = 'Played',
  });

  /// The two moves as arrows, or null when a board cannot show the difference.
  ///
  /// Refuses two cases. A uci that will not parse — nothing to draw at all. And
  /// two moves with the same origin and destination, which happens on a
  /// promotion where only the piece chosen differs (e7e8q vs e7e8n): the arrows
  /// would land on the identical line and read as one, so a sentence naming the
  /// piece is the only thing that can tell them apart.
  static (NormalMove, NormalMove)? arrowsFor(String playedUci, String bestUci) {
    final played = _normalMove(playedUci);
    final best = _normalMove(bestUci);
    if (played == null || best == null) return null;
    if (played.from == best.from && played.to == best.to) return null;
    return (played, best);
  }

  static NormalMove? _normalMove(String uci) {
    if (uci.length < 4) return null;
    final move = Move.parse(uci);
    // Arrow asserts orig != dest, and a drop move has no origin square at all.
    return move is NormalMove && move.from != move.to ? move : null;
  }

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
            // Fixed opacity, not the user's arrow/threat sliders: here the
            // arrows are the entire content, and a slider left low would leave a
            // board with nothing on it.
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
              _key(kThreatArrowRed, '$playedLabel $playedSan'),
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
