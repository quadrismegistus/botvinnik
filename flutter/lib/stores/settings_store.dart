// App settings, persisted in shared_preferences under the same botvinnik-*
// key names the web app uses in localStorage — same shapes, so a future
// backup import can carry settings across.

import 'dart:convert';

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shipped board theme: chessground's brown, which is what the app used
/// before any of the theming work. Users override it in Settings, and the
/// grayscale variant the overlays were tuned against is a preset.
const Color kDefaultLightSquare = Color(0xfff0d9b6);
const Color kDefaultDarkSquare = Color(0xffb58863);
const Color kDefaultLastMove = Color(0x809cc700);
const String kDefaultPieceSet = 'cburnett';

/// Peak opacity of the overlays. Both arrow kinds sit at 70%: fully opaque
/// arrows dominated the position, and matching them keeps the engine's
/// suggestion and the opponent's threat weighted the same. The control tint
/// is separate: as a flat wash over the whole square, 30% carries further
/// than the old fading circle did at 38%.
const double kDefaultArrowOpacity = 0.7;
const double kDefaultControlOpacity = 0.3;

/// The threat arrow's opacity. It sat at 90% while every other overlay
/// became adjustable — loud for a hint you see on most moves.
const double kDefaultThreatOpacity = 0.7;

/// How many engine arrows to draw. Analysis already runs MultiPV-5, so all
/// five lines exist regardless — this only decides how many are shown.
const int kDefaultArrowCount = 5;

class SettingsStore extends ChangeNotifier {
  final SharedPreferences _prefs;

  String _personaId;
  String _playerColor; // 'w' | 'b' — the side the HUMAN plays
  bool _botEnabled; // false = analysis board (you move both sides)
  int _collectThreshold; // practice serves puzzles with drop ≥ this
  bool _showArrows; // top-3 engine arrows on the board
  bool _blind; // no forward-looking engine help while playing
  bool _showThreats; // opponent-threat arrow (null-move probe)
  bool _showControl; // square-control tint
  Color _lightSquare;
  Color _darkSquare;
  Color _lastMoveColor;
  String _pieceSet; // a chessground PieceSet name
  String _boardTexture; // a chessground board texture name; '' = flat colors
  double _arrowOpacity;
  int _arrowCount;
  double _threatOpacity;
  double _controlOpacity;

  // Named on purpose: these are a dozen fields of only three distinct types,
  // so positional arguments would let a swapped pair compile silently.
  // Initializing formals aren't available here — Dart forbids named
  // parameters that start with an underscore.
  // ignore_for_file: prefer_initializing_formals
  SettingsStore._({
    required SharedPreferences prefs,
    required String personaId,
    required String playerColor,
    required bool botEnabled,
    required int collectThreshold,
    required bool showArrows,
    required bool blind,
    required bool showThreats,
    required bool showControl,
    required Color lightSquare,
    required Color darkSquare,
    required Color lastMoveColor,
    required String pieceSet,
    required String boardTexture,
    required double arrowOpacity,
    required int arrowCount,
    required double threatOpacity,
    required double controlOpacity,
  })  : _prefs = prefs,
        _personaId = personaId,
        _playerColor = playerColor,
        _botEnabled = botEnabled,
        _collectThreshold = collectThreshold,
        _showArrows = showArrows,
        _blind = blind,
        _showThreats = showThreats,
        _showControl = showControl,
        _lightSquare = lightSquare,
        _darkSquare = darkSquare,
        _lastMoveColor = lastMoveColor,
        _pieceSet = pieceSet,
        _boardTexture = boardTexture,
        _arrowOpacity = arrowOpacity,
        _arrowCount = arrowCount,
        _threatOpacity = threatOpacity,
        _controlOpacity = controlOpacity;

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    var personaId = 'square-900';
    var playerColor = 'w';
    var botEnabled = true;
    final raw = prefs.getString('botvinnik-bot-v1');
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        personaId = (json['personaId'] as String?) ?? personaId;
        botEnabled = (json['enabled'] as bool?) ?? true;
        // web stores the BOT's color; the human plays the other side
        final botColor = (json['color'] as String?) ?? 'b';
        playerColor = botColor == 'w' ? 'b' : 'w';
      } catch (_) {/* corrupted settings: fall back to defaults */}
    }
    final threshold =
        int.tryParse(prefs.getString('botvinnik-collect-threshold') ?? '') ??
            15;
    return SettingsStore._(
      prefs: prefs,
      personaId: personaId,
      playerColor: playerColor,
      botEnabled: botEnabled,
      collectThreshold: threshold,
      showArrows: prefs.getString('botvinnik-arrows') != '0', // ON, like web
      blind: prefs.getString('botvinnik-blind') == '1',
      showThreats: prefs.getString('botvinnik-threats') == '1',
      showControl: prefs.getString('botvinnik-control') == '1',
      lightSquare: _color(prefs, 'botvinnik-sq-light', kDefaultLightSquare),
      darkSquare: _color(prefs, 'botvinnik-sq-dark', kDefaultDarkSquare),
      lastMoveColor: _color(prefs, 'botvinnik-lastmove', kDefaultLastMove),
      pieceSet: prefs.getString('botvinnik-pieces') ?? kDefaultPieceSet,
      boardTexture: prefs.getString('botvinnik-board-texture') ?? '',
      arrowOpacity: prefs.getDouble('botvinnik-arrow-opacity') ??
          kDefaultArrowOpacity,
      arrowCount: prefs.getInt('botvinnik-arrow-count') ?? kDefaultArrowCount,
      threatOpacity: prefs.getDouble('botvinnik-threat-opacity') ??
          kDefaultThreatOpacity,
      controlOpacity: prefs.getDouble('botvinnik-control-opacity') ??
          kDefaultControlOpacity,
    );
  }

  /// Stored as 0xAARRGGBB hex; falls back to the theme default if unset or
  /// unparseable, so a corrupted value can never leave the board invisible.
  static Color _color(SharedPreferences prefs, String key, Color fallback) {
    final raw = prefs.getString(key);
    if (raw == null) return fallback;
    final v = int.tryParse(raw, radix: 16);
    return v == null ? fallback : Color(v);
  }

  double get threatOpacity => _threatOpacity;

  set threatOpacity(double v) {
    if (v == _threatOpacity) return;
    _threatOpacity = v;
    _prefs.setDouble('botvinnik-threat-opacity', v);
    notifyListeners();
  }

  int get arrowCount => _arrowCount;

  set arrowCount(int n) {
    if (n == _arrowCount) return;
    _arrowCount = n;
    _prefs.setInt('botvinnik-arrow-count', n);
    notifyListeners();
  }

  double get arrowOpacity => _arrowOpacity;
  double get controlOpacity => _controlOpacity;

  set arrowOpacity(double v) {
    if (v == _arrowOpacity) return;
    _arrowOpacity = v;
    _prefs.setDouble('botvinnik-arrow-opacity', v);
    notifyListeners();
  }

  set controlOpacity(double v) {
    if (v == _controlOpacity) return;
    _controlOpacity = v;
    _prefs.setDouble('botvinnik-control-opacity', v);
    notifyListeners();
  }

  String get boardTexture => _boardTexture;

  /// Selecting a texture replaces the squares wholesale; '' returns the
  /// board to whatever flat colors are set.
  set boardTexture(String name) {
    if (name == _boardTexture) return;
    _boardTexture = name;
    _prefs.setString('botvinnik-board-texture', name);
    notifyListeners();
  }

  String get pieceSet => _pieceSet;

  set pieceSet(String name) {
    if (name == _pieceSet) return;
    _pieceSet = name;
    _prefs.setString('botvinnik-pieces', name);
    notifyListeners();
  }

  /// Applies a preset's two square colors in a single repaint.
  void applySquares(Color light, Color dark) {
    if (light.toARGB32() == _lightSquare.toARGB32() &&
        dark.toARGB32() == _darkSquare.toARGB32()) {
      return;
    }
    _lightSquare = light;
    _darkSquare = dark;
    _clearTexture();
    _prefs.setString(
        'botvinnik-sq-light', light.toARGB32().toRadixString(16).padLeft(8, '0'));
    _prefs.setString(
        'botvinnik-sq-dark', dark.toARGB32().toRadixString(16).padLeft(8, '0'));
    notifyListeners();
  }

  Color get lightSquare => _lightSquare;
  Color get darkSquare => _darkSquare;
  Color get lastMoveColor => _lastMoveColor;

  set lightSquare(Color c) => _setColor(
      c, () => _lightSquare, (v) => _lightSquare = v, 'botvinnik-sq-light');
  set darkSquare(Color c) => _setColor(
      c, () => _darkSquare, (v) => _darkSquare = v, 'botvinnik-sq-dark');
  set lastMoveColor(Color c) => _setColor(
      c, () => _lastMoveColor, (v) => _lastMoveColor = v, 'botvinnik-lastmove');

  void _setColor(Color c, Color Function() get, void Function(Color) set,
      String key) {
    if (c.toARGB32() == get().toARGB32()) return;
    set(c);
    _prefs.setString(key, c.toARGB32().toRadixString(16).padLeft(8, '0'));
    if (key != 'botvinnik-lastmove') _clearTexture();
    notifyListeners();
  }

  void _clearTexture() {
    if (_boardTexture.isEmpty) return;
    _boardTexture = '';
    _prefs.remove('botvinnik-board-texture');
  }

  /// Puts all three board colors back to the shipped theme in one repaint.
  void resetBoardColors() {
    _lightSquare = kDefaultLightSquare;
    _darkSquare = kDefaultDarkSquare;
    _lastMoveColor = kDefaultLastMove;
    _prefs.remove('botvinnik-sq-light');
    _prefs.remove('botvinnik-sq-dark');
    _prefs.remove('botvinnik-lastmove');
    _pieceSet = kDefaultPieceSet;
    _prefs.remove('botvinnik-pieces');
    _clearTexture();
    notifyListeners();
  }

  String get personaId => _personaId;
  String get playerColor => _playerColor;
  bool get botEnabled => _botEnabled;
  int get collectThreshold => _collectThreshold;
  bool get showArrows => _showArrows;
  bool get blind => _blind;

  set showArrows(bool on) {
    if (on == _showArrows) return;
    _showArrows = on;
    _prefs.setString('botvinnik-arrows', on ? '1' : '0');
    notifyListeners();
  }
  bool get showThreats => _showThreats;
  bool get showControl => _showControl;

  set blind(bool on) {
    if (on == _blind) return;
    _blind = on;
    _prefs.setString('botvinnik-blind', on ? '1' : '0');
    notifyListeners();
  }

  set showThreats(bool on) {
    if (on == _showThreats) return;
    _showThreats = on;
    _prefs.setString('botvinnik-threats', on ? '1' : '0');
    notifyListeners();
  }

  set showControl(bool on) {
    if (on == _showControl) return;
    _showControl = on;
    _prefs.setString('botvinnik-control', on ? '1' : '0');
    notifyListeners();
  }

  set personaId(String id) {
    if (id == _personaId) return;
    _personaId = id;
    _persistBot();
    notifyListeners();
  }

  set playerColor(String color) {
    if (color == _playerColor) return;
    _playerColor = color;
    _persistBot();
    notifyListeners();
  }

  set botEnabled(bool on) {
    if (on == _botEnabled) return;
    _botEnabled = on;
    _persistBot();
    notifyListeners();
  }

  set collectThreshold(int pct) {
    if (pct == _collectThreshold) return;
    _collectThreshold = pct;
    _prefs.setString('botvinnik-collect-threshold', '$pct');
    notifyListeners();
  }

  void _persistBot() {
    _prefs.setString(
      'botvinnik-bot-v1',
      jsonEncode({
        'enabled': _botEnabled,
        'personaId': _personaId,
        'color': _playerColor == 'w' ? 'b' : 'w',
      }),
    );
  }
}
