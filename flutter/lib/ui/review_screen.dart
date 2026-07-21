// Review one stored game: static board with the played move highlighted and
// the best move as a green arrow, verdict strip, tappable move list,
// prev/next scrubbing in the bottom bar.
//
// A BODY, not a screen: it renders inside the Review tab rather than as a
// pushed route. A route would cover the shell — which is what made the bottom
// tabs vanish the moment you opened a game, stranding you in a mode you could
// only leave with the app bar's back arrow.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/pgn_import.dart';
import '../stores/review_controller.dart';
import '../stores/settings_store.dart';
import 'board_theme.dart';
import 'grade_strip.dart';
import 'layout.dart';

class ReviewBody extends StatelessWidget {
  const ReviewBody({super.key});

  @override
  Widget build(BuildContext context) {
    final review = context.watch<ReviewController>();
    final table = context.read<ClassTable>();
    final game = review.current;
    if (game == null) return const SizedBox();
    // An import has no "you" in it, so there is no side to take: show it from
    // White's, which is how every published game is printed.
    final youAreWhite =
        game[kImportedKey] == true || (game['botColor'] as String?) == 'b';
    final m = review.currentMove;
    // The brain's ranking, not one written out here — the grade strip and the
    // brain both order by LABEL_ORDER, and a second list would drift from it.
    final summary = _summary(game, table, table.labelOrder);

    return SafeArea(
      bottom: false,
      // Square board, so full width on a desktop window meant a board taller
      // than the viewport: it overflowed by ~870px and buried the move list
      // and scrub bar. Capped when stacked, beside the list when wide.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final settings = context.watch<SettingsStore>();
          Widget board(double size) => StaticChessboard(
            settings: staticBoardSettingsFor(settings),
            size: size,
            orientation: youAreWhite ? Side.white : Side.black,
            fen: review.fen,
            lastMove: m == null ? null : NormalMove.fromUci(m['uci'] as String),
            shapes: _shapes(m),
          );

          if (constraints.maxWidth < kWideBreakpoint) {
            final size = panedBoardSize(
              constraints.maxWidth,
              constraints.maxHeight,
              kReviewFixed,
            );
            return Column(
              children: [
                Center(child: board(size)),
                _verdictStrip(m, table),
                Expanded(child: _moveList(review, table, summary)),
                _scrubBar(review, context),
              ],
            );
          }
          final size = wideBoardSize(
            constraints.maxWidth,
            constraints.maxHeight,
            settings.split,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              board(size),
              Expanded(
                child: Column(
                  children: [
                    _verdictStrip(m, table),
                    Expanded(child: _moveList(review, table, summary)),
                    _scrubBar(review, context),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Set<Shape> _shapes(Map<String, dynamic>? m) {
    if (m == null) return const {};
    final bestUci = m['bestUci'] as String?;
    final label = m['label'] as String?;
    // show the best-move arrow when the played move wasn't it
    if (bestUci == null ||
        label == 'best' ||
        label == 'brilliant' ||
        label == 'great') {
      return const {};
    }
    final best = NormalMove.fromUci(bestUci);
    return {
      Arrow(color: const Color(0xB33BAB4A), orig: best.from, dest: best.to),
    };
  }

  Widget _verdictStrip(Map<String, dynamic>? m, ClassTable table) {
    Widget content;
    if (m == null) {
      content = const Text(
        'Start position',
        style: TextStyle(color: Colors.white38, fontSize: 13),
      );
    } else {
      final label = m['label'] as String?;
      final expl = (m['explanation'] as Map?)?.cast<String, dynamic>();
      final prose =
          expl?['playedIssue'] ?? expl?['playedPoint'] ?? expl?['bestPoint'];
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                m['san'] as String,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              if (label != null)
                Text.rich(
                  TextSpan(
                    children: [
                      table.glyphSpan(label, size: 14),
                      TextSpan(text: ' ${table.noun(label)}'),
                    ],
                  ),
                  style: TextStyle(
                    color: table.color(label),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              const Spacer(),
              if (m['bestSan'] != null && label != 'best')
                Text(
                  'best: ${m['bestSan']}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
            ],
          ),
          if (prose != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                prose as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF262421),
      child: content,
    );
  }

  /// The whole-game summary: both sides' accuracy, and how many of their moves
  /// fell into each label. Everything here was computed at save time and is
  /// stored on the record (game_controller's save path) — nothing is
  /// recalculated, and nothing crosses the engine.
  ///
  /// [order] is the brain's LABEL_ORDER. Rows are dropped when neither side
  /// has any, so a clean game is a short grid rather than seven zeroes.
  Widget _summary(
    Map<String, dynamic> game,
    ClassTable table,
    List<String> order,
  ) {
    final counts = game['labelCounts'] as Map?;
    final w = counts?['w'] as Map?;
    final b = counts?['b'] as Map?;
    int n(Map? side, String label) => (side?[label] as num?)?.toInt() ?? 0;
    final wAcc = game['whiteAccuracy'] as num?;
    final bAcc = game['blackAccuracy'] as num?;
    final rows = order.where((l) => n(w, l) + n(b, l) > 0).toList();

    // An import was never analysed — no labels and no accuracy, says
    // pgn_import — and records written before accuracy existed have neither
    // either. A grid of dashes would say nothing, so say nothing.
    if (wAcc == null && bAcc == null && rows.isEmpty) return const SizedBox();

    // botColor names the side the player did NOT take. It is absent from
    // imports and from analysis games, where there is no "you" to point at.
    final botColor = game['botColor'] as String?;
    String who(String side) {
      final colour = side == 'w' ? 'White' : 'Black';
      if (botColor == null) return colour;
      return '$colour (${botColor == side ? 'bot' : 'you'})';
    }

    // Two fixed columns with the label taking what is left: the label
    // ellipsises rather than pushing the numbers off a phone.
    const double kCol = 74;
    Widget accuracyCell(String side, num? acc) => SizedBox(
      width: kCol,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            who(side),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          Text(
            acc == null ? '—' : '${acc.toStringAsFixed(0)}%',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ],
      ),
    );

    Widget countCell(int v) => SizedBox(
      width: kCol,
      child: Text(
        '$v',
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 12.5,
          color: v == 0 ? Colors.white24 : Colors.white70,
        ),
      ),
    );

    return Container(
      color: const Color(0xFF1f1e1b),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Text(
                  'Accuracy',
                  style: TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ),
              accuracyCell('w', wAcc),
              accuracyCell('b', bAcc),
            ],
          ),
          if (rows.isNotEmpty) const SizedBox(height: 8),
          for (final label in rows)
            Padding(
              // Keyed so a test can address a row without matching on the
              // rendered string — the glyph and the name share one rich span,
              // so there is no plain Text to find.
              key: ValueKey('summary-row-$label'),
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  // Glyph and name in ONE Text.rich rather than a nested Row.
                  // Split across a Row, the glyph and its 6px gap were rigid, so
                  // when the Review pane is narrow the label's Expanded got a few
                  // pixels and the glyph alone burst it — nine overflow stripes
                  // on a 720-800px window with the splitter at kMaxSplit. As one
                  // rich string the whole thing ellipsizes instead.
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          table.glyphSpan(label, size: 12),
                          const TextSpan(text: '  '),
                          TextSpan(
                            text: _capitalised(label),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: table.color(label), fontSize: 12),
                    ),
                  ),
                  countCell(n(w, label)),
                  countCell(n(b, label)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _capitalised(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// The move list, with [summary] as its first row.
  ///
  /// The summary rides INSIDE the scrollable rather than above it: Review's
  /// board is sized against `kReviewFixed` (layout.dart), so anything added to
  /// that column has to be paid for out of the board — and this is read once
  /// on opening a game, not while scrubbing through it.
  Widget _moveList(ReviewController review, ClassTable table, Widget summary) {
    final moves = review.moves;
    return ListView.builder(
      itemCount: (moves.length + 1) ~/ 2 + 1,
      itemBuilder: (context, index) {
        if (index == 0) return summary;
        final i = index - 1;
        final white = moves[i * 2];
        final black = i * 2 + 1 < moves.length ? moves[i * 2 + 1] : null;
        Widget cell(Map<String, dynamic>? m, int ply) {
          if (m == null) return const SizedBox();
          final label = m['label'] as String?;
          final active = review.cursor == ply;
          return InkWell(
            onTap: () => review.goto(ply),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: active
                  ? BoxDecoration(
                      color: const Color(0xFF3a3733),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m['san'] as String,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (label != null) ...[
                    const SizedBox(width: 3),
                    Text.rich(
                      table.glyphSpan(label, size: 11),
                      style: TextStyle(color: table.color(label), fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${i + 1}.',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
              Expanded(child: cell(white, i * 2 + 1)),
              Expanded(child: cell(black, i * 2 + 2)),
            ],
          ),
        );
      },
    );
  }

  Widget _scrubBar(ReviewController review, BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4 + MediaQuery.of(context).padding.bottom,
      ),
      color: const Color(0xFF1f1e1b),
      // Four 48dp buttons plus a 20px gap need ~212px, and in the wide layout
      // this bar lives in the Review pane — which at kMaxSplit on an 800px
      // window is 200px. It overflowed by 12px there (32px at 720) before the
      // summary existed; scrolling is better than clipping a control, and the
      // bar still centres whenever there is room.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: review.canPrev ? () => review.goto(0) : null,
              icon: const Icon(Icons.first_page),
              color: Colors.white70,
            ),
            IconButton(
              onPressed: review.canPrev ? review.prev : null,
              icon: const Icon(Icons.chevron_left),
              color: Colors.white70,
              iconSize: 30,
            ),
            const SizedBox(width: 20),
            IconButton(
              onPressed: review.canNext ? review.next : null,
              icon: const Icon(Icons.chevron_right),
              color: Colors.white70,
              iconSize: 30,
            ),
            IconButton(
              onPressed: review.canNext
                  ? () => review.goto(review.moves.length)
                  : null,
              icon: const Icon(Icons.last_page),
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }
}
