// The Lines view: the engine's top lines for the current position, streaming
// in as the search deepens. Tap a line to watch it play out on the board
// (the same preview machinery as the insight card).

import 'dart:math' as math;

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

  /// Measured widths, keyed by the string itself. SANs repeat constantly
  /// across lines and depths, so this stays small and warm.
  final Map<String, double> _textWidth = {};

  /// Column widths only ever grow while the position stands. The lines are
  /// replaced wholesale on every depth update, so re-measuring from scratch
  /// makes the columns twitch as the search streams; letting them settle at
  /// their widest is calmer and costs a few pixels.
  List<double> _colMax = [];

  double _measure(String text) => _textWidth.putIfAbsent(text, () {
        final tp = TextPainter(
          text: TextSpan(text: text, style: _sanStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        return tp.width;
      });

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final chess = context.read<ChessApi>();
    final fen = game.position.fen;
    if (_cacheFen != fen) {
      _cacheFen = fen;
      _stepCache.clear();
      _colMax = [];
    }
    // `!gameOver` because the message below promises the engine comes back when
    // the game ends — without it the pane says so and never reopens. book_pane
    // already gated this way; the two disagreed.
    if (game.blind && game.botEnabled && !game.gameOver) {
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
        // One horizontal scroll for the whole block, not one per line: the
        // columns only mean anything if every line scrolls together, and it
        // keeps the eval chips pinned on the left while the moves move.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 14),
            Column(
              children: [
                for (final line in lines.take(5))
                  _evalChip(context, game, fen, line, blackToMove),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Builder(builder: (context) {
                final shown = lines.take(5).toList();
                final rows = [
                  for (final line in shown)
                    _rowCells(fen, _steps(chess, fen, line))
                ];
                final widths = _columnWidths(rows);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < shown.length; i++)
                        _lineRow(game, fen, shown[i], rows[i], widths),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ],
    );
  }

  /// Rows are a fixed height so the pinned chips stay level with the moves
  /// they belong to — they are in two different columns now.
  static const double _rowHeight = 26;

  // Alignment is done with layout, not with padded text in a monospace font:
  // CanvasKit does not resolve a 'monospace' family on the web, so padding
  // silently falls back to a proportional font and the columns drift.
  //
  // Column widths are measured per ply across the visible lines, so a column
  // of e4/d4/Nf3 stays narrow and only a column that actually contains
  // something like Qa1xd4# (the longest legal SAN, 7 characters) gets wide.
  static const double _colGap = 9;
  static const TextStyle _sanStyle =
      TextStyle(fontSize: 12, color: Colors.white70, height: 1.45);

  /// One line's cells as text: (content, isMoveNumber).
  ///
  /// Every line starts from the same position, so their cell sequences match
  /// and column i is the same ply on every line — which is what makes it
  /// possible to see at a glance where two lines diverge.
  List<(String, bool)> _rowCells(String fen, List<Map<String, dynamic>> steps) {
    final parts = fen.split(' ');
    var num = int.tryParse(parts.length > 5 ? parts[5] : '1') ?? 1;
    var whiteToMove = parts.length > 1 ? parts[1] == 'w' : true;
    final out = <(String, bool)>[];
    for (final step in steps) {
      final san = (step['san'] as String?) ?? '';
      if (whiteToMove) {
        out.add(('$num.', true));
      } else if (out.isEmpty) {
        // a line starting mid-move still needs its white column, or its black
        // moves would sit under the white ones on every other line
        out
          ..add(('$num.', true))
          ..add(('…', false));
      }
      out.add((san, false));
      if (!whiteToMove) num++;
      whiteToMove = !whiteToMove;
    }
    return out;
  }

  /// The width of each column: the widest cell any line puts there, measured
  /// rather than assumed. Sizing every cell for the longest legal SAN
  /// (Qa1xd4#, 7 characters) would be correct and mostly wasted — nearly
  /// every move is two to four.
  List<double> _columnWidths(List<List<(String, bool)>> rows) {
    var count = 0;
    for (final r in rows) {
      if (r.length > count) count = r.length;
    }
    final widths = [
      for (var i = 0; i < count; i++)
        rows.fold<double>(
              0,
              (w, r) => i < r.length ? math.max(w, _measure(r[i].$1)) : w,
            ) +
            _colGap,
    ];
    for (var i = 0; i < widths.length; i++) {
      if (i < _colMax.length) {
        widths[i] = math.max(widths[i], _colMax[i]);
      }
    }
    _colMax = widths;
    return widths;
  }

  void _preview(GameController game, String fen, EngineMove line) =>
      game.previewing ? game.stopPreview() : game.startPreview(fen, line.pv.toList());

  Widget _evalChip(BuildContext context, GameController game, String fen,
      EngineMove line, bool blackToMove) {
    // white-POV
    final String evalText;
    if (line.mate != null) {
      final m = blackToMove ? -line.mate! : line.mate!;
      evalText = '#$m';
    } else {
      final e = blackToMove ? -line.score : line.score;
      evalText = (e >= 0 ? '+' : '') + e.toStringAsFixed(1);
    }
    return SizedBox(
      height: _rowHeight,
      child: InkWell(
        onTap: () => _preview(game, fen, line),
        child: Center(
          child: Container(
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
        ),
      ),
    );
  }

  /// The whole line the engine actually has, not a fixed slice of it — its
  /// length is itself information (a shallow line means less was resolved).
  List<Map<String, dynamic>> _steps(ChessApi chess, String fen, EngineMove line) =>
      _stepCache.putIfAbsent('${line.multipv}|${line.depth}|${line.pv.join()}',
          () => chess.sanSteps(fen, line.pv));

  Widget _lineRow(GameController game, String fen, EngineMove line,
      List<(String, bool)> cells, List<double> widths) {
    return SizedBox(
      height: _rowHeight,
      child: InkWell(
        onTap: () => _preview(game, fen, line),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < cells.length; i++)
              SizedBox(
                width: widths[i],
                child: Text(cells[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: cells[i].$2
                        ? _sanStyle.copyWith(color: Colors.white30)
                        : _sanStyle),
              ),
          ],
        ),
      ),
    );
  }
}
