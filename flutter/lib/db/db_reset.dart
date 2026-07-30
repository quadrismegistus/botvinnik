// Getting rid of an unreadable database, per platform.
export 'db_reset_io.dart' if (dart.library.js_interop) 'db_reset_web.dart';
