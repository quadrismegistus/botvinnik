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
  /// {fen, uci, san, gain, targets} or null when the "threat" doesn't win
  /// material; targets are the current squares of the pieces the line wins
  /// (the mated king for a mate) — attacked by the threat move and lost even
  /// under best defense, possibly empty.
  /// A mate threat arrives with gain == null (Infinity doesn't survive JSON).
  Map<String, dynamic>? judgeThreat(String fen, Map<String, dynamic> bestLine) {
    final r = _bridge.call('judgeThreat', args: [fen, bestLine]);
    return r == null ? null : (r as Map).cast<String, dynamic>();
  }

  /// The green mirror of judgeThreat: the same judgment on the side to
  /// move's OWN top analysis line — what the mover wins by playing it.
  /// Same shape as judgeThreat; costs no engine time.
  Map<String, dynamic>? judgeTacticalWin(String fen, Map<String, dynamic> bestLine) {
    final r = _bridge.call('judgeTacticalWin', args: [fen, bestLine]);
    return r == null ? null : (r as Map).cast<String, dynamic>();
  }

  /// Square-control tint: {square: ControlCell} for squares one side owns.
  Map<String, ControlCell> controlSquares(String fen) {
    final raw = _bridge.call('controlSquares', args: [fen]) as Map;
    return {
      for (final e in raw.entries)
        e.key as String: ControlCell.fromJson((e.value as Map).cast<String, dynamic>()),
    };
  }
}

/// One square's control claim. [side] ('w'|'b') owns it; [margin] is the
/// material (pawns) the exchange there decides, so tint intensity can be
/// graded instead of flat; [held] flags an occupied piece its own side merely
/// holds under fire (opt-in on the brain side, so normally false).
class ControlCell {
  final String side;
  final double margin;
  final bool held;
  const ControlCell(this.side, this.margin, this.held);

  factory ControlCell.fromJson(Map<String, dynamic> j) => ControlCell(
        j['side'] as String,
        (j['margin'] as num).toDouble(),
        j['held'] as bool? ?? false,
      );
}
