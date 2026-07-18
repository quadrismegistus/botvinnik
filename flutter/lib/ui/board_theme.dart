// The board's visual theme: near-neutral squares so the overlay colors carry
// ALL the signal — red/green control tints and threat arrows read instantly
// (the original brown theme's dark squares fought the red).
//
// The squares aren't on the pure black-gray-white axis: they sit on the
// SAME chroma ratio as the app background (0xFF161512), so extrapolating
// the ramp downward lands exactly on the shell color. Warm enough to feel
// of a piece with the app, far too desaturated to compete with the tints.
// Lightness is tuned to keep the black pieces' silhouette. Last move: yellow.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/widgets.dart';

const ChessboardColorScheme kGrayScheme = ChessboardColorScheme(
  lightSquare: Color(0xff86806e),
  darkSquare: Color(0xff565246),
  background: SolidColorChessboardBackground(
    lightSquare: Color(0xff86806e),
    darkSquare: Color(0xff565246),
  ),
  whiteCoordBackground: SolidColorChessboardBackground(
    lightSquare: Color(0xff86806e),
    darkSquare: Color(0xff565246),
    coordinates: true,
  ),
  blackCoordBackground: SolidColorChessboardBackground(
    lightSquare: Color(0xff86806e),
    darkSquare: Color(0xff565246),
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
