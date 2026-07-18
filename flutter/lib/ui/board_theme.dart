// The board's visual theme: grayscale squares so the overlay colors carry
// ALL the signal — red/green control tints and threat arrows read instantly
// against neutral squares (the brown theme's dark squares fought the red).
// Squares sit just below/above the app background (0xFF161512) so the board
// reads as a subtle inset panel. Last-move highlight is yellow.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/widgets.dart';

const ChessboardColorScheme kGrayScheme = ChessboardColorScheme(
  lightSquare: Color(0xff2c2b28),
  darkSquare: Color(0xff0e0d0c),
  background: SolidColorChessboardBackground(
    lightSquare: Color(0xff2c2b28),
    darkSquare: Color(0xff0e0d0c),
  ),
  whiteCoordBackground: SolidColorChessboardBackground(
    lightSquare: Color(0xff2c2b28),
    darkSquare: Color(0xff0e0d0c),
    coordinates: true,
  ),
  blackCoordBackground: SolidColorChessboardBackground(
    lightSquare: Color(0xff2c2b28),
    darkSquare: Color(0xff0e0d0c),
    coordinates: true,
    orientation: Side.black,
  ),
  lastMove: HighlightDetails(solidColor: Color(0x99f0d000)),
  selected: HighlightDetails(solidColor: Color(0x59ffffff)),
  validMoves: Color(0x3affffff),
  validPremoves: Color(0x40203085),
);

/// Shared settings for the interactive boards.
const ChessboardSettings kBoardSettings = ChessboardSettings(
  colorScheme: kGrayScheme,
  enableCoordinates: true,
  animationDuration: Duration(milliseconds: 150),
  drawShape: DrawShapeOptions(enable: true),
);

/// Shared settings for read-only boards (review).
const StaticChessboardSettings kStaticBoardSettings =
    StaticChessboardSettings(colorScheme: kGrayScheme);

/// The web's top-3 engine-arrow brushes: green fading by rank.
const List<Color> kEngineArrowColors = [
  Color(0xFF15781B), // g0: opacity 1
  Color(0x8C15781B), // g1: 0.55
  Color(0x5215781B), // g2: 0.32
];
