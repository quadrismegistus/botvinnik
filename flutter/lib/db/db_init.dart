// sqflite talks to the platform's own SQLite on mobile and macOS, but the
// browser has none — web needs the sqlite3 WASM build wired in as the
// database factory before any query runs.
export 'db_init_io.dart' if (dart.library.js_interop) 'db_init_web.dart';
