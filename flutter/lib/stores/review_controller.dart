// The review archive: the stored games list, and which one is open.
// Pure reads over AppDb — grading already happened at save time.
//
// NAVIGATION WITHIN a game lives in ReviewBoardController's ReviewTree (#196),
// not here. This owns the archive; that owns where you are in it.

import 'package:flutter/foundation.dart';

import '../db/app_db.dart';
import 'pgn_import.dart';

class ReviewController extends ChangeNotifier {
  final AppDb _db;
  List<Map<String, dynamic>> games = [];
  bool loaded = false;

  Map<String, dynamic>? current; // the StoredGame under review

  // There is no cursor here any more (#196). Where you are in a reviewed game
  // is a node of ReviewBoardController's tree, not a ply of a list: once a
  // variation can be branched off and walked back into, an integer cannot say
  // where you are. One owner, so the board and the move list cannot disagree.

  ReviewController(this._db);

  /// The store behind the archive.
  ///
  /// Exposed for BackupService (#138), which writes the games table AND the
  /// practice kv row in one pass and so has no single controller to go
  /// through. This is the one controller in the tree that already holds the
  /// db, so a getter here is cheaper than a second provider carrying the same
  /// object.
  AppDb get db => _db;

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
    notifyListeners();
  }

  void close() {
    current = null;
    notifyListeners();
  }

  /// The archived moves, as the move list and the win chart read them.
  ///
  /// Filtered, not cast: every consumer here does `m['san'] as String` on the
  /// way to a row, so one malformed record turned the whole tab into an error
  /// box — and unlike the board, which degrades to an empty position, a
  /// ListView itemBuilder throwing takes the pane with it. A row that cannot
  /// be drawn is dropped; a broken archive shows fewer moves rather than none.
  List<Map<String, dynamic>> get moves {
    final raw = current?['moves'];
    if (raw is! List) return const [];
    return [
      for (final e in raw.whereType<Map>())
        if (e['san'] is String && e['ply'] is num) e.cast<String, dynamic>()
    ];
  }

}
