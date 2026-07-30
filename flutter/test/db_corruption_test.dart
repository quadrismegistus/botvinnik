// Which errors mean "throw the local database away".
//
// Reported from botvinnik.app: `SqfliteFfiException(sqlite_error 11 …
// database disk image is malformed)` on `SELECT * FROM games ORDER BY endedAt
// DESC`, which took the whole app down at startup with no way in to fix it.
// The cause is in db_init_web.dart; this is the other half — surviving a file
// that is already torn, since every user hit by it has one.
//
// The classifier is the risky part, not the recovery: it decides whether to
// DISCARD data. sqflite flattens every backend into DatabaseException /
// SqfliteFfiException with no result-code field, so it has to match on the
// message, and a match that is too eager deletes a database over a typo in a
// query.
//
//   cd flutter && flutter test test/db_corruption_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/db/app_db.dart';

void main() {
  group('is this the database itself being unreadable?', () {
    test('the reported error is recognised, verbatim', () {
      // Copied from the screenshot rather than paraphrased — the whole value
      // of this test is that it matches the string the app really produced.
      const reported =
          'SqfliteFfiException(sqlite_error: 11, , SqliteException(11): while '
          'selecting from statement, database disk image is malformed, database '
          'disk image is malformed (code 11) Causing statement: SELECT * FROM '
          'games ORDER BY endedAt DESC';
      expect(AppDb.isCorruptionError(Exception(reported)), isTrue);
    });

    test('a file that is not a database at all counts', () {
      expect(
        AppDb.isCorruptionError(Exception('SqliteException(26): file is not a database')),
        isTrue,
      );
    });

    test('ordinary errors do NOT count — they must not delete anything', () {
      // Each of these is a bug to fix, not a database to discard. If any of
      // them matched, a mistyped column name would silently wipe the games.
      for (final ordinary in [
        'DatabaseException(no such table: games)',
        'DatabaseException(no such column: endedAt)',
        'DatabaseException(UNIQUE constraint failed: games.id)',
        'DatabaseException(database is locked)',
        'DatabaseException(attempt to write a readonly database)',
        'DatabaseException(syntax error near "SELECT")',
        'Exception(disk I/O error)',
      ]) {
        expect(
          AppDb.isCorruptionError(Exception(ordinary)),
          isFalse,
          reason: 'must not discard the database for: $ordinary',
        );
      }
    });

    test('matching is case-insensitive', () {
      expect(
        AppDb.isCorruptionError(Exception('DATABASE DISK IMAGE IS MALFORMED')),
        isTrue,
      );
    });
  });
}
