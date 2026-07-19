// The Practice tab: one puzzle at a time — play the strong move on a live
// board. The attempt lands on the board immediately (optimistic) while the
// depth-14 check runs; hints escalate (text → origin square → reveal);
// pass/fail records into the Leitner schedule.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/practice_controller.dart';
import '../stores/settings_store.dart';
import 'board_theme.dart';
import 'layout.dart';

class PracticeTab extends StatefulWidget {
  const PracticeTab({super.key});

  @override
  State<PracticeTab> createState() => _PracticeTabState();
}

class _PracticeTabState extends State<PracticeTab> {
  ChessboardController? _controller;
  String _boardSig = '';

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// The shown position: puzzle fen, plus the attempt (or the optimistic
  /// pending move while the check runs).
  Position _position(Map<String, dynamic> item, String? appliedUci) {
    Position pos = Chess.fromSetup(Setup.parseFen(item['fen'] as String));
    if (appliedUci != null) {
      final m = NormalMove.fromUci(appliedUci);
      if (pos.isLegal(m)) pos = pos.playUnchecked(m);
    }
    return pos;
  }

  GameData _gameData(Position pos, String? appliedUci) => GameData(
        fen: pos.fen,
        lastMove: appliedUci == null ? null : NormalMove.fromUci(appliedUci),
        playerSide: appliedUci == null
            ? (pos.turn == Side.white ? PlayerSide.white : PlayerSide.black)
            : PlayerSide.none,
        validMoves: makeLegalMoves(pos),
        sideToMove: pos.turn,
        kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
      );

  @override
  Widget build(BuildContext context) {
    final practice = context.watch<PracticeController>();
    final item = practice.current;

    if (item == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No puzzles yet.\nMoves that lose ≥15% win chance are '
            'collected here automatically as you play.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, height: 1.4),
          ),
        ),
      );
    }
    return _puzzle(context, practice, item);
  }

  Widget _puzzle(BuildContext context, PracticeController practice,
      Map<String, dynamic> item) {
    final appliedUci = practice.attempt?.uci ?? practice.pendingUci;
    final pos = _position(item, appliedUci);
    final sideToMove =
        (item['fen'] as String).split(' ')[1] == 'w' ? 'White' : 'Black';

    final sig = '${item['id']}-${appliedUci ?? ''}';
    _controller ??= ChessboardController(game: _gameData(pos, appliedUci));
    if (_boardSig != sig) {
      _boardSig = sig;
      _controller!.updatePosition(_gameData(pos, appliedUci));
    }

    final settings = context.watch<SettingsStore>();

    // The board is square, so on a desktop window full width means full-width
    // TALL — which overflowed the viewport by ~900px and pushed the action row
    // off the bottom. Same treatment as PlayTab: cap it when stacked, and put
    // it beside the furniture once there is room.
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget board(double size) => Chessboard(
              controller: _controller!,
              size: size,
              orientation: (item['fen'] as String).split(' ')[1] == 'w'
                  ? Side.white
                  : Side.black,
              onMove: (move, {viaDragAndDrop}) {
                if (move is! NormalMove || !pos.isLegal(move)) return;
                final (_, san) = pos.makeSan(move);
                final after = pos.playUnchecked(move);
                practice.checkAttempt(move.uci, san, after.fen);
              },
              shapes: _shapes(item, practice),
              settings: boardSettingsFor(settings),
            );

        if (constraints.maxWidth < kWideBreakpoint) {
          final size = stackedBoardSize(
              constraints.maxWidth, constraints.maxHeight, kPracticeChrome);
          return Column(
            children: [
              Center(child: board(size)),
              _promptStrip(item, practice, sideToMove),
              _actionRow(practice),
            ],
          );
        }
        final size = wideBoardSize(
            constraints.maxWidth, constraints.maxHeight, settings.split);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            board(size),
            // Hint/Retry/Next belong directly under the prompt they answer.
            // A Spacer here pushed them to the far bottom-right of the pane,
            // half a screen from the sentence they respond to.
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _promptStrip(item, practice, sideToMove),
                  _actionRow(practice),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Set<Shape> _shapes(Map<String, dynamic> item, PracticeController practice) {
    final best = NormalMove.fromUci(item['bestUci'] as String);
    final shapes = <Shape>{};
    if (practice.revealBest) {
      shapes.add(Arrow(
          color: const Color(0xB33BAB4A), orig: best.from, dest: best.to));
    } else if (practice.hintTier >= 2) {
      shapes.add(Circle(color: const Color(0xB3D0B755), orig: best.from));
    }
    final refutation = practice.attempt?.refutationUci;
    if (refutation != null) {
      final r = NormalMove.fromUci(refutation);
      shapes.add(
          Arrow(color: const Color(0xB3CA3431), orig: r.from, dest: r.to));
    }
    return shapes;
  }

  /// Icon plus text. Replaces the ✓ / ✗ these lines used to start with: those
  /// glyphs are in no bundled font, so drawing them made Flutter web fetch
  /// Noto Sans Symbols from fonts.gstatic.com — on every graded attempt, and
  /// unservable offline. The icon font is already here and tree-shaken.
  Widget _verdict(IconData icon, Color color, String text, {TextStyle? style}) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5, right: 6),
            child: Icon(icon, color: color, size: 15),
          ),
          Expanded(child: Text(text, style: style)),
        ],
      );

  Widget _promptStrip(Map<String, dynamic> item, PracticeController practice,
      String sideToMove) {
    final attempt = practice.attempt;
    Widget content;
    if (practice.checking) {
      content = const Text('Checking…',
          style: TextStyle(color: Colors.white54, fontSize: 13));
    } else if (attempt == null) {
      final drop = (item['drop'] as num).toDouble();
      final motifs = (item['motifs'] as List?)?.cast<String>() ?? const [];
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$sideToMove to move — find a strong move',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text(
            'you lost ${drop.round()}% here with ${item['playedSan']}'
            '${practice.hintTier >= 1 && motifs.isNotEmpty ? ' · think: ${motifs.join(', ')}' : ''}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      );
    } else if (attempt.pass) {
      content = _verdict(
        Icons.check_circle_outline,
        const Color(0xFF81B64C),
        '${attempt.san}'
        '${attempt.drop <= 0 ? ' — as strong as the best move' : ' — costs ${attempt.drop.round()}%, good enough'}'
        '${practice.revealBest && attempt.uci != item['bestUci'] ? ' · best was ${item['bestSan']}' : ''}',
        style: const TextStyle(
            color: Color(0xFF81B64C), fontWeight: FontWeight.w600),
      );
    } else {
      content = _verdict(
        Icons.cancel_outlined,
        const Color(0xFFCA3431),
        '${attempt.san} — drops ${attempt.drop.round()}% '
        '${practice.revealBest ? '· best was ${item['bestSan']}' : ''}',
        style: const TextStyle(
            color: Color(0xFFCA3431), fontWeight: FontWeight.w600),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color(0xFF262421),
      child: content,
    );
  }

  Widget _actionRow(PracticeController practice) {
    final attempt = practice.attempt;
    final bestUci = practice.current?['bestUci'] as String?;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF1f1e1b),
      child: Row(
        children: [
          if (attempt == null && practice.hintTier < 3)
            TextButton(
              onPressed: practice.hint,
              child: Text(
                practice.hintTier == 0
                    ? 'Hint'
                    : practice.hintTier == 1
                        ? 'Another hint'
                        : 'Show best',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          // pass or fail: retry to hunt the best, reveal if you haven't
          // found it (a "good enough" pass still has a better move to see)
          if (attempt != null)
            TextButton(
              onPressed: practice.retry,
              child:
                  const Text('Retry', style: TextStyle(color: Colors.white70)),
            ),
          if (attempt != null &&
              !practice.revealBest &&
              attempt.uci != bestUci)
            TextButton(
              onPressed: practice.reveal,
              child: const Text('Show best',
                  style: TextStyle(color: Colors.white70)),
            ),
          const Spacer(),
          FilledButton(
            onPressed: practice.nextPuzzle,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF81B64C),
              foregroundColor: const Color(0xFF161512),
            ),
            child: Text(attempt == null ? 'Skip' : 'Next',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
