// A database that opens but cannot be read (#254).
//
// Reported from botvinnik.app as `SqfliteFfiException(sqlite_error: 11 …
// database disk image is malformed)` on `SELECT * FROM games ORDER BY endedAt
// DESC`. Two things made that a dead end rather than an inconvenience:
//
//   * `openDatabase` reads `PRAGMA user_version`, which lives in the page-1
//     header and survives torn DATA pages — so open() succeeded and the app
//     died on the first screen that asked for a game.
//   * there was no reset anywhere in the app, so the only way out was knowing
//     where the file lives.
//
// These tests build a real database, tear real pages, and check the app can
// tell "unreadable" from "ordinary error" — the distinction that decides
// whether a human is offered a destructive button.
//
// In test/vm/ because it writes files: the top level of test/ is run a second
// time in a browser (`flutter test test/*.dart --platform chrome`).
//
//   cd flutter && flutter test test/vm/db_unreadable_test.dart

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:botvinnik_mobile/db/app_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A database with the app's schema and [games] games in it.
Future<String> buildDb(String dir, {int games = 200}) async {
  final path = '$dir/botvinnik.db';
  final db = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(version: 1));
  await db.execute(
      'CREATE TABLE games (id TEXT PRIMARY KEY, endedAt INTEGER NOT NULL, json TEXT NOT NULL)');
  await db.execute('CREATE INDEX games_endedAt ON games(endedAt DESC)');
  await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)');
  final batch = db.batch();
  for (var i = 0; i < games; i++) {
    batch.insert('games', {
      'id': 'g$i',
      'endedAt': 1700000000000 + i,
      // padded, so the file is big enough to have pages worth tearing
      'json': '{"id":"g$i","pad":"${'x' * 400}"}',
    });
  }
  batch.insert('kv', {'key': 'practice', 'value': '[]'});
  await batch.commit(noResult: true);
  await db.close();
  return path;
}

/// Overwrite [count] pages with noise, leaving page 1 (the header) alone —
/// which is what makes open() succeed and the read fail.
void tearPages(String path, {int from = 4, int count = 8}) {
  const pageSize = 4096;
  final f = File(path);
  final bytes = f.readAsBytesSync();
  final rnd = Random(7);
  final out = Uint8List.fromList(bytes);
  for (var p = from; p < from + count; p++) {
    final start = p * pageSize;
    if (start + pageSize > out.length) break;
    for (var i = 0; i < pageSize; i++) {
      out[start + i] = rnd.nextInt(256);
    }
  }
  f.writeAsBytesSync(out);
}

/// Run the real [AppDb.openChecked] against a database at [dir].
Future<AppDb> openCheckedAt(String path) async {
  await databaseFactory.setDatabasesPath(File(path).parent.path);
  return AppDb.openChecked();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('db-unreadable'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a torn database opens fine and only fails when READ', () async {
    // The precondition that made the first recovery attempt useless. If this
    // ever stops holding, the probe in openChecked is unnecessary and should
    // go — but while it holds, wrapping open() alone guards nothing.
    final path = await buildDb(tmp.path);
    tearPages(path);

    final db = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(version: 1));
    // opening is not enough to notice
    expect(await db.rawQuery('PRAGMA user_version'), isNotEmpty);

    Object? thrown;
    try {
      await db.rawQuery('SELECT * FROM games ORDER BY endedAt DESC');
    } catch (e) {
      thrown = e;
    }
    await db.close();

    expect(thrown, isNotNull, reason: 'the read is where it surfaces');
    expect(AppDb.isUnreadable(thrown!), isTrue,
        reason: 'and it must be recognised as the file being unreadable');
  });

  test('ordinary errors are not "unreadable" — they must not offer a reset',
      () async {
    // Each of these is a bug to fix, not a database to move aside. The button
    // this gates is destructive on web, so a false positive costs real games.
    final path = await buildDb(tmp.path, games: 2);
    final db = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(version: 1));

    Future<Object> failing(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        return e;
      }
      fail('expected a throw');
    }

    expect(
      AppDb.isUnreadable(await failing(() => db.rawQuery('SELECT * FROM nope'))),
      isFalse,
      reason: 'no such table',
    );
    expect(
      AppDb.isUnreadable(
          await failing(() => db.rawQuery('SELECT nope FROM games'))),
      isFalse,
      reason: 'no such column',
    );
    expect(
      AppDb.isUnreadable(await failing(() => db.insert('games', {
            'id': 'g0', // already there
            'endedAt': 1,
            'json': '{}',
          }))),
      isFalse,
      reason: 'UNIQUE constraint',
    );
    expect(
      AppDb.isUnreadable(await failing(() => db.rawQuery('SELEKT 1'))),
      isFalse,
      reason: 'syntax error',
    );

    // The one that killed the string-matching version: the message
    // interpolates BOUND ARGUMENTS, so user data lands in it.
    final poisoned = await failing(() => db.insert('games', {
          'id': 'g0',
          'endedAt': 2,
          'json': '{"note":"database disk image is malformed"}',
        }));
    expect(poisoned.toString().toLowerCase(),
        contains('database disk image is malformed'),
        reason: 'precondition: the phrase really does reach the message');
    expect(AppDb.isUnreadable(poisoned), isFalse,
        reason: 'a game whose text quotes the error is not a corrupt database');

    await db.close();
  });

  test('a truncated database is recoverable, not a red wall', () async {
    // open() used to sit OUTSIDE the try, so this whole family — truncation,
    // header damage, not-a-database — threw a raw driver exception and the
    // boot screen hid the reset button, which is the one thing that would have
    // helped. Truncation reports code 11 at `PRAGMA user_version`.
    final path = await buildDb(tmp.path);
    final f = File(path);
    final bytes = f.readAsBytesSync();
    f.writeAsBytesSync(bytes.sublist(0, (bytes.length * 0.6).round()));

    await expectLater(
      openCheckedAt(path),
      throwsA(isA<DatabaseUnreadable>()),
      reason: 'must reach the screen that offers a way out',
    );
  });

  test('a file that is not a database at all', () async {
    final path = '${tmp.path}/botvinnik.db';
    File(path).writeAsStringSync('this is not a database' * 100);
    await expectLater(openCheckedAt(path), throwsA(isA<DatabaseUnreadable>()));
  });

  test('damage the cheap probe missed — a middle table page', () async {
    // The original probe read the FIRST index leaf and one table leaf, so a
    // tear anywhere else slipped through: measured, it caught 6 of 191 random
    // single-page tears. A full scan caught 191 of 191.
    final path = await buildDb(tmp.path, games: 400);
    tearPages(path, from: 30, count: 6);
    await expectLater(openCheckedAt(path), throwsA(isA<DatabaseUnreadable>()));
  });

  test('a healthy database passes the full scan', () async {
    // The other half of a destructive gate: it must not fire on a good file.
    final path = await buildDb(tmp.path, games: 300);
    await expectLater(openCheckedAt(path), completes);
  });
}
