import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Points sqflite at the sqlite3 WASM build (web/sqlite3.wasm + the worker
/// installed by `dart run sqflite_common_ffi_web:setup`). Storage lands in
/// IndexedDB, so games and practice items persist across reloads.
void initDatabaseFactory() {
  // the shared-worker factory needs sqflite_sw.js to load and hand back a
  // port; the no-worker build keeps sqlite3 on the main isolate and boots
  // reliably, which is what a spike wants
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}
