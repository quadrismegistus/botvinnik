// Moving the games database out of the user's Documents folder (#255).
//
// `getDatabasesPath()` on darwin is NSDocumentDirectory. Inside a sandbox that
// is a private container; the macOS build drops app-sandbox so it can exec
// player-supplied UCI engines (#183), so it resolves to the REAL ~/Documents —
// where the app has been writing a 3.6MB SQLite file that looks like junk,
// syncs to iCloud Drive, and is invisible to the app's own Backup screen.
//
// These test the migration, not the destination, because the destination is a
// one-line path change and the migration is where data gets lost. The author's
// own machine has TWO databases with different games in them (95 in Documents,
// 10 in an abandoned sandbox container), which is why the rules below are
// deliberately timid.
//
// In test/vm/ because it writes files; the top level of test/ is also run in a
// browser.
//
//   cd flutter && flutter test test/vm/db_migration_test.dart

import 'dart:io';

import 'package:botvinnik_mobile/db/db_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('db-migrate'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String legacyPath() => '${tmp.path}/Documents/botvinnik.db';
  String targetPath() => '${tmp.path}/Support/botvinnik.db';

  File seed(String path, String contents) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contents);
    return f;
  }

  test('moves a database out of Documents when the new home is empty', () {
    seed(legacyPath(), 'the real games');
    Directory('${tmp.path}/Support').createSync(recursive: true);

    expect(migrateDatabase(legacy: legacyPath(), target: targetPath()), isTrue);

    expect(File(targetPath()).readAsStringSync(), 'the real games');
    expect(File(legacyPath()).existsSync(), isFalse,
        reason: 'moved, not copied — two live databases is the bug');
  });

  test('carries the sidecars, or the newest transactions are lost', () {
    // A database separated from its write-ahead log has silently rolled back
    // to its last checkpoint. Worse than a visible failure.
    seed(legacyPath(), 'db');
    seed('${legacyPath()}-wal', 'recent transactions');
    seed('${legacyPath()}-shm', 'shared memory');

    expect(migrateDatabase(legacy: legacyPath(), target: targetPath()), isTrue);

    expect(File('${targetPath()}-wal').readAsStringSync(), 'recent transactions');
    expect(File('${targetPath()}-shm').existsSync(), isTrue);
    expect(File('${legacyPath()}-wal').existsSync(), isFalse);
  });

  test('REFUSES when a database already exists at the new home', () {
    // The case that would destroy data. Two databases with different games is
    // a real state — picking between them by size or mtime is the kind of
    // cleverness that loses somebody's history. The target wins; the legacy
    // file is left exactly where it is, for a human to look at.
    seed(legacyPath(), 'ten old games');
    seed(targetPath(), 'ninety-five current games');

    expect(migrateDatabase(legacy: legacyPath(), target: targetPath()), isFalse);

    expect(File(targetPath()).readAsStringSync(), 'ninety-five current games',
        reason: 'the target must never be overwritten');
    expect(File(legacyPath()).readAsStringSync(), 'ten old games',
        reason: 'and the legacy file must not be destroyed either');
  });

  test('does nothing when there is nothing to move', () {
    Directory('${tmp.path}/Support').createSync(recursive: true);
    expect(migrateDatabase(legacy: legacyPath(), target: targetPath()), isFalse);
    expect(File(targetPath()).existsSync(), isFalse);
  });

  test('is idempotent — a second boot does not move anything back', () {
    seed(legacyPath(), 'games');
    Directory('${tmp.path}/Support').createSync(recursive: true);

    expect(migrateDatabase(legacy: legacyPath(), target: targetPath()), isTrue);
    expect(migrateDatabase(legacy: legacyPath(), target: targetPath()), isFalse);
    expect(File(targetPath()).readAsStringSync(), 'games');
  });

  test('reports failure rather than claiming a move it did not make', () {
    // The caller uses the return value to decide whether to fall back to the
    // legacy path. A migration that says "true" after failing would open an
    // empty database beside the player's whole history.
    seed(legacyPath(), 'games');
    // A FILE where the target's directory should be: creating the parent
    // cannot succeed, so neither can the rename. (A merely absent directory is
    // no longer a failure — migrateDatabase creates it.)
    seed('${tmp.path}/blocked', 'not a directory');
    expect(
      migrateDatabase(legacy: legacyPath(), target: '${tmp.path}/blocked/botvinnik.db'),
      isFalse,
    );
    expect(File(legacyPath()).existsSync(), isTrue,
        reason: 'and the original is still there to fall back to');
  });
}
