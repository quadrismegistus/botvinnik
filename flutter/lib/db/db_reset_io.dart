import 'dart:io' show File;

/// Move the database aside on a platform with a real filesystem, and report
/// where it went.
///
/// Renamed rather than deleted: "unreadable by us" is not "unrecoverable".
/// Most of a torn SQLite file is still there — #254 records 77% of games
/// readable by rowid walk, and 100% when only the index root is damaged —
/// and nothing in the app can salvage it today. A rename costs nothing and
/// keeps that door open; a delete closes it forever.
Future<String?> moveDatabaseAside(String path) async {
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final to = '$path.corrupt-$stamp';
  await File(path).rename(to);
  // The sidecars belong to the file that just moved. A fresh database
  // inheriting a stale write-ahead log is its own corruption.
  for (final suffix in ['-wal', '-shm', '-journal']) {
    final f = File('$path$suffix');
    if (f.existsSync()) f.renameSync('$to$suffix');
  }
  return to;
}
