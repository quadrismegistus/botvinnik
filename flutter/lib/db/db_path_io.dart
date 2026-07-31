import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath, openDatabase;

/// Where the games database lives, and — on macOS — moving it out of the
/// user's own Documents folder if it is still there (#255).
///
/// `getDatabasesPath()` on darwin is
/// `NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, …)`
/// (`sqflite_darwin/SqflitePlugin.m:766`). Inside a sandbox that is a private
/// container and perfectly fine, which is why iOS keeps it. The macOS build
/// deliberately drops `app-sandbox` so it can exec player-supplied UCI engines
/// (#183) — and without the sandbox, that same call returns the REAL
/// `~/Documents`. So the app has been writing a 3.6MB SQLite file into the
/// folder where people keep their letters.
///
/// Three ways that bites, in rough order of how much it would annoy someone:
///
///  * It looks like junk and gets deleted. It is named `botvinnik.db` and sits
///    beside their actual documents.
///  * **It syncs.** Anyone with iCloud Drive's Desktop & Documents option on is
///    uploading a file that changes after every game — and file-level cloud
///    sync racing an open SQLite database is its own corruption route, quite
///    separate from the multi-tab one fixed in #252.
///  * It is invisible to the app's own Backup screen, so a user who finds it
///    has no way to know what it is.
///
/// Application Support is where an unsandboxed Mac app's private data belongs,
/// and cloud sync leaves it alone.
/// Point the database somewhere else, for tests.
///
/// Needed because the macOS branch resolves through path_provider and ignores
/// sqflite's own `setDatabasesPath`, which is what tests had been using — so
/// without this seam, every test touching a real database file would silently
/// operate on the developer's actual Application Support directory. That is
/// not a hypothetical: adding the macOS branch broke #254's suite exactly that
/// way, and the failure mode of NOT noticing would have been a test suite
/// quietly reading and deleting real games.
@visibleForTesting
String? databasePathOverride;

Future<String> databasePath() async {
  final override = databasePathOverride;
  if (override != null) return override;
  if (!Platform.isMacOS) return '${await getDatabasesPath()}/botvinnik.db';
  return _resolved ??= await resolveMacosPath(
    support: () async => (await getApplicationSupportDirectory()).path,
    legacy: getDatabasesPath,
  );
}

/// The answer for this process, computed once.
///
/// Memoised because [AppDb.open] and [AppDb.moveAside] each ask independently,
/// and the answer could otherwise CHANGE between them. Concretely: with a
/// database at both paths the target wins and the legacy one is left alone —
/// then "Start fresh" renames the winner aside, the retry asks again, and the
/// migration fires and opens the abandoned copy. The user pressed a button
/// promising a fresh start and silently got a stale archive, from the module
/// whose stated rule is that it never picks between two databases.
String? _resolved;

/// The macOS decision, with its two directory lookups injected.
///
/// Separated so it can be tested at all. The branch this replaces was
/// unreachable from any test — `databasePathOverride` short-circuits before it
/// and `Platform.isMacOS` gates the rest — so replacing its entire body with a
/// `throw` left the whole suite green. The migration's own tests covered the
/// piece that was easy to reach, and nothing covered the composition, which is
/// exactly where the archive-destroying bug lived.
@visibleForTesting
Future<String> resolveMacosPath({
  required Future<String> Function() support,
  required Future<String> Function() legacy,
}) async {
  final legacyPath = '${await legacy()}/botvinnik.db';
  String targetPath;
  try {
    final dir = Directory(await support());
    await dir.create(recursive: true);
    targetPath = '${dir.path}/botvinnik.db';
  } catch (e) {
    // path_provider failing, or a support directory we cannot create. Before
    // this branch existed macOS had no such dependency, and letting it throw
    // fails boot with an error that is NOT DatabaseUnreadable — so the recovery
    // screen shows a generic message and its button, which resolves this same
    // path, throws again. Fall back to where the games already are.
    debugPrint('[db] no application support directory ($e); staying in place');
    return legacyPath;
  }

  final moved = await migrateDatabase(legacy: legacyPath, target: targetPath);

  // If the move did not happen and the ONLY database is the legacy one, keep
  // using it. Returning the new path here would open an empty database beside
  // a file holding every game the player has — the worst outcome available,
  // and worse than never having moved at all.
  if (!moved && File(legacyPath).existsSync() && !File(targetPath).existsSync()) {
    return legacyPath;
  }
  return targetPath;
}

/// Move a database from [legacy] to [target] if that is the safe thing to do.
///
/// Returns true when it moved something. Deliberately conservative: it moves
/// ONLY when the target does not exist. If both are there, the target wins and
/// the legacy file is left untouched — two databases with different games in
/// them is exactly the situation on the author's machine (95 games in
/// Documents, 10 in an abandoned sandbox container), and picking between them
/// by mtime or size is the kind of cleverness that loses somebody's history.
///
/// ## Why it opens the database before moving it
///
/// The first version renamed the database and THEN looped its `-wal`/`-shm`/
/// `-journal` sidecars. Any failure in that loop — a blocked destination, a
/// permission difference, an unmaterialised iCloud placeholder — returned
/// false with the database already moved and its journal left behind. Proved
/// with a real 40-game database: the move reported failure, the caller's
/// "fall back to legacy" guard could not fire because the legacy file was gone
/// by then, and the app opened a database separated from its journal.
///
/// macOS makes that worse than lost transactions. `sqflite_darwin` sets no
/// `journal_mode`, so it inherits SQLite's `delete` default and the sidecar is
/// a HOT JOURNAL — separating it from the database skips the rollback and
/// yields `SQLITE_CORRUPT`. The migration would have manufactured the exact
/// failure #254 exists to survive, and "Start fresh" would then move the only
/// copy of the games aside while the journal that could repair it sat in
/// Documents forever.
///
/// So: open the database and close it cleanly first. SQLite rolls back a hot
/// journal or checkpoints a WAL and removes the sidecar ITSELF. What remains
/// is a single-file rename, which either happens or does not — no half state
/// to recover from, and nothing to keep in sync.
Future<bool> migrateDatabase({required String legacy, required String target}) async {
  final from = File(legacy);
  if (!from.existsSync() || File(target).existsSync()) return false;
  try {
    File(target).parent.createSync(recursive: true);

    // Settle the journal, and confirm this is a database at all.
    //
    // The read is not ceremony: `openDatabase` SUCCEEDS on arbitrary bytes,
    // because SQLite does not touch the header until a statement runs. Opening
    // alone therefore validates nothing, and a file that is not a database
    // would be moved to a path the recovery UI has no reason to look at.
    // `PRAGMA user_version` is the cheapest statement that reads page 1.
    //
    // A database with torn DATA pages still passes this and still moves, which
    // is right — it is a real database file, and openChecked offers recovery
    // wherever it lands.
    final db = await openDatabase(legacy);
    try {
      await db.rawQuery('PRAGMA user_version');
    } finally {
      await db.close();
    }

    // If anything is still beside it, something holds the database open (a
    // second instance) or SQLite did not clean up. Refuse rather than move a
    // database away from state it still needs.
    for (final suffix in ['-wal', '-shm', '-journal']) {
      if (File('$legacy$suffix').existsSync()) {
        debugPrint('[db] not moving the database: $suffix still present');
        return false;
      }
    }

    from.renameSync(target);
    debugPrint('[db] moved the games database out of Documents to $target');
    return true;
  } catch (e) {
    // A cross-device rename (a home directory on a network mount or external
    // volume), a permission problem, an unreadable database. Keep using the
    // legacy path rather than starting empty beside a database full of games.
    debugPrint('[db] could not move the database out of Documents: $e');
    return false;
  }
}
