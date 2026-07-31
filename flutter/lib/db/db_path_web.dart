import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

/// Declared so both branches of the conditional export offer the same surface.
/// Unused on web, where there is one store and nowhere else to point.
@visibleForTesting
String? databasePathOverride;

/// Where the database lives on web: inside sqflite's IndexedDB store, whose
/// "path" is a key rather than a filesystem location. Nothing to choose and
/// nothing to migrate.
Future<String> databasePath() async => '${await getDatabasesPath()}/botvinnik.db';
