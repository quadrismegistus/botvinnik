// Picks the Maia transport for the platform. Web only today.
export 'maia_engine_io.dart' if (dart.library.js_interop) 'maia_engine_web.dart';
