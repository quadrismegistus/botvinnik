// The review archive: stored games list + the replay cursor for one game.
// Pure reads over AppDb — grading already happened at save time.

import 'package:flutter/foundation.dart';

import '../db/app_db.dart';

class ReviewController extends ChangeNotifier {
  final AppDb _db;
  List<Map<String, dynamic>> games = [];
  bool loaded = false;

  Map<String, dynamic>? current; // the StoredGame under review
  int cursor = 0; // 0 = start position, n = after ply n

  ReviewController(this._db);

  Future<void> loadGames() async {
    games = await _db.listGames();
    loaded = true;
    notifyListeners();
  }

  Future<void> deleteGame(String id) async {
    await _db.deleteGame(id);
    games.removeWhere((g) => g['id'] == id);
    notifyListeners();
  }

  void open(Map<String, dynamic> game) {
    current = game;
    cursor = (game['moves'] as List).length; // land on the final position
    notifyListeners();
  }

  void close() {
    current = null;
    notifyListeners();
  }

  List<Map<String, dynamic>> get moves =>
      ((current?['moves'] as List?) ?? const [])
          .map((m) => (m as Map).cast<String, dynamic>())
          .toList();

  /// The move the cursor sits AFTER (null at the start position).
  Map<String, dynamic>? get currentMove =>
      cursor == 0 ? null : moves[cursor - 1];

  String get fen {
    if (cursor == 0) {
      final m = moves;
      return m.isEmpty
          ? 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
          : m.first['fenBefore'] as String;
    }
    return currentMove!['fenAfter'] as String;
  }

  bool get canPrev => cursor > 0;
  bool get canNext => cursor < moves.length;

  void prev() => _goto(cursor - 1);
  void next() => _goto(cursor + 1);
  void goto(int ply) => _goto(ply);

  void _goto(int ply) {
    final clamped = ply.clamp(0, moves.length);
    if (clamped == cursor) return;
    cursor = clamped;
    notifyListeners();
  }
}
