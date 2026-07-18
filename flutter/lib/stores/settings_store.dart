// App settings, persisted in shared_preferences under the same botvinnik-*
// key names the web app uses in localStorage — same shapes, so a future
// backup import can carry settings across.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  SettingsStore._(this._prefs, this._personaId, this._playerColor,
      this._botEnabled, this._collectThreshold, this._showArrows, this._blind,
      this._showThreats, this._showControl);

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
      prefs,
      personaId,
      playerColor,
      botEnabled,
      threshold,
      prefs.getString('botvinnik-arrows') != '0', // default ON, like web
      prefs.getString('botvinnik-blind') == '1',
      prefs.getString('botvinnik-threats') == '1',
      prefs.getString('botvinnik-control') == '1',
    );
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
