// Picks the Garbochess transport for the platform. Web only today, for the
// same shape of reason as retro: the engine is a Web Worker script, and the
// native side has no Worker to run it in.
export 'garbo_engine_io.dart' if (dart.library.js_interop) 'garbo_engine_web.dart';
