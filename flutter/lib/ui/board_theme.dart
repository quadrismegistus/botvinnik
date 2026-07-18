// The board's visual theme: grayscale squares so the overlay colors carry
// ALL the signal — red/green control tints and threat arrows read instantly
// against neutral squares (the brown theme's dark squares fought the red).
// Squares are mid-gray: dark enough to sit inside the near-black shell,
// light enough that the black pieces keep their silhouette.
// Last-move highlight is yellow.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/widgets.dart';

const ChessboardColorScheme kGrayScheme = ChessboardColorScheme(
  lightSquare: Color(0xff827f7a),
  darkSquare: Color(0xff54524e),
  background: SolidColorChessboardBackground(
    lightSquare: Color(0xff827f7a),
    darkSquare: Color(0xff54524e),
  ),
  whiteCoordBackground: SolidColorChessboardBackground(
    lightSquare: Color(0xff827f7a),
    darkSquare: Color(0xff54524e),
    coordinates: true,
  ),
  blackCoordBackground: SolidColorChessboardBackground(
    lightSquare: Color(0xff827f7a),
    darkSquare: Color(0xff54524e),
    coordinates: true,
    orientation: Side.black,
  ),
  lastMove: HighlightDetails(solidColor: Color(0x80f0d000)),
  selected: HighlightDetails(solidColor: Color(0x60303030)),
  validMoves: Color(0x40222222),
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
