import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Points sqflite at the sqlite3 WASM build. Storage lands in IndexedDB, so
/// games and practice items persist across reloads.
///
/// The SHARED-WORKER factory, and the difference is not performance.
///
/// This was `databaseFactoryFfiWebNoWebWorker`, chosen during the Flutter
/// spike because it "boots reliably" without needing `sqflite_sw.js` to load
/// and hand back a port. That factory runs sqlite3 on the main isolate of
/// whatever tab opened it — so two tabs, or the installed PWA plus a browser
/// tab, are two independent sqlite3 instances with two page caches writing one
/// IndexedDB-backed file, with nothing serialising them. Interleaved page
/// writes tear the image, and the next read fails with
/// `SQLITE_CORRUPT (11): database disk image is malformed`. Reported from
/// botvinnik.app while testing cross-device sync, which is not sync's fault:
/// having the app open in two places is how you exercise sync, and that is
/// exactly how you get the second writer.
///
/// A SharedWorker is one instance per ORIGIN however many tabs connect, so
/// every tab's queries go through a single sqlite3 with a single cache. macOS
/// never had the problem because it reaches a real file through FFI, with real
/// OS locking.
///
/// `flutter/web/sqflite_sw.js` must be deployed for this to work; it is
/// committed rather than generated, and e2e/web_db.spec.ts asserts the browser
/// really fetches it.
void initDatabaseFactory() {
  databaseFactory = databaseFactoryFfiWeb;
}
