// The Lines view: the engine's top lines for the current position, streaming
// in as the search deepens. Tap a line to watch it play out on the board
// (the same preview machinery as the insight card).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/chess_api.dart';
import '../brain/types.dart';
import '../engine/arbiter.dart' show kAnalysisDepth;
import '../stores/game_controller.dart';
import 'eval_text.dart';

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
    if (game.hidingHelp) {
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

    final blackToMove = fenBlackToMove(fen);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AnalysisProgress(
            depth: lines.first.depth, settled: game.analysisSettled),
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
    final evalText = whitePovEvalOf(line, blackToMove);
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

/// The filled part of the progress bar. Public only so a test can MEASURE what
/// the pane drew, rather than take the fraction it was handed on trust — the
/// bar's width is the claim, and a widthFactor read back out of the widget
/// tree would restate the code instead of checking it.
const kAnalysisProgressFillKey = ValueKey('analysis-progress-fill');

/// How far the search has got, above the lines it has produced so far (#95).
///
/// The bare "depth 14" this replaced was a number with nothing to be a number
/// OF: [kAnalysisDepth] is not something a player has any way to know, so 14
/// could equally have been nearly done or barely started. The fraction says
/// what it is out of and a hairline bar carries the same fact pre-attentively
/// — this sits above a dense list and is glanced at, not read, which is also
/// why it stays at 11pt white24 and gains no border, label or affordance.
class _AnalysisProgress extends StatelessWidget {
  const _AnalysisProgress({required this.depth, required this.settled});

  /// The deepest ply the streamed lines report.
  final int depth;

  /// The search has ENDED — see [GameController.analysisSettled]. Not the same
  /// as `depth >= kAnalysisDepth`: most searches end on the movetime backstop
  /// or on the board moving on, so they settle short of the target.
  final bool settled;

  @override
  Widget build(BuildContext context) {
    // The bar answers "is the engine still working on this", not "how deep did
    // it get" — the number's job. So a finished search fills it whatever depth
    // it stopped at, and the state this was most at risk of shipping (a bar
    // parked at 19/22 for the rest of the position's life, which is what a
    // settled search normally is) cannot occur. The rejected alternative was
    // to freeze the bar at its true fraction and grey it out: honest about the
    // depth, but it reads as a stalled download, and it would have made the
    // ordinary case look like a failure.
    final fraction = settled ? 1.0 : (depth / kAnalysisDepth).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The denominator shows only while it is still a target being
          // pursued; once the search is over the target is moot and the depth
          // reached is the whole of the fact. 'final' is what keeps that from
          // reading as a search that stalled — and the separator is a middle
          // dot rather than anything prettier because Roboto covers it, and an
          // uncovered glyph sends Flutter web to fonts.gstatic.com.
          Text(settled ? 'depth $depth · final' : 'depth $depth / $kAnalysisDepth',
              style: const TextStyle(color: Colors.white24, fontSize: 11)),
          const SizedBox(height: 4),
          // Always in the tree, full-width track included: removing it when the
          // search settles would reflow the whole lines list underneath at the
          // one moment the player is reading it.
          SizedBox(
            height: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(1),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  heightFactor: 1,
                  child: DecoratedBox(
                    key: kAnalysisProgressFillKey,
                    decoration: BoxDecoration(
                      // Dimmer once settled, to just above the track: a full
                      // bar that has stopped meaning anything should not be
                      // the brightest thing in the pane.
                      color: settled ? Colors.white12 : Colors.white24,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
