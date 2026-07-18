// Spike: prove the three things a botvinnik port needs from a Flutter board —
// 1. render a position (FEN), 2. interactive moves with legal-move dots,
// 3. programmatic arrows (our hint/threat/refutation annotations).
// Chessground (lichess's board) + dartchess (their rules library).

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart' hide Step;

void main() {
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'botvinnik spike',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF81B64C),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF161512),
      ),
      home: const BoardPage(),
    );
  }
}

class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  Position position = Chess.initial;
  Move? lastMove;
  late final ChessboardController controller;
  bool showArrows = true;

  @override
  void initState() {
    super.initState();
    controller = ChessboardController(game: _gameData());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  GameData _gameData() {
    return GameData(
      fen: position.fen,
      lastMove: lastMove,
      // both sides playable — it's a spike, not a game
      playerSide:
          position.turn == Side.white ? PlayerSide.white : PlayerSide.black,
      validMoves: makeLegalMoves(position),
      sideToMove: position.turn,
      kingSquareInCheck:
          position.isCheck ? position.board.kingOf(position.turn) : null,
    );
  }

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    if (!position.isLegal(move)) return;
    setState(() {
      position = position.playUnchecked(move);
      lastMove = move;
      controller.updatePosition(_gameData());
    });
  }

  String _sanOfLast() {
    // spike-grade: uci of the last move (real SAN needs the pre-move position)
    final m = lastMove;
    return m is NormalMove ? m.uci : '—';
  }

  /// A fake "hint" arrow: the first legal move of the side to move —
  /// stands in for our engine-driven hint/threat/refutation arrows.
  Set<Shape> _annotationShapes() {
    if (!showArrows) return const {};
    final entry = position.legalMoves.entries
        .where((e) => e.value.squares.isNotEmpty)
        .firstOrNull;
    if (entry == null) return const {};
    final from = entry.key;
    final to = entry.value.squares.first;
    return {
      Arrow(
        color: const Color(0xB33BAB4A), // green, translucent — hint style
        orig: from,
        dest: to,
      ),
      Circle(
        color: const Color(0xB3CA3431), // red circle — threat style
        orig: position.board.kingOf(position.turn) ?? Square.e4,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('botvinnik flutter spike'),
        actions: [
          IconButton(
            icon: Icon(showArrows ? Icons.visibility : Icons.visibility_off),
            tooltip: 'Toggle annotation shapes',
            onPressed: () => setState(() => showArrows = !showArrows),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset',
            onPressed: () => setState(() {
              position = Chess.initial;
              lastMove = null;
              controller.updatePosition(_gameData());
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return Chessboard(
                controller: controller,
                size: constraints.maxWidth,
                orientation: Side.white,
                onMove: _onMove,
                shapes: _annotationShapes(),
                settings: const ChessboardSettings(
                  enableCoordinates: true,
                  animationDuration: Duration(milliseconds: 150),
                  // let users draw their own arrows with a long press, like lichess
                  drawShape: DrawShapeOptions(enable: true),
                ),
              );
            },
          ),
          // grade-strip mock: where the play→verdict loop will live
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFF262421),
            child: Row(
              children: [
                Text(
                  lastMove != null ? _sanOfLast() : '—',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(width: 10),
                Text(
                  lastMove != null ? '✓ excellent' : 'play a move',
                  style: const TextStyle(
                      color: Color(0xFF81B64C), fontSize: 14),
                ),
                const Spacer(),
                const Text('94% of best',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          position.isCheckmate
              ? 'Checkmate.'
              : '${position.turn == Side.white ? "White" : "Black"} to move'
                  ' — fen: ${position.fen.split(' ').first}',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
