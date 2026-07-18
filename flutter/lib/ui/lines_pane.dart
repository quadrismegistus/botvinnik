// The Lines view: the engine's top lines for the current position, streaming
// in as the search deepens. Tap a line to watch it play out on the board
// (the same preview machinery as the insight card).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/chess_api.dart';
import '../brain/types.dart';
import '../stores/game_controller.dart';

class LinesPane extends StatefulWidget {
  const LinesPane({super.key});

  @override
  State<LinesPane> createState() => _LinesPaneState();
}

class _LinesPaneState extends State<LinesPane> {
  // SAN rendering goes through the brain (chess.js) — cache per line+depth
  // so streaming updates don't re-render unchanged pvs
  final Map<String, List<Map<String, dynamic>>> _stepCache = {};
  String _cacheFen = '';

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final chess = context.read<ChessApi>();
    final fen = game.position.fen;
    if (_cacheFen != fen) {
      _cacheFen = fen;
      _stepCache.clear();
    }
    if (game.blind && game.botEnabled) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text('Blind mode — no engine help until the game ends.',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }
    final lines = game.visibleLines;

    if (lines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text('Analyzing…',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }

    final blackToMove = fen.split(' ')[1] == 'b';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
          child: Text('depth ${lines.first.depth}',
              style: const TextStyle(color: Colors.white24, fontSize: 11)),
        ),
        for (final line in lines.take(5))
          _lineRow(context, game, chess, fen, line, blackToMove),
      ],
    );
  }

  // Alignment is done with layout, not with padded text in a monospace font:
  // CanvasKit does not resolve a 'monospace' family on the web, so padding
  // silently falls back to a proportional font and the columns drift.
  //
  // The widths are sized for the longest legal SAN, which is 7 characters —
  // Qa1xd4# (piece, full disambiguation, capture, square, mate) or exd8=Q+
  // (pawn capture with promotion). Castling tops out at 6 (O-O-O#).
  static const double _sanCell = 56;
  static const double _numCell = 32;
  static const TextStyle _sanStyle =
      TextStyle(fontSize: 12, color: Colors.white70, height: 1.45);

  /// The variation as fixed-width cells, so the same ply sits in the same
  /// column on every line. Every line starts from one position, so their cell
  /// sequences match and the columns line up — which is what makes it
  /// possible to see at a glance where two lines diverge.
  List<Widget> _cells(String fen, List<Map<String, dynamic>> steps) {
    final parts = fen.split(' ');
    var num = int.tryParse(parts.length > 5 ? parts[5] : '1') ?? 1;
    var whiteToMove = parts.length > 1 ? parts[1] == 'w' : true;
    final out = <Widget>[];

    void cell(String text, double width, {Color? color}) => out.add(SizedBox(
          width: width,
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: color == null ? _sanStyle : _sanStyle.copyWith(color: color)),
        ));

    for (final step in steps) {
      final san = (step['san'] as String?) ?? '';
      if (whiteToMove) {
        cell('$num.', _numCell, color: Colors.white30);
        cell(san, _sanCell);
      } else {
        // a line starting mid-move still needs its white column, or its black
        // moves would sit under the white ones on every other line
        if (out.isEmpty) {
          cell('$num.', _numCell, color: Colors.white30);
          cell('…', _sanCell, color: Colors.white24);
        }
        cell(san, _sanCell);
        num++;
      }
      whiteToMove = !whiteToMove;
    }
    return out;
  }

  Widget _lineRow(BuildContext context, GameController game, ChessApi chess,
      String fen, EngineMove line, bool blackToMove) {
    final key = 'g2|${line.multipv}|${line.depth}|${line.pv.join()}';
    // the whole line the engine actually has, not a fixed slice of it — its
    // length is itself information (a shallow line means less was resolved)
    final steps = _stepCache.putIfAbsent(key, () => chess.sanSteps(fen, line.pv));

    // white-POV eval chip
    final String evalText;
    if (line.mate != null) {
      final m = blackToMove ? -line.mate! : line.mate!;
      evalText = '#$m';
    } else {
      final e = blackToMove ? -line.score : line.score;
      evalText = (e >= 0 ? '+' : '') + e.toStringAsFixed(1);
    }

    return InkWell(
      onTap: () => game.previewing
          ? game.stopPreview()
          : game.startPreview(fen, line.pv.toList()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF3a3733),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(evalText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(runSpacing: 2, children: _cells(fen, steps)),
            ),
          ],
        ),
      ),
    );
  }
}
