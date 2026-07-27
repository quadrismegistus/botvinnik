// ChessGPT's transport: ORT's native library over dart:ffi on macOS/iOS, and
// deliberately absent on the web. See chessgpt_engine_web.dart.
export 'chessgpt_engine_io.dart'
    if (dart.library.js_interop) 'chessgpt_engine_web.dart';
