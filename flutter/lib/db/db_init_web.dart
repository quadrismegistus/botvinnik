import 'dart:js_interop';

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
/// ## The guarantee is conditional, and the condition is not universal
///
/// `sqflite_common_ffi_web` tries `new SharedWorker(...)` and, if that throws,
/// SILENTLY falls back to `new Worker(...)` — a DEDICATED worker per tab, i.e.
/// the same one-sqlite3-per-tab topology, merely moved off the main thread
/// (`load_sqlite_web.dart`: the `catch` only logs when its private `_debug` is
/// on). Measured across two tabs against the real bundle: `sqlite3.wasm` loads
/// ONCE with SharedWorker available and FIVE times without.
///
/// So this fix does not hold everywhere. `SharedWorker` is absent on Chrome
/// for Android before milestone 148 and on current Samsung Internet (added in
/// 4.0, removed in 5.0); desktop browsers and iOS Safari 16.4+ are fine — the
/// exposed platform is Android, not iOS as first guessed.
///
/// [webDatabaseIsShared] reports which path was taken so the degradation is at
/// least observable rather than silent. It does not change the choice: a
/// dedicated worker is still strictly better than the main-isolate factory this
/// replaced, and refusing to run would be worse than running at risk.
///
/// `flutter/web/sqflite_sw.js` must be deployed for this to work; it is
/// committed rather than generated, and e2e/web_db.spec.ts asserts the app
/// really constructs a SharedWorker — not merely that the script was fetched,
/// which the fallback does too.
///
/// Being committed means it can go stale against the client encoding compiled
/// into this file's imports, which pubspec.yaml pins only to a caret range. To
/// move it, from `flutter/`:
///
/// ```
/// dart run sqflite_common_ffi_web:setup
/// ```
///
/// That rewrites `web/sqflite_sw.js` AND `web/sqlite3.wasm` — one command, two
/// files — after which `flutter/web/sqflite_sw.version` needs the new version
/// and hashes. `scripts/check-sqflite-provenance.sh` fails CI if either half of
/// that is skipped (#256).
void initDatabaseFactory() {
  databaseFactory = databaseFactoryFfiWeb;
}

/// Whether this browser can give every tab ONE database writer.
///
/// False means `SharedWorker` is unavailable and sqflite has fallen back to a
/// per-tab dedicated worker, where two open tabs can still corrupt the
/// database. Reported rather than acted on; see above.
bool get webDatabaseIsShared => _sharedWorkerCtor != null;

/// `globalThis.SharedWorker`, or null where the browser has no such thing.
@JS('SharedWorker')
external JSAny? get _sharedWorkerCtor;
