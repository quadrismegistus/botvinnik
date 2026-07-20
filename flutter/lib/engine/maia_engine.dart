// Picks the Maia transport for the platform: ort-web in a Worker on the web,
// ORT's native library over dart:ffi on macOS/iOS. Both run the same nets and
// the same brain/maia/ encode/decode.
export 'maia_engine_io.dart' if (dart.library.js_interop) 'maia_engine_web.dart';
