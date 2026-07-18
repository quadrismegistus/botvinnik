// SAN/FEN helpers from the brain's chess.js — so Dart never re-implements
// move rendering. (The board's own dartchess handles legality; these cover
// text: SAN names, line rendering, fen-after.)

import 'js_bridge.dart';

class ChessApi {
  final JsBridge _bridge;
  const ChessApi(this._bridge);

  String san(String fen, String uci) =>
      _bridge.call('getSan', args: [fen, uci]) as String;

  String? fenAfter(String fen, String uci) =>
      _bridge.call('getFenAfter', args: [fen, uci]) as String?;

  String numberedSanLine(String fen, List<String> ucis, {int max = 12}) =>
      _bridge.call('getNumberedSanLine', args: [fen, ucis, max]) as String;

  /// getSanLine: each step {san, uci, color, piece} for a uci line from fen.
  List<Map<String, dynamic>> sanSteps(String fen, List<String> ucis) =>
      (_bridge.call('getSanLine', args: [fen, ucis]) as List)
          .map((s) => (s as Map).cast<String, dynamic>())
          .toList();

  bool isCapture(String fen, String uci) =>
      _bridge.call('isCapture', args: [fen, uci]) as bool;

  // ---- board overlays ----

  /// Where to point the null-move threat probe, or null when the position
  /// can't carry a threat (in check / game over).
  String? threatProbeFen(String fen) =>
      _bridge.call('threatProbeFen', args: [fen]) as String?;

  /// The material judgment on the probe's top line. Returns
  /// {fen, uci, san, gain, target} or null when the "threat" doesn't win
  /// material; target is the square of the piece the line wins (the mated
  /// king for a mate), null when the gain has no one square to point at.
  /// A mate threat arrives with gain == null (Infinity doesn't survive JSON).
  Map<String, dynamic>? judgeThreat(String fen, Map<String, dynamic> bestLine) {
    final r = _bridge.call('judgeThreat', args: [fen, bestLine]);
    return r == null ? null : (r as Map).cast<String, dynamic>();
  }

  /// Square-control tint: {square: 'w'|'b'} for squares one side owns.
  Map<String, String> controlSquares(String fen) =>
      (_bridge.call('controlSquares', args: [fen]) as Map)
          .cast<String, String>();
}
