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
