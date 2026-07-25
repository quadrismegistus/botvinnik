// "Best was Nc6" as a picture: the position a move was chosen in, with the move
// PLAYED and the move the engine WANTED drawn on it. Shared by the Insight card
// (a graded game move) and Practice (a solved/revealed puzzle) — both want the
// same comparison, so it lives here rather than in either panel.
//
// Two arrows when the moves differ: RED is the move that cost you, GREEN is
// what the engine wanted (#185 — chess.com/lichess's ordinary verdict pairing,
// not #29's board-wide blue, because a comparison needs a LOSS/WIN pair, not
// "here is the engine's move" read in isolation). One arrow, BLUE, when they
// were the same move: neither red nor green alone would be honest about a
// move that is simultaneously "what you played" and "what wins" — see
// [MovePreview.same]. Nothing else drawn on the squares — so this needs no
// blind-mode gate that the caller's own sentence does not already have.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Move, NormalMove, Side;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/settings_store.dart';
import 'board_theme.dart';

class MovePreview extends StatelessWidget {
  final String fen;
  final NormalMove? played;
  final NormalMove? best;
  final String? playedSan;
  final String? bestSan;
  /// The played move, when it WAS the engine's move — set by [MovePreview.same]
  /// instead of [played]/[best], which describe the two-arrow comparison. Never
  /// both null and both non-null: [build] switches on this alone.
  final NormalMove? same;
  final String? sameSan;
  final Side orientation;
  /// The label under the red arrow (or the blue one, in the coincide case).
  /// "Played Nf3" in a game, "You played Nf3" in practice — the caller owns
  /// the voice.
  final String playedLabel;

  const MovePreview({
    super.key,
    required this.fen,
    required NormalMove this.played,
    required NormalMove this.best,
    required String this.playedSan,
    required String this.bestSan,
    required this.orientation,
    this.playedLabel = 'Played',
  })  : same = null,
        sameSan = null;

  /// The coincide case (#185): the played move WAS the best move, so there is
  /// only one fact to draw, not two — a red arrow beside a green one on the
  /// identical squares would just be two facts, overlapping, in the loser's
  /// colour underneath the winner's. One blue arrow says both things at once,
  /// in the app's ordinary "this is the engine's move" colour.
  const MovePreview.same({
    super.key,
    required this.fen,
    required NormalMove move,
    required String san,
    required this.orientation,
    this.playedLabel = 'Played',
  })  : same = move,
        sameSan = san,
        played = null,
        best = null,
        playedSan = null,
        bestSan = null;

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

  /// The played move alone, for [MovePreview.same] (#185): the identical parse
  /// guard as [arrowsFor], since a malformed uci would trip the same Arrow
  /// assertion here that it would there — just with no second move to compare
  /// it against.
  static NormalMove? soleMoveFor(String uci) => _normalMove(uci);

  /// Small enough to leave the legend room at 320pt (the card is ~276pt wide
  /// there), big enough for a piece to be recognisable at 13pt a square.
  static const double _size = 104;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final solo = same;
    final Set<Shape> shapes;
    final List<Widget> legend;
    if (solo != null) {
      shapes = {
        Arrow(
            color: kEngineArrowBlue.withValues(alpha: 0.9),
            orig: solo.from,
            dest: solo.to),
      };
      legend = [_key(kEngineArrowBlue, '$playedLabel $sameSan — also the best move')];
    } else {
      shapes = {
        // Fixed opacity, not the user's arrow/threat sliders: here the
        // arrows are the entire content, and a slider left low would leave a
        // board with nothing on it.
        Arrow(
            color: kThreatArrowRed.withValues(alpha: 0.85),
            orig: played!.from,
            dest: played!.to),
        Arrow(
            color: kBestMoveArrowGreen.withValues(alpha: 0.9),
            orig: best!.from,
            dest: best!.to),
      };
      legend = [
        _key(kThreatArrowRed, '$playedLabel $playedSan'),
        const SizedBox(height: 6),
        _key(kBestMoveArrowGreen, 'Best was $bestSan'),
      ];
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaticChessboard(
          size: _size,
          orientation: orientation,
          fen: fen,
          settings: staticBoardSettingsFor(settings),
          shapes: shapes,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: legend,
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
