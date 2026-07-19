// Picks the retro transport for the platform. The engines are morlock's Go
// re-implementations of TUROCHAMP (1948), BERNSTEIN (1957) and SARGON (1978);
// the shipped build is WebAssembly, so today only the web can drive them.
//
// The conditional export keeps dart:js_interop out of the native compile, and
// gives both sides a `supported` flag — the roster picker refuses to OFFER a
// persona the platform cannot play, rather than offering it and substituting
// a different opponent under its name.
export 'retro_engine_io.dart' if (dart.library.js_interop) 'retro_engine_web.dart';
