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
  final Map<String, String> _sanCache = {};
  String _cacheFen = '';

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final chess = context.read<ChessApi>();
    final fen = game.position.fen;
    if (_cacheFen != fen) {
      _cacheFen = fen;
      _sanCache.clear();
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

  Widget _lineRow(BuildContext context, GameController game, ChessApi chess,
      String fen, EngineMove line, bool blackToMove) {
    final key = '${line.multipv}|${line.depth}|${line.pv.join()}';
    final san = _sanCache.putIfAbsent(
        key, () => chess.numberedSanLine(fen, line.pv.take(10).toList()));

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
          : game.startPreview(fen, line.pv.take(10).toList()),
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
              child: Text(san,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.white70, height: 1.3)),
            ),
          ],
        ),
      ),
    );
  }
}
