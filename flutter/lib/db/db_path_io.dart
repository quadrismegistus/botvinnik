import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

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

  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final target = '${dir.path}/botvinnik.db';
  final legacy = '${await getDatabasesPath()}/botvinnik.db';
  final moved = migrateDatabase(legacy: legacy, target: target);

  // If the move did not happen and the ONLY database is the legacy one, keep
  // using it. Returning the new path here would open an empty database beside
  // a file holding every game the player has — the worst outcome available,
  // and worse than never having moved at all.
  if (!moved && File(legacy).existsSync() && !File(target).existsSync()) {
    return legacy;
  }
  return target;
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
/// Renames rather than copies, so it cannot half-succeed into two live
/// databases, and carries the `-wal`/`-shm`/`-journal` sidecars: a database
/// separated from its write-ahead log is a database missing its most recent
/// transactions.
@visibleForTesting
bool migrateDatabase({required String legacy, required String target}) {
  final from = File(legacy);
  if (!from.existsSync() || File(target).existsSync()) return false;
  try {
    // Own the whole job rather than depending on the caller having made the
    // directory first — an ordering dependency between two functions is a bug
    // waiting for someone to reorder them.
    File(target).parent.createSync(recursive: true);
    from.renameSync(target);
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final side = File('$legacy$suffix');
      if (side.existsSync()) side.renameSync('$target$suffix');
    }
    debugPrint('[db] moved the games database out of Documents to $target');
    return true;
  } on FileSystemException catch (e) {
    // A cross-device rename, a permission problem, an iCloud placeholder that
    // is not really there yet. Keep using the legacy path rather than starting
    // empty beside a database full of the user's games.
    debugPrint('[db] could not move the database out of Documents: $e');
    return false;
  }
}
