import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

/// Point the database somewhere else, for tests.
///
/// HONOURED here, not merely declared. An earlier version defined it on this
/// branch and ignored it — and this repo really does run
/// `flutter test test/*.dart --platform chrome`, so a browser test that set it
/// would have looked steered while operating on the real store.
@visibleForTesting
String? databasePathOverride;

/// Where the database lives on web: inside sqflite's IndexedDB store, whose
/// "path" is a key rather than a filesystem location. Nothing to choose and
/// nothing to migrate — see db_path_io.dart for the macOS story (#255).
Future<String> databasePath() async =>
    databasePathOverride ?? '${await getDatabasesPath()}/botvinnik.db';
