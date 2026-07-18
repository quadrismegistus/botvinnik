// The board: chessground wired to GameController. Full viewport width —
// the agreed phone shell pins it at the top.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';
import '../stores/settings_store.dart';
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
    // browsing history: show the past position, input off until you come back
    final browseFen = game.browseFen;
    if (browseFen != null) {
      final pos = Chess.fromSetup(Setup.parseFen(browseFen));
      return GameData(
        fen: browseFen,
        lastMove: game.browseLastMove,
        playerSide: PlayerSide.none,
        validMoves: makeLegalMoves(pos),
        sideToMove: pos.turn,
        kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
      );
    }
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
    final settings = context.watch<SettingsStore>();
    final sig = '${game.browseFen ?? game.previewFen ?? game.position.fen}'
        '|${game.botEnabled}|${game.playerColor}';
    _controller ??= ChessboardController(game: _gameData(game));
    if (_lastFen != sig) {
      _lastFen = sig;
      _controller!.updatePosition(_gameData(game));
    }

    final white = (game.playerColor == 'w') != game.flipped;
    final orientation = white ? Side.white : Side.black;
    // the overlays describe the LIVE position, so they are meaningless while
    // the board is showing a preview or a past move
    final still = game.previewing || game.browsing;
    final threatUci = still ? null : game.threatUci;
    final control = still ? null : game.controlMap;
    final engineArrows = still ? const <String>[] : game.engineArrowUcis;
    final arrowColors = engineArrowColors(settings.arrowOpacity);

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
            // the engine's top moves, fading by rank (web's g0/g1/g2)
            for (var i = 0; i < engineArrows.length; i++)
              Arrow(
                color: arrowColors[i],
                orig: NormalMove.fromUci(engineArrows[i]).from,
                dest: NormalMove.fromUci(engineArrows[i]).to,
              ),
            // the opponent's threat (null-move probe), drawn as a warning
            if (threatUci != null)
              Arrow(
                color: threatArrowColor(settings.threatOpacity),
                orig: NormalMove.fromUci(threatUci).from,
                dest: NormalMove.fromUci(threatUci).to,
              ),
          },
          settings: boardSettingsFor(settings),
        );
        final threatLabel = threatUci == null ? null : _threatLabel(game);
        if ((control == null || control.isEmpty) && threatLabel == null) {
          return board;
        }
        return Stack(children: [
          board,
          if (threatLabel != null)
            _ThreatHover(
              size: size,
              orientation: orientation,
              square: NormalMove.fromUci(threatUci!).to.name,
              label: threatLabel,
            ),
          if (control != null && control.isNotEmpty)
          IgnorePointer(
            child: CustomPaint(
              size: Size(size, size),
              painter: _ControlPainter(control, orientation,
                  game.playerColor == 'w' ? 'w' : 'b', settings.controlOpacity),
            ),
          ),
        ]);
      },
    );
  }
}

String? _threatLabel(GameController game) {
  final san = game.threatSan;
  if (san == null || game.threatUci == null) return null;
  final gain = game.threatGain;
  // a null gain is mate, not nothing: Infinity cannot cross the JSON bridge
  return gain == null
      ? '$san — mates'
      : '$san — costs ${gain.abs().toStringAsFixed(1)}';
}

/// Hovering the square the threat lands on explains it. Hover only, and
/// deliberately not a Tooltip: a Tooltip brings a long-press recogniser with
/// it, which on a touch screen would fight the board for the same gesture.
/// Touch users get the same sentence in the grade strip instead.
class _ThreatHover extends StatefulWidget {
  final double size;
  final Side orientation;
  final String square;
  final String label;
  const _ThreatHover({
    required this.size,
    required this.orientation,
    required this.square,
    required this.label,
  });

  @override
  State<_ThreatHover> createState() => _ThreatHoverState();
}

class _ThreatHoverState extends State<_ThreatHover> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final sq = widget.size / 8;
    final file = widget.square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.parse(widget.square[1]) - 1;
    final x = widget.orientation == Side.white ? file : 7 - file;
    final y = widget.orientation == Side.white ? 7 - rank : rank;
    return Positioned(
      left: x * sq,
      top: y * sq,
      width: sq,
      height: sq,
      child: MouseRegion(
        opaque: false, // taps and drags still reach the board underneath
        onEnter: (_) => setState(() => _over = true),
        onExit: (_) => setState(() => _over = false),
        child: !_over
            ? const SizedBox.expand()
            : OverflowBox(
                maxWidth: 260,
                alignment: y == 0 ? Alignment.bottomCenter : Alignment.topCenter,
                child: Padding(
                  // clear of the square itself so the arrowhead stays visible
                  padding: EdgeInsets.only(
                      top: y == 0 ? sq + 4 : 0, bottom: y == 0 ? 0 : sq + 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xF01f1e1b),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0x66C62828)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      child: Text('threat: ${widget.label}',
                          maxLines: 1,
                          style: const TextStyle(
                              color: Color(0xFFE0908E),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The square-control tint: green where your side owns the square, red where
/// the opponent does. A flat wash of the whole square — the web draws a
/// fading circle because the tint is a CSS background there, but on this
/// canvas layer the square itself is the honest unit of "who controls it".
class _ControlPainter extends CustomPainter {
  final Map<String, String> control;
  final Side orientation;
  final String us;
  final double peak;
  _ControlPainter(this.control, this.orientation, this.us, this.peak);

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.width / 8;
    for (final entry in control.entries) {
      final file = entry.key.codeUnitAt(0) - 'a'.codeUnitAt(0);
      final rank = int.parse(entry.key[1]) - 1;
      final x = orientation == Side.white ? file : 7 - file;
      final y = orientation == Side.white ? 7 - rank : rank;
      final ours = entry.value == us;
      final base = ours ? kControlOurs : kControlTheirs;
      canvas.drawRect(
        Rect.fromLTWH(x * sq, y * sq, sq, sq),
        Paint()..color = base.withValues(alpha: peak),
      );
    }
  }

  @override
  bool shouldRepaint(_ControlPainter old) =>
      old.control != control ||
      old.orientation != orientation ||
      old.peak != peak;
}
