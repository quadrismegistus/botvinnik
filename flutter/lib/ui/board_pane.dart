// The board: chessground wired to GameController. Full viewport width —
// the agreed phone shell pins it at the top.

import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:flutter/foundation.dart' show setEquals, visibleForTesting;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/chess_api.dart' show ControlCell;
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
          : game.botBothSides
              ? PlayerSide.none // bot-vs-bot: you watch, nothing to drag
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
        '|${game.botEnabled}|${game.playerColor}|${game.botBothSides}';
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
    // ring the pieces the threat actually wins — minus the arrow's own
    // destination square, which already carries the arrowhead
    final threatTargets = still || threatUci == null
        ? const <String>[]
        : [
            for (final t in game.threatTargets)
              if (t != threatUci.substring(2, 4)) t
          ];
    final control = still ? null : game.controlMap;
    final engineArrows = still ? const <String>[] : game.engineArrowUcis;
    final arrowColors = engineArrowColors(settings.arrowOpacity);
    // the green mirror: pieces YOUR top line wins, in the engine-arrow
    // grammar — minus the top arrow's own destination (a direct capture
    // already carries the arrowhead). They can never collide with the red
    // rings: threat victims are your pieces, win victims are theirs.
    final winTargets = still
        ? const <String>[]
        : [
            for (final t in game.winTargets)
              if (engineArrows.isEmpty ||
                  t != engineArrows.first.substring(2, 4))
                t
          ];

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
            // the pieces that threat wins, ringed — the arrow shows the MOVE,
            // and on a quiet setup move (fork, mate threat, chase) the
            // victims stand elsewhere
            for (final t in threatTargets)
              Circle(
                color: threatArrowColor(settings.threatOpacity),
                orig: Square.fromName(t),
              ),
            // the pieces your own top line wins, in the arrows' colour
            for (final t in winTargets)
              Circle(
                color: arrowColors.first,
                orig: Square.fromName(t),
              ),
          },
          settings: boardSettingsFor(settings),
        );
        if (control == null || control.isEmpty) {
          return board;
        }
        return Stack(children: [
          board,
          if (control.isNotEmpty)
          IgnorePointer(
            child: CustomPaint(
              size: Size(size, size),
              painter: _ControlPainter(
                control,
                orientation,
                game.playerColor == 'w' ? 'w' : 'b',
                settings.controlOpacity,
                {for (final s in game.position.board.occupied.squares) s.name},
                // one glyph per square: threat/win rings and any arrowhead
                // (red or blue) outrank control's ring on the same piece
                {
                  ...threatTargets,
                  ...winTargets,
                  if (threatUci != null) threatUci.substring(2, 4),
                  for (final u in engineArrows) u.substring(2, 4),
                },
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// The square-control overlay, two claims in two shapes. EMPTY squares get a
/// flat wash — "this side owns this square", a statement about territory.
/// OCCUPIED squares get a ring around the piece — "this piece is winnable /
/// falling where it stands", a statement about the piece, and the urgent one.
/// Rings share the visual grammar of the threat overlay's victim rings, which
/// outrank them on the same square.
///
/// Opacity is graded by each cell's exchange margin: an uncontested square
/// (margin 0) paints at the base opacity the user chose, and a square where a
/// whole queen swings paints up toward full — so "how decisively" reads off
/// the board, not just "who". The base for margin 0 matches the old flat
/// look, so nothing dims; contested squares only get brighter.
/// The exchange-margin → tint-intensity multiplier the control painter grades
/// opacity by. Exposed for tests: canvas alpha can't be asserted through a
/// widget test, but this pure mapping is the whole of the new intensity logic —
/// margin 0 returns 1.0 (the old flat look, so nothing dims), a queen (9) returns
/// 2.0, and anything beyond is clamped so a high base opacity still holds.
@visibleForTesting
double controlTintGrade(double margin) => 1 + (margin.clamp(0, 9) / 9);

class _ControlPainter extends CustomPainter {
  final Map<String, ControlCell> control;
  final Side orientation;
  final String us;
  final double peak;
  final Set<String> occupied;
  final Set<String> threatRinged;
  _ControlPainter(this.control, this.orientation, this.us, this.peak,
      this.occupied, this.threatRinged);

  // margin 0 -> 1x, a queen (9) -> 2x; clamped so a base past 0.5 still holds.
  static double _grade(double margin) => controlTintGrade(margin);

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.width / 8;
    for (final entry in control.entries) {
      final cell = entry.value;
      final file = entry.key.codeUnitAt(0) - 'a'.codeUnitAt(0);
      final rank = int.parse(entry.key[1]) - 1;
      final x = orientation == Side.white ? file : 7 - file;
      final y = orientation == Side.white ? 7 - rank : rank;
      final ours = cell.side == us;
      final base = ours ? kControlOurs : kControlTheirs;
      final grade = _grade(cell.margin);
      if (occupied.contains(entry.key)) {
        if (threatRinged.contains(entry.key)) continue;
        // twice the wash's opacity: the piece-level claim should pop out of
        // the ambient territory it sits in — then graded by the stake
        final stroke = sq / 14;
        canvas.drawCircle(
          Offset(x * sq + sq / 2, y * sq + sq / 2),
          sq / 2 - stroke * 0.75,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..color = base.withValues(alpha: math.min(1.0, peak * 2 * grade)),
        );
      } else {
        canvas.drawRect(
          Rect.fromLTWH(x * sq, y * sq, sq, sq),
          Paint()
            ..color = base.withValues(alpha: math.min(1.0, peak * grade)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ControlPainter old) =>
      old.control != control ||
      old.orientation != orientation ||
      old.us != us ||
      old.peak != peak ||
      !setEquals(old.occupied, occupied) ||
      !setEquals(old.threatRinged, threatRinged);
}
