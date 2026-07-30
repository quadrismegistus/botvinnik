// Persistence: sqflite with the StoredGame JSON kept whole — the web app
// never queries per-move, so one row per game (id + endedAt indexed, the
// rest as a JSON document in the same shape as the web's IndexedDB store,
// which keeps a future backup import pass-through).

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class AppDb {
  final Database _db;
  AppDb._(this._db);

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
