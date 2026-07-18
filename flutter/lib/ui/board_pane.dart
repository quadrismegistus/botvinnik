// The board: chessground wired to GameController. Full viewport width —
// the agreed phone shell pins it at the top.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';
import 'board_theme.dart';

class BoardPane extends StatefulWidget {
  const BoardPane({super.key});

  @override
  State<BoardPane> createState() => _BoardPaneState();
}

class _BoardPaneState extends State<BoardPane> {
  ChessboardController? _controller;
  String? _lastFen;

  GameData _gameData(GameController game) {
    // preview: the board narrates a line; input off until it comes home
    final previewFen = game.previewFen;
    if (previewFen != null) {
      final pos = Chess.fromSetup(Setup.parseFen(previewFen));
      return GameData(
        fen: previewFen,
        lastMove: game.previewLastMove,
        playerSide: PlayerSide.none,
        validMoves: makeLegalMoves(pos),
        sideToMove: pos.turn,
        kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
      );
    }
    final pos = game.position;
    return GameData(
      fen: pos.fen,
      lastMove: game.lastMove,
      playerSide: !game.botEnabled
          ? PlayerSide.both // analysis board: move either side
          : game.playerColor == 'w'
              ? PlayerSide.white
              : PlayerSide.black,
      validMoves: makeLegalMoves(pos),
      sideToMove: pos.turn,
      kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final sig =
        '${game.previewFen ?? game.position.fen}|${game.botEnabled}|${game.playerColor}';
    _controller ??= ChessboardController(game: _gameData(game));
    if (_lastFen != sig) {
      _lastFen = sig;
      _controller!.updatePosition(_gameData(game));
    }

    final orientation = game.playerColor == 'w' ? Side.white : Side.black;
    final threatUci = game.previewing ? null : game.threatUci;
    final control = game.previewing ? null : game.controlMap;
    final engineArrows = game.previewing ? const <String>[] : game.engineArrowUcis;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        final board = Chessboard(
          controller: _controller!,
          size: size,
          orientation: orientation,
          onMove: (move, {viaDragAndDrop}) {
            if (move is! NormalMove || !game.position.isLegal(move)) return;
            final (_, san) = game.position.makeSan(move);
            game.playerMove(move, san);
          },
          shapes: {
            // the engine's top moves, green fading by rank (web's g0/g1/g2)
            for (var i = 0; i < engineArrows.length; i++)
              Arrow(
                color: kEngineArrowColors[i],
                orig: NormalMove.fromUci(engineArrows[i]).from,
                dest: NormalMove.fromUci(engineArrows[i]).to,
              ),
            // the opponent's threat (null-move probe), drawn as a warning
            if (threatUci != null)
              Arrow(
                color: const Color(0xE6C62828),
                orig: NormalMove.fromUci(threatUci).from,
                dest: NormalMove.fromUci(threatUci).to,
              ),
          },
          settings: kBoardSettings,
        );
        if (control == null || control.isEmpty) return board;
        return Stack(children: [
          board,
          IgnorePointer(
            child: CustomPaint(
              size: Size(size, size),
              painter: _ControlPainter(control, orientation,
                  game.playerColor == 'w' ? 'w' : 'b'),
            ),
          ),
        ]);
      },
    );
  }
}

/// The square-control tint: green where your side owns the square, red where
/// the opponent does (the web's radial-gradient look, canvas edition).
class _ControlPainter extends CustomPainter {
  final Map<String, String> control;
  final Side orientation;
  final String us;
  _ControlPainter(this.control, this.orientation, this.us);

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.width / 8;
    for (final entry in control.entries) {
      final file = entry.key.codeUnitAt(0) - 'a'.codeUnitAt(0);
      final rank = int.parse(entry.key[1]) - 1;
      final x = orientation == Side.white ? file : 7 - file;
      final y = orientation == Side.white ? 7 - rank : rank;
      final center = Offset((x + 0.5) * sq, (y + 0.5) * sq);
      final ours = entry.value == us;
      final base = ours ? const Color(0xFF81B64C) : const Color(0xFFCA3431);
      canvas.drawCircle(
        center,
        sq * 0.5,
        Paint()
          ..shader = RadialGradient(colors: [
            base.withValues(alpha: 0.38),
            base.withValues(alpha: 0.14),
          ]).createShader(
              Rect.fromCircle(center: center, radius: sq * 0.5)),
      );
    }
  }

  @override
  bool shouldRepaint(_ControlPainter old) =>
      old.control != control || old.orientation != orientation;
}
