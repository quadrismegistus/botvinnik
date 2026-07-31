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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

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

  /// A real SQLite database with [rows] rows, cleanly closed.
  Future<void> seedDb(String path, int rows) async {
    File(path).parent.createSync(recursive: true);
    final db = await databaseFactory.openDatabase(path);
    await db.execute('CREATE TABLE games (id TEXT PRIMARY KEY)');
    for (var i = 0; i < rows; i++) {
      await db.insert('games', {'id': 'g$i'});
    }
    await db.close();
  }

  test('moves a database out of Documents when the new home is empty', () async {
    await seedDb(legacyPath(), 7);
    Directory('${tmp.path}/Support').createSync(recursive: true);

    expect(await migrateDatabase(legacy: legacyPath(), target: targetPath()), isTrue);

    final moved = await databaseFactory.openDatabase(targetPath());
    expect((await moved.query('games')).length, 7, reason: 'all rows arrived');
    await moved.close();
    expect(File(legacyPath()).existsSync(), isFalse,
        reason: 'moved, not copied — two live databases is the bug');
  });

  test('NEVER moves a database away from a sidecar it still needs', () async {
    // The invariant, not the mechanism. The original design carried the
    // sidecars after the database and destroyed archives when that half-failed
    // (proved on a real 40-game database: the move reported failure with the
    // database already gone and its journal stranded, and the caller's
    // fallback could not fire because it tests for the legacy file). Now the
    // database is opened and closed first so SQLite settles its own journal.
    //
    // Asserted as "these two never come apart" because how SQLite disposes of
    // a given sidecar is its business — a hot journal it can roll back it
    // deletes, one it cannot it may leave. Either outcome is fine; splitting
    // them is not.
    await seedDb(legacyPath(), 3);
    File('${legacyPath()}-journal').writeAsStringSync('a hot journal');

    final moved = await migrateDatabase(legacy: legacyPath(), target: targetPath());

    final home = moved ? targetPath() : legacyPath();
    final away = moved ? legacyPath() : targetPath();
    expect(File(home).existsSync(), isTrue);
    expect(File(away).existsSync(), isFalse, reason: 'exactly one database');
    expect(File('$away-journal').existsSync(), isFalse,
        reason: 'a journal must never be left beside the database it left');

    // and whatever moved is still a readable database with its rows
    final db = await databaseFactory.openDatabase(home);
    expect((await db.query('games')).length, 3);
    await db.close();
  });

  test('a database it cannot open is left exactly where it is', () async {
    // Moving an unreadable database would strand the user's only copy at a
    // path nothing looks at; openChecked can offer recovery where it lies.
    File(legacyPath()).parent.createSync(recursive: true);
    File(legacyPath()).writeAsStringSync('this is not a database at all');

    expect(await migrateDatabase(legacy: legacyPath(), target: targetPath()), isFalse);
    expect(File(legacyPath()).existsSync(), isTrue);
    expect(File(targetPath()).existsSync(), isFalse);
  });

  test('REFUSES when a database already exists at the new home', () async {
    // The case that would destroy data. Two databases with different games is
    // a real state — picking between them by size or mtime is the kind of
    // cleverness that loses somebody's history. The target wins; the legacy
    // file is left exactly where it is, for a human to look at.
    await seedDb(legacyPath(), 1);
    seed(targetPath(), 'ninety-five current games');

    expect(await migrateDatabase(legacy: legacyPath(), target: targetPath()), isFalse);

    expect(File(targetPath()).readAsStringSync(), 'ninety-five current games',
        reason: 'the target must never be overwritten');
    expect(File(legacyPath()).existsSync(), isTrue,
        reason: 'and the legacy file must not be destroyed either');
  });

  test('does nothing when there is nothing to move', () async {
    Directory('${tmp.path}/Support').createSync(recursive: true);
    expect(await migrateDatabase(legacy: legacyPath(), target: targetPath()), isFalse);
    expect(File(targetPath()).existsSync(), isFalse);
  });

  test('is idempotent — a second boot does not move anything back', () async {
    await seedDb(legacyPath(), 2);
    Directory('${tmp.path}/Support').createSync(recursive: true);

    expect(await migrateDatabase(legacy: legacyPath(), target: targetPath()), isTrue);
    expect(await migrateDatabase(legacy: legacyPath(), target: targetPath()), isFalse);
    expect(File(targetPath()).existsSync(), isTrue);
  });

  test('reports failure rather than claiming a move it did not make', () async {
    // The caller uses the return value to decide whether to fall back to the
    // legacy path. A migration that says "true" after failing would open an
    // empty database beside the player's whole history.
    await seedDb(legacyPath(), 2);
    // A FILE where the target's directory should be: creating the parent
    // cannot succeed, so neither can the rename. (A merely absent directory is
    // no longer a failure — migrateDatabase creates it.)
    seed('${tmp.path}/blocked', 'not a directory');
    expect(
      await migrateDatabase(legacy: legacyPath(), target: '${tmp.path}/blocked/botvinnik.db'),
      isFalse,
    );
    expect(File(legacyPath()).existsSync(), isTrue,
        reason: 'and the original is still there to fall back to');
  });

  group('the macOS decision (previously untestable)', () {
    // Replacing the whole macOS body with `throw` used to leave 969 tests
    // green: `databasePathOverride` short-circuits before it and
    // `Platform.isMacOS` gates the rest. These reach it through injected
    // directory lookups, so the DECISION is covered, not just the move.

    Future<String> resolve({String? supportDir, Object? supportThrows}) =>
        resolveMacosPath(
          support: () async {
            if (supportThrows != null) throw supportThrows;
            return supportDir ?? '${tmp.path}/Support';
          },
          legacy: () async => '${tmp.path}/Documents',
        );

    test('returns the new home, having moved the games there', () async {
      await seedDb(legacyPath(), 5);
      expect(await resolve(), targetPath());
      expect(File(targetPath()).existsSync(), isTrue);
      expect(File(legacyPath()).existsSync(), isFalse);
    });

    test('returns the LEGACY path when the move could not happen', () async {
      // The case that matters most: never hand back a path with no database
      // while one full of games sits at the other.
      await seedDb(legacyPath(), 5);
      File('${tmp.path}/blocked').writeAsStringSync('not a directory');

      expect(await resolve(supportDir: '${tmp.path}/blocked/Support'), legacyPath());
      expect(File(legacyPath()).existsSync(), isTrue);
    });

    test('a path_provider failure does not brick boot', () async {
      // Before this branch existed macOS had no such dependency. A throw here
      // reaches boot as something that is NOT DatabaseUnreadable, so the
      // recovery screen offers a button that resolves the same path and
      // throws again.
      await seedDb(legacyPath(), 5);
      expect(
        await resolve(supportThrows: StateError('no support directory')),
        legacyPath(),
      );
    });

    test('a fresh install with no database anywhere gets the new home', () async {
      expect(await resolve(), targetPath());
    });
  });
}
