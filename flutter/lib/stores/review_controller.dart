// The review archive: stored games list + the replay cursor for one game.
// Pure reads over AppDb — grading already happened at save time.

import 'package:flutter/foundation.dart';

import '../db/app_db.dart';
import 'pgn_import.dart';

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

  /// Archive a pasted PGN and open it. False when the text carries no legal
  /// moves, which is the caller's cue to say so rather than fail silently.
  /// The import has no grades — it was never analysed — and Review reads all
  /// of those as nullable, so it steps through like any other stored game.
  Future<bool> importPgn(String pgn) async {
    final game = gameFromPgn(pgn, now: DateTime.now());
    if (game == null) return false;
    await _db.saveGame(game);
    await loadGames();
    open(game);
    return true;
  }

  void open(Map<String, dynamic> game) {
    current = game;
    // Open at the START, not the end. Reviewing runs forwards — the whole UI
    // is built around → stepping into the next move's verdict — but this used
    // to land on the final position, so every review began by scrubbing all
    // the way back. cursor = 0 is the true start (canPrev is false, the
    // verdict strip reads "Start position"), which is how lichess and
    // chess.com open a game too.
    cursor = 0;
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
