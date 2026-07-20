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

/// The board out of the box. Newspaper reads well against the app's dark
/// shell and stays quiet under the overlays.
const String kDefaultBoardTexture = 'newspaper';

/// The two overlays that explain the position are on by default: they are the
/// point of the app, and a first-time player will not know to go and find them.
const bool kDefaultShowThreats = true;
const bool kDefaultShowControl = true;

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

/// Which panels are open on a wide window, by their index in the view bar.
/// Insights alone to start.
const Set<int> kDefaultPanels = {0};

/// The board's share of a wide window's width.
const double kDefaultSplit = 0.58;
const double kMinSplit = 0.32;
const double kMaxSplit = 0.75;

/// One brush per rank in board_theme's fade; more arrows than brushes would
/// index off the end.
const int kMaxArrowCount = 5;

class SettingsStore extends ChangeNotifier {
  final SharedPreferences _prefs;

  String _personaId;
  // Per-side assignment: null = the human plays that side, otherwise a bot's
  // persona id. Both null = analysis; exactly one null = you vs a bot; neither
  // null = bot-vs-bot (and the two may be DIFFERENT bots). _personaId above is
  // only the picker's remembered default.
  String? _whitePersonaId;
  String? _blackPersonaId;
  int _collectThreshold; // practice serves puzzles with drop ≥ this
  int _botDelayMs; // pause between moves when a bot plays both sides
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
  Set<int> _panels;
  double _split;
  double _controlOpacity;

  // Named on purpose: these are a dozen fields of only three distinct types,
  // so positional arguments would let a swapped pair compile silently.
  // Initializing formals aren't available here — Dart forbids named
  // parameters that start with an underscore.
  // ignore_for_file: prefer_initializing_formals
  SettingsStore._({
    required SharedPreferences prefs,
    required String personaId,
    required String? whitePersonaId,
    required String? blackPersonaId,
    required int collectThreshold,
    required int botDelayMs,
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
    required Set<int> panels,
    required double split,
    required double controlOpacity,
  })  : _prefs = prefs,
        _personaId = personaId,
        _whitePersonaId = whitePersonaId,
        _blackPersonaId = blackPersonaId,
        _collectThreshold = collectThreshold,
        _botDelayMs = botDelayMs,
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
        _panels = panels,
        _split = split,
        _controlOpacity = controlOpacity;

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    var personaId = 'square-900';
    // default: you play White, the bot plays Black
    String? whitePersonaId;
    String? blackPersonaId = personaId;
    final raw = prefs.getString('botvinnik-bot-v1');
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        personaId = (json['personaId'] as String?) ?? personaId;
        if (json.containsKey('white') || json.containsKey('black')) {
          whitePersonaId = json['white'] as String?;
          blackPersonaId = json['black'] as String?;
        } else {
          // migrate the old {enabled, bothSides, color} shape
          final enabled = (json['enabled'] as bool?) ?? true;
          final bothSides = (json['bothSides'] as bool?) ?? false;
          final botColor = (json['color'] as String?) ?? 'b';
          if (!enabled) {
            whitePersonaId = null;
            blackPersonaId = null;
          } else if (bothSides) {
            whitePersonaId = personaId;
            blackPersonaId = personaId;
          } else if (botColor == 'w') {
            whitePersonaId = personaId;
            blackPersonaId = null;
          } else {
            whitePersonaId = null;
            blackPersonaId = personaId;
          }
        }
      } catch (_) {/* corrupted settings: fall back to defaults */}
    }
    final threshold =
        int.tryParse(prefs.getString('botvinnik-collect-threshold') ?? '') ??
            15;
    return SettingsStore._(
      prefs: prefs,
      personaId: personaId,
      whitePersonaId: whitePersonaId,
      blackPersonaId: blackPersonaId,
      collectThreshold: threshold,
      botDelayMs: (int.tryParse(prefs.getString('botvinnik-bot-delay') ?? '') ?? 650).clamp(0, 3000),
      showArrows: prefs.getString('botvinnik-arrows') != '0', // ON, like web
      blind: prefs.getString('botvinnik-blind') == '1',
      // '0' means the user turned it off; absent means they never touched it
      showThreats: prefs.getString('botvinnik-threats') != '0',
      showControl: prefs.getString('botvinnik-control') != '0',
      lightSquare:
          _color(prefs, 'botvinnik-sq-light', kDefaultLightSquare, opaque: true),
      darkSquare:
          _color(prefs, 'botvinnik-sq-dark', kDefaultDarkSquare, opaque: true),
      lastMoveColor: _color(prefs, 'botvinnik-lastmove', kDefaultLastMove),
      pieceSet: prefs.getString('botvinnik-pieces') ?? kDefaultPieceSet,
      boardTexture:
          prefs.getString('botvinnik-board-texture') ?? kDefaultBoardTexture,
      arrowOpacity: prefs.getDouble('botvinnik-arrow-opacity') ??
          kDefaultArrowOpacity,
      arrowCount: (prefs.getInt('botvinnik-arrow-count') ?? kDefaultArrowCount)
          .clamp(1, kMaxArrowCount),
      threatOpacity: prefs.getDouble('botvinnik-threat-opacity') ??
          kDefaultThreatOpacity,
      panels: _panelSet(prefs.getString('botvinnik-panels')),
      split: (prefs.getDouble('botvinnik-split') ?? kDefaultSplit)
          .clamp(kMinSplit, kMaxSplit),
      controlOpacity: prefs.getDouble('botvinnik-control-opacity') ??
          kDefaultControlOpacity,
    );
  }

  /// Stored as 0xAARRGGBB hex; falls back to the theme default if unset or
  /// unparseable. [opaque] forces full alpha for the square colours: a
  /// 6-digit value (which an import from the web could well produce) parses
  /// fine but yields alpha 0 — a completely invisible board that only "Reset
  /// to default" can recover. The last-move colour keeps its alpha, which is
  /// meaningful there.
  static Color _color(SharedPreferences prefs, String key, Color fallback,
      {bool opaque = false}) {
    final raw = prefs.getString(key);
    if (raw == null) return fallback;
    final v = int.tryParse(raw, radix: 16);
    if (v == null || v < 0 || v > 0xFFFFFFFF) return fallback;
    return Color(opaque ? v | 0xFF000000 : v);
  }

  /// Stored as '0,2,3'. A missing or unparseable value falls back to the
  /// default rather than leaving the panel column empty.
  static Set<int> _panelSet(String? raw) {
    if (raw == null || raw.isEmpty) return {...kDefaultPanels};
    final out = <int>{};
    for (final part in raw.split(',')) {
      final v = int.tryParse(part);
      if (v != null && v >= 0 && v < 6) out.add(v);
    }
    return out.isEmpty ? {...kDefaultPanels} : out;
  }

  Set<int> get panels => _panels;

  /// Toggles a panel. The last one cannot be closed — an empty column just
  /// looks broken.
  void togglePanel(int i) {
    final next = {..._panels};
    if (!next.remove(i)) next.add(i);
    if (next.isEmpty) return;
    _panels = next;
    _prefs.setString('botvinnik-panels', (next.toList()..sort()).join(','));
    notifyListeners();
  }

  double get split => _split;

  set split(double v) {
    final c = v.clamp(kMinSplit, kMaxSplit);
    if (c == _split) return;
    _split = c;
    _prefs.setDouble('botvinnik-split', c);
    notifyListeners();
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
    // stored, not removed: an absent value means "never chose", which now
    // means the default texture — picking a colour has to stick
    _prefs.setString('botvinnik-board-texture', '');
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
    _boardTexture = kDefaultBoardTexture;
    _prefs.remove('botvinnik-board-texture');
    notifyListeners();
  }

  String get personaId => _personaId; // the picker's remembered default
  String? get whitePersonaId => _whitePersonaId;
  String? get blackPersonaId => _blackPersonaId;
  // Derived compatibility views over the per-side model.
  bool get botEnabled => _whitePersonaId != null || _blackPersonaId != null;
  // The human's side, for board orientation; White by default (bvb/analysis).
  String get playerColor => _whitePersonaId == null
      ? 'w'
      : _blackPersonaId == null
          ? 'b'
          : 'w';
  int get collectThreshold => _collectThreshold;
  int get botDelayMs => _botDelayMs;
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

  /// Assign each side: null = the human, otherwise a bot persona id.
  void setPlayers({required String? white, required String? black}) {
    if (white == _whitePersonaId && black == _blackPersonaId) return;
    _whitePersonaId = white;
    _blackPersonaId = black;
    // remember a chosen bot as the picker's default for next time
    final bot = white ?? black;
    if (bot != null) _personaId = bot;
    _persistBot();
    notifyListeners();
  }

  set collectThreshold(int pct) {
    if (pct == _collectThreshold) return;
    _collectThreshold = pct;
    _prefs.setString('botvinnik-collect-threshold', '$pct');
    notifyListeners();
  }

  set botDelayMs(int ms) {
    final v = ms.clamp(0, 3000);
    if (v == _botDelayMs) return;
    _botDelayMs = v;
    _prefs.setString('botvinnik-bot-delay', '$v');
    notifyListeners();
  }

  void _persistBot() {
    _prefs.setString(
      'botvinnik-bot-v1',
      jsonEncode({
        'white': _whitePersonaId,
        'black': _blackPersonaId,
        'personaId': _personaId,
      }),
    );
  }
}
