// Persistence: sqflite with the StoredGame JSON kept whole — the web app
// never queries per-move, so one row per game (id + endedAt indexed, the
// rest as a JSON document in the same shape as the web's IndexedDB store,
// which keeps a future backup import pass-through).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class AppDb {
  final Database _db;
  AppDb._(this._db);

  /// Whether [e] is SQLite reporting that the file itself is unreadable —
  /// SQLITE_CORRUPT (11) or SQLITE_NOTADB (26) — rather than a bad row or a
  /// bad query.
  ///
  /// Matched on the message because sqflite flattens every backend into
  /// DatabaseException/SqfliteFfiException and does not surface the result
  /// code as a field. Narrow on purpose: this decides whether to DISCARD the
  /// local database, so it must not fire on an ordinary error.
  @visibleForTesting
  static bool isCorruptionError(Object e) {
    final m = e.toString().toLowerCase();
    return m.contains('database disk image is malformed') ||
        m.contains('file is not a database') ||
        m.contains('database corrupt');
  }

  /// Opens the database, rebuilding it from empty if the stored file is
  /// corrupt. Returns whether that happened, so the caller can say so.
  ///
  /// A torn database used to take the whole app down with a red screen on
  /// `SELECT * FROM games ORDER BY endedAt DESC` — every other store here
  /// already degrades instead (practice, settings and custom engines each
  /// treat a corrupt document as an empty one). This is the same policy for
  /// the file: the games are recoverable from sync, and an app that starts
  /// empty can re-sync them, while an app that will not start cannot do
  /// anything at all.
  ///
  /// Discarding is safe ONLY because it is unreadable — the rows cannot be
  /// salvaged by any path this app has, since the failure is in the pages
  /// under them.
  static Future<({AppDb db, bool recovered})> openOrRecover() async {
    try {
      return (db: await open(), recovered: false);
    } catch (e) {
      if (!isCorruptionError(e)) rethrow;
      debugPrint('[db] corrupt database, starting fresh: $e');
      await deleteDatabase('${await getDatabasesPath()}/botvinnik.db');
      return (db: await open(), recovered: true);
    }
  }

  static Future<AppDb> open() async {
    final path = '${await getDatabasesPath()}/botvinnik.db';
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE games (
            id TEXT PRIMARY KEY,
            endedAt INTEGER NOT NULL,
            json TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX games_endedAt ON games(endedAt DESC)');
        await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)');
      },
    );
    return AppDb._(db);
  }

  Future<void> saveGame(Map<String, dynamic> storedGame) async {
    await _db.insert(
      'games',
      {
        'id': storedGame['id'] as String,
        'endedAt':
            DateTime.parse(storedGame['endedAt'] as String).millisecondsSinceEpoch,
        'json': jsonEncode(storedGame),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// All games, newest first — full documents (the archive list is small;
  /// paginate if it ever isn't).
  Future<List<Map<String, dynamic>>> listGames() async {
    final rows = await _db.query('games', orderBy: 'endedAt DESC');
    return rows
        .map((r) =>
            (jsonDecode(r['json'] as String) as Map).cast<String, dynamic>())
        .toList();
  }

  Future<void> deleteGame(String id) async {
    await _db.delete('games', where: 'id = ?', whereArgs: [id]);
  }

  // kv: whole-document storage (practice items in M3, misc)
  Future<String?> kvGet(String key) async {
    final rows = await _db.query('kv', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> kvPut(String key, String value) async {
    await _db.insert('kv', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
