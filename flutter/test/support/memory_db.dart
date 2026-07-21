// A complete in-memory AppDb: both tables, no sqflite.
//
// Deliberately NOT a noSuchMethod fake. test/support/fake_db.dart answers
// anything it has not implemented with null, and before it grew real methods
// no test had ever reached the end of a save because a `Future<T>` that
// resolves to null type-errors somewhere upstream of the assertion. Backup
// touches both tables, so a fake that quietly returned null from `listGames`
// would let a restore "pass" having written nothing. Implementing the whole
// interface means the day AppDb grows a method, this stops COMPILING — which
// is the loudest failure available.

import 'package:botvinnik_mobile/db/app_db.dart';

class MemoryDb implements AppDb {
  /// The games table, keyed by id as the real PRIMARY KEY is.
  final Map<String, Map<String, dynamic>> games = {};
  final Map<String, String> kv = {};

  /// Every id handed to [saveGame], including repeats — so a test can tell an
  /// upsert apart from a skip, which the map alone cannot show.
  final List<String> writes = [];

  MemoryDb([List<Map<String, dynamic>> initial = const []]) {
    for (final g in initial) {
      games[g['id'] as String] = g;
    }
  }

  @override
  Future<void> saveGame(Map<String, dynamic> storedGame) async {
    // The real one parses endedAt to build its index and casts id to String;
    // both throw on a malformed record, and the import path is expected to
    // have filtered those out before reaching here.
    final id = storedGame['id'] as String;
    DateTime.parse(storedGame['endedAt'] as String);
    writes.add(id);
    games[id] = storedGame;
  }

  /// Newest first, as the real one's `ORDER BY endedAt DESC`.
  @override
  Future<List<Map<String, dynamic>>> listGames() async {
    final rows = games.values.toList()
      ..sort((a, b) =>
          (b['endedAt'] as String).compareTo(a['endedAt'] as String));
    return rows;
  }

  @override
  Future<void> deleteGame(String id) async {
    games.remove(id);
  }

  @override
  Future<String?> kvGet(String key) async => kv[key];

  @override
  Future<void> kvPut(String key, String value) async => kv[key] = value;
}
