import 'package:sqflite/sqflite.dart' show deleteDatabase;

/// Drop the database on web.
///
/// There is nowhere to move it TO: the file lives inside sqflite's IndexedDB
/// store, which has no rename. So unlike native this really does discard, and
/// the UI says so before the button is pressed. Reading the bytes out first
/// (`readDatabaseBytes`) would preserve them for a salvage that does not exist
/// yet — see #254.
Future<String?> moveDatabaseAside(String path) async {
  await deleteDatabase(path);
  return null;
}
