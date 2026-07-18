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

  SettingsStore._(this._prefs, this._personaId, this._playerColor);

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    var personaId = 'square-900';
    var playerColor = 'w';
    final raw = prefs.getString('botvinnik-bot-v1');
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        personaId = (json['personaId'] as String?) ?? personaId;
        // web stores the BOT's color; the human plays the other side
        final botColor = (json['color'] as String?) ?? 'b';
        playerColor = botColor == 'w' ? 'b' : 'w';
      } catch (_) {/* corrupted settings: fall back to defaults */}
    }
    return SettingsStore._(prefs, personaId, playerColor);
  }

  String get personaId => _personaId;
  String get playerColor => _playerColor;

  set personaId(String id) {
    if (id == _personaId) return;
    _personaId = id;
    _persist();
    notifyListeners();
  }

  set playerColor(String color) {
    if (color == _playerColor) return;
    _playerColor = color;
    _persist();
    notifyListeners();
  }

  void _persist() {
    _prefs.setString(
      'botvinnik-bot-v1',
      jsonEncode({
        'enabled': true,
        'personaId': _personaId,
        'color': _playerColor == 'w' ? 'b' : 'w',
      }),
    );
  }
}
