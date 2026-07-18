// Spike: the full botvinnik pipeline on a phone —
//   native Stockfish (FFI) → MultiPV lines → bot.ts (JavaScriptCore) → move
// You play White; Square 600 (the shaped bot, exact web code) plays Black.

import 'dart:math';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart' hide Step;

import 'engine.dart';
import 'shaping.dart';

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

const int kLabel = 600; // Square 600 — the shaped bot's calibrated label

class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  Position position = Chess.initial;
  Move? lastMove;
  late final ChessboardController controller;

  SearchEngine? engine;
  ShapingLayer? shaping;
  String status = 'booting engine…';
  String botSays = '';
  bool botThinking = false;
  final String gameSeed = 'spike${Random().nextInt(1 << 30)}';

  @override
  void initState() {
    super.initState();
    controller = ChessboardController(game: _gameData());
    _boot();
  }

  Future<void> _boot() async {
    try {
      shaping = await ShapingLayer.load();
      engine = await SearchEngine.start();
      setState(() => status = 'Square $kLabel ready — you are White');
      // pipeline self-test: play 1.e4 so the bot must answer through the
      // whole chain (remove once the board is tappable by a human)
      await Future.delayed(const Duration(milliseconds: 500));
      await _onUserMove(NormalMove.fromUci('e2e4'));
    } catch (e) {
      setState(() => status = 'boot failed: $e');
    }
  }

  @override
  void dispose() {
    engine?.dispose();
    shaping?.dispose();
    controller.dispose();
    super.dispose();
  }

  GameData _gameData() {
    return GameData(
      fen: position.fen,
      lastMove: lastMove,
      playerSide: PlayerSide.white,
      validMoves: makeLegalMoves(position),
      sideToMove: position.turn,
      kingSquareInCheck:
          position.isCheck ? position.board.kingOf(position.turn) : null,
    );
  }

  void _applyMove(Move move) {
    position = position.playUnchecked(move);
    lastMove = move;
    controller.updatePosition(_gameData());
  }

  Future<void> _onUserMove(Move move, {bool? viaDragAndDrop}) async {
    if (!position.isLegal(move) || botThinking) return;
    setState(() => _applyMove(move));
    await _botReply();
  }

  Future<void> _botReply() async {
    final sf = engine;
    final js = shaping;
    if (sf == null || js == null || position.isGameOver) return;

    setState(() {
      botThinking = true;
      status = 'Square $kLabel is thinking…';
    });
    try {
      final depth = js.searchDepth(kLabel);
      final lines = await sf.search(position.fen, depth);
      final lastTo =
          lastMove is NormalMove ? (lastMove as NormalMove).uci.substring(2, 4) : null;
      final uci = js.pickMove(
        lines: lines,
        label: kLabel,
        seed: gameSeed,
        fen: position.fen,
        lastMoveTo: lastTo,
      );
      final best = (lines.first['pv'] as List).first as String;
      final chosen = uci ?? best;
      final move = NormalMove.fromUci(chosen);
      if (position.isLegal(move)) {
        setState(() {
          _applyMove(move);
          botSays = chosen == best
              ? 'played $chosen (the best move)'
              : 'played $chosen (best was $best — shaped miss)';
          status = position.isGameOver
              ? 'game over'
              : 'Square $kLabel ready — your move';
        });
      } else {
        setState(() => status = 'illegal pick $chosen ?!');
      }
    } catch (e) {
      setState(() => status = 'bot error: $e');
    } finally {
      setState(() => botThinking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('botvinnik flutter spike'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'New game',
            onPressed: () => setState(() {
              position = Chess.initial;
              lastMove = null;
              botSays = '';
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
                onMove: _onUserMove,
                settings: const ChessboardSettings(
                  enableCoordinates: true,
                  animationDuration: Duration(milliseconds: 150),
                  drawShape: DrawShapeOptions(enable: true),
                ),
              );
            },
          ),
          // grade-strip slot: engine status + what the bot did
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFF262421),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status,
                    style: const TextStyle(
                        color: Color(0xFF81B64C), fontSize: 14)),
                if (botSays.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(botSays,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
