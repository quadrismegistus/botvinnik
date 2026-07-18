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

/// A textured board: chessground bundles the lichess board images, each with
/// the square colors that go under it.
class BoardTexture {
  final String name;
  final String label;
  final ChessboardColorScheme scheme;
  const BoardTexture(this.name, this.label, this.scheme);

  /// The texture image itself, for previewing the board as what it is.
  AssetImage? get image {
    final bg = scheme.background;
    return bg is ImageChessboardBackground ? bg.image : null;
  }
}

const List<BoardTexture> kBoardTextures = [
  BoardTexture('wood', 'Wood', ChessboardColorScheme.wood),
  BoardTexture('wood2', 'Wood 2', ChessboardColorScheme.wood2),
  BoardTexture('wood3', 'Wood 3', ChessboardColorScheme.wood3),
  BoardTexture('wood4', 'Wood 4', ChessboardColorScheme.wood4),
  BoardTexture('maple', 'Maple', ChessboardColorScheme.maple),
  BoardTexture('maple2', 'Maple 2', ChessboardColorScheme.maple2),
  BoardTexture('marble', 'Marble', ChessboardColorScheme.marble),
  BoardTexture('blueMarble', 'Blue marble', ChessboardColorScheme.blueMarble),
  BoardTexture('leather', 'Leather', ChessboardColorScheme.leather),
  BoardTexture('canvas', 'Canvas', ChessboardColorScheme.canvas),
  BoardTexture('metal', 'Metal', ChessboardColorScheme.metal),
  BoardTexture('olive', 'Olive', ChessboardColorScheme.olive),
  BoardTexture('grey', 'Grey', ChessboardColorScheme.grey),
  BoardTexture('newspaper', 'Newspaper', ChessboardColorScheme.newspaper),
  BoardTexture('purple', 'Purple', ChessboardColorScheme.purple),
  BoardTexture('purpleDiag', 'Purple diag', ChessboardColorScheme.purpleDiag),
  BoardTexture('pinkPyramid', 'Pink', ChessboardColorScheme.pinkPyramid),
  BoardTexture('greenPlastic', 'Plastic', ChessboardColorScheme.greenPlastic),
  BoardTexture('blue2', 'Blue', ChessboardColorScheme.blue2),
  BoardTexture('blue3', 'Blue 3', ChessboardColorScheme.blue3),
  BoardTexture('horsey', 'Horsey', ChessboardColorScheme.horsey),
];

/// The active texture, or null when the board is on custom colors.
BoardTexture? textureFor(SettingsStore s) {
  if (s.boardTexture.isEmpty) return null;
  for (final t in kBoardTextures) {
    if (t.name == s.boardTexture) return t;
  }
  return null;
}

/// The user's piece set, falling back to the default if a stored name no
/// longer exists in chessground.
PieceSet pieceSetFor(SettingsStore s) => PieceSet.values.firstWhere(
      (p) => p.name == s.pieceSet,
      orElse: () => PieceSet.cburnett,
    );

/// The color scheme for the user's chosen square/highlight colors.
ChessboardColorScheme schemeFor(SettingsStore s) {
  // A texture brings its own squares; the last-move color stays the user's
  // in both modes, so that picker never silently stops working.
  final texture = textureFor(s);
  if (texture != null) {
    return texture.scheme.copyWith(
      lastMove: HighlightDetails(solidColor: s.lastMoveColor),
    );
  }
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

/// The engine-arrow brushes: one per analysis line, fading by rank.
/// Blue, not green — green is the control tint's "your squares", and the
/// arrows need to stay legible on top of both tints. [peak] is the
/// opacity of the best move's arrow; the other two keep their relative
/// weight beneath it, so one slider moves the whole set coherently.
const Color kEngineArrowBlue = Color(0xFF2E6FD0);
const List<double> _kArrowRanks = [1.0, 0.62, 0.42, 0.28, 0.18];

List<Color> engineArrowColors(double peak) => [
      for (final rank in _kArrowRanks)
        kEngineArrowBlue.withValues(alpha: peak * rank),
    ];

/// The opponent's threat arrow: red, the color of danger on this board.
const Color kThreatArrowRed = Color(0xFFC62828);

Color threatArrowColor(double opacity) =>
    kThreatArrowRed.withValues(alpha: opacity);

/// The square-control tint, washed flat across the square at [peak].
// Cooler than the web's yellow-green (0xFF81B64C): on warm boards that hue
// sat too close to the squares, so the same alpha bought far less separation
// for green than the red got. This sits nearer emerald, away from both the
// wood tones and the engine arrows' green.
const Color kControlOurs = Color(0xFF3FA06E);
const Color kControlTheirs = Color(0xFFCA3431);
