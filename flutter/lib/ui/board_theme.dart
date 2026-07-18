// The board's visual theme.
//
// The defaults are near-neutral so the overlay colors carry ALL the signal —
// red/green control tints and threat arrows read instantly (the original
// brown theme's dark squares fought the red). They aren't on the pure
// black-gray-white axis: they sit on the SAME chroma ratio as the app
// background (0xFF161512), so the ramp extrapolates down to exactly the
// shell color. Lightness is tuned to keep the black pieces' silhouette.
//
// All three are user-overridable (Settings › Board colors), so nothing here
// is const at the point of use: build the scheme from SettingsStore via
// [schemeFor] so a change repaints the board immediately.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/widgets.dart';

import '../stores/settings_store.dart';

/// A named pair of square colors.
class BoardPreset {
  final String name;
  final Color light;
  final Color dark;
  const BoardPreset(this.name, this.light, this.dark);
}

/// Ready-made boards. The first two are ours — chessground's brown (the
/// default) and the grayscale the control-square overlays were tuned
/// against. The rest are the chessboard.js theme set by Joshua Kunst
/// (github.com/jbkunst/chessboardjs-themes, MIT). That source lists each
/// theme as an unordered pair, so light/dark here are assigned by
/// luminance rather than by the order they appear in.
const List<BoardPreset> kBoardPresets = [
  BoardPreset('Brown', Color(0xfff0d9b6), Color(0xffb58863)),
  BoardPreset('Gray', Color(0xff86806e), Color(0xff565246)),
  BoardPreset('Chess24', Color(0xff9e7863), Color(0xff633526)),
  BoardPreset('Metro', Color(0xffffffff), Color(0xffefefef)),
  BoardPreset('Leipzig', Color(0xffffffff), Color(0xffe1e1e1)),
  BoardPreset('Wikipedia', Color(0xffffce9e), Color(0xffd18b47)),
  BoardPreset('Dilena', Color(0xffffe5b6), Color(0xffb16228)),
  BoardPreset('USCF', Color(0xffc3c6be), Color(0xff727fa2)),
  BoardPreset('Symbol', Color(0xffffffff), Color(0xff58ac8a)),
];

/// The user's piece set, falling back to the default if a stored name no
/// longer exists in chessground.
PieceSet pieceSetFor(SettingsStore s) => PieceSet.values.firstWhere(
      (p) => p.name == s.pieceSet,
      orElse: () => PieceSet.cburnett,
    );

/// The color scheme for the user's chosen square/highlight colors.
ChessboardColorScheme schemeFor(SettingsStore s) {
  final light = s.lightSquare;
  final dark = s.darkSquare;
  return ChessboardColorScheme(
    lightSquare: light,
    darkSquare: dark,
    background:
        SolidColorChessboardBackground(lightSquare: light, darkSquare: dark),
    whiteCoordBackground: SolidColorChessboardBackground(
      lightSquare: light,
      darkSquare: dark,
      coordinates: true,
    ),
    blackCoordBackground: SolidColorChessboardBackground(
      lightSquare: light,
      darkSquare: dark,
      coordinates: true,
      orientation: Side.black,
    ),
    lastMove: HighlightDetails(solidColor: s.lastMoveColor),
    selected: const HighlightDetails(solidColor: Color(0x60303030)),
    validMoves: const Color(0x40222222),
    validPremoves: const Color(0x40203085),
  );
}

/// Settings for the interactive boards.
ChessboardSettings boardSettingsFor(SettingsStore s) => ChessboardSettings(
      colorScheme: schemeFor(s),
      pieceAssets: pieceSetFor(s).assets,
      enableCoordinates: true,
      animationDuration: const Duration(milliseconds: 150),
      drawShape: const DrawShapeOptions(enable: true),
    );

/// Settings for read-only boards (review).
StaticChessboardSettings staticBoardSettingsFor(SettingsStore s) =>
    StaticChessboardSettings(
      colorScheme: schemeFor(s),
      pieceAssets: pieceSetFor(s).assets,
    );

/// The web's top-3 engine-arrow brushes: green fading by rank.
const List<Color> kEngineArrowColors = [
  Color(0xFF15781B), // g0: opacity 1
  Color(0x8C15781B), // g1: 0.55
  Color(0x5215781B), // g2: 0.32
];
