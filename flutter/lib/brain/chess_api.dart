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
}
