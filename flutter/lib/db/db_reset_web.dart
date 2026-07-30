import 'package:sqflite/sqflite.dart' show databaseExists, deleteDatabase;

/// Drop the database on web, and VERIFY it is gone.
///
/// There is nowhere to move it to — the file lives inside sqflite's IndexedDB
/// store, which has no rename — so unlike native this really does discard, and
/// the UI says so before the button is pressed.
///
/// The verification is the point, and it was missing. `deleteDatabase` swallows
/// its own failures at two layers:
///
///   sqflite_common_ffi/sqflite_ffi_impl.dart:
///     // Ignore failure
///     try { await sqfliteFfiHandler.deleteDatabasePlatform(path!); } catch (_) {}
///
///   sqflite_common_ffi_web/database_file_system_web.dart:
///     try { … fs.xDelete(path, 0); await _flush(); } catch (_) { … }
///
/// So a delete that does nothing at all returns normally. The first version of
/// this reported "discarded", the app retried, reopened the same corrupt file,
/// and showed the identical error — a reset button that looked like it worked
/// and did nothing, which is worse than no button.
///
/// Throws [DatabaseStillThere] when the browser will not let go, so the UI can
/// say what actually helps instead of claiming success.
Future<String?> moveDatabaseAside(String path) async {
  await deleteDatabase(path);
  if (await databaseExists(path)) throw const DatabaseStillThere();
  return null;
}

/// The delete ran and the database is still there.
class DatabaseStillThere implements Exception {
  const DatabaseStillThere();
  @override
  String toString() => 'the browser did not release the database';
}
