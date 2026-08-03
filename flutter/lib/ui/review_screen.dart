// Review one stored game: the ANALYSIS BOARD over the record (#194) — square
// tinting, engine arrows, threat and win glyphs, all live for whichever ply
// the cursor is on — plus the verdict strip, tappable move list and prev/next
// scrubbing in the bottom bar.
//
// The board is [BoardPane], the same widget the Play tab uses, driven by a
// [ReviewBoardController] that follows this tab's cursor. Nothing about the
// overlays is reimplemented here; the board republishes that controller AS the
// GameController for its subtree, so BoardPane and everything under it resolve
// to the review board without knowing review exists. What is left in this file
// is the archive's own furniture: the stored grades, which never cross the
// engine.
//
// A BODY, not a screen: it renders inside the Review tab rather than as a
// pushed route. A route would cover the shell — which is what made the bottom
// tabs vanish the moment you opened a game, stranding you in a mode you could
// only leave with the app bar's back arrow.

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import '../stores/game_controller.dart';
import '../stores/review_tree.dart';
import '../stores/practice_controller.dart';
import '../stores/review_controller.dart';
import '../stores/settings_store.dart';
import 'board_pane.dart';
import 'grade_strip.dart';
import 'layout.dart';
import 'move_preview.dart';
import 'review_win_chart.dart';

class ReviewBody extends StatelessWidget {
  /// Switch to the Practice tab and drill the passed positions — this game's
  /// blunder fens (#197). Null when there is nowhere to send them (a plain
  /// game list with no shell around it, e.g. a widget test that only wants the
  /// board), which hides the affordance.
  final void Function(Set<String> fens)? onPractiseGame;

  const ReviewBody({super.key, this.onPractiseGame});

  @override
  Widget build(BuildContext context) {
    final review = context.watch<ReviewController>();
    final board = context.watch<ReviewBoardController>();
    final table = context.read<ClassTable>();
    final game = review.current;
    if (game == null) return const SizedBox();
    // The archived record for whatever the cursor is on — the BOARD's cursor,
    // which inside a variation is not on the played game at all and has no
    // record to show (#196).
    final m = board.reviewStoredMove;
    // The brain's ranking, not one written out here — the grade strip and the
    // brain both order by LABEL_ORDER, and a second list would drift from it.
    final summary =
        _summary(game, table, table.labelOrder, board);
    // Both ride in the move-list header (index 0) so they cost the board no
    // height — Review's board is sized against kReviewFixed, and anything in
    // the fixed column comes straight out of the board.
    final practiseCta = _practiseCta(context, review);
    // Whether a mini-board is drawn at all. Two independent questions, both
    // answered per GAME or per VIEWPORT rather than per ply, so neither can
    // change under a scrub and make the board resize in the player's hand:
    //
    //   * has this game got a best move to compare against? An ungraded
    //     import has none anywhere in it, so it keeps the height rather than
    //     paying for a widget it can never draw.
    //   * can this viewport afford one? See [reviewShowsPreview] — on a small
    //     phone the 120px comes out of the move list, not the board, and the
    //     list absorbs it silently down to nothing.
    final graded = review.moves.any((m) => m['bestUci'] is String);

    return SafeArea(
      bottom: false,
      // Square board, so full width on a desktop window meant a board taller
      // than the viewport: it overflowed by ~870px and buried the move list
      // and scrub bar. Capped when stacked, beside the list when wide.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final settings = context.watch<SettingsStore>();
          // One answer, read by BOTH the board's sizing and the strip's
          // content. Split, they disagree about who is paying for the
          // mini-board's height and the difference comes out of the move list.
          final preview = graded &&
              reviewShowsPreview(constraints.maxWidth, constraints.maxHeight);
          // The review board republished as THE GameController for this
          // subtree: BoardPane, and everything it draws, reads
          // `context.watch<GameController>()` and must find the review board
          // here without any of them learning that review exists. Outside this
          // subtree that read still means the live game.
          //
          // Orientation, the played move's highlight and the best-move arrow
          // all come from the controller now — it knows the reviewed game's
          // colour, its cursor, and the engine's own top lines — so none of
          // them are passed in.
          Widget boardView(double size) => SizedBox(
                width: size,
                height: size,
                child: ChangeNotifierProvider<GameController>.value(
                  value: board,
                  child: const BoardPane(),
                ),
              );

          if (!reviewSideBySide(constraints.maxWidth, constraints.maxHeight)) {
            final size = reviewStackedBoard(
              constraints.maxWidth,
              constraints.maxHeight,
              kReviewFixed + (preview ? kMovePreview : 0),
            );
            return Column(
              children: [
                Center(child: boardView(size)),
                _verdictStrip(m, table, board, preview),
                Expanded(
                    child: _moveList(review, board, table, summary, practiseCta)),
                _scrubBar(board, context),
              ],
            );
          }
          // Beside the list: either a genuinely wide window, or a landscape
          // phone with no height to stack in (#239).
          final size = wideBoardSize(
            constraints.maxWidth,
            constraints.maxHeight,
            settings.split,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              boardView(size),
              Expanded(
                child: Column(
                  children: [
                    _verdictStrip(m, table, board, preview),
                    Expanded(
                        child: _moveList(
                            review, board, table, summary, practiseCta)),
                    _scrubBar(board, context),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // The stored best-move arrow that used to be drawn here is GONE, and
  // deliberately: BoardPane now draws the engine's own top lines for the
  // position on the board, in the same green. The stored arrow was a
  // different fact in the same ink — the move you should have played INSTEAD
  // of the one just made — and it was drawn on the position AFTER that move,
  // where its from-square may hold nothing or hold something else. Two greens
  // meaning opposite directions in time is exactly the collision the overlay
  // grammar exists to prevent.
  //
  // The retrospective advice lives in the verdict strip instead, and since
  // #233 as a PICTURE rather than a sentence — see [_preview]. That is not the
  // stored arrow coming back: a mini-board is a separate surface drawn on
  // `fenBefore`, so the from-square is the one the move actually left and its
  // red/green pair cannot be mistaken for the engine's own green lines on the
  // live board. Both objections above are about drawing it HERE.


  Widget _verdictStrip(Map<String, dynamic>? m, ClassTable table,
      ReviewBoardController board, bool showPreview) {
    Widget content;
    if (board.inVariation) {
      // A variation move was never played, so it was never graded and there is
      // no verdict to give it. Say where you are instead — and offer the way
      // back, which is the whole reason a variation is safe to start.
      final node = board.tree?.current;
      content = Row(
        children: [
          Expanded(
            child: Text(
              node?.san == null
                  ? 'Variation'
                  : 'Variation — ${node!.san} (not played)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xFFE8B44A),
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: board.discardVariation,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE8B44A),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              // 48dp, per this project's own precedent (#221 enlarged the
              // review toggle for the same reason).
              minimumSize: const Size(0, 48),
            ),
            child: const Text('Back to the game', style: TextStyle(fontSize: 12)),
          ),
        ],
      );
    } else if (m == null) {
      content = const Text(
        'Start position',
        style: TextStyle(color: Colors.white38, fontSize: 13),
      );
    } else {
      final label = m['label'] as String?;
      final expl = (m['explanation'] as Map?)?.cast<String, dynamic>();
      final prose =
          expl?['playedIssue'] ?? expl?['playedPoint'] ?? expl?['bestPoint'];
      // The picture, when there is one to draw. Its legend already says
      // "Best was e4", so the sentence below is the FALLBACK rather than a
      // caption — printing both would name the same move twice in one strip.
      final preview = showPreview ? _preview(m, board) : null;
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
              // `m['uci'] != m['bestUci']`, not `label != 'best'`. The label was
              // a valid proxy only while a bestSan implied a mistake; now that
              // every analysed ply carries the engine's move (#281) it is not —
              // and labelForDrop, which is what an import gets, never returns
              // 'best' at all, so the old guard could not fire on one. It
              // printed "best: e4" beside a move that WAS e4. _preview below
              // already keys off the uci, with a comment saying why.
              if (preview == null &&
                  m['bestSan'] != null &&
                  m['uci'] != m['bestUci'])
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
          if (preview != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: preview),
        ],
      );
    }
    return Container(
      // Keyed so a test can measure the strip's own height against what
      // [kMovePreview] reserves for it — there is no other way to address it,
      // and an unmeasured reservation is the one that silently goes stale.
      key: const ValueKey('review-verdict'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF262421),
      child: content,
    );
  }

  /// The move played and the move the engine wanted, drawn on the position the
  /// move was chosen in (#233) — the same [MovePreview] the Insight card has
  /// used since #185 and Practice since #215, so Review is the third consumer
  /// of one widget rather than a fourth way of saying the same thing.
  ///
  /// Review is the mode where this matters most. Insights speaks about a move
  /// you played a moment ago and still have in your head; Review is where you
  /// come back to a game from last week, and "best: Nf3" asks you to find Nf3
  /// on the board yourself.
  ///
  /// Null for anything it cannot draw honestly, and the caller falls back to
  /// the sentence: a move with no grade, an archive written before `uci` was
  /// stored, or a promotion differing only in the piece chosen — for which
  /// [MovePreview.arrowsFor] returns null, since the two arrows would land on
  /// the identical line and only a sentence can tell e8=Q from e8=N.
  Widget? _preview(Map<String, dynamic> m, ReviewBoardController board) {
    final fen = m['fenBefore'];
    final uci = m['uci'];
    final bestUci = m['bestUci'];
    final bestSan = m['bestSan'];
    final san = m['san'];
    if (fen is! String ||
        uci is! String ||
        bestUci is! String ||
        bestSan is! String ||
        san is! String) {
      return null;
    }
    // Oriented like the board above it, not like the mover. The analysis board
    // is fixed to the reviewed game's colour (and to any flip the user has
    // asked for), so a mini-board that turned over every half-move would be a
    // second, contradicting frame of reference two inches below the first.
    // That is the one place this departs from the Insight card, which only
    // ever describes a single move and has no board of its own to agree with.
    final orientation = board.whiteAtBottom ? Side.white : Side.black;
    // `uci == bestUci`, NOT `label == 'best'`. backfillGrade widens isBest to
    // any move that scores 100% under the deeper post-move search, while
    // bestUci stays pinned to the pre-move MultiPV winner — so a move labelled
    // best is regularly not the move bestUci names. Keyed off the label, this
    // would draw the played move in the engine's blue, captioned "also the
    // best move", for a move the engine did not pick. insight_card.dart makes
    // the same choice, at more length, for the same reason.
    if (uci == bestUci) {
      final solo = MovePreview.soleMoveFor(uci);
      if (solo == null) return null;
      return MovePreview.same(
        fen: fen,
        move: solo,
        san: san,
        orientation: orientation,
      );
    }
    final arrows = MovePreview.arrowsFor(uci, bestUci);
    if (arrows == null) return null;
    return MovePreview(
      fen: fen,
      played: arrows.$1,
      best: arrows.$2,
      playedSan: san,
      bestSan: bestSan,
      orientation: orientation,
    );
  }

  /// The whole-game summary: both sides' accuracy, how many of their moves
  /// fell into each label, and how often each side played the engine's own
  /// move.
  ///
  /// Accuracy and the label counts were computed at save time and are read off
  /// the record — nothing recalculates them here. The correlation row is the
  /// exception and crosses the bridge, which is why it is memoised on the board
  /// controller rather than computed in this method: it walks every move
  /// through chess.js, and this rebuilds on every cursor step.
  ///
  /// [order] is the brain's LABEL_ORDER. Rows are dropped when neither side
  /// has any, so a clean game is a short grid rather than seven zeroes.
  Widget _summary(
    Map<String, dynamic> game,
    ClassTable table,
    List<String> order,
    ReviewBoardController board,
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
    // How often each side found the engine's own first choice (#276). Derived
    // rather than read off the record, so it works for the whole archive and
    // not only for games saved after it existed — and it disagrees with
    // accuracy in a useful way, because accuracy is dominated by the worst
    // move in the game while this counts how often you actually saw it.
    // Memoised on the board controller: it walks every move through chess.js,
    // and this method reruns on every cursor move.
    final wCorr = board.correlationFor('w');
    final bCorr = board.correlationFor('b');

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

    // "31 of 40" rather than a bare percentage: the denominator is the point,
    // because forced moves are excluded and a short game says less than a long
    // one. A side with nothing countable gets a dash, never 0%.
    Widget correlationCell(({int played, int total})? c) => SizedBox(
      width: kCol,
      child: Text(
        c == null ? '—' : '${c.played} of ${c.total}',
        textAlign: TextAlign.end,
        style: const TextStyle(fontSize: 12.5, color: Colors.white70),
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
          if (wCorr != null || bCorr != null)
            Padding(
              key: const ValueKey('summary-row-correlation'),
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Expanded(
                    // maxLines/overflow for the same reason every label row
                    // below has them: at 720px with the splitter at kMaxSplit
                    // this wrapped to fifteen lines, one character each, and
                    // ate 276px of the pane without ever throwing.
                    child: Text(
                      'Played the top move',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white54, fontSize: 12.5),
                    ),
                  ),
                  correlationCell(wCorr),
                  correlationCell(bCorr),
                ],
              ),
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

  /// "Practise this game's mistakes" (#197): sends this game's collected
  /// blunder positions to the Practice tab as a scoped drill.
  ///
  /// Drawn only when there is somewhere to send them AND something to send —
  /// the count is the collection's own items that fall on this game's
  /// move-before fens, so a game whose mistakes were never collected (an
  /// ungraded import) or already curated away offers no button rather than a
  /// dead one. The scope handed on is every move-before fen; the controller
  /// intersects it with the collection, so what runs is exactly those [n].
  ///
  /// The fens handed over are the ones YOU faced, not every position in the
  /// game. Matching the move played there as well would be exact for committed
  /// moves and WRONG for the two kinds this app collects deliberately: a
  /// blunder refusal mode caught before it was played, and one you took back —
  /// neither is in the move list, and both are this game's own mistakes.
  Widget _practiseCta(BuildContext context, ReviewController review) {
    final onPractise = onPractiseGame;
    if (onPractise == null) return const SizedBox.shrink();
    final practice = context.watch<PracticeController>();
    if (!practice.loaded) return const SizedBox.shrink();
    // YOUR positions, not every position in the game (#285). An item's id is
    // its fen and items are deduped on that across the whole collection, so
    // handing over the bot's positions too offered puzzles collected in some
    // OTHER game where you had the other colour — moves you never made.
    //
    // botColor names the side you did NOT play. It is absent on a pasted PGN
    // and on an analysis game, where there is no "you" — and `!=` against null
    // is true for both colours, so those keep every position without needing a
    // guard of their own. (Neither collects anything anyway: the collector
    // gates on botEnabled && isHumanSide.)
    final botColor = review.current?['botColor'];
    final fens = <String>{
      for (final m in review.moves)
        if (m['fenBefore'] is String && m['color'] != botColor)
          m['fenBefore'] as String,
    };
    final n = practice.countForGame(fens);
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => onPractise(fens),
          icon: const Icon(Icons.fitness_center, size: 18),
          label: Text(
            n == 1
                ? "Practise this game's mistake"
                : "Practise this game's $n mistakes",
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF81B64C),
            foregroundColor: const Color(0xFF161512),
          ),
        ),
      ),
    );
  }

  /// The move list, headed by the win-chance chart and the [summary].
  ///
  /// Both ride INSIDE the scrollable rather than above it: Review's board is
  /// sized against `kReviewFixed` (layout.dart), so anything added to that
  /// column has to be paid for out of the board. The chart is scroll-away
  /// context, not a control — and both it and the summary are cheap to keep in
  /// the header, drawn from stored numbers rather than recomputed on a scrub.
  Widget _moveList(ReviewController review, ReviewBoardController board,
      ClassTable table, Widget summary, Widget practiseCta) {
    final moves = review.moves;
    final tree = board.tree;
    final mainline = tree?.mainline ?? const <ReviewNode>[];
    // A move played PAST the end of the game replaces ply n+1, which on an
    // even-length game falls in a row the archive does not reach. Without the
    // extra row that branch — the "how should it have gone on?" line, the most
    // natural thing to try — prints nowhere.
    final trailing = mainline.isNotEmpty &&
        mainline.length.isEven &&
        mainline.last.variations.isNotEmpty;
    return ListView.builder(
      itemCount: (moves.length + 1) ~/ 2 + 1 + (trailing ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          // The chart hides itself on an ungraded game (fewer than two graded
          // plies), so this header collapses to just the summary there. The
          // practise CTA sits under the summary — a whole-game action beside
          // the whole-game numbers — and hides itself when there is nothing to
          // drill.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [const ReviewWinChart(), summary, practiseCta],
          );
        }
        final i = index - 1;
        // Both nullable: the trailing row above has no archived moves in it at
        // all, only the branch that continues past them.
        final white = i * 2 < moves.length ? moves[i * 2] : null;
        final black = i * 2 + 1 < moves.length ? moves[i * 2 + 1] : null;
        Widget cell(Map<String, dynamic>? m, int ply) {
          if (m == null) return const SizedBox();
          final label = m['label'] as String?;
          // Highlighted from the BOARD's cursor, and only when it is actually
          // on the played game — inside a variation the anchor says which move
          // the branch hangs off, which is context, not "you are here".
          final active = board.reviewAnchorPly == ply && !board.inVariation;
          return InkWell(
            onTap: () => board.gotoMainlinePly(ply),
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

        // Variations replacing either half of this move pair, printed under it
        // the way a book does — the played move keeps the row, the
        // alternatives are indented beneath it (#196).
        //
        // A variation hangs off the node BEFORE the move it replaces: it is a
        // child of the position that move was played from. So an alternative
        // to ply P is carried by ply P-1, and ply 1's alternatives are carried
        // by the ROOT. Indexing the carrier instead of the replaced move put
        // every branch one row too early — an alternative to White's second
        // move printed above move 1 — and left a branch off the start position
        // rendered by nothing at all, since no mainline node carries it.
        final branches = <ReviewNode>[
          // `<= length + 1`, not `<= length`: the ply one past the end of the
          // game is a real place to have played something, and its carrier is
          // the game's last move.
          for (final ply in [i * 2 + 1, i * 2 + 2])
            if (ply <= mainline.length + 1)
              ...(ply == 1 ? tree!.root : mainline[ply - 2]).variations
        ];

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${i + 1}.',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                  Expanded(child: cell(white, i * 2 + 1)),
                  Expanded(child: cell(black, i * 2 + 2)),
                ],
              ),
              for (final b in branches) _variationRow(b, board),
            ],
          ),
        );
      },
    );
  }

  /// One variation, printed as its line of moves — and, indented under it,
  /// any variation branching off THAT line.
  ///
  /// The recursion is not a flourish. Without it a second reply to a branch
  /// move rendered nowhere, and because backing out of a branch deliberately
  /// forgets the way onward, it was then reachable by no control at all: the
  /// tree held a line the user had played and could neither see nor return to,
  /// and the only way to be rid of it was discarding the whole outer branch.
  ///
  /// [depth] only sets the indent. Real games do not nest deeply, and a line
  /// that did would wrap rather than overflow (the moves live in a [Wrap]).
  Widget _variationRow(ReviewNode branch, ReviewBoardController board,
      {int depth = 0}) {
    final line = <ReviewNode>[];
    for (ReviewNode? n = branch; n != null; n = n.mainChild) {
      line.add(n);
    }
    final current = board.tree?.current;
    // Numbered like a book — "2." for a White alternative, "2..." for a Black
    // one. Without it, two branches replacing different moves render as two
    // identical indented rows in the same group, and nothing says which move
    // either departs from.
    final ply = branch.ply;
    final label =
        branch.color == 'b' ? '${(ply + 1) ~/ 2}...' : '${(ply + 1) ~/ 2}.';
    // Sub-branches of every move ON this line, each printed under it.
    final nested = <ReviewNode>[
      for (final n in line) ...n.variations,
    ];
    return Padding(
      padding: EdgeInsets.only(left: 30.0 + depth * 12, top: 1, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(label,
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11)),
              ),
              for (final n in line)
                InkWell(
                  onTap: () => board.gotoNode(n),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: identical(n, current)
                        ? BoxDecoration(
                            color: const Color(0xFF3a3733),
                            borderRadius: BorderRadius.circular(4),
                          )
                        : null,
                    child: Text(
                      n.san ?? '',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFE8B44A)),
                    ),
                  ),
                ),
            ],
          ),
          for (final b in nested)
            _variationRow(b, board, depth: depth + 1),
        ],
      ),
    );
  }

  Widget _scrubBar(ReviewBoardController board, BuildContext context) {
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
              onPressed: board.canStepBack ? () => board.gotoStart() : null,
              icon: const Icon(Icons.first_page),
              color: Colors.white70,
            ),
            IconButton(
              onPressed: board.canStepBack ? board.stepBack : null,
              icon: const Icon(Icons.chevron_left),
              color: Colors.white70,
              iconSize: 30,
            ),
            const SizedBox(width: 20),
            IconButton(
              onPressed: board.canStepForward ? board.stepForward : null,
              icon: const Icon(Icons.chevron_right),
              color: Colors.white70,
              iconSize: 30,
            ),
            IconButton(
              onPressed: board.canStepForward ? () => board.gotoEnd() : null,
              icon: const Icon(Icons.last_page),
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }
}
