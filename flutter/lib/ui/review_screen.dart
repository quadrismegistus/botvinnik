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
    final youAreWhite = (game['botColor'] as String?) == 'b';
    final m = review.currentMove;

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
                  lastMove: m == null
                      ? null
                      : NormalMove.fromUci(m['uci'] as String),
                  shapes: _shapes(m),
                );

            if (constraints.maxWidth < kWideBreakpoint) {
              final size = panedBoardSize(
                  constraints.maxWidth, constraints.maxHeight, kReviewFixed);
              return Column(
                children: [
                  Center(child: board(size)),
                  _verdictStrip(m, table),
                  Expanded(child: _moveList(review, table)),
                  _scrubBar(review, context),
                ],
              );
            }
            final size = wideBoardSize(
                constraints.maxWidth, constraints.maxHeight, settings.split);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                board(size),
                Expanded(
                  child: Column(
                    children: [
                      _verdictStrip(m, table),
                      Expanded(child: _moveList(review, table)),
                      _scrubBar(review, context),
                    ],
                  ),
                ),
              ],
            );
          },
        ));
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
      Arrow(
        color: const Color(0xB33BAB4A),
        orig: best.from,
        dest: best.to,
      ),
    };
  }

  Widget _verdictStrip(Map<String, dynamic>? m, ClassTable table) {
    Widget content;
    if (m == null) {
      content = const Text('Start position',
          style: TextStyle(color: Colors.white38, fontSize: 13));
    } else {
      final label = m['label'] as String?;
      final expl = (m['explanation'] as Map?)?.cast<String, dynamic>();
      final prose = expl?['playedIssue'] ?? expl?['playedPoint'] ?? expl?['bestPoint'];
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(m['san'] as String,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(width: 8),
            if (label != null)
              Text.rich(
                  TextSpan(children: [
                    table.glyphSpan(label, size: 14),
                    TextSpan(text: ' ${table.noun(label)}'),
                  ]),
                  style: TextStyle(
                      color: table.color(label),
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            const Spacer(),
            if (m['bestSan'] != null && label != 'best')
              Text('best: ${m['bestSan']}',
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
          if (prose != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(prose as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12, height: 1.3)),
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

  Widget _moveList(ReviewController review, ClassTable table) {
    final moves = review.moves;
    return ListView.builder(
      itemCount: (moves.length + 1) ~/ 2,
      itemBuilder: (context, i) {
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
                      borderRadius: BorderRadius.circular(4))
                  : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(m['san'] as String, style: const TextStyle(fontSize: 13)),
                if (label != null) ...[
                  const SizedBox(width: 3),
                  Text.rich(table.glyphSpan(label, size: 11),
                      style:
                          TextStyle(color: table.color(label), fontSize: 11)),
                ],
              ]),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
          child: Row(children: [
            SizedBox(
                width: 30,
                child: Text('${i + 1}.',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12))),
            Expanded(child: cell(white, i * 2 + 1)),
            Expanded(child: cell(black, i * 2 + 2)),
          ]),
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
    );
  }
}
