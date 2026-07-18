// The drill: one puzzle at a time — play the strong move on a live board.
// Hints escalate (text → origin square → reveal), pass/fail records into the
// Leitner schedule, the action row is Retry / Show best / Next.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/practice_controller.dart';

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  ChessboardController? _controller;
  String _boardSig = '';

  @override
  void initState() {
    super.initState();
    final practice = context.read<PracticeController>();
    if (practice.current == null) practice.startSession();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Position _position(Map<String, dynamic> item, AttemptOutcome? attempt) {
    Position pos = Chess.fromSetup(Setup.parseFen(item['fen'] as String));
    if (attempt != null) {
      final m = NormalMove.fromUci(attempt.uci);
      if (pos.isLegal(m)) pos = pos.playUnchecked(m);
    }
    return pos;
  }

  GameData _gameData(Position pos, AttemptOutcome? attempt) => GameData(
        fen: pos.fen,
        lastMove:
            attempt == null ? null : NormalMove.fromUci(attempt.uci),
        playerSide: attempt == null
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Practice · ${practice.due} due'
          '${practice.sessionSolved > 0 ? ' · ✓${practice.sessionSolved}' : ''}'
          '${practice.sessionStreak > 1 ? ' · 🔥${practice.sessionStreak}' : ''}',
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: item == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No puzzles yet.\nMoves that lose ≥15% win chance are '
                  'collected here automatically as you play.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, height: 1.4),
                ),
              ),
            )
          : _puzzle(context, practice, item),
    );
  }

  Widget _puzzle(BuildContext context, PracticeController practice,
      Map<String, dynamic> item) {
    final attempt = practice.attempt;
    final pos = _position(item, attempt);
    final sideToMove =
        (item['fen'] as String).split(' ')[1] == 'w' ? 'White' : 'Black';

    final sig = '${item['id']}-${attempt?.uci ?? ''}';
    _controller ??= ChessboardController(game: _gameData(pos, attempt));
    if (_boardSig != sig) {
      _boardSig = sig;
      _controller!.updatePosition(_gameData(pos, attempt));
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Chessboard(
              controller: _controller!,
              size: constraints.maxWidth,
              orientation:
                  (item['fen'] as String).split(' ')[1] == 'w'
                      ? Side.white
                      : Side.black,
              onMove: (move, {viaDragAndDrop}) {
                if (move is! NormalMove || !pos.isLegal(move)) return;
                final (_, san) = pos.makeSan(move);
                final after = pos.playUnchecked(move);
                practice.checkAttempt(move.uci, san, after.fen);
              },
              shapes: _shapes(item, practice),
              settings: const ChessboardSettings(
                enableCoordinates: true,
                animationDuration: Duration(milliseconds: 150),
              ),
            ),
          ),
          _promptStrip(item, practice, sideToMove),
          const Spacer(),
          _actionRow(practice),
        ],
      ),
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
      shapes.add(Arrow(
          color: const Color(0xB3CA3431), orig: r.from, dest: r.to));
    }
    return shapes;
  }

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
      content = Text(
        '✓ ${attempt.san}'
        '${attempt.drop <= 0 ? ' — as strong as the best move' : ' — costs ${attempt.drop.round()}%, good enough'}',
        style: const TextStyle(
            color: Color(0xFF81B64C), fontWeight: FontWeight.w600),
      );
    } else {
      content = Text(
        '✗ ${attempt.san} — drops ${attempt.drop.round()}% '
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
    return Container(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        top: 6,
        bottom: 6 + MediaQuery.of(context).padding.bottom,
      ),
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
          if (attempt != null && !attempt.pass)
            TextButton(
              onPressed: practice.retry,
              child: const Text('Retry',
                  style: TextStyle(color: Colors.white70)),
            ),
          if (attempt != null && !attempt.pass && !practice.revealBest)
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
