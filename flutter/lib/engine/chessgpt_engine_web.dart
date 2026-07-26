// ChessGPT is native-only, and unlike Maia that is a decision rather than a
// port that has not happened yet.
//
// The net is ~26MB quantised — roughly the whole Maia band set several times
// over — and #30 already settled that we do not send weights of that size to a
// browser unasked. On native it is an on-demand download onto a machine where
// an app is already installed; on the web it would be the first thing a
// stranger paid for. The roster filters this family out rather than offering a
// persona that would stall.

import 'dart:math';

const String kChessGptVocab = ' #+-.0123456789;=BKNOQRabcdefghx';

class ChessGptEngine {
  ChessGptEngine();

  static bool get supported => false;

  /// Same shape as the native one, so callers need no platform branch — see
  /// chessgpt_engine_io.dart for what it does there.
  static String movesToPgn(List<String> sans,
      {required bool whiteToMove, required int fullmove}) {
    final b = StringBuffer(';');
    for (var i = 0; i < sans.length; i++) {
      if (i.isEven) b.write('${(i ~/ 2) + 1}.');
      b
        ..write(sans[i])
        ..write(' ');
    }
    if (whiteToMove) b.write('$fullmove.');
    return b.toString();
  }

  Future<String?> pickMove(String pgn,
      {required bool Function(String san) isLegalSan,
      double temperature = 0.0,
      Random? random}) async => null;

  void dispose() {}
}
