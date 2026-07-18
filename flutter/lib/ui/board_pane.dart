// The board: chessground wired to GameController. Full viewport width —
// the agreed phone shell pins it at the top.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';

class BoardPane extends StatefulWidget {
  const BoardPane({super.key});

  @override
  State<BoardPane> createState() => _BoardPaneState();
}

class _BoardPaneState extends State<BoardPane> {
  ChessboardController? _controller;
  String? _lastFen;

  GameData _gameData(GameController game) {
    final pos = game.position;
    return GameData(
      fen: pos.fen,
      lastMove: game.lastMove,
      playerSide: game.playerColor == 'w' ? PlayerSide.white : PlayerSide.black,
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
    _controller ??= ChessboardController(game: _gameData(game));
    if (_lastFen != game.position.fen) {
      _lastFen = game.position.fen;
      _controller!.updatePosition(_gameData(game));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Chessboard(
          controller: _controller!,
          size: constraints.maxWidth,
          orientation: game.playerColor == 'w' ? Side.white : Side.black,
          onMove: (move, {viaDragAndDrop}) {
            if (move is! NormalMove || !game.position.isLegal(move)) return;
            final (_, san) = game.position.makeSan(move);
            game.playerMove(move, san);
          },
          settings: const ChessboardSettings(
            enableCoordinates: true,
            animationDuration: Duration(milliseconds: 150),
            drawShape: DrawShapeOptions(enable: true),
          ),
        );
      },
    );
  }
}
