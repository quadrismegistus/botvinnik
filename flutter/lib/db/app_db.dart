// Persistence: sqflite with the StoredGame JSON kept whole — the web app
// never queries per-move, so one row per game (id + endedAt indexed, the
// rest as a JSON document in the same shape as the web's IndexedDB store,
// which keeps a future backup import pass-through).

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'db_reset.dart';

/// The local database exists but cannot be read.
///
/// Thrown at boot so the failure arrives as something the UI can offer a way
/// out of, rather than as a raw driver exception in a red wall of text.
class DatabaseUnreadable implements Exception {
  final Object cause;
  DatabaseUnreadable(this.cause);
  @override
  String toString() => 'DatabaseUnreadable: $cause';
}

class AppDb {
  final Database _db;
  AppDb._(this._db);

  /// SQLITE_CORRUPT (11) or SQLITE_NOTADB (26) — the file itself, not a bad row
  /// or a bad query.
  ///
  /// Read from the RESULT CODE, never from the message. sqflite does surface
  /// the code (`DatabaseException.getResultCode()`); an earlier version of this
  /// matched on `toString()`, which is unsound because it interpolates the
  /// BOUND ARGUMENTS — and this app binds game JSON carrying imported PGN
  /// comments and user-typed engine names. A player whose engine was called
  /// "database disk image is malformed" would have had their database
  /// classified as corrupt, which is silly until you realise the same is true
  /// of any imported game whose comments quote an error message.
  static bool isUnreadable(Object e) {
    final code = e is DatabaseException ? e.getResultCode() : null;
    // 267/523/779 are the extended forms (CORRUPT_VTAB, INDEX, SEQUENCE).
    return code == 11 || code == 26 || code == 267 || code == 523 || code == 779;
  }

  /// Opens the database AND reads from it, so a file that opens but cannot be
  /// read fails here rather than four screens later.
  ///
  /// `openDatabase` only reads `PRAGMA user_version`, which lives in the page-1
  /// header and survives torn data pages — so the reported corruption
  /// (`SELECT * FROM games ORDER BY endedAt DESC`) left open() perfectly happy
  /// and killed the first screen that asked for a game instead. The probe
  /// mimics that statement, index and all, because the index root is exactly
  /// what was damaged in the case that was reproduced.
  ///
  /// Not a guarantee: a page this never touches can still be torn, and the read
  /// that finds it will still throw uncaught. It converts the common case into
  /// something recoverable, which is the whole of the ambition here — see #254
  /// for what a real salvage would involve.
  static Future<AppDb> openChecked() async {
    final db = await open();
    try {
      await db._db.rawQuery('SELECT id FROM games ORDER BY endedAt DESC LIMIT 1');
      await db._db.rawQuery('SELECT value FROM kv LIMIT 1');
    } catch (e) {
      if (isUnreadable(e)) throw DatabaseUnreadable(e);
      rethrow;
    }
    return db;
  }

  /// Move the local database out of the way and report where it went, so the
  /// app can start fresh. Returns null on web, where there is nowhere to move
  /// it TO and the file is simply dropped.
  ///
  /// Moved rather than deleted, on native, because "unreadable by us" is not
  /// "unrecoverable" — most of a torn database is still there, and #254 records
  /// how much (77% by rowid walk; 100% when only the index root is gone).
  /// Nothing in the app can salvage it today, but throwing the bytes away
  /// forecloses that, and a rename costs nothing.
  ///
  /// Only ever called from the button a human presses.
  static Future<String?> moveAside() async =>
      moveDatabaseAside('${await getDatabasesPath()}/botvinnik.db');

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
