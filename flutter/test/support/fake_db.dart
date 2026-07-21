// An in-memory AppDb for tests: the archive without sqflite, which needs a
// platform channel no unit test has.

import 'package:botvinnik_mobile/db/app_db.dart';

class FakeDb implements AppDb {
  /// Every record handed to [saveGame], in save order.
  final List<Map<String, dynamic>> saved = [];

  FakeDb([List<Map<String, dynamic>> initial = const []]) {
    saved.addAll(initial);
  }

  @override
  Future<void> saveGame(Map<String, dynamic> storedGame) async {
    saved.add(storedGame);
  }

  /// Newest first, as the real one orders by endedAt DESC.
  @override
  Future<List<Map<String, dynamic>>> listGames() async =>
      saved.reversed.toList();

  @override
  Future<void> deleteGame(String id) async {
    saved.removeWhere((g) => g['id'] == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
