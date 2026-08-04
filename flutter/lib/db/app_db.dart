// Persistence: sqflite with the StoredGame JSON kept whole — the web app
// never queries per-move, so one row per game (id + endedAt indexed, the
// rest as a JSON document in the same shape as the web's IndexedDB store,
// which keeps a future backup import pass-through).

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'db_path.dart';
import 'db_reset.dart';

// Callers of [AppDb.moveAside] have to be able to catch what it throws.
export 'db_reset.dart' show DatabaseStillThere;

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
    // 26 is only reachable now that open() is inside the try — a file that is
    // not a database at all cannot fail any later than that.
    if (code == 11 || code == 26 || code == 267 || code == 523 || code == 779) {
      return true;
    }
    // Damage to an overflow page — where the `json` column lives once it
    // outgrows a row — does not raise a SQLite error at all. SQLite hands back
    // bytes it considers valid and the DRIVER fails decoding them, arriving as
    // a FormatException with no result code. On an archive of real games
    // (8KB of JSON each) this is the MAJORITY of corruption: 101 of 195
    // breakages in a 200-tear sample, every one of them invisible to a check
    // that only reads result codes.
    //
    // Safe to treat as unreadable because it is not reachable from data: a
    // string this app wrote round-trips, so bytes that will not decode are
    // bytes that changed underneath us.
    return e.toString().contains('FormatException');
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
    try {
      final db = await open();
      // A FULL read of both tables, not a cheap `LIMIT 1`. The first version
      // asked for `SELECT id FROM games ORDER BY endedAt DESC LIMIT 1`, which
      // SQLite answers from the first index leaf and one table leaf — about 7
      // pages of a 2452-page file. Measured over 200 random single-page tears
      // of a 3000-game archive: 191 broke the app and that probe caught SIX.
      // A full scan caught 191 of 191.
      //
      // It is close to free, and not because the scan is cheap in absolute
      // terms (~25ms on a 39MB archive) but because the app ALREADY does it:
      // main.dart builds BackgroundGrader with `lazy: false` and starts it, and
      // its first pass calls listGames(). This moves that read onto the boot
      // path rather than adding one.
      //
      // `SELECT *` rather than a count, deliberately: the json column lives on
      // overflow pages that no count or aggregate touches, and marshalling the
      // text to Dart is what surfaces damage there at all.
      try {
        await db._db.rawQuery('SELECT * FROM games ORDER BY endedAt DESC');
        await db._db.rawQuery('SELECT * FROM kv');
      } catch (_) {
        // Close before rethrowing. sqflite opens single-instance and caches the
        // handle by path, so a boot that threw here used to leave the corrupt
        // database OPEN — once per failed boot, and holding the very file the
        // reset then tries to remove.
        await db._db.close();
        rethrow;
      }
      return db;
    } catch (e) {
      if (isUnreadable(e)) throw DatabaseUnreadable(e);
      rethrow;
    }
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
  static Future<String?> moveAside() async => moveDatabaseAside(await databasePath());

  static Future<AppDb> open() async {
    final path = await databasePath();
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

  /// Bumped by every bulk wipe. The background grader samples this when it
  /// LISTS games and re-checks before each write: its sweep runs minutes and
  /// deliberately seeds-then-saves, so a wipe mid-sweep would otherwise be
  /// followed by the whole stale snapshot being graded and written straight
  /// back — the archive resurrecting itself, run-proven in #293's review.
  int wipeEpoch = 0;

  /// The bulk clear behind Settings' "Clear local games" (#292). Games only:
  /// the kv table (practice, misc) is someone else's data.
  Future<void> deleteAllGames() async {
    wipeEpoch++;
    await _db.delete('games');
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
