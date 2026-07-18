// Picks the engine transport for the platform. Everything downstream (the
// arbiter, and therefore all of the app) sees only UciSearcher.
//
// The conditional export keeps dart:ffi (package:stockfish) out of the web
// compile; web uses the same Stockfish WASM worker the Svelte app runs.
export 'engine_factory_io.dart' if (dart.library.js_interop) 'engine_factory_web.dart';
