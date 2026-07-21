// One formatter for an engine evaluation, shared by every panel that prints one.
//
// The brain reports scores from the MOVER's point of view; the app prints them
// from White's, so the same move reads the same way whoever is to move. That
// conversion used to be written out twice — once in lines_pane, once in
// book_pane — and the two panels stack in the wide layout, so the duplication
// was the bug: nothing stopped one being changed and the other not, and a
// reader would see +1.0 in one panel and -1.0 in the other for the same move.
//
// #154 added a black-to-move test for book_pane's copy. Deleting lines_pane's
// copy still left the suite green, which is what prompted collapsing them into
// this.

import '../brain/types.dart';

/// The white-POV evaluation for [score]/[mate], formatted for display.
///
/// [blackToMove] comes from the FEN's side-to-move field. Mates print as `#N`
/// with the sign carried, so a mate FOR Black at a black-to-move position reads
/// `#-3` — Black is winning, which is what a negative score means everywhere
/// else in the app.
/// [score] is nullable because a mate row carries no centipawn score — and
/// taking it as non-null made the caller force-unwrap before the mate check,
/// which threw on exactly those rows and took the whole table down with it.
String whitePovEval({
  required double? score,
  required int? mate,
  required bool blackToMove,
}) {
  if (mate != null) return '#${blackToMove ? -mate : mate}';
  if (score == null) return '';
  // `+ 0.0` normalises negative zero. Negating an exactly-level score gives
  // -0.0, which is `>= 0` in Dart (so the '+' is prepended) AND formats as
  // "-0.0" — printing "+-0.0" at any dead-level position with Black to move.
  // Both panes carried this before the two copies were collapsed into one.
  final e = (blackToMove ? -score : score) + 0.0;
  return (e >= 0 ? '+' : '') + e.toStringAsFixed(1);
}

/// Whether [fen] has Black to move. The one place that field is parsed.
bool fenBlackToMove(String fen) => fen.split(' ')[1] == 'b';

/// Convenience for an [EngineMove], which carries both fields.
String whitePovEvalOf(EngineMove line, bool blackToMove) => whitePovEval(
      score: line.score,
      mate: line.mate,
      blackToMove: blackToMove,
    );
